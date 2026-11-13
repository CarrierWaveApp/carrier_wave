//! In-memory evaluation of a `ParsedQuery` against a single QSO.
//!
//! Parity port of the SQL lowering in `cw-store/src/query/compiler.rs`: where the
//! store compiles the AST to a SQL `WHERE` clause, this walks the same AST and
//! answers "does this row match?" directly. It exists for consumers that hold
//! QSOs in memory rather than in the SQLite store — notably the browser logbook
//! viewer, which decrypts QSOs client-side (no SQL engine available) and reuses
//! this exact logic via WASM so filtering can never drift from the app.
//!
//! The parity rules mirror the compiler leaf-for-leaf:
//! - string compares are case-insensitive via `to_lowercase()` (= the `cw_lower`
//!   UDF), literal `contains`/`starts_with`/`ends_with`/`==` (LIKE with the value
//!   escaped is a literal match);
//! - an absent (`None`) optional field makes a leaf predicate **false**, so under
//!   `NOT` it becomes true — matching SQL's `COALESCE(pred, 0)` + Swift's
//!   `?? false`;
//! - `freq:` compares in MHz (the row exposes kHz; we divide by 1000);
//! - dates resolve through `DateMatch::resolve()` (local time) exactly as the
//!   compiler does.
//!
//! `synced:`/`pending:` depend on `service_presence` rows, which an in-memory
//! consumer may not carry; [`QueryRow::service_presence_supported`] defaults to
//! `false`, in which case those leaves evaluate to `false` (documented divergence
//! for consumers without presence data).

use super::ast::{ParsedQuery, QueryExpression, QueryTerm, TermCondition};
use super::token::QueryField;
use crate::service_type::ServiceType;
use chrono::{Local, TimeZone};

/// A QSO viewed as query-addressable fields. Accessors return the same values the
/// store columns hold (see `compiler.rs::string_column` for the field→column map).
/// Optional fields return `None` when absent (→ leaf predicate false).
pub trait QueryRow {
    fn callsign(&self) -> Option<&str>;
    fn band(&self) -> Option<&str>;
    fn mode(&self) -> Option<&str>;
    fn my_callsign(&self) -> Option<&str>;
    fn park(&self) -> Option<&str>;
    fn sota_ref(&self) -> Option<&str>;
    fn their_grid(&self) -> Option<&str>;
    fn state(&self) -> Option<&str>;
    fn country(&self) -> Option<&str>;
    fn name(&self) -> Option<&str>;
    fn qth(&self) -> Option<&str>;
    fn notes(&self) -> Option<&str>;
    fn my_grid(&self) -> Option<&str>;

    /// Frequency in **kHz** (as stored). The evaluator divides by 1000 for `freq:`.
    fn frequency_khz(&self) -> Option<f64>;
    fn dxcc(&self) -> Option<f64>;
    fn power(&self) -> Option<f64>;

    /// QSO timestamp, unix seconds (the `qso_date` column).
    fn qso_date(&self) -> i64;

    fn qrz_confirmed(&self) -> bool;
    fn lotw_confirmed(&self) -> bool;

    /// `import_source` raw value (e.g. `"logger"`, `"qrz"`, `"adif"`).
    fn import_source(&self) -> &str;

    /// Whether `synced:`/`pending:` (service-presence) filters can be answered.
    /// Defaults to `false`; such leaves then evaluate to `false`.
    fn service_presence_supported(&self) -> bool {
        false
    }
    /// Is the QSO present on `service`? Only consulted when
    /// [`service_presence_supported`](Self::service_presence_supported) is true.
    fn is_present_on(&self, _service: ServiceType) -> bool {
        false
    }
    /// Does the QSO still need upload to `service` (or any, when `None`)?
    fn needs_upload_to(&self, _service: Option<ServiceType>) -> bool {
        false
    }
}

/// Evaluate `query` against `row`. Honors `date_window` exactly like
/// `compile_where` (ANDs the inclusive unix-seconds bounds onto the expression).
pub fn matches<R: QueryRow>(query: &ParsedQuery, row: &R) -> bool {
    if !eval_expr(&query.expression, row) {
        return false;
    }
    let (start, end) = query.date_window;
    if let Some(start) = start {
        if row.qso_date() < start {
            return false;
        }
    }
    if let Some(end) = end {
        if row.qso_date() > end {
            return false;
        }
    }
    true
}

fn eval_expr<R: QueryRow>(expr: &QueryExpression, row: &R) -> bool {
    match expr {
        QueryExpression::Empty => true, // "1=1"
        QueryExpression::Term(term) => eval_term(term, row),
        QueryExpression::And(exprs) => exprs.iter().all(|e| eval_expr(e, row)),
        QueryExpression::Or(exprs) => exprs.iter().any(|e| eval_expr(e, row)),
        QueryExpression::Not(inner) => !eval_expr(inner, row),
    }
}

fn eval_term<R: QueryRow>(term: &QueryTerm, row: &R) -> bool {
    match term.field {
        Some(field) => eval_field_term(field, &term.condition, row),
        None => eval_bare_term(&term.condition, row),
    }
}

fn eval_field_term<R: QueryRow>(field: QueryField, cond: &TermCondition, row: &R) -> bool {
    use QueryField::*;
    if let Some(col) = string_value(field, row) {
        return eval_string_match(col, cond);
    }
    // The string fields above returned `Some`; a `None` for a string field means the
    // value is absent → leaf is false (COALESCE(_, 0)).
    if is_string_field(field) {
        return false;
    }
    match field {
        // `freq:` compares in MHz (kHz / 1000), matching the compiler.
        Frequency => eval_numeric(row.frequency_khz().map(|khz| khz / 1000.0), cond),
        Dxcc => eval_numeric(row.dxcc(), cond),
        Power => eval_numeric(row.power(), cond),
        Date | After | Before => eval_date(cond, row.qso_date()),
        Confirmed => eval_confirmed(cond, row),
        Synced => eval_presence(cond, row, Presence::Synced),
        Pending => eval_presence(cond, row, Presence::Pending),
        Source => eval_source(cond, row),
        _ => true,
    }
}

fn is_string_field(field: QueryField) -> bool {
    use QueryField::*;
    matches!(
        field,
        Callsign | Band | Mode | MyCallsign | Park | Sota | Grid | State | Country | Name | Qth
            | Notes | MyGrid
    )
}

/// The string-column value for a field, mirroring `compiler.rs::string_column`.
fn string_value<R: QueryRow>(field: QueryField, row: &R) -> Option<&str> {
    use QueryField::*;
    match field {
        Callsign => row.callsign(),
        Band => row.band(),
        Mode => row.mode(),
        MyCallsign => row.my_callsign(),
        Park => row.park(),
        Sota => row.sota_ref(),
        Grid => row.their_grid(),
        State => row.state(),
        Country => row.country(),
        Name => row.name(),
        Qth => row.qth(),
        Notes => row.notes(),
        MyGrid => row.my_grid(),
        _ => None,
    }
}

/// Case-insensitive literal match (LIKE-with-escaped-value is literal). `to_lowercase`
/// mirrors the `cw_lower` UDF (`String::to_lowercase`).
fn eval_string_match(col: &str, cond: &TermCondition) -> bool {
    let lc = col.to_lowercase();
    match cond {
        TermCondition::Equals(v) => lc == v.to_lowercase(),
        TermCondition::Contains(v) => lc.contains(&v.to_lowercase()),
        TermCondition::Prefix(v) => lc.starts_with(&v.to_lowercase()),
        TermCondition::Suffix(v) => lc.ends_with(&v.to_lowercase()),
        TermCondition::Range(a, b) => {
            let (a, b) = (a.to_lowercase(), b.to_lowercase());
            lc >= a && lc <= b
        }
        _ => true, // "1=1" for conditions that don't apply to string columns
    }
}

fn eval_numeric(value: Option<f64>, cond: &TermCondition) -> bool {
    let Some(x) = value else {
        // NULL column → COALESCE(pred, 0) = false, except the non-numeric
        // conditions which lower to "1=1" (true) regardless of the value.
        return matches!(
            cond,
            TermCondition::DateEquals(_)
                | TermCondition::DateAfter(_)
                | TermCondition::DateBefore(_)
                | TermCondition::DateRange(_, _)
                | TermCondition::Boolean(_)
                | TermCondition::Service(_)
                | TermCondition::Contains(_)
                | TermCondition::Prefix(_)
                | TermCondition::Suffix(_)
                | TermCondition::Range(_, _)
        );
    };
    match cond {
        TermCondition::GreaterThan(n) => x > *n,
        TermCondition::LessThan(n) => x < *n,
        TermCondition::GreaterThanOrEqual(n) => x >= *n,
        TermCondition::LessThanOrEqual(n) => x <= *n,
        TermCondition::NumericRange(a, b) => x >= *a && x <= *b,
        TermCondition::Equals(v) => match v.parse::<f64>() {
            Ok(n) => x == n,
            Err(_) => true, // compiler emits "1=1"
        },
        _ => true,
    }
}

fn eval_date(cond: &TermCondition, qso_date: i64) -> bool {
    // Resolve a NaiveDateTime to unix seconds in local time, matching the
    // compiler's `unix` closure.
    let unix = |dt: chrono::NaiveDateTime| -> i64 {
        Local
            .from_local_datetime(&dt)
            .single()
            .map(|d| d.timestamp())
            .unwrap_or_else(|| dt.and_utc().timestamp())
    };
    match cond {
        TermCondition::DateEquals(d) => {
            let (start, end) = d.resolve();
            qso_date >= unix(start) && qso_date < unix(end)
        }
        TermCondition::DateAfter(d) => {
            let (start, _) = d.resolve();
            qso_date >= unix(start)
        }
        TermCondition::DateBefore(d) => {
            let (_, end) = d.resolve();
            qso_date < unix(end)
        }
        TermCondition::DateRange(a, b) => {
            let (start, _) = a.resolve();
            let (_, end) = b.resolve();
            qso_date >= unix(start) && qso_date < unix(end)
        }
        _ => true,
    }
}

fn eval_confirmed<R: QueryRow>(cond: &TermCondition, row: &R) -> bool {
    match cond {
        TermCondition::Boolean(true) => row.qrz_confirmed() || row.lotw_confirmed(),
        TermCondition::Boolean(false) => !row.qrz_confirmed() && !row.lotw_confirmed(),
        TermCondition::Service(ServiceType::Lotw) => row.lotw_confirmed(),
        TermCondition::Service(ServiceType::Qrz) => row.qrz_confirmed(),
        TermCondition::Service(_) => false, // only LoTW/QRZ confirm
        _ => true,
    }
}

enum Presence {
    Synced,
    Pending,
}

fn eval_presence<R: QueryRow>(cond: &TermCondition, row: &R, kind: Presence) -> bool {
    if !row.service_presence_supported() {
        // Documented divergence: consumers without presence data can't answer
        // these; the leaf is false (so bare `synced:`/`pending:` match nothing).
        return false;
    }
    match (kind, cond) {
        (Presence::Synced, TermCondition::Boolean(true)) => {
            ServiceType::ALL.iter().any(|s| row.is_present_on(*s))
        }
        (Presence::Synced, TermCondition::Boolean(false)) => {
            !ServiceType::ALL.iter().any(|s| row.is_present_on(*s))
        }
        (Presence::Synced, TermCondition::Service(svc)) => row.is_present_on(*svc),
        (Presence::Pending, TermCondition::Boolean(true)) => row.needs_upload_to(None),
        (Presence::Pending, TermCondition::Boolean(false)) => !row.needs_upload_to(None),
        (Presence::Pending, TermCondition::Service(svc)) => row.needs_upload_to(Some(*svc)),
        _ => true,
    }
}

fn eval_source<R: QueryRow>(cond: &TermCondition, row: &R) -> bool {
    match cond {
        TermCondition::Service(svc) => row.import_source() == svc.raw_value(),
        TermCondition::Equals(v)
            if v.eq_ignore_ascii_case("manual") || v.eq_ignore_ascii_case("logger") =>
        {
            row.import_source() == "logger"
        }
        _ => false,
    }
}

/// Bare term (no field): mirrors `compiler.rs::lower_bare_term`. Contains searches
/// callsign/park/sota/notes; equals/prefix/suffix search callsign/park/sota.
fn eval_bare_term<R: QueryRow>(cond: &TermCondition, row: &R) -> bool {
    let contains_cols = [row.callsign(), row.park(), row.sota_ref(), row.notes()];
    let other_cols = [row.callsign(), row.park(), row.sota_ref()];
    let any = |cols: &[Option<&str>], f: &dyn Fn(&str) -> bool| -> bool {
        cols.iter().any(|c| c.map(f).unwrap_or(false))
    };
    match cond {
        TermCondition::Contains(v) => {
            let needle = v.to_lowercase();
            any(&contains_cols, &|c| c.to_lowercase().contains(&needle))
        }
        TermCondition::Equals(v) => {
            let needle = v.to_lowercase();
            any(&other_cols, &|c| c.to_lowercase() == needle)
        }
        TermCondition::Prefix(v) => {
            let needle = v.to_lowercase();
            any(&other_cols, &|c| c.to_lowercase().starts_with(&needle))
        }
        TermCondition::Suffix(v) => {
            let needle = v.to_lowercase();
            any(&other_cols, &|c| c.to_lowercase().ends_with(&needle))
        }
        _ => true,
    }
}
