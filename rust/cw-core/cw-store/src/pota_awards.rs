//! POTA activator awards aggregate — faithful port of `POTAAwardsActor` +
//! `POTAAwardsComputation` (iOS). Unlike the SQL-only aggregates in
//! `analytics.rs`, the award metrics need per-activation dedup, two-fer park
//! splitting, per-park band sets, and a park → US-state resolution that joins the
//! `pota_park` reference table with a Maidenhead grid fallback — none of which is
//! a flat `GROUP BY`. So this fetches the minimal park-QSO columns once and folds
//! in Rust, mirroring the Swift actor's grouping/order exactly.
//!
//! Order parity: the Swift actor fetches `timestamp DESC`, so the per-activation
//! "first" QSO (used for the DXCC entity and the grid fallback) is the newest. We
//! fetch `qso_date DESC, id DESC` and preserve encounter order per group so
//! `first` matches. The raw park-QSO totals (kilo counts, park-to-park,
//! `metadataExcluded`) include metadata pseudo-modes, exactly as the actor's
//! `allSnapshots` does; activations exclude them.

use std::collections::{HashMap, HashSet};

use crate::query::compile_where;
use crate::Result;
use crate::Store;
use cw_domain::park_reference;
use cw_domain::query::ParsedQuery;
use cw_domain::us_grid_state::grid_to_us_state;
use serde::{Deserialize, Serialize};

/// Minimum unique QSOs for an activation to count toward awards. Mirrors
/// `POTARules.activationMinQSOs`.
const ACTIVATION_MIN_QSOS: i64 = 10;
/// Kilo threshold (QSOs at a single park). Mirrors the Swift `1_000`.
const KILO_THRESHOLD: i64 = 1_000;
/// "Near kilo" lower bound (900–999). Mirrors `1_000 - nearKiloThreshold (100)`.
const NEAR_KILO_LOWER: i64 = KILO_THRESHOLD - 100;
/// LaPorta N1CC band threshold: parks with this many distinct bands.
const LA_PORTA_BANDS: usize = 10;
/// LaPorta award: this many qualifying parks earns it.
const LA_PORTA_PARKS: usize = 10;
/// Six Pack: 6m QSOs per park and qualifying-park count.
const SIX_PACK_MIN_6M: usize = 10;
const SIX_PACK_PARKS: usize = 6;

/// Metadata pseudo-modes excluded from activations (but still counted in the
/// raw park-QSO totals, mirroring the actor's `allSnapshots`). Delegates to the
/// shared `cw_domain::mode::METADATA_MODES` so PoLo's TODO/START/BREAK markers
/// are excluded too (CAR-278).
fn is_metadata_mode(mode: &str) -> bool {
    cw_domain::mode::is_metadata_mode(mode)
}

/// Country prefix of a park reference ("US" from "US-1234"). Mirrors
/// `POTAPark.countryPrefix`.
fn country_prefix(park_ref: &str) -> &str {
    park_ref.split('-').next().unwrap_or("")
}

/// `true` when the park's prefix is a US prefix WAS counts ("US" or "K").
fn is_us_prefix(park_ref: &str) -> bool {
    matches!(country_prefix(park_ref), "US" | "K")
}

/// State abbreviations from a `location_desc` ("US-WY,US-MT" → ["WY","MT"]).
/// Mirrors `POTAPark.states` then `statesForPark`'s non-empty filter.
fn states_from_location_desc(location_desc: &str) -> Vec<String> {
    location_desc
        .split(',')
        .filter_map(|loc| {
            let trimmed = loc.trim();
            let mut parts = trimmed.split('-');
            let _prefix = parts.next();
            parts.next().map(|st| st.to_string())
        })
        .filter(|st| !st.is_empty())
        .collect()
}

/// A park approaching the 1,000-QSO kilo threshold. Mirrors `NearKiloPark`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NearKiloPark {
    pub reference: String,
    pub qso_count: i64,
}

/// POTA activator awards progress. Mirrors `POTAAwardsProgress`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PotaAwards {
    pub unique_parks_count: i64,
    pub dx_entities_count: i64,
    /// Valid-activation US states, sorted for determinism (Swift uses a `Set`).
    pub states_activated: Vec<String>,
    pub rover_max_parks: i64,
    pub repeat_offender_max_count: i64,
    pub park_to_park_count: i64,
    /// Parks with 1000+ QSOs, sorted ascending.
    pub kilo_parks: Vec<String>,
    /// Parks in 900–999, sorted by QSO count descending (ties by reference asc).
    pub near_kilo_parks: Vec<NearKiloPark>,
    pub la_porta_earned: bool,
    pub la_porta_qualifying_parks: i64,
    pub six_pack_earned: bool,
    pub best_single_park_total: i64,
    pub total_park_qsos: i64,
    pub metadata_excluded: i64,
    pub total_activation_groups: i64,
    pub valid_activation_groups: i64,
}

/// One park QSO, the columns the awards fold needs. Mirrors the actor's
/// private `QSOSnapshot`.
struct ParkSnapshot {
    callsign: String,
    band: String,
    mode: String,
    /// Operator callsign, uppercased (group key component).
    my_callsign: String,
    my_grid: Option<String>,
    /// Full (possibly multi-park) reference, uppercased.
    park_reference: String,
    their_park: Option<String>,
    dxcc: Option<i64>,
    /// UTC day "yyyy-MM-dd" (group key component).
    day: String,
}

/// An activation group: park × operator × UTC-day. Mirrors `ActivationGroup`.
/// `qsos` are indices into the snapshot vec, in fetch (newest-first) order.
struct Activation {
    /// Uppercased full park reference (the group key's park component).
    park_reference: String,
    utc_date: String,
    qsos: Vec<usize>,
}

impl Activation {
    /// Unique QSOs deduped by `callsign|band|mode|park`. Mirrors
    /// `ActivationGroup.uniqueQSOCount` (band/mode raw, callsign/park uppercased).
    fn unique_qso_count(&self, snaps: &[ParkSnapshot]) -> i64 {
        let mut seen = HashSet::new();
        for &idx in &self.qsos {
            let snap = &snaps[idx];
            seen.insert(format!(
                "{}|{}|{}|{}",
                snap.callsign.to_uppercase(),
                snap.band,
                snap.mode,
                self.park_reference
            ));
        }
        seen.len() as i64
    }

    fn is_valid(&self, snaps: &[ParkSnapshot]) -> bool {
        self.unique_qso_count(snaps) >= ACTIVATION_MIN_QSOS
    }

    /// Split individual park references (two-fer aware), uppercased.
    fn split_parks(&self) -> Vec<String> {
        park_reference::split(&self.park_reference)
    }
}

impl Store {
    /// POTA activator awards progress over non-hidden park QSOs matching `query`.
    /// The app passes an empty query (all park QSOs); the parameter exists for
    /// symmetry with the other aggregates.
    pub fn pota_awards(&self, query: &ParsedQuery) -> Result<PotaAwards> {
        let snaps = self.fetch_park_snapshots(query)?;
        let activations = group_activations(&snaps);
        let location_descs = self.fetch_location_descs(&activations, &snaps)?;
        Ok(compute_awards(&snaps, &activations, &location_descs))
    }

    /// Fetch park-QSO columns the fold needs, newest first. No metadata exclusion —
    /// the actor's `allSnapshots` includes metadata for the raw totals.
    fn fetch_park_snapshots(&self, query: &ParsedQuery) -> Result<Vec<ParkSnapshot>> {
        let (where_sql, values) = compile_where(query);
        let sql = format!(
            "SELECT callsign, COALESCE(band, ''), COALESCE(mode, ''), \
                    UPPER(COALESCE(my_callsign, '')), my_grid, UPPER(park), their_park, dxcc, \
                    strftime('%Y-%m-%d', qso_date, 'unixepoch') \
             FROM qso \
             WHERE is_hidden = 0 AND park IS NOT NULL AND park <> '' AND ({where_sql}) \
             ORDER BY qso_date DESC, id DESC"
        );
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map(refs.as_slice(), |row| {
            Ok(ParkSnapshot {
                callsign: row.get(0)?,
                band: row.get(1)?,
                mode: row.get(2)?,
                my_callsign: row.get(3)?,
                my_grid: row.get(4)?,
                park_reference: row.get(5)?,
                their_park: row.get(6)?,
                dxcc: row.get(7)?,
                day: row.get(8)?,
            })
        })?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Map of `pota_park.reference` → `location_desc` for every individual park in
    /// a valid activation. One batched `IN` query; absent parks fall to the grid path.
    fn fetch_location_descs(
        &self,
        activations: &[Activation],
        snaps: &[ParkSnapshot],
    ) -> Result<HashMap<String, String>> {
        let mut refs: HashSet<String> = HashSet::new();
        for activation in activations {
            if activation.is_valid(snaps) {
                for park in activation.split_parks() {
                    refs.insert(park);
                }
            }
        }
        if refs.is_empty() {
            return Ok(HashMap::new());
        }
        let refs: Vec<String> = refs.into_iter().collect();
        let placeholders = vec!["?"; refs.len()].join(", ");
        let sql = format!(
            "SELECT reference, location_desc FROM pota_park WHERE reference IN ({placeholders})"
        );
        let params: Vec<&dyn rusqlite::types::ToSql> =
            refs.iter().map(|r| r as &dyn rusqlite::types::ToSql).collect();
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map(params.as_slice(), |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?;
        let mut out = HashMap::new();
        for row in rows {
            let (reference, location_desc) = row?;
            out.insert(reference, location_desc);
        }
        Ok(out)
    }
}

/// Group metadata-filtered snapshots into activations (park × operator × UTC-day),
/// preserving fetch order per group. Mirrors `POTAAwardsActor.groupActivations`.
fn group_activations(snaps: &[ParkSnapshot]) -> Vec<Activation> {
    let mut order: Vec<String> = Vec::new();
    let mut groups: HashMap<String, Activation> = HashMap::new();
    for (idx, snap) in snaps.iter().enumerate() {
        if is_metadata_mode(&snap.mode) {
            continue;
        }
        let key = format!("{}|{}|{}", snap.park_reference, snap.my_callsign, snap.day);
        let activation = groups.entry(key.clone()).or_insert_with(|| {
            order.push(key.clone());
            Activation {
                park_reference: snap.park_reference.clone(),
                utc_date: snap.day.clone(),
                qsos: Vec::new(),
            }
        });
        activation.qsos.push(idx);
    }
    // Preserve first-seen group order (matches the fetch order of the first QSO in
    // each group) for deterministic output; group order doesn't affect any metric.
    order.into_iter().filter_map(|key| groups.remove(&key)).collect()
}

/// The whole fold. Mirrors `POTAAwardsActor.computeAwardsProgress`.
fn compute_awards(
    snaps: &[ParkSnapshot],
    activations: &[Activation],
    location_descs: &HashMap<String, String>,
) -> PotaAwards {
    let valid: Vec<&Activation> = activations.iter().filter(|act| act.is_valid(snaps)).collect();

    let park_qso_counts = compute_park_qso_counts(snaps);
    let la_porta_count = compute_la_porta_count(&valid, snaps);

    PotaAwards {
        unique_parks_count: compute_unique_parks(&valid),
        dx_entities_count: compute_dx_entities(&valid, snaps),
        states_activated: compute_worked_all_states(&valid, snaps, location_descs),
        rover_max_parks: compute_rover(&valid),
        repeat_offender_max_count: compute_repeat_offender(&valid),
        park_to_park_count: compute_park_to_park(snaps),
        kilo_parks: kilo_parks(&park_qso_counts),
        near_kilo_parks: near_kilo_parks(&park_qso_counts),
        la_porta_earned: la_porta_count >= LA_PORTA_PARKS,
        la_porta_qualifying_parks: la_porta_count as i64,
        six_pack_earned: compute_six_pack(&valid, snaps),
        best_single_park_total: park_qso_counts.values().copied().max().unwrap_or(0),
        total_park_qsos: snaps.len() as i64,
        metadata_excluded: snaps.iter().filter(|sn| is_metadata_mode(&sn.mode)).count() as i64,
        total_activation_groups: activations.len() as i64,
        valid_activation_groups: valid.len() as i64,
    }
}

/// Parks with 10+ QSOs (valid activations), splitting two-fers.
fn compute_unique_parks(valid: &[&Activation]) -> i64 {
    let mut parks = HashSet::new();
    for act in valid {
        for park in act.split_parks() {
            parks.insert(park);
        }
    }
    parks.len() as i64
}

/// Unique DXCC entities (one per activation: first QSO with dxcc > 0).
fn compute_dx_entities(valid: &[&Activation], snaps: &[ParkSnapshot]) -> i64 {
    let mut entities = HashSet::new();
    for act in valid {
        for &idx in &act.qsos {
            if let Some(dxcc) = snaps[idx].dxcc {
                if dxcc > 0 {
                    entities.insert(dxcc);
                    break;
                }
            }
        }
    }
    entities.len() as i64
}

/// US states with valid activations: pota_park `location_desc`, then grid fallback.
fn compute_worked_all_states(
    valid: &[&Activation],
    snaps: &[ParkSnapshot],
    location_descs: &HashMap<String, String>,
) -> Vec<String> {
    let mut states = HashSet::new();
    for act in valid {
        let first_grid = act.qsos.first().and_then(|&idx| snaps[idx].my_grid.as_deref());
        for park in act.split_parks() {
            for state in states_for_park(&park, first_grid, location_descs) {
                states.insert(state);
            }
        }
    }
    let mut out: Vec<String> = states.into_iter().collect();
    out.sort();
    out
}

/// Resolve US state(s) for a park: cache `location_desc`, then grid fallback.
/// Mirrors `statesForPark`.
fn states_for_park(
    park_ref: &str,
    first_grid: Option<&str>,
    location_descs: &HashMap<String, String>,
) -> Vec<String> {
    // Cache path: park found AND US/K prefix AND non-empty parsed states.
    if let Some(location_desc) = location_descs.get(park_ref) {
        if is_us_prefix(park_ref) {
            let park_states = states_from_location_desc(location_desc);
            if !park_states.is_empty() {
                return park_states;
            }
        }
    }
    // Grid fallback (US/K parks only).
    if !is_us_prefix(park_ref) {
        return Vec::new();
    }
    if let Some(grid) = first_grid {
        if let Some(state) = grid_to_us_state(grid) {
            return vec![state];
        }
    }
    Vec::new()
}

/// Max unique parks activated in a single UTC day.
fn compute_rover(valid: &[&Activation]) -> i64 {
    let mut parks_by_date: HashMap<String, HashSet<String>> = HashMap::new();
    for act in valid {
        for park in act.split_parks() {
            parks_by_date.entry(act.utc_date.clone()).or_default().insert(park);
        }
    }
    parks_by_date.values().map(|set| set.len()).max().unwrap_or(0) as i64
}

/// Most activations of a single park (splitting two-fers).
fn compute_repeat_offender(valid: &[&Activation]) -> i64 {
    let mut count_by_park: HashMap<String, i64> = HashMap::new();
    for act in valid {
        for park in act.split_parks() {
            *count_by_park.entry(park).or_insert(0) += 1;
        }
    }
    count_by_park.values().copied().max().unwrap_or(0)
}

/// QSOs where both sides are in a park (raw snapshots, incl. metadata).
fn compute_park_to_park(snaps: &[ParkSnapshot]) -> i64 {
    snaps
        .iter()
        .filter(|sn| {
            !sn.park_reference.is_empty()
                && sn.their_park.as_deref().map(|tp| !tp.is_empty()).unwrap_or(false)
        })
        .count() as i64
}

/// QSO counts per individual park (raw snapshots, incl. metadata).
fn compute_park_qso_counts(snaps: &[ParkSnapshot]) -> HashMap<String, i64> {
    let mut counts: HashMap<String, i64> = HashMap::new();
    for sn in snaps {
        if sn.park_reference.is_empty() {
            continue;
        }
        for park in park_reference::split(&sn.park_reference) {
            *counts.entry(park).or_insert(0) += 1;
        }
    }
    counts
}

/// Parks with 1000+ QSOs, sorted ascending. Mirrors `kiloParks`.
fn kilo_parks(counts: &HashMap<String, i64>) -> Vec<String> {
    let mut parks: Vec<String> =
        counts.iter().filter(|(_, &cnt)| cnt >= KILO_THRESHOLD).map(|(park, _)| park.clone()).collect();
    parks.sort();
    parks
}

/// Parks in 900–999, sorted by count descending (ties by reference ascending for
/// determinism). Mirrors `nearKiloParks` (which sorts by count desc only).
fn near_kilo_parks(counts: &HashMap<String, i64>) -> Vec<NearKiloPark> {
    let mut parks: Vec<NearKiloPark> = counts
        .iter()
        .filter(|(_, &cnt)| (NEAR_KILO_LOWER..KILO_THRESHOLD).contains(&cnt))
        .map(|(park, &cnt)| NearKiloPark { reference: park.clone(), qso_count: cnt })
        .collect();
    parks.sort_by(|left, right| {
        right.qso_count.cmp(&left.qso_count).then_with(|| left.reference.cmp(&right.reference))
    });
    parks
}

/// Parks with 10+ distinct bands from valid activations (N1CC LaPorta input).
fn compute_la_porta_count(valid: &[&Activation], snaps: &[ParkSnapshot]) -> usize {
    let mut bands_by_park: HashMap<String, HashSet<String>> = HashMap::new();
    for act in valid {
        for park in act.split_parks() {
            let entry = bands_by_park.entry(park).or_default();
            for &idx in &act.qsos {
                entry.insert(snaps[idx].band.to_uppercase());
            }
        }
    }
    bands_by_park.values().filter(|set| set.len() >= LA_PORTA_BANDS).count()
}

/// 10 QSOs on 6m from 6 different parks (valid activations).
fn compute_six_pack(valid: &[&Activation], snaps: &[ParkSnapshot]) -> bool {
    let mut parks_with_ten_on_6m = HashSet::new();
    for act in valid {
        let six_m = act.qsos.iter().filter(|&&idx| snaps[idx].band == "6m").count();
        if six_m >= SIX_PACK_MIN_6M {
            for park in act.split_parks() {
                parks_with_ten_on_6m.insert(park);
            }
        }
    }
    parks_with_ten_on_6m.len() >= SIX_PACK_PARKS
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::qso::Qso;
    use crate::PotaPark;

    /// Same UTC day as 1_700_000_000 (2023-11-14); +offset seconds stays in-day.
    const DAY_BASE: i64 = 1_700_000_000;

    fn parse(query: &str) -> ParsedQuery {
        cw_domain::query::parse(query).unwrap()
    }

    fn base_qso(id: &str) -> Qso {
        Qso {
            id: id.to_string(),
            callsign: "W1AW".to_string(),
            band: Some("20m".to_string()),
            mode: Some("FT8".to_string()),
            freq_khz: Some(14_074.0),
            qso_date: DAY_BASE,
            my_grid: Some("FN31".to_string()),
            their_grid: Some("EM12".to_string()),
            rst_sent: None,
            rst_rcvd: None,
            my_callsign: Some("W6JY".to_string()),
            park: None,
            their_park: None,
            notes: None,
            notes_user_authored: false,
            spot_comments_data: None,
            callsign_change_note: None,
            original_callsign: None,
            import_source_raw_value: "logger".to_string(),
            imported_at: DAY_BASE,
            modified_at: None,
            raw_adif: None,
            name: None,
            qth: None,
            state: None,
            country: None,
            power: None,
            my_rig: None,
            station_profile_name: None,
            sota_ref: None,
            wwff_ref: None,
            aoa_code: None,
            qrz_log_id: None,
            qrz_confirmed: false,
            lotw_confirmed_date: None,
            lotw_confirmed: false,
            dxcc: Some(291),
            their_license_class: None,
            contest_name: None,
            contest_serial_sent: None,
            contest_serial_received: None,
            contest_exchange_sent: None,
            contest_exchange_received: None,
            is_hidden: false,
            is_activity_log_qso: false,
            station_callsign: None,
            logging_session_id: None,
            dirty: true,
            sat_name: None,
            prop_mode: None,
        }
    }

    /// Insert `count` QSOs for one park/op/day, each a distinct callsign (so they
    /// are all unique under the dedup key). `tag` keeps ids globally unique.
    fn insert_activation(
        store: &Store,
        tag: &str,
        park: &str,
        op: &str,
        day_offset_secs: i64,
        count: usize,
        band: &str,
    ) {
        for idx in 0..count {
            let mut qso = base_qso(&format!("{tag}-{idx}"));
            qso.callsign = format!("W{idx:04}");
            qso.park = Some(park.to_string());
            qso.my_callsign = Some(op.to_string());
            qso.band = Some(band.to_string());
            qso.mode = Some("CW".to_string());
            qso.qso_date = DAY_BASE + day_offset_secs + idx as i64;
            store.upsert_qso(&qso).unwrap();
        }
    }

    fn park(reference: &str, location_desc: &str) -> PotaPark {
        PotaPark {
            reference: reference.to_string(),
            name: format!("{reference} Park"),
            location_desc: location_desc.to_string(),
            latitude: None,
            longitude: None,
            grid: None,
            entity_id: 291,
            is_active: true,
        }
    }

    #[test]
    fn valid_activation_threshold() {
        let store = Store::open_in_memory("k").unwrap();
        // 9 QSOs → below the 10-unique threshold; not a valid activation.
        insert_activation(&store, "a", "US-0001", "W6JY", 0, 9, "20m");
        let awards = store.pota_awards(&parse("")).unwrap();
        assert_eq!(awards.total_activation_groups, 1);
        assert_eq!(awards.valid_activation_groups, 0);
        assert_eq!(awards.unique_parks_count, 0);

        // One more distinct callsign → 10 unique → valid.
        let mut extra = base_qso("a-extra");
        extra.callsign = "W9999".to_string();
        extra.park = Some("US-0001".to_string());
        extra.band = Some("20m".to_string());
        extra.mode = Some("CW".to_string());
        store.upsert_qso(&extra).unwrap();
        let awards = store.pota_awards(&parse("")).unwrap();
        assert_eq!(awards.valid_activation_groups, 1);
        assert_eq!(awards.unique_parks_count, 1);
    }

    #[test]
    fn dedup_by_callsign_band_mode_park() {
        let store = Store::open_in_memory("k").unwrap();
        // 10 distinct callsigns = 10 unique; plus 5 duplicates of W0000 (same
        // band/mode/park) which do NOT raise the unique count past the bar via dups.
        insert_activation(&store, "a", "US-0001", "W6JY", 0, 10, "20m");
        for dup in 0..5 {
            let mut qso = base_qso(&format!("dup-{dup}"));
            qso.callsign = "W0000".to_string();
            qso.park = Some("US-0001".to_string());
            qso.band = Some("20m".to_string());
            qso.mode = Some("CW".to_string());
            store.upsert_qso(&qso).unwrap();
        }
        let awards = store.pota_awards(&parse("")).unwrap();
        assert_eq!(awards.valid_activation_groups, 1);
        // total_park_qsos counts every row (10 + 5 dups).
        assert_eq!(awards.total_park_qsos, 15);
    }

    #[test]
    fn two_fer_splits_into_two_parks() {
        let store = Store::open_in_memory("k").unwrap();
        insert_activation(&store, "a", "US-0001, US-0002", "W6JY", 0, 10, "20m");
        let awards = store.pota_awards(&parse("")).unwrap();
        assert_eq!(awards.valid_activation_groups, 1);
        assert_eq!(awards.unique_parks_count, 2);
        assert_eq!(awards.repeat_offender_max_count, 1);
    }

    #[test]
    fn metadata_excluded_from_activations_but_counted_in_totals() {
        let store = Store::open_in_memory("k").unwrap();
        insert_activation(&store, "a", "US-0001", "W6JY", 0, 10, "20m");
        let mut meta = base_qso("meta");
        meta.callsign = "META".to_string();
        meta.mode = Some("WEATHER".to_string());
        meta.park = Some("US-0001".to_string());
        store.upsert_qso(&meta).unwrap();
        let awards = store.pota_awards(&parse("")).unwrap();
        assert_eq!(awards.metadata_excluded, 1);
        assert_eq!(awards.total_park_qsos, 11);
        // The metadata QSO does not create/extend an activation group.
        assert_eq!(awards.valid_activation_groups, 1);
        // …but it DOES count toward raw per-park QSO totals (best single park).
        assert_eq!(awards.best_single_park_total, 11);
    }

    #[test]
    fn states_via_location_desc_then_grid_fallback() {
        let store = Store::open_in_memory("k").unwrap();
        // US-0001 has a cached location_desc → WY (cache path).
        insert_activation(&store, "a", "US-0001", "W6JY", 0, 10, "20m");
        store.upsert_pota_parks(&[park("US-0001", "US-WY")]).unwrap();
        // US-0002 is NOT cached; its QSOs carry my_grid=DN44 → grid fallback → CO.
        for idx in 0..10 {
            let mut qso = base_qso(&format!("b-{idx}"));
            qso.callsign = format!("K{idx:04}");
            qso.park = Some("US-0002".to_string());
            qso.my_callsign = Some("W6JY".to_string());
            qso.my_grid = Some("DN44".to_string());
            qso.band = Some("40m".to_string());
            qso.mode = Some("CW".to_string());
            qso.qso_date = DAY_BASE + 100 + idx as i64;
            store.upsert_qso(&qso).unwrap();
        }
        let awards = store.pota_awards(&parse("")).unwrap();
        assert_eq!(awards.states_activated, vec!["CO".to_string(), "WY".to_string()]);
    }

    #[test]
    fn multi_state_park_yields_both_states() {
        let store = Store::open_in_memory("k").unwrap();
        insert_activation(&store, "a", "US-0001", "W6JY", 0, 10, "20m");
        store.upsert_pota_parks(&[park("US-0001", "US-WY,US-MT")]).unwrap();
        let awards = store.pota_awards(&parse("")).unwrap();
        assert_eq!(awards.states_activated, vec!["MT".to_string(), "WY".to_string()]);
    }

    #[test]
    fn non_us_park_contributes_no_state() {
        let store = Store::open_in_memory("k").unwrap();
        // GB park, no cache row, grid present but prefix not US/K → no state.
        for idx in 0..10 {
            let mut qso = base_qso(&format!("g-{idx}"));
            qso.callsign = format!("M{idx:04}");
            qso.park = Some("G-0001".to_string());
            qso.my_grid = Some("FN31".to_string());
            qso.band = Some("20m".to_string());
            qso.mode = Some("CW".to_string());
            store.upsert_qso(&qso).unwrap();
        }
        let awards = store.pota_awards(&parse("")).unwrap();
        assert!(awards.states_activated.is_empty());
        assert_eq!(awards.unique_parks_count, 1);
    }

    #[test]
    fn dx_entities_one_per_activation() {
        let store = Store::open_in_memory("k").unwrap();
        // Activation 1 at US-0001 — all dxcc 291.
        insert_activation(&store, "a", "US-0001", "W6JY", 0, 10, "20m");
        // Activation 2 at US-0002 — dxcc 291 too (first QSO). Only one entity overall.
        insert_activation(&store, "b", "US-0002", "W6JY", 0, 10, "40m");
        let awards = store.pota_awards(&parse("")).unwrap();
        assert_eq!(awards.dx_entities_count, 1);
    }

    #[test]
    fn rover_counts_max_parks_in_a_day() {
        let store = Store::open_in_memory("k").unwrap();
        // Same op, same day, three different parks → rover 3.
        insert_activation(&store, "p1", "US-0001", "W6JY", 0, 10, "20m");
        insert_activation(&store, "p2", "US-0002", "W6JY", 1_000, 10, "20m");
        insert_activation(&store, "p3", "US-0003", "W6JY", 2_000, 10, "20m");
        let awards = store.pota_awards(&parse("")).unwrap();
        assert_eq!(awards.rover_max_parks, 3);
    }

    #[test]
    fn repeat_offender_counts_activations_of_one_park() {
        let store = Store::open_in_memory("k").unwrap();
        // Same park on two different days → 2 activations.
        // Day 1
        insert_activation(&store, "d1", "US-0001", "W6JY", 0, 10, "20m");
        // Day 2 (offset > 86400s)
        for idx in 0..10 {
            let mut qso = base_qso(&format!("d2-{idx}"));
            qso.callsign = format!("W{idx:04}");
            qso.park = Some("US-0001".to_string());
            qso.band = Some("20m".to_string());
            qso.mode = Some("CW".to_string());
            qso.qso_date = DAY_BASE + 90_000 + idx as i64;
            store.upsert_qso(&qso).unwrap();
        }
        let awards = store.pota_awards(&parse("")).unwrap();
        assert_eq!(awards.repeat_offender_max_count, 2);
    }

    #[test]
    fn park_to_park_counts_both_sides_in_park() {
        let store = Store::open_in_memory("k").unwrap();
        insert_activation(&store, "a", "US-0001", "W6JY", 0, 10, "20m");
        // Add a P2P QSO (their_park set).
        let mut p2p = base_qso("p2p");
        p2p.callsign = "P2P".to_string();
        p2p.park = Some("US-0001".to_string());
        p2p.their_park = Some("US-9999".to_string());
        store.upsert_qso(&p2p).unwrap();
        let awards = store.pota_awards(&parse("")).unwrap();
        assert_eq!(awards.park_to_park_count, 1);
    }

    #[test]
    fn la_porta_needs_ten_bands_at_a_park() {
        let store = Store::open_in_memory("k").unwrap();
        let bands = [
            "160m", "80m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m",
        ];
        // 10 QSOs, each on a distinct band → 10 bands at the park.
        for (idx, band) in bands.iter().enumerate() {
            let mut qso = base_qso(&format!("lp-{idx}"));
            qso.callsign = format!("W{idx:04}");
            qso.park = Some("US-0001".to_string());
            qso.band = Some((*band).to_string());
            qso.mode = Some("CW".to_string());
            qso.qso_date = DAY_BASE + idx as i64;
            store.upsert_qso(&qso).unwrap();
        }
        let awards = store.pota_awards(&parse("")).unwrap();
        assert_eq!(awards.la_porta_qualifying_parks, 1);
        assert!(!awards.la_porta_earned); // needs 10 qualifying parks
    }

    #[test]
    fn six_pack_needs_ten_6m_at_six_parks() {
        let store = Store::open_in_memory("k").unwrap();
        for park_n in 0..6 {
            let reference = format!("US-100{park_n}");
            insert_activation(&store, &format!("sp{park_n}"), &reference, "W6JY", 0, 10, "6m");
        }
        let awards = store.pota_awards(&parse("")).unwrap();
        assert!(awards.six_pack_earned);

        // Only five parks with 10 on 6m → not earned.
        let store2 = Store::open_in_memory("k").unwrap();
        for park_n in 0..5 {
            let reference = format!("US-100{park_n}");
            insert_activation(&store2, &format!("sp{park_n}"), &reference, "W6JY", 0, 10, "6m");
        }
        assert!(!store2.pota_awards(&parse("")).unwrap().six_pack_earned);
    }

    #[test]
    fn kilo_and_near_kilo_classification() {
        let store = Store::open_in_memory("k").unwrap();
        // US-0001: 1000 raw QSOs (kilo). Same callsign is fine — kilo counts rows.
        for idx in 0..1_000 {
            let mut qso = base_qso(&format!("kilo-{idx}"));
            qso.park = Some("US-0001".to_string());
            qso.qso_date = DAY_BASE + idx as i64;
            store.upsert_qso(&qso).unwrap();
        }
        // US-0002: 950 raw QSOs (near-kilo).
        for idx in 0..950 {
            let mut qso = base_qso(&format!("near-{idx}"));
            qso.park = Some("US-0002".to_string());
            qso.qso_date = DAY_BASE + idx as i64;
            store.upsert_qso(&qso).unwrap();
        }
        let awards = store.pota_awards(&parse("")).unwrap();
        assert_eq!(awards.kilo_parks, vec!["US-0001".to_string()]);
        assert_eq!(awards.near_kilo_parks.len(), 1);
        assert_eq!(awards.near_kilo_parks[0].reference, "US-0002");
        assert_eq!(awards.near_kilo_parks[0].qso_count, 950);
        assert_eq!(awards.best_single_park_total, 1_000);
    }

    #[test]
    fn dsl_filter_restricts_input() {
        let store = Store::open_in_memory("k").unwrap();
        insert_activation(&store, "a", "US-0001", "W6JY", 0, 10, "20m");
        insert_activation(&store, "b", "US-0002", "W6JY", 0, 10, "40m");
        // Filter to 20m → only the first activation survives.
        let awards = store.pota_awards(&parse("band:20m")).unwrap();
        assert_eq!(awards.valid_activation_groups, 1);
        assert_eq!(awards.unique_parks_count, 1);
        assert_eq!(awards.total_park_qsos, 10);
    }

    #[test]
    fn empty_store_is_all_zero() {
        let store = Store::open_in_memory("k").unwrap();
        let awards = store.pota_awards(&parse("")).unwrap();
        assert_eq!(awards.total_park_qsos, 0);
        assert_eq!(awards.valid_activation_groups, 0);
        assert!(awards.states_activated.is_empty());
        assert!(awards.kilo_parks.is_empty());
        assert!(awards.near_kilo_parks.is_empty());
        assert_eq!(awards.best_single_park_total, 0);
        assert!(!awards.la_porta_earned);
        assert!(!awards.six_pack_earned);
    }
}
