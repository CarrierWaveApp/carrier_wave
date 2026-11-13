//! Contest definition format (v0.3) — types, parser, and validator.
//!
//! See `docs/features/contest-definitions.md` for the canonical format
//! reference.
//!
//! This module exposes the data types ([`ContestDefinition`], [`Contest`],
//! [`Phase`], etc.) along with a semantic validation pass
//! ([`ContestDefinition::validate`]). Loading and validating a definition is
//! a two-step process:
//!
//! ```ignore
//! let def: ContestDefinition = serde_json::from_str(json)?;
//! let problems = def.validate();
//! if !def.is_valid() {
//!     // surface problems to the user
//! }
//! ```
//!
//! Scoring engine, dupe checking, and Cabrillo export are deferred to a
//! later pass.

#![allow(dead_code, unused_imports)]

pub mod cabrillo;
pub mod engine;
pub mod types;
pub mod validation;

pub use engine::{
    wpx_prefix, CallsignResolver, ContestSession, PhaseKind, PhaseResult, QsoRecord,
    ResolvedStation, ScoreSummary, ScoredQso, StationConfig,
};
pub use types::*;
pub use validation::{Severity, ValidationError};

#[cfg(test)]
mod tests {
    use super::*;

    fn load(name: &str) -> ContestDefinition {
        let path = format!("docs/examples/contests/{name}");
        let bytes = std::fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("failed to read {path}: {e}"));
        serde_json::from_str(&bytes)
            .unwrap_or_else(|e| panic!("failed to parse {path}: {e}"))
    }

    fn assert_valid(def: &ContestDefinition) {
        let problems = def.validate();
        let errors: Vec<_> = problems
            .iter()
            .filter(|p| p.severity == Severity::Error)
            .collect();
        if !errors.is_empty() {
            panic!(
                "expected no errors, got:\n{}",
                errors
                    .iter()
                    .map(|e| e.to_string())
                    .collect::<Vec<_>>()
                    .join("\n")
            );
        }
    }

    #[test]
    fn parses_cwt_example() {
        let def = load("cwt.json");
        assert_eq!(def.version, "0.3.0");
        assert_eq!(def.contests.len(), 1);
        let cwt = &def.contests[0];
        assert_eq!(cwt.id, "cwops-cwt");
        assert!(matches!(cwt.schedule, Schedule::RecurringWeekly { .. }));
        assert_valid(&def);
    }

    #[test]
    fn parses_sst_example() {
        let def = load("sst.json");
        assert_valid(&def);
    }

    #[test]
    fn parses_mst_example() {
        let def = load("mst.json");
        assert_valid(&def);
        // MST uses an auto-incrementing serial on the sent side.
        let mst = &def.contests[0];
        let serial = mst
            .exchange
            .sent
            .iter()
            .find(|f| f.field_type == "serial_number")
            .expect("MST has a serial_number sent field");
        assert_eq!(serial.auto_increment, Some(true));
    }

    #[test]
    fn parses_cqww_example() {
        let def = load("cqww-cw.json");
        assert_valid(&def);
        let cqww = &def.contests[0];
        assert!(matches!(cqww.schedule, Schedule::Annual { .. }));
        assert!(cqww.dupe_rules.zero_point_qsos_count_for_mults);
        assert_eq!(cqww.scoring.phases.len(), 4);
    }

    #[test]
    fn parses_combined_bundle() {
        let def = load("sample-bundle.json");
        assert_eq!(def.contests.len(), 4);
        assert_valid(&def);
    }

    #[test]
    fn round_trip_serialize() {
        let def = load("cqww-cw.json");
        let serialized = serde_json::to_string(&def).expect("serialize");
        let again: ContestDefinition =
            serde_json::from_str(&serialized).expect("re-deserialize");
        assert_eq!(again.contests.len(), def.contests.len());
        assert_valid(&again);
    }

    // ---------- negative cases ----------

    #[test]
    fn rejects_unknown_band() {
        let def = load("cwt.json");
        let mut def = def;
        def.contests[0].bands.push("99m".to_string());
        let problems = def.validate();
        assert!(problems
            .iter()
            .any(|p| p.severity == Severity::Error && p.path.contains("bands")));
    }

    #[test]
    fn rejects_unknown_mode() {
        let def = load("cwt.json");
        let mut def = def;
        def.contests[0].modes.push("MAGIC".to_string());
        let problems = def.validate();
        assert!(problems
            .iter()
            .any(|p| p.severity == Severity::Error && p.path.contains("modes")));
    }

    #[test]
    fn rejects_forward_phase_ref() {
        // Build a definition where the aggregate references a later phase.
        let json = r#"{
            "version": "0.3.0",
            "contests": [{
                "id": "bad",
                "name": "Bad",
                "modes": ["CW"],
                "bands": ["20m"],
                "schedule": {
                    "type": "recurring_weekly",
                    "sessions": [{ "day": "monday", "start_utc": "00:00", "duration_minutes": 60 }],
                    "session_scoring": "independent"
                },
                "exchange": { "sent": [], "received": [] },
                "dupe_rules": { "scope": "session", "key": ["callsign", "band"] },
                "scoring": {
                    "phases": [
                        { "id": "total", "type": "aggregate",
                          "operation": { "op": "ref", "phase": "qso_points" } },
                        { "id": "qso_points", "type": "per_qso",
                          "rules": [{ "value": 1 }] }
                    ]
                },
                "categories": [{ "id": "single_op", "label": "Single Op" }]
            }]
        }"#;
        let def: ContestDefinition = serde_json::from_str(json).unwrap();
        let problems = def.validate();
        assert!(
            problems
                .iter()
                .any(|p| p.severity == Severity::Error && p.message.contains("not defined earlier")),
            "expected forward-ref error, got {problems:?}"
        );
    }

    #[test]
    fn rejects_unknown_condition_field() {
        let json = r#"{
            "version": "0.3.0",
            "contests": [{
                "id": "bad",
                "name": "Bad",
                "modes": ["CW"],
                "bands": ["20m"],
                "schedule": {
                    "type": "recurring_weekly",
                    "sessions": [{ "day": "monday", "start_utc": "00:00", "duration_minutes": 60 }],
                    "session_scoring": "independent"
                },
                "exchange": { "sent": [], "received": [] },
                "dupe_rules": { "scope": "session", "key": ["callsign", "band"] },
                "scoring": {
                    "phases": [{
                        "id": "qso_points", "type": "per_qso",
                        "rules": [{
                            "conditions": [
                                { "field": "their_unicorn", "op": "eq", "value": "x" }
                            ],
                            "value": 1
                        }]
                    }]
                },
                "categories": [{ "id": "single_op", "label": "Single Op" }]
            }]
        }"#;
        let def: ContestDefinition = serde_json::from_str(json).unwrap();
        let problems = def.validate();
        assert!(problems
            .iter()
            .any(|p| p.severity == Severity::Error && p.message.contains("their_unicorn")));
    }

    #[test]
    fn rejects_received_serial_with_auto_increment() {
        let json = r#"{
            "version": "0.3.0",
            "contests": [{
                "id": "bad",
                "name": "Bad",
                "modes": ["CW"],
                "bands": ["20m"],
                "schedule": {
                    "type": "recurring_weekly",
                    "sessions": [{ "day": "monday", "start_utc": "00:00", "duration_minutes": 60 }],
                    "session_scoring": "independent"
                },
                "exchange": {
                    "sent": [],
                    "received": [
                        { "name": "serial", "type": "serial_number", "label": "S#",
                          "auto_increment": true }
                    ]
                },
                "dupe_rules": { "scope": "session", "key": ["callsign", "band"] },
                "scoring": {
                    "phases": [{ "id": "qp", "type": "per_qso", "rules": [{ "value": 1 }] }]
                },
                "categories": [{ "id": "single_op", "label": "Single Op" }]
            }]
        }"#;
        let def: ContestDefinition = serde_json::from_str(json).unwrap();
        let problems = def.validate();
        assert!(problems
            .iter()
            .any(|p| p.severity == Severity::Error && p.message.contains("sent side")));
    }

    // ---------- engine ----------

    use std::collections::HashMap;

    /// Test resolver mapping a few callsigns to known DXCC info.
    struct StubResolver(HashMap<String, ResolvedStation>);

    impl StubResolver {
        fn new() -> Self {
            let mut m = HashMap::new();
            m.insert(
                "K1XX".to_string(),
                ResolvedStation {
                    country: "K".to_string(),
                    continent: "NA".to_string(),
                    cq_zone: 5,
                    itu_zone: 8,
                    latitude: None,
                    longitude: None,
                    is_wae_entity: false,
                },
            );
            m.insert(
                "VE3ABC".to_string(),
                ResolvedStation {
                    country: "VE".to_string(),
                    continent: "NA".to_string(),
                    cq_zone: 4,
                    itu_zone: 4,
                    latitude: None,
                    longitude: None,
                    is_wae_entity: false,
                },
            );
            m.insert(
                "G3XYZ".to_string(),
                ResolvedStation {
                    country: "G".to_string(),
                    continent: "EU".to_string(),
                    cq_zone: 14,
                    itu_zone: 27,
                    latitude: None,
                    longitude: None,
                    is_wae_entity: false,
                },
            );
            m.insert(
                "JA1ABC".to_string(),
                ResolvedStation {
                    country: "JA".to_string(),
                    continent: "AS".to_string(),
                    cq_zone: 25,
                    itu_zone: 45,
                    latitude: None,
                    longitude: None,
                    is_wae_entity: false,
                },
            );
            Self(m)
        }
    }

    impl CallsignResolver for StubResolver {
        fn resolve(&self, callsign: &str) -> Option<ResolvedStation> {
            self.0.get(callsign).cloned()
        }
    }

    fn cqww_station() -> StationConfig {
        StationConfig {
            callsign: "W1AW".to_string(),
            country: "K".to_string(),
            continent: "NA".to_string(),
            cq_zone: 5,
            itu_zone: 8,
            ..Default::default()
        }
    }

    fn make_qso(call: &str, band: &str, mode: &str, recv: &[(&str, serde_json::Value)]) -> QsoRecord {
        let mut received = HashMap::new();
        for (k, v) in recv {
            received.insert(k.to_string(), v.clone());
        }
        QsoRecord {
            callsign: call.to_string(),
            band: band.to_string(),
            mode: mode.to_string(),
            timestamp_ms: 1_700_000_000_000,
            frequency_khz: None,
            received,
            sent_serial: None,
        }
    }

    #[test]
    fn cwt_simple_scoring() {
        let def = load("cwt.json");
        let contest = def.contests[0].clone();
        let mut session = ContestSession::new(contest, cqww_station(), StubResolver::new());

        // Three QSOs, two unique callsigns.
        let q1 = session.log_qso(make_qso(
            "K1XX",
            "20m",
            "CW",
            &[
                ("name", serde_json::json!("BOB")),
                ("identifier", serde_json::json!("123")),
            ],
        ));
        assert!(!q1.is_dupe);
        assert_eq!(q1.points, 1);

        let q2 = session.log_qso(make_qso(
            "VE3ABC",
            "20m",
            "CW",
            &[
                ("name", serde_json::json!("ANN")),
                ("identifier", serde_json::json!("999")),
            ],
        ));
        assert_eq!(q2.points, 1);

        // Same callsign and band → dupe.
        let q3 = session.log_qso(make_qso(
            "K1XX",
            "20m",
            "CW",
            &[
                ("name", serde_json::json!("BOB")),
                ("identifier", serde_json::json!("123")),
            ],
        ));
        assert!(q3.is_dupe);
        assert_eq!(q3.points, 0);

        let summary = session.summary();
        assert_eq!(summary.qso_count, 2);
        assert_eq!(summary.dupe_count, 1);
        // 2 QSOs * 2 mults = 4
        assert_eq!(summary.total, 4);
    }

    #[test]
    fn cqww_continent_scoring_and_mults() {
        let def = load("cqww-cw.json");
        let contest = def.contests[0].clone();
        let mut session = ContestSession::new(contest, cqww_station(), StubResolver::new());

        // Same country (K → K): 0 points but counts for mults.
        let q1 = session.log_qso(make_qso(
            "K1XX",
            "20m",
            "CW",
            &[("rst", serde_json::json!("599")), ("cq_zone", serde_json::json!(5))],
        ));
        assert_eq!(q1.points, 0);
        assert!(!q1.is_dupe);

        // Same continent NA (W → VE): 2 points.
        let q2 = session.log_qso(make_qso(
            "VE3ABC",
            "20m",
            "CW",
            &[("rst", serde_json::json!("599")), ("cq_zone", serde_json::json!(4))],
        ));
        assert_eq!(q2.points, 2);

        // Different continent (W → G): 3 points.
        let q3 = session.log_qso(make_qso(
            "G3XYZ",
            "20m",
            "CW",
            &[("rst", serde_json::json!("599")), ("cq_zone", serde_json::json!(14))],
        ));
        assert_eq!(q3.points, 3);

        // Different continent (W → JA): 3 points.
        let q4 = session.log_qso(make_qso(
            "JA1ABC",
            "20m",
            "CW",
            &[("rst", serde_json::json!("599")), ("cq_zone", serde_json::json!(25))],
        ));
        assert_eq!(q4.points, 3);

        let summary = session.summary();
        assert_eq!(summary.qso_count, 4);
        // qso_points: 0 + 2 + 3 + 3 = 8
        let qp = summary.phases.iter().find(|p| p.id == "qso_points").unwrap();
        assert_eq!(qp.value, 8);

        // Country mults on 20m: K, VE, G, JA = 4
        let mc = summary.phases.iter().find(|p| p.id == "mult_countries").unwrap();
        assert_eq!(mc.value, 4);
        // Zone mults on 20m: 5, 4, 14, 25 = 4
        let mz = summary.phases.iter().find(|p| p.id == "mult_zones").unwrap();
        assert_eq!(mz.value, 4);
        // total = qso_points * (countries + zones) = 8 * (4 + 4) = 64
        assert_eq!(summary.total, 64);
    }

    #[test]
    fn cqww_per_band_mults_separate() {
        let def = load("cqww-cw.json");
        let contest = def.contests[0].clone();
        let mut session = ContestSession::new(contest, cqww_station(), StubResolver::new());

        // Work G3XYZ on 20m and 15m → counts as 2 country mults total.
        session.log_qso(make_qso(
            "G3XYZ",
            "20m",
            "CW",
            &[("rst", serde_json::json!("599")), ("cq_zone", serde_json::json!(14))],
        ));
        session.log_qso(make_qso(
            "G3XYZ",
            "15m",
            "CW",
            &[("rst", serde_json::json!("599")), ("cq_zone", serde_json::json!(14))],
        ));

        let summary = session.summary();
        let mc = summary.phases.iter().find(|p| p.id == "mult_countries").unwrap();
        assert_eq!(mc.value, 2);
        assert_eq!(mc.per_band.get("20m").copied(), Some(1));
        assert_eq!(mc.per_band.get("15m").copied(), Some(1));
    }

    #[test]
    fn rescore_matches_incremental() {
        let def = load("cqww-cw.json");
        let contest = def.contests[0].clone();
        let mut s1 = ContestSession::new(contest.clone(), cqww_station(), StubResolver::new());
        let records = vec![
            make_qso("VE3ABC", "20m", "CW", &[("rst", serde_json::json!("599")), ("cq_zone", serde_json::json!(4))]),
            make_qso("G3XYZ", "20m", "CW", &[("rst", serde_json::json!("599")), ("cq_zone", serde_json::json!(14))]),
            make_qso("JA1ABC", "15m", "CW", &[("rst", serde_json::json!("599")), ("cq_zone", serde_json::json!(25))]),
        ];
        for r in &records {
            s1.log_qso(r.clone());
        }
        let inc = s1.summary();

        let mut s2 = ContestSession::new(contest, cqww_station(), StubResolver::new());
        s2.rescore(records);
        let resc = s2.summary();

        assert_eq!(inc.total, resc.total);
        assert_eq!(inc.qso_count, resc.qso_count);
    }

    #[test]
    fn mst_assigns_serial_numbers() {
        let def = load("mst.json");
        let contest = def.contests[0].clone();
        let mut session = ContestSession::new(contest, cqww_station(), StubResolver::new());

        let q1 = session.log_qso(make_qso(
            "K1XX",
            "20m",
            "CW",
            &[("name", serde_json::json!("BOB")), ("serial", serde_json::json!(1))],
        ));
        assert_eq!(q1.sent_serial, Some(1));

        let q2 = session.log_qso(make_qso(
            "VE3ABC",
            "20m",
            "CW",
            &[("name", serde_json::json!("ANN")), ("serial", serde_json::json!(1))],
        ));
        assert_eq!(q2.sent_serial, Some(2));

        // Dupe does not consume a serial number.
        let q3 = session.log_qso(make_qso(
            "K1XX",
            "20m",
            "CW",
            &[("name", serde_json::json!("BOB")), ("serial", serde_json::json!(1))],
        ));
        assert!(q3.is_dupe);
        assert_eq!(q3.sent_serial, None);

        let q4 = session.log_qso(make_qso(
            "G3XYZ",
            "20m",
            "CW",
            &[("name", serde_json::json!("JOE")), ("serial", serde_json::json!(1))],
        ));
        assert_eq!(q4.sent_serial, Some(3));
    }

    #[test]
    fn callsign_normalization() {
        assert_eq!(engine::normalize_callsign("k1abc"), "K1ABC");
        assert_eq!(engine::normalize_callsign("K1ABC/QRP"), "K1ABC");
        assert_eq!(engine::normalize_callsign("K1ABC/M"), "K1ABC");
        assert_eq!(engine::normalize_callsign("K1ABC/P"), "K1ABC");
        // /W1 is a different entity, do not strip.
        assert_eq!(engine::normalize_callsign("VE3XYZ/W1"), "VE3XYZ/W1");
    }

    #[test]
    fn wpx_prefix_extraction() {
        // Simple calls: up to and including the last digit.
        assert_eq!(engine::wpx_prefix("K4XL"), "K4");
        assert_eq!(engine::wpx_prefix("ve3xyz"), "VE3");
        assert_eq!(engine::wpx_prefix("4U1UN"), "4U1");
        assert_eq!(engine::wpx_prefix("OE25XYZ"), "OE25");
        // No digit anywhere: zero after the first two letters.
        assert_eq!(engine::wpx_prefix("RAEM"), "RA0");
        // Strippable suffixes don't change the prefix.
        assert_eq!(engine::wpx_prefix("K4XL/QRP"), "K4");
        assert_eq!(engine::wpx_prefix("G3XYZ/P"), "G3");
        // Portable host designator (letters) forms the prefix.
        assert_eq!(engine::wpx_prefix("KH6/N8BJQ"), "KH6");
        assert_eq!(engine::wpx_prefix("PA/N8BJQ"), "PA0");
        assert_eq!(engine::wpx_prefix("VP2E/K4XL"), "VP2");
        assert_eq!(engine::wpx_prefix("W1/K4XL"), "W1");
        // Single-number portable: home-call letters + the digit.
        assert_eq!(engine::wpx_prefix("N8BJQ/9"), "N9");
        assert_eq!(engine::wpx_prefix("WB8XYZ/4"), "WB4");
        assert_eq!(engine::wpx_prefix("9/N8BJQ"), "N9");
    }

    #[test]
    fn parses_cqwpx_cw_example() {
        let def = load("cqwpx-cw.json");
        assert_valid(&def);
        let wpx = &def.contests[0];
        assert!(matches!(wpx.schedule, Schedule::Annual { .. }));
        // qso_points + mult_prefixes + total
        assert_eq!(wpx.scoring.phases.len(), 3);
    }

    #[test]
    fn parses_cqwpx_ssb_example() {
        let def = load("cqwpx-ssb.json");
        assert_valid(&def);
    }

    #[test]
    fn cqwpx_prefix_mults_and_points() {
        let def = load("cqwpx-cw.json");
        let contest = def.contests[0].clone();
        // Station W1AW: K / NA / zone 5.
        let mut session = ContestSession::new(contest, cqww_station(), StubResolver::new());

        // Same country (K → K): 1 point, prefix K1.
        let q1 = session.log_qso(make_qso("K1XX", "20m", "CW", &[("rst", serde_json::json!("599"))]));
        assert_eq!(q1.points, 1);

        // NA → NA, different country, high band: 2 points, prefix VE3.
        let q2 = session.log_qso(make_qso("VE3ABC", "20m", "CW", &[("rst", serde_json::json!("599"))]));
        assert_eq!(q2.points, 2);

        // Different continent (EU), high band: 3 points, prefix G3.
        let q3 = session.log_qso(make_qso("G3XYZ", "20m", "CW", &[("rst", serde_json::json!("599"))]));
        assert_eq!(q3.points, 3);

        // Different continent (AS), low band: 6 points, prefix JA1.
        let q4 = session.log_qso(make_qso("JA1ABC", "40m", "CW", &[("rst", serde_json::json!("599"))]));
        assert_eq!(q4.points, 6);

        // Same station on a different band → not a dupe, scores QSO points
        // again, but its prefix (K1) is already counted (per-contest scope).
        let q5 = session.log_qso(make_qso("K1XX", "40m", "CW", &[("rst", serde_json::json!("599"))]));
        assert_eq!(q5.points, 1);

        let summary = session.summary();
        // Prefixes: K1, VE3, G3, JA1 → 4 unique.
        assert_eq!(summary.total, (1 + 2 + 3 + 6 + 1) * 4);
    }

    #[test]
    fn cabrillo_export_smoke() {
        let def = load("cwt.json");
        let contest = def.contests[0].clone();
        let mut session = ContestSession::new(contest, cqww_station(), StubResolver::new());
        session.log_qso(make_qso(
            "K1XX",
            "20m",
            "CW",
            &[("name", serde_json::json!("BOB")), ("identifier", serde_json::json!("123"))],
        ));
        let log = cabrillo::export(&session);
        assert!(log.starts_with("START-OF-LOG: 3.0\n"));
        assert!(log.contains("CONTEST: CWT"));
        assert!(log.contains("CALLSIGN: W1AW"));
        assert!(log.contains("QSO:"));
        assert!(log.contains("K1XX"));
        assert!(log.trim_end().ends_with("END-OF-LOG:"));
    }

    #[test]
    fn warns_when_last_rule_has_conditions() {
        let json = r#"{
            "version": "0.3.0",
            "contests": [{
                "id": "warn",
                "name": "Warn",
                "modes": ["CW"],
                "bands": ["20m"],
                "schedule": {
                    "type": "recurring_weekly",
                    "sessions": [{ "day": "monday", "start_utc": "00:00", "duration_minutes": 60 }],
                    "session_scoring": "independent"
                },
                "exchange": { "sent": [], "received": [] },
                "dupe_rules": { "scope": "session", "key": ["callsign", "band"] },
                "scoring": {
                    "phases": [{
                        "id": "qp", "type": "per_qso", "rules": [{
                            "conditions": [
                                { "field": "band", "op": "eq", "value": "20m" }
                            ],
                            "value": 1
                        }]
                    }]
                },
                "categories": [{ "id": "single_op", "label": "Single Op" }]
            }]
        }"#;
        let def: ContestDefinition = serde_json::from_str(json).unwrap();
        let problems = def.validate();
        assert!(problems
            .iter()
            .any(|p| p.severity == Severity::Warning && p.message.contains("silently score 0")));
    }
}
