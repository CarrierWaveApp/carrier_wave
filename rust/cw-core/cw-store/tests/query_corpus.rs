//! Shared corpus + fixture parity test.
//!
//! Loads `tests/fixtures/query_fixture.json` (QSO + ServicePresence rows) into
//! an in-memory Store, then for every query string in
//! `tests/fixtures/query_corpus.json`:
//!   - parses it with `cw_domain::query::parse`
//!   - runs `fetch_qsos_query` and `count_query`
//!   - asserts page and count are consistent
//!   - compares the ordered id list to the golden in
//!     `tests/fixtures/query_corpus_expected.json`
//!
//! Generation mode: if the expected file is empty (`{}`) the test writes the
//! actual results as the new golden and passes. On all subsequent runs it
//! validates against that golden. This lets us generate the golden from a
//! single `cargo test` run then commit it.

use cw_store::{
    qso::Qso,
    service_presence::ServicePresence,
    Store,
};
use serde::Deserialize;
use std::{
    collections::BTreeMap,
    fs,
    path::PathBuf,
};

// --------------------------------------------------------------------------
// JSON schema types
// --------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
struct Fixture {
    qsos: Vec<QsoRow>,
    service_presence: Vec<SpRow>,
}

/// Mirrors Qso field-for-field with JSON-friendly bool/Option types.
/// Fields with `_comment` keys in the JSON are silently skipped by serde.
#[derive(Debug, Deserialize)]
struct QsoRow {
    id: String,
    callsign: String,
    band: Option<String>,
    mode: Option<String>,
    freq_khz: Option<f64>,
    qso_date: i64,
    my_grid: Option<String>,
    their_grid: Option<String>,
    rst_sent: Option<String>,
    rst_rcvd: Option<String>,
    my_callsign: Option<String>,
    park: Option<String>,
    their_park: Option<String>,
    notes: Option<String>,
    notes_user_authored: bool,
    spot_comments_data: Option<Vec<u8>>,
    callsign_change_note: Option<String>,
    original_callsign: Option<String>,
    import_source_raw_value: String,
    imported_at: i64,
    modified_at: Option<i64>,
    raw_adif: Option<String>,
    name: Option<String>,
    qth: Option<String>,
    state: Option<String>,
    country: Option<String>,
    power: Option<i64>,
    my_rig: Option<String>,
    station_profile_name: Option<String>,
    sota_ref: Option<String>,
    wwff_ref: Option<String>,
    aoa_code: Option<String>,
    qrz_log_id: Option<String>,
    qrz_confirmed: bool,
    lotw_confirmed_date: Option<i64>,
    lotw_confirmed: bool,
    dxcc: Option<i64>,
    their_license_class: Option<String>,
    contest_name: Option<String>,
    contest_serial_sent: Option<i64>,
    contest_serial_received: Option<i64>,
    contest_exchange_sent: Option<String>,
    contest_exchange_received: Option<String>,
    is_hidden: bool,
    is_activity_log_qso: bool,
    station_callsign: Option<String>,
    logging_session_id: Option<String>,
    dirty: bool,
}

impl From<QsoRow> for Qso {
    fn from(r: QsoRow) -> Self {
        Qso {
            id: r.id,
            callsign: r.callsign,
            band: r.band,
            mode: r.mode,
            freq_khz: r.freq_khz,
            qso_date: r.qso_date,
            my_grid: r.my_grid,
            their_grid: r.their_grid,
            rst_sent: r.rst_sent,
            rst_rcvd: r.rst_rcvd,
            my_callsign: r.my_callsign,
            park: r.park,
            their_park: r.their_park,
            notes: r.notes,
            notes_user_authored: r.notes_user_authored,
            spot_comments_data: r.spot_comments_data,
            callsign_change_note: r.callsign_change_note,
            original_callsign: r.original_callsign,
            import_source_raw_value: r.import_source_raw_value,
            imported_at: r.imported_at,
            modified_at: r.modified_at,
            raw_adif: r.raw_adif,
            name: r.name,
            qth: r.qth,
            state: r.state,
            country: r.country,
            power: r.power,
            my_rig: r.my_rig,
            station_profile_name: r.station_profile_name,
            sota_ref: r.sota_ref,
            wwff_ref: r.wwff_ref,
            aoa_code: r.aoa_code,
            qrz_log_id: r.qrz_log_id,
            qrz_confirmed: r.qrz_confirmed,
            lotw_confirmed_date: r.lotw_confirmed_date,
            lotw_confirmed: r.lotw_confirmed,
            dxcc: r.dxcc,
            their_license_class: r.their_license_class,
            contest_name: r.contest_name,
            contest_serial_sent: r.contest_serial_sent,
            contest_serial_received: r.contest_serial_received,
            contest_exchange_sent: r.contest_exchange_sent,
            contest_exchange_received: r.contest_exchange_received,
            is_hidden: r.is_hidden,
            is_activity_log_qso: r.is_activity_log_qso,
            station_callsign: r.station_callsign,
            logging_session_id: r.logging_session_id,
            dirty: r.dirty,
            sat_name: None,
            prop_mode: None,
        }
    }
}

#[derive(Debug, Deserialize)]
struct SpRow {
    id: String,
    qso_id: Option<String>,
    service_type_raw_value: String,
    is_present: bool,
    needs_upload: bool,
    upload_rejected: bool,
    rejected_at_build: Option<String>,
    is_submitted: bool,
    last_confirmed_at: Option<i64>,
    park_reference: Option<String>,
    cloud_dirty_flag: bool,
}

impl From<SpRow> for ServicePresence {
    fn from(r: SpRow) -> Self {
        ServicePresence {
            id: r.id,
            service_type_raw_value: r.service_type_raw_value,
            is_present: r.is_present,
            needs_upload: r.needs_upload,
            upload_rejected: r.upload_rejected,
            rejected_at_build: r.rejected_at_build,
            is_submitted: r.is_submitted,
            last_confirmed_at: r.last_confirmed_at,
            park_reference: r.park_reference,
            cloud_dirty_flag: r.cloud_dirty_flag,
            qso_id: r.qso_id,
        }
    }
}

#[derive(Debug, Deserialize)]
struct Corpus {
    queries: Vec<CorpusEntry>,
}

#[derive(Debug, Deserialize)]
struct CorpusEntry {
    id: String,
    query: String,
}

// Golden: map from query id → ordered list of QSO ids.
type Golden = BTreeMap<String, Vec<String>>;

// --------------------------------------------------------------------------
// Helpers
// --------------------------------------------------------------------------

fn fixtures_dir() -> PathBuf {
    // `CARGO_MANIFEST_DIR` is set by Cargo at test time to the crate root.
    let manifest = std::env::var("CARGO_MANIFEST_DIR")
        .expect("CARGO_MANIFEST_DIR not set");
    PathBuf::from(manifest).join("tests").join("fixtures")
}

fn load_store() -> Store {
    let fix_path = fixtures_dir().join("query_fixture.json");
    let json = fs::read_to_string(&fix_path)
        .unwrap_or_else(|e| panic!("Cannot read {}: {e}", fix_path.display()));
    let fixture: Fixture = serde_json::from_str(&json)
        .unwrap_or_else(|e| panic!("Cannot parse query_fixture.json: {e}"));

    let store = Store::open_in_memory("corpus_key").expect("open_in_memory failed");
    for row in fixture.qsos {
        store.upsert_qso(&row.into()).expect("upsert_qso failed");
    }
    for row in fixture.service_presence {
        store.upsert_service_presence(&row.into()).expect("upsert_service_presence failed");
    }
    store
}

/// Re-parse the fixture file (independent of `load_store`, which consumes it)
/// so a test can compare projected presence against the source-of-truth rows.
fn load_fixture() -> Fixture {
    let fix_path = fixtures_dir().join("query_fixture.json");
    let json = fs::read_to_string(&fix_path)
        .unwrap_or_else(|e| panic!("Cannot read {}: {e}", fix_path.display()));
    serde_json::from_str(&json)
        .unwrap_or_else(|e| panic!("Cannot parse query_fixture.json: {e}"))
}

// --------------------------------------------------------------------------
// The test
// --------------------------------------------------------------------------

#[test]
fn query_corpus_parity() {
    let store = load_store();

    let corpus_path = fixtures_dir().join("query_corpus.json");
    let corpus_json = fs::read_to_string(&corpus_path)
        .unwrap_or_else(|e| panic!("Cannot read {}: {e}", corpus_path.display()));
    let corpus: Corpus = serde_json::from_str(&corpus_json)
        .unwrap_or_else(|e| panic!("Cannot parse query_corpus.json: {e}"));

    let expected_path = fixtures_dir().join("query_corpus_expected.json");
    let expected_json = fs::read_to_string(&expected_path)
        .unwrap_or_else(|e| panic!("Cannot read {}: {e}", expected_path.display()));
    let expected: Golden = serde_json::from_str(&expected_json)
        .unwrap_or_else(|e| panic!("Cannot parse query_corpus_expected.json: {e}"));

    let generate_mode = expected.is_empty();
    if generate_mode {
        eprintln!("[query_corpus] expected is empty — generating golden");
    }

    let mut actual: Golden = BTreeMap::new();

    for entry in &corpus.queries {
        let parsed = cw_domain::query::parse(&entry.query)
            .unwrap_or_else(|e| panic!("parse({:?}) failed: {e}", entry.query));

        let rows = store.fetch_qsos_query(&parsed, 1000, 0)
            .unwrap_or_else(|e| panic!("fetch_qsos_query({:?}) failed: {e}", entry.query));
        let count = store.count_query(&parsed)
            .unwrap_or_else(|e| panic!("count_query({:?}) failed: {e}", entry.query));

        let ids: Vec<String> = rows.iter().map(|r| r.id.clone()).collect();

        // Page / count must always be consistent.
        assert_eq!(
            ids.len() as i64, count,
            "page/count mismatch for query {:?} (id={:?}): page={} count={}",
            entry.query, entry.id, ids.len(), count
        );

        actual.insert(entry.id.clone(), ids);
    }

    if generate_mode {
        // Write golden and pass — caller must commit the generated file.
        let out = serde_json::to_string_pretty(&actual).expect("serialise golden");
        fs::write(&expected_path, out).unwrap_or_else(|e| {
            panic!("Cannot write {}: {e}", expected_path.display())
        });
        eprintln!("[query_corpus] golden written to {}", expected_path.display());
        eprintln!("[query_corpus] Re-run to validate against golden.");
        return;
    }

    // Validation mode: compare actual vs expected entry by entry for clear diffs.
    let mut failures = Vec::new();
    for entry in &corpus.queries {
        let act = actual.get(&entry.id).expect("missing actual entry");
        match expected.get(&entry.id) {
            None => failures.push(format!(
                "  [{}] {:?} — no expected entry (add it or regenerate golden)",
                entry.id, entry.query
            )),
            Some(exp) if exp != act => failures.push(format!(
                "  [{}] {:?}\n    expected: {exp:?}\n    actual:   {act:?}",
                entry.id, entry.query
            )),
            _ => {}
        }
    }
    // Also flag any expected entries no longer in corpus (stale keys).
    for key in expected.keys() {
        if !corpus.queries.iter().any(|e| &e.id == key) {
            failures.push(format!("  [{key}] stale key in expected — not in corpus"));
        }
    }

    if !failures.is_empty() {
        panic!(
            "query_corpus_parity: {} failure(s):\n{}",
            failures.len(),
            failures.join("\n")
        );
    }
}

/// The presence projection (`fetch_service_presences_for_qsos`) used by the
/// Logbook query page must, over the full corpus fixture, return exactly the
/// fixture's presence rows grouped by `qso_id`. This guards the batched
/// `WHERE qso_id IN (...)` grouping the FFI layer relies on for the badges.
#[test]
fn presence_projection_matches_fixture() {
    let fixture = load_fixture();
    let store = load_store();

    // Source of truth: presence ids grouped by qso_id, from the fixture.
    let mut expected: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for sp in &fixture.service_presence {
        if let Some(qso_id) = &sp.qso_id {
            expected.entry(qso_id.clone()).or_default().push(sp.id.clone());
        }
    }
    for ids in expected.values_mut() {
        ids.sort();
    }

    let all_qso_ids: Vec<String> = fixture.qsos.iter().map(|q| q.id.clone()).collect();
    let projected = store
        .fetch_service_presences_for_qsos(&all_qso_ids)
        .expect("fetch_service_presences_for_qsos failed");

    let mut actual: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for sp in projected {
        if let Some(qso_id) = sp.qso_id {
            actual.entry(qso_id).or_default().push(sp.id);
        }
    }
    for ids in actual.values_mut() {
        ids.sort();
    }

    assert_eq!(actual, expected, "projected presence grouping diverged from fixture");
}
