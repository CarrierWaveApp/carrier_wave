//! Parity gate: the in-memory `cw_domain::query::matches` evaluator must select
//! exactly the same QSOs as the SQL `compile_where` lowering, over a diverse
//! fixture and a broad query battery. This is the acceptance bar for the browser
//! logbook viewer reusing the evaluator — if the two ever diverge, filtering in
//! the web viewer would differ from the app.
//!
//! Service-presence filters (`synced:`/`pending:`) are excluded: they require a
//! `service_presence` join the in-memory evaluator intentionally doesn't model.

use cw_domain::query::{matches, parse, QueryRow};
use cw_store::query::compile_where;
use cw_store::query::sql::{register_cw_lower, SqlValue};
use rusqlite::Connection;

#[derive(Clone, Default)]
struct TestQso {
    id: &'static str,
    callsign: Option<&'static str>,
    band: Option<&'static str>,
    mode: Option<&'static str>,
    my_callsign: Option<&'static str>,
    park: Option<&'static str>,
    sota_ref: Option<&'static str>,
    their_grid: Option<&'static str>,
    state: Option<&'static str>,
    country: Option<&'static str>,
    name: Option<&'static str>,
    qth: Option<&'static str>,
    notes: Option<&'static str>,
    my_grid: Option<&'static str>,
    freq_khz: Option<f64>,
    dxcc: Option<f64>,
    power: Option<f64>,
    qso_date: i64,
    qrz_confirmed: bool,
    lotw_confirmed: bool,
    import_source: &'static str,
}

impl QueryRow for TestQso {
    fn callsign(&self) -> Option<&str> {
        self.callsign
    }
    fn band(&self) -> Option<&str> {
        self.band
    }
    fn mode(&self) -> Option<&str> {
        self.mode
    }
    fn my_callsign(&self) -> Option<&str> {
        self.my_callsign
    }
    fn park(&self) -> Option<&str> {
        self.park
    }
    fn sota_ref(&self) -> Option<&str> {
        self.sota_ref
    }
    fn their_grid(&self) -> Option<&str> {
        self.their_grid
    }
    fn state(&self) -> Option<&str> {
        self.state
    }
    fn country(&self) -> Option<&str> {
        self.country
    }
    fn name(&self) -> Option<&str> {
        self.name
    }
    fn qth(&self) -> Option<&str> {
        self.qth
    }
    fn notes(&self) -> Option<&str> {
        self.notes
    }
    fn my_grid(&self) -> Option<&str> {
        self.my_grid
    }
    fn frequency_khz(&self) -> Option<f64> {
        self.freq_khz
    }
    fn dxcc(&self) -> Option<f64> {
        self.dxcc
    }
    fn power(&self) -> Option<f64> {
        self.power
    }
    fn qso_date(&self) -> i64 {
        self.qso_date
    }
    fn qrz_confirmed(&self) -> bool {
        self.qrz_confirmed
    }
    fn lotw_confirmed(&self) -> bool {
        self.lotw_confirmed
    }
    fn import_source(&self) -> &str {
        self.import_source
    }
}

fn fixture() -> Vec<TestQso> {
    // 2024-06-15 12:00:00 UTC and neighbours, plus a very old + very recent row.
    let base = 1_718_452_800; // 2024-06-15T12:00:00Z
    let day = 86_400;
    vec![
        TestQso {
            id: "a",
            callsign: Some("W1AW"),
            band: Some("20m"),
            mode: Some("FT8"),
            my_callsign: Some("W6JY"),
            park: Some("US-1234"),
            their_grid: Some("FN31"),
            state: Some("CT"),
            country: Some("United States"),
            name: Some("Hiram"),
            freq_khz: Some(14074.0),
            dxcc: Some(291.0),
            power: Some(100.0),
            qso_date: base,
            lotw_confirmed: true,
            import_source: "logger",
            ..Default::default()
        },
        TestQso {
            id: "b",
            callsign: Some("K6ABC"),
            band: Some("40m"),
            mode: Some("CW"),
            my_callsign: Some("W6JY"),
            their_grid: Some("CM87"),
            state: Some("CA"),
            country: Some("United States"),
            notes: Some("nice POTA chat"),
            freq_khz: Some(7030.0),
            dxcc: Some(291.0),
            power: Some(5.0),
            qso_date: base - 10 * day,
            qrz_confirmed: true,
            import_source: "qrz",
            ..Default::default()
        },
        TestQso {
            id: "c",
            callsign: Some("VK3XYZ"),
            band: Some("20m"),
            mode: Some("SSB"),
            park: Some("K-5678"),
            sota_ref: Some("W6/CT-001"),
            their_grid: Some("QF22"),
            country: Some("Australia"),
            freq_khz: Some(14250.0),
            dxcc: Some(150.0),
            power: Some(1000.0),
            qso_date: base + 5 * day,
            import_source: "adif",
            ..Default::default()
        },
        TestQso {
            id: "d",
            callsign: Some("w1aw"), // lowercase to exercise case-insensitivity
            band: Some("80m"),
            mode: Some("FT8"),
            notes: Some("nighttime DX"),
            qso_date: base - 400 * day,
            import_source: "adif",
            ..Default::default()
        },
        TestQso {
            // Mostly-null row: exercises COALESCE(_, 0) + negation-includes-null.
            id: "e",
            callsign: Some("N0CALL"),
            qso_date: base + 1,
            import_source: "manual",
            ..Default::default()
        },
    ]
}

fn create_and_insert(conn: &Connection, rows: &[TestQso]) {
    conn.execute_batch(
        "CREATE TABLE qso (
            id TEXT PRIMARY KEY,
            callsign TEXT, band TEXT, mode TEXT, my_callsign TEXT,
            park TEXT, sota_ref TEXT, their_grid TEXT, state TEXT, country TEXT,
            name TEXT, qth TEXT, notes TEXT, my_grid TEXT,
            freq_khz REAL, dxcc REAL, power REAL, qso_date INTEGER,
            qrz_confirmed INTEGER, lotw_confirmed INTEGER, import_source_raw_value TEXT
        );",
    )
    .unwrap();
    for r in rows {
        conn.execute(
            "INSERT INTO qso VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17,?18,?19,?20,?21)",
            rusqlite::params![
                r.id, r.callsign, r.band, r.mode, r.my_callsign, r.park, r.sota_ref,
                r.their_grid, r.state, r.country, r.name, r.qth, r.notes, r.my_grid,
                r.freq_khz, r.dxcc, r.power, r.qso_date,
                r.qrz_confirmed as i64, r.lotw_confirmed as i64, r.import_source,
            ],
        )
        .unwrap();
    }
}

fn sql_ids(conn: &Connection, query: &str) -> Vec<String> {
    let parsed = parse(query).unwrap();
    let (where_sql, params) = compile_where(&parsed);
    let boxed: Vec<Box<dyn rusqlite::ToSql>> = params
        .iter()
        .map(|p: &SqlValue| p.to_sql_param())
        .collect();
    let refs: Vec<&dyn rusqlite::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
    let mut stmt = conn
        .prepare(&format!("SELECT id FROM qso WHERE {where_sql} ORDER BY id"))
        .unwrap();
    stmt.query_map(refs.as_slice(), |row| row.get::<_, String>(0))
        .unwrap()
        .map(Result::unwrap)
        .collect()
}

fn eval_ids(rows: &[TestQso], query: &str) -> Vec<String> {
    let parsed = parse(query).unwrap();
    let mut ids: Vec<String> = rows
        .iter()
        .filter(|r| matches(&parsed, *r))
        .map(|r| r.id.to_string())
        .collect();
    ids.sort();
    ids
}

#[test]
fn evaluator_matches_sql_compiler_across_battery() {
    let conn = Connection::open_in_memory().unwrap();
    register_cw_lower(&conn).unwrap();
    let rows = fixture();
    create_and_insert(&conn, &rows);

    let battery = [
        // bare + callsign
        "",
        "W1",
        "w1aw",
        "call:W1AW",
        "call:k6abc",
        "*aw*",
        "*abc",
        "N0*",
        // band / mode / geo
        "band:20m",
        "band:20m mode:ft8",
        "mode:CW",
        "state:CA",
        "state:ca",
        "country:*states*",
        "grid:FN31",
        "park:K-*",
        "park:US-1234",
        "sota:W6*",
        // numeric
        "freq:>14",
        "freq:>14000",
        "freq:14.074",
        "power:>100",
        "power:<10",
        "dxcc:291",
        // dates (absolute + relative; both paths share resolve())
        "after:2024-01-01",
        "before:2025-01-01",
        "date:2024-06",
        "after:2000-01-01 before:2100-01-01",
        // status / source
        "confirmed:yes",
        "confirmed:no",
        "confirmed:lotw",
        "confirmed:qrz",
        "source:qrz",
        "source:manual",
        // boolean logic
        "-mode:FT8",
        "-park:US-1234",
        "band:20m | band:40m",
        "W1AW | K6ABC",
        "band:20m -mode:SSB",
        "notes:*pota*",
    ];

    for query in battery {
        let expected = sql_ids(&conn, query);
        let actual = eval_ids(&rows, query);
        assert_eq!(actual, expected, "mismatch for query {query:?}");
    }
}
