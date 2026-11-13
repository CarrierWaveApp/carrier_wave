//! Wire-compat check for the contest-definition parser: every production
//! definition served by activities.carrierwave.app (captured 2026-07-04 as
//! `tests/fixtures/contests/*.json`, full `GET /v1/contests/:id` envelopes)
//! must parse, cover every key the server sends, and round-trip through
//! serde without drift.

use std::collections::HashSet;
use std::fs;
use std::path::PathBuf;

use cw_domain::contest::model::{parse_definition, ContestSchedule};

fn fixture_definitions() -> Vec<(String, String)> {
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/contests");
    let mut fixtures: Vec<(String, String)> = fs::read_dir(&dir)
        .expect("fixtures dir")
        .filter_map(|entry| {
            let path = entry.ok()?.path();
            if path.extension()? != "json" {
                return None;
            }
            let raw = fs::read_to_string(&path).ok()?;
            let envelope: serde_json::Value = serde_json::from_str(&raw).ok()?;
            let definition = envelope.get("data")?.get("definition")?;
            Some((
                path.file_stem()?.to_string_lossy().to_string(),
                serde_json::to_string(definition).ok()?,
            ))
        })
        .collect();
    fixtures.sort();
    assert!(fixtures.len() >= 12, "expected the 12 captured production definitions");
    fixtures
}

#[test]
fn every_production_definition_parses() {
    for (id, json) in fixture_definitions() {
        let definition =
            parse_definition(&json).unwrap_or_else(|error| panic!("{id} failed to parse: {error}"));
        assert_eq!(definition.id, id, "definition id matches file name");
        assert!(!definition.name.is_empty(), "{id} has a name");
        assert!(!definition.scoring.phases.is_empty(), "{id} has scoring phases");
        assert!(!definition.exchange.received.is_empty(), "{id} has received exchange");
        assert!(!definition.dupe_rules.key.is_empty(), "{id} has a dupe key");
        match &definition.schedule {
            ContestSchedule::RecurringWeekly { sessions, .. } => {
                assert!(!sessions.is_empty(), "{id} has weekly sessions");
            }
            ContestSchedule::Annual(annual) => {
                assert!(!annual.rule.is_empty(), "{id} has an annual rule");
            }
            ContestSchedule::FixedDates { .. } => {}
        }
    }
}

#[test]
fn no_server_keys_are_silently_dropped() {
    // Guards against the server adding top-level fields we'd swallow: the
    // parser must know every key the production payloads carry.
    let known: HashSet<&str> = [
        "id", "name", "short_name", "sponsor", "modes", "bands", "data_dependencies",
        "schedule", "exchange", "dupe_rules", "scoring", "operating_constraints",
        "cabrillo", "categories", "overlay_categories", "experimental",
    ]
    .into();
    for (id, json) in fixture_definitions() {
        let value: serde_json::Value = serde_json::from_str(&json).expect("raw json");
        for key in value.as_object().expect("definition object").keys() {
            assert!(known.contains(key.as_str()), "{id} carries unknown key `{key}`");
        }
    }
}

#[test]
fn definitions_round_trip_through_serde() {
    for (id, json) in fixture_definitions() {
        let parsed = parse_definition(&json).expect("parse");
        let encoded = serde_json::to_string(&parsed).expect("encode");
        let reparsed = parse_definition(&encoded)
            .unwrap_or_else(|error| panic!("{id} re-parse failed: {error}"));
        assert_eq!(parsed, reparsed, "{id} drifts across encode/decode");
    }
}
