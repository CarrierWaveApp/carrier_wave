//! Low-level SQL building blocks for the query compiler: bound-parameter values,
//! the `cw_lower` UDF registration, and `LIKE` escaping. Kept apart from the AST
//! lowering so the string-handling parity rules live in one place.

use rusqlite::Connection;

/// A bound SQL parameter. Mirrors the value kinds the lowering produces.
#[derive(Debug, Clone, PartialEq)]
pub enum SqlValue {
    Text(String),
    Int(i64),
    Real(f64),
}

impl SqlValue {
    /// Convert to a heap-boxed `ToSql` for dynamic parameter binding.
    pub fn to_sql_param(&self) -> Box<dyn rusqlite::types::ToSql> {
        match self {
            SqlValue::Text(s) => Box::new(s.clone()),
            SqlValue::Int(n) => Box::new(*n),
            SqlValue::Real(n) => Box::new(*n),
        }
    }
}

/// Escape `%`, `_`, and `\` in a user value so it is matched literally inside a
/// `LIKE` pattern using `ESCAPE '\'`. Mirrors Swift's literal `contains/hasPrefix/
/// hasSuffix` (which are NOT pattern matches).
pub fn escape_like(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for ch in value.chars() {
        if ch == '\\' || ch == '%' || ch == '_' {
            out.push('\\');
        }
        out.push(ch);
    }
    out
}

/// Register `cw_lower(x)` — a Unicode-aware lowercaser matching Swift
/// `String.lowercased()` closely enough for log fields. Used on both column and
/// value sides so comparisons are case-insensitive identically to the Swift path.
pub fn register_cw_lower(conn: &Connection) -> rusqlite::Result<()> {
    use rusqlite::functions::FunctionFlags;
    conn.create_scalar_function(
        "cw_lower",
        1,
        FunctionFlags::SQLITE_UTF8 | FunctionFlags::SQLITE_DETERMINISTIC,
        |ctx| {
            let s: Option<String> = ctx.get(0)?;
            Ok(s.map(|v| v.to_lowercase()))
        },
    )
}

/// Register `cw_mode_family(mode)` — maps a raw mode string to its family label
/// ("Phone"/"CW"/"Digital"/"Other") via `cw_domain::mode::ModeEquivalence`, so the
/// analytics layer can `GROUP BY` mode family in SQL (correct per-family
/// `COUNT(DISTINCT callsign)`) instead of folding rows in Rust. NULL → "Other".
pub fn register_cw_mode_family(conn: &Connection) -> rusqlite::Result<()> {
    use cw_domain::mode::{ModeEquivalence, ModeFamily};
    use rusqlite::functions::FunctionFlags;
    conn.create_scalar_function(
        "cw_mode_family",
        1,
        FunctionFlags::SQLITE_UTF8 | FunctionFlags::SQLITE_DETERMINISTIC,
        |ctx| {
            let mode: Option<String> = ctx.get(0)?;
            let label = match mode.as_deref().map(ModeEquivalence::family) {
                Some(ModeFamily::Phone) => "Phone",
                Some(ModeFamily::Cw) => "CW",
                Some(ModeFamily::Digital) => "Digital",
                Some(ModeFamily::Other) | None => "Other",
            };
            Ok(label.to_string())
        },
    )
}

/// Register `cw_grid_distance_km(grid_a, grid_b)` — the great-circle distance in km
/// between two Maidenhead locators via `cw_domain::maidenhead::distance_km` (haversine,
/// 6371 km radius), so the analytics layer can compute per-QSO distance in SQL. Returns
/// NULL when either argument is NULL or fails to parse (grids shorter than 4 chars /
/// out-of-range fields), matching `MaidenheadConverter.distanceKm`'s `nil`. Two-arg form.
pub fn register_cw_grid_distance_km(conn: &Connection) -> rusqlite::Result<()> {
    use cw_domain::maidenhead;
    use rusqlite::functions::FunctionFlags;
    conn.create_scalar_function(
        "cw_grid_distance_km",
        2,
        FunctionFlags::SQLITE_UTF8 | FunctionFlags::SQLITE_DETERMINISTIC,
        |ctx| {
            let grid_a: Option<String> = ctx.get(0)?;
            let grid_b: Option<String> = ctx.get(1)?;
            Ok(match (grid_a, grid_b) {
                (Some(grid_a), Some(grid_b)) => maidenhead::distance_km(&grid_a, &grid_b),
                _ => None,
            })
        },
    )
}

/// Register `cw_mode_canonical(mode)` — the canonical mode name via
/// `cw_domain::mode::ModeEquivalence::canonical_name`, so the brag records aggregate can
/// `COUNT(DISTINCT)` / `GROUP BY` canonical mode in SQL (matching `activeModes` / `busiestMode`).
/// NULL → "".
pub fn register_cw_mode_canonical(conn: &Connection) -> rusqlite::Result<()> {
    use cw_domain::mode::ModeEquivalence;
    use rusqlite::functions::FunctionFlags;
    conn.create_scalar_function(
        "cw_mode_canonical",
        1,
        FunctionFlags::SQLITE_UTF8 | FunctionFlags::SQLITE_DETERMINISTIC,
        |ctx| {
            let mode: Option<String> = ctx.get(0)?;
            Ok(ModeEquivalence::canonical_name(mode.as_deref().unwrap_or("")))
        },
    )
}

/// Register `cw_continent(dxcc)` — maps a DXCC entity number to its continent abbreviation
/// ("NA"/"SA"/"EU"/"AF"/"AS"/"OC") via `cw_domain::continent`, so the brag geographic
/// aggregate can `GROUP BY`/`COUNT(DISTINCT)` continent in SQL. NULL / unmapped → NULL.
pub fn register_cw_continent(conn: &Connection) -> rusqlite::Result<()> {
    use rusqlite::functions::FunctionFlags;
    conn.create_scalar_function(
        "cw_continent",
        1,
        FunctionFlags::SQLITE_UTF8 | FunctionFlags::SQLITE_DETERMINISTIC,
        |ctx| {
            let dxcc: Option<i64> = ctx.get(0)?;
            Ok(dxcc.and_then(cw_domain::continent::continent_for_dxcc).map(str::to_string))
        },
    )
}

/// Register `cw_rst_s(rst)` — extracts the S (readability/strength) digit from an RST report,
/// replicating `BragSheetComputationActor.computeAverageRST`: collect the digit characters in
/// order, drop the first, and take the next. Returns that digit as an integer, or NULL when the
/// report is NULL, shorter than 2 characters, or has fewer than 2 digits.
pub fn register_cw_rst_s(conn: &Connection) -> rusqlite::Result<()> {
    use rusqlite::functions::FunctionFlags;
    conn.create_scalar_function(
        "cw_rst_s",
        1,
        FunctionFlags::SQLITE_UTF8 | FunctionFlags::SQLITE_DETERMINISTIC,
        |ctx| {
            let rst: Option<String> = ctx.get(0)?;
            Ok(rst.and_then(|value| {
                // Mirror the Swift guard: `rst.count >= 2` (Unicode scalar / character count).
                if value.chars().count() < 2 {
                    return None;
                }
                // compactMap(\.wholeNumberValue).dropFirst().first
                value
                    .chars()
                    .filter_map(|ch| ch.to_digit(10))
                    .nth(1)
                    .map(i64::from)
            }))
        },
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn escape_like_escapes_wildcards() {
        assert_eq!(escape_like("a%b_c\\d"), "a\\%b\\_c\\\\d");
        assert_eq!(escape_like("plain"), "plain");
    }

    #[test]
    fn cw_lower_lowercases_via_sql() {
        let conn = Connection::open_in_memory().unwrap();
        register_cw_lower(&conn).unwrap();
        let out: String = conn
            .query_row("SELECT cw_lower('AbÇD')", [], |r| r.get(0))
            .unwrap();
        assert_eq!(out, "abçd");
    }

    #[test]
    fn store_registers_cw_lower() {
        let store = crate::Store::open_in_memory("k").unwrap();
        let out: String = store
            .conn
            .query_row("SELECT cw_lower('XY')", [], |r| r.get(0))
            .unwrap();
        assert_eq!(out, "xy");
    }

    #[test]
    fn cw_grid_distance_km_via_sql() {
        let conn = Connection::open_in_memory().unwrap();
        register_cw_grid_distance_km(&conn).unwrap();
        // FN31 → DM12 is ~4000 km; match the cw_domain unit-test tolerance.
        let km: f64 = conn
            .query_row("SELECT cw_grid_distance_km('FN31', 'DM12')", [], |r| r.get(0))
            .unwrap();
        assert!((km - 4012.0).abs() < 200.0, "got {km}");
        // NULL / invalid grids → NULL.
        let none: Option<f64> = conn
            .query_row("SELECT cw_grid_distance_km('FN31', NULL)", [], |r| r.get(0))
            .unwrap();
        assert!(none.is_none());
        let bad: Option<f64> = conn
            .query_row("SELECT cw_grid_distance_km('ZZ', 'FN31')", [], |r| r.get(0))
            .unwrap();
        assert!(bad.is_none());
    }

    #[test]
    fn cw_rst_s_extracts_strength_digit() {
        let conn = Connection::open_in_memory().unwrap();
        register_cw_rst_s(&conn).unwrap();
        let strength = |rst: &str| -> Option<i64> {
            conn.query_row("SELECT cw_rst_s(?)", [rst], |r| r.get(0)).unwrap()
        };
        // "599" → digits [5,9,9], drop first → 9.
        assert_eq!(strength("599"), Some(9));
        // "59" → digits [5,9], drop first → 9.
        assert_eq!(strength("59"), Some(9));
        // "5" is < 2 characters → NULL.
        assert_eq!(strength("5"), None);
        // "5N" has only one digit → NULL.
        assert_eq!(strength("5N"), None);
        // NULL → NULL.
        let none: Option<i64> = conn
            .query_row("SELECT cw_rst_s(NULL)", [], |r| r.get(0))
            .unwrap();
        assert!(none.is_none());
    }
}
