//! AST → SQL lowering at parity with Swift `QueryCompiler`.

use crate::query::sql::{escape_like, SqlValue};
use chrono::{Local, TimeZone};
use cw_domain::query::{ParsedQuery, QueryExpression, QueryField, QueryTerm, TermCondition};
use cw_domain::service_type::ServiceType;

/// Lower a parsed query to a SQL boolean expression over the `qso` table plus
/// `service_presence` EXISTS subqueries, with its bound parameters in order.
///
/// A `query.date_window` (inclusive `[start, end]` unix-seconds bounds, set by the brag-sheet
/// consumer whose UTC instant period the day-granular DSL can't express) is ANDed onto the
/// lowered expression: `(<expr>) [AND qso_date >= ?] [AND qso_date <= ?]`, the window values
/// bound AFTER the expression's in textual placeholder order. `None` bounds are omitted.
pub fn compile_where(query: &ParsedQuery) -> (String, Vec<SqlValue>) {
    let mut params = Vec::new();
    let mut sql = lower_expr(&query.expression, &mut params);
    let (start, end) = query.date_window;
    if let Some(start) = start {
        sql = format!("({sql}) AND qso_date >= ?");
        params.push(SqlValue::Int(start));
    }
    if let Some(end) = end {
        sql = format!("({sql}) AND qso_date <= ?");
        params.push(SqlValue::Int(end));
    }
    (sql, params)
}

fn lower_expr(expr: &QueryExpression, params: &mut Vec<SqlValue>) -> String {
    match expr {
        QueryExpression::Empty => "1=1".to_string(),
        QueryExpression::Term(term) => format!("({})", lower_term(term, params)),
        QueryExpression::And(exprs) => join(exprs, " AND ", params),
        QueryExpression::Or(exprs) => join(exprs, " OR ", params),
        QueryExpression::Not(inner) => format!("(NOT ({}))", lower_expr(inner, params)),
    }
}

fn join(exprs: &[QueryExpression], op: &str, params: &mut Vec<SqlValue>) -> String {
    let parts: Vec<String> = exprs.iter().map(|e| lower_expr(e, params)).collect();
    format!("({})", parts.join(op))
}

/// `column` for the simple string/numeric fields. `None` ⇒ handled specially
/// (date/status/bare).
fn string_column(field: QueryField) -> Option<&'static str> {
    use QueryField::*;
    Some(match field {
        Callsign => "callsign",
        Band => "band",
        Mode => "mode",
        MyCallsign => "my_callsign",
        Park => "park",
        Sota => "sota_ref",
        Grid => "their_grid",
        State => "state",
        Country => "country",
        Name => "name",
        Qth => "qth",
        Notes => "notes",
        MyGrid => "my_grid",
        _ => return None,
    })
}

fn lower_term(term: &QueryTerm, params: &mut Vec<SqlValue>) -> String {
    match term.field {
        Some(field) => lower_field_term(field, &term.condition, params),
        None => lower_bare_term(&term.condition, params),
    }
}

fn lower_field_term(field: QueryField, cond: &TermCondition, params: &mut Vec<SqlValue>) -> String {
    use QueryField::*;
    if let Some(col) = string_column(field) {
        return lower_string_match(col, cond, params);
    }
    match field {
        // Swift `QueryCompiler` compares `freq:` values against the `@Model`
        // `frequency` property, which is in **MHz**. The store column `freq_khz`
        // is kHz (the projection multiplies MHz × 1000). Divide back to MHz so
        // `freq:14074` / `freq:>14000` / ranges match Swift's MHz comparison
        // exactly (e.g. a 14074 kHz QSO is 14.074 MHz, which is NOT > 14000).
        Frequency => lower_numeric("(freq_khz / 1000.0)", cond, params),
        Dxcc => lower_numeric("dxcc", cond, params),
        Power => lower_numeric("power", cond, params),
        Date | After | Before => lower_date(field, cond, params),
        Confirmed => lower_confirmed(cond, params),
        Synced => lower_presence("sp.is_present = 1", cond, params),
        Pending => lower_presence("sp.needs_upload = 1", cond, params),
        Source => lower_source(cond, params),
        _ => "1=1".to_string(), // string fields handled above
    }
}

/// Wrap a leaf predicate over a (possibly NULL) column so SQL three-valued logic
/// collapses to a definite boolean, matching Swift's `?? false` on optional
/// fields. Without this, `NOT (col = ?)` over a NULL column yields NULL (row
/// excluded) where Swift's `!(false)` yields `true` (row included).
fn coalesce_false(pred: String) -> String {
    format!("COALESCE({pred}, 0)")
}

/// String comparisons reproduce Swift `lowercased()` semantics via `cw_lower`.
/// Each predicate is `COALESCE(..., 0)`-wrapped so a NULL column matches Swift's
/// optional `?? false` semantics under negation.
fn lower_string_match(col: &str, cond: &TermCondition, params: &mut Vec<SqlValue>) -> String {
    match cond {
        TermCondition::Equals(v) => {
            params.push(SqlValue::Text(v.clone()));
            coalesce_false(format!("cw_lower({col}) = cw_lower(?)"))
        }
        TermCondition::Contains(v) => {
            params.push(SqlValue::Text(escape_like(v)));
            coalesce_false(format!(
                "cw_lower({col}) LIKE '%' || cw_lower(?) || '%' ESCAPE '\\'"
            ))
        }
        TermCondition::Prefix(v) => {
            params.push(SqlValue::Text(escape_like(v)));
            coalesce_false(format!("cw_lower({col}) LIKE cw_lower(?) || '%' ESCAPE '\\'"))
        }
        TermCondition::Suffix(v) => {
            params.push(SqlValue::Text(escape_like(v)));
            coalesce_false(format!("cw_lower({col}) LIKE '%' || cw_lower(?) ESCAPE '\\'"))
        }
        TermCondition::Range(a, b) => {
            params.push(SqlValue::Text(a.clone()));
            params.push(SqlValue::Text(b.clone()));
            coalesce_false(format!(
                "cw_lower({col}) >= cw_lower(?) AND cw_lower({col}) <= cw_lower(?)"
            ))
        }
        _ => "1=1".to_string(),
    }
}

fn lower_numeric(col: &str, cond: &TermCondition, params: &mut Vec<SqlValue>) -> String {
    match cond {
        TermCondition::GreaterThan(n) => {
            params.push(SqlValue::Real(*n));
            coalesce_false(format!("{col} > ?"))
        }
        TermCondition::LessThan(n) => {
            params.push(SqlValue::Real(*n));
            coalesce_false(format!("{col} < ?"))
        }
        TermCondition::GreaterThanOrEqual(n) => {
            params.push(SqlValue::Real(*n));
            coalesce_false(format!("{col} >= ?"))
        }
        TermCondition::LessThanOrEqual(n) => {
            params.push(SqlValue::Real(*n));
            coalesce_false(format!("{col} <= ?"))
        }
        TermCondition::NumericRange(a, b) => {
            params.push(SqlValue::Real(*a));
            params.push(SqlValue::Real(*b));
            coalesce_false(format!("{col} >= ? AND {col} <= ?"))
        }
        TermCondition::Equals(v) => {
            // numeric field given a bare value — match Swift's numeric equality
            if let Ok(n) = v.parse::<f64>() {
                params.push(SqlValue::Real(n));
                coalesce_false(format!("{col} = ?"))
            } else {
                "1=1".to_string()
            }
        }
        _ => "1=1".to_string(),
    }
}

fn lower_date(field: QueryField, cond: &TermCondition, params: &mut Vec<SqlValue>) -> String {
    let unix = |dt: chrono::NaiveDateTime| -> i64 {
        Local
            .from_local_datetime(&dt)
            .single()
            .map(|d| d.timestamp())
            .unwrap_or_else(|| dt.and_utc().timestamp())
    };
    match cond {
        TermCondition::DateEquals(d) | TermCondition::DateAfter(d) | TermCondition::DateBefore(d) => {
            let (start, end) = d.resolve();
            match cond {
                TermCondition::DateEquals(_) => {
                    params.push(SqlValue::Int(unix(start)));
                    params.push(SqlValue::Int(unix(end)));
                    "qso_date >= ? AND qso_date < ?".to_string()
                }
                TermCondition::DateAfter(_) => {
                    params.push(SqlValue::Int(unix(start)));
                    "qso_date >= ?".to_string()
                }
                _ => {
                    params.push(SqlValue::Int(unix(end)));
                    "qso_date < ?".to_string()
                }
            }
        }
        TermCondition::DateRange(a, b) => {
            let (start, _) = a.resolve();
            let (_, end) = b.resolve();
            params.push(SqlValue::Int(unix(start)));
            params.push(SqlValue::Int(unix(end)));
            "qso_date >= ? AND qso_date < ?".to_string()
        }
        _ => {
            let _ = field;
            "1=1".to_string()
        }
    }
}

fn lower_confirmed(cond: &TermCondition, _params: &mut Vec<SqlValue>) -> String {
    match cond {
        TermCondition::Boolean(true) => "qrz_confirmed = 1 OR lotw_confirmed = 1".to_string(),
        TermCondition::Boolean(false) => "qrz_confirmed = 0 AND lotw_confirmed = 0".to_string(),
        TermCondition::Service(ServiceType::Lotw) => "lotw_confirmed = 1".to_string(),
        TermCondition::Service(ServiceType::Qrz) => "qrz_confirmed = 1".to_string(),
        TermCondition::Service(_) => "0".to_string(), // only LoTW/QRZ confirm
        _ => "1=1".to_string(),
    }
}

fn lower_presence(predicate: &str, cond: &TermCondition, params: &mut Vec<SqlValue>) -> String {
    let base = "EXISTS (SELECT 1 FROM service_presence sp WHERE sp.qso_id = qso.id";
    let not_base = "NOT EXISTS (SELECT 1 FROM service_presence sp WHERE sp.qso_id = qso.id";
    match cond {
        TermCondition::Boolean(true) => format!("{base} AND {predicate})"),
        TermCondition::Boolean(false) => format!("{not_base} AND {predicate})"),
        TermCondition::Service(svc) => {
            params.push(SqlValue::Text(svc.raw_value().to_string()));
            format!("{base} AND {predicate} AND sp.service_type_raw_value = ?)")
        }
        _ => "1=1".to_string(),
    }
}

fn lower_source(cond: &TermCondition, params: &mut Vec<SqlValue>) -> String {
    match cond {
        TermCondition::Service(svc) => {
            params.push(SqlValue::Text(svc.raw_value().to_string()));
            "import_source_raw_value = ?".to_string()
        }
        TermCondition::Equals(v)
            if v.eq_ignore_ascii_case("manual") || v.eq_ignore_ascii_case("logger") =>
        {
            params.push(SqlValue::Text("logger".to_string()));
            "import_source_raw_value = ?".to_string()
        }
        _ => "0".to_string(),
    }
}

fn lower_bare_term(cond: &TermCondition, params: &mut Vec<SqlValue>) -> String {
    // Mirrors Swift compileBareSearchTerm: contains→call/park/sota/notes;
    // equals/prefix/suffix→call/park/sota. Each leaf is COALESCE-wrapped so NULL
    // optional columns (park/sota_ref/notes) collapse to false like Swift's
    // `?? false`, keeping parity under negation.
    let cols_contains = ["callsign", "park", "sota_ref", "notes"];
    let cols_other = ["callsign", "park", "sota_ref"];
    let like = |col: &str, params: &mut Vec<SqlValue>, value: &str, pat: &str| -> String {
        params.push(SqlValue::Text(escape_like(value)));
        let raw = match pat {
            "contains" => format!("cw_lower({col}) LIKE '%' || cw_lower(?) || '%' ESCAPE '\\'"),
            "prefix" => format!("cw_lower({col}) LIKE cw_lower(?) || '%' ESCAPE '\\'"),
            _ => format!("cw_lower({col}) LIKE '%' || cw_lower(?) ESCAPE '\\'"),
        };
        coalesce_false(raw)
    };
    match cond {
        TermCondition::Contains(v) => {
            let parts: Vec<String> = cols_contains
                .iter()
                .map(|c| like(c, params, v, "contains"))
                .collect();
            format!("({})", parts.join(" OR "))
        }
        TermCondition::Equals(v) => {
            let parts: Vec<String> = cols_other
                .iter()
                .map(|c| {
                    params.push(SqlValue::Text(v.clone()));
                    coalesce_false(format!("cw_lower({c}) = cw_lower(?)"))
                })
                .collect();
            format!("({})", parts.join(" OR "))
        }
        TermCondition::Prefix(v) => {
            let parts: Vec<String> = cols_other
                .iter()
                .map(|c| like(c, params, v, "prefix"))
                .collect();
            format!("({})", parts.join(" OR "))
        }
        TermCondition::Suffix(v) => {
            let parts: Vec<String> = cols_other
                .iter()
                .map(|c| like(c, params, v, "suffix"))
                .collect();
            format!("({})", parts.join(" OR "))
        }
        _ => "1=1".to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use cw_domain::query::parse;

    fn lower(input: &str) -> (String, Vec<SqlValue>) {
        let q = parse(input).unwrap();
        compile_where(&q)
    }

    #[test]
    fn callsign_equals_is_case_insensitive() {
        let (sql, params) = lower("call:w1aw");
        assert_eq!(sql, "(COALESCE(cw_lower(callsign) = cw_lower(?), 0))");
        assert_eq!(params, vec![SqlValue::Text("w1aw".into())]);
    }

    #[test]
    fn notes_contains_escapes_and_wraps() {
        // `*de_x*` parses as Contains("de_x"); the `_` is a LIKE wildcard so
        // escape_like must escape it. (The plan's `notes:de%` input is avoided:
        // a trailing `%` hangs the cw-domain lexer — see the report's
        // DONE_WITH_CONCERNS note. `_` exercises the same escape path safely.)
        let (sql, params) = lower("notes:*de_x*");
        assert_eq!(
            sql,
            "(COALESCE(cw_lower(notes) LIKE '%' || cw_lower(?) || '%' ESCAPE '\\', 0))"
        );
        assert_eq!(params, vec![SqlValue::Text(escape_like("de_x"))]);
        // Confirm the wildcard was escaped, not passed through literally.
        assert_eq!(params, vec![SqlValue::Text("de\\_x".into())]);
    }

    #[test]
    fn band_and_mode_compose_with_and() {
        let (sql, _) = lower("band:20m mode:ft8");
        assert_eq!(
            sql,
            "((COALESCE(cw_lower(band) = cw_lower(?), 0)) AND \
             (COALESCE(cw_lower(mode) = cw_lower(?), 0)))"
        );
    }

    #[test]
    fn frequency_greater_than_is_numeric_in_mhz() {
        // `freq:` compares in MHz at parity with Swift's `@Model.frequency`
        // (MHz); the kHz column is divided by 1000 before comparison.
        let (sql, params) = lower("freq:>14000");
        assert_eq!(sql, "(COALESCE((freq_khz / 1000.0) > ?, 0))");
        assert_eq!(params, vec![SqlValue::Real(14000.0)]);
    }

    #[test]
    fn confirmed_yes_is_any_service() {
        let (sql, _) = lower("confirmed:yes");
        assert_eq!(sql, "(qrz_confirmed = 1 OR lotw_confirmed = 1)");
    }

    #[test]
    fn synced_qrz_is_exists_subquery() {
        let (sql, params) = lower("synced:qrz");
        assert_eq!(
            sql,
            "(EXISTS (SELECT 1 FROM service_presence sp WHERE sp.qso_id = qso.id \
             AND sp.is_present = 1 AND sp.service_type_raw_value = ?))"
        );
        assert_eq!(params, vec![SqlValue::Text("qrz".into())]);
    }

    #[test]
    fn pending_yes_is_exists_needs_upload() {
        let (sql, _) = lower("pending:yes");
        assert_eq!(
            sql,
            "(EXISTS (SELECT 1 FROM service_presence sp WHERE sp.qso_id = qso.id \
             AND sp.needs_upload = 1))"
        );
    }

    #[test]
    fn source_qrz_maps_to_import_source() {
        let (sql, params) = lower("source:qrz");
        assert_eq!(sql, "(import_source_raw_value = ?)");
        assert_eq!(params, vec![SqlValue::Text("qrz".into())]);
    }

    #[test]
    fn not_wraps() {
        let (sql, _) = lower("-mode:cw");
        assert_eq!(sql, "(NOT ((COALESCE(cw_lower(mode) = cw_lower(?), 0))))");
    }

    #[test]
    fn bare_contains_searches_call_park_sota_notes() {
        // A `*pota*` bare term parses as Contains → searches callsign/park/sota/notes,
        // mirroring Swift `compileBareSearchTerm`'s `.contains` branch.
        let (sql, _) = lower("*pota*");
        assert!(sql.contains("cw_lower(callsign) LIKE"));
        assert!(sql.contains("cw_lower(park) LIKE"));
        assert!(sql.contains("cw_lower(sota_ref) LIKE"));
        assert!(sql.contains("cw_lower(notes) LIKE"));
    }

    #[test]
    fn bare_word_is_implicit_callsign_prefix() {
        // A bare word with no wildcard parses (in BOTH Swift and Rust) as
        // `field: .callsign, condition: .prefix(uppercased)` — an implicit
        // callsign prefix search, NOT a multi-field bare term. The multi-field
        // (call/park/sota[/notes]) path only fires for `*`/range bare terms.
        let (sql, params) = lower("pota");
        assert_eq!(
            sql,
            "(COALESCE(cw_lower(callsign) LIKE cw_lower(?) || '%' ESCAPE '\\', 0))"
        );
        assert!(!sql.contains("cw_lower(park)"));
        assert!(!sql.contains("cw_lower(sota_ref)"));
        // Value is uppercased by the parser before escaping.
        assert_eq!(params, vec![SqlValue::Text(escape_like("POTA"))]);
    }

    #[test]
    fn date_after_resolves_to_unix_lower_bound() {
        let (sql, params) = lower("after:2026-01-01");
        assert_eq!(sql, "(qso_date >= ?)");
        // 2026-01-01 00:00 local → unix seconds
        let expected = Local
            .with_ymd_and_hms(2026, 1, 1, 0, 0, 0)
            .single()
            .unwrap()
            .timestamp();
        assert_eq!(params, vec![SqlValue::Int(expected)]);
    }

    /// Parity regression: under negation, a NULL optional column must match
    /// Swift's `!(... ?? false)` = true (row included). The COALESCE-wrapped
    /// predicate `NOT (COALESCE(pred, 0))` evaluates NULL→0→NOT 0→1 (included),
    /// where a bare `NOT (col = ?)` would yield NULL (excluded).
    #[test]
    fn negated_optional_field_includes_null_rows() {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        crate::query::sql::register_cw_lower(&conn).unwrap();
        conn.execute_batch(
            "CREATE TABLE qso (id TEXT PRIMARY KEY, park TEXT);
             INSERT INTO qso (id, park) VALUES ('with', 'US-1234');
             INSERT INTO qso (id, park) VALUES ('null', NULL);",
        )
        .unwrap();

        let (sql, params) = lower("-park:US-1234");
        let mut stmt = conn
            .prepare(&format!("SELECT id FROM qso WHERE {sql} ORDER BY id"))
            .unwrap();
        let bound: Vec<&dyn rusqlite::ToSql> = params
            .iter()
            .map(|param| match param {
                SqlValue::Text(text) => text as &dyn rusqlite::ToSql,
                SqlValue::Int(int) => int as &dyn rusqlite::ToSql,
                SqlValue::Real(real) => real as &dyn rusqlite::ToSql,
            })
            .collect();
        let ids: Vec<String> = stmt
            .query_map(bound.as_slice(), |row| row.get::<_, String>(0))
            .unwrap()
            .map(Result::unwrap)
            .collect();
        // The NULL-park row is INCLUDED by `-park:...` (parity with Swift).
        assert_eq!(ids, vec!["null".to_string()]);
    }
}
