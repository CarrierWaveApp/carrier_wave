//! Whether a satellite (and which of its capabilities) is worth showing.
//! Originally a port of `SatelliteWorkability.swift` (since deleted — this
//! is now the only implementation): a curated derelict list plus the AMSAT
//! community signal — tracked birds nobody has heard within the capability's
//! silence window are hidden; untracked ones keep the benefit of the doubt.
//! Linear/CW capabilities get a longer window than FM/digital because AMSAT
//! reporting skews heavily FM. `now` is injected for tests.

use std::collections::HashSet;

use chrono::{DateTime, Duration, Utc};

use super::amsat::AmsatStatus;
use super::mode_category::ModeCategory;
use super::SatTransmitter;

/// A pass is "workable" when it peaks at or above this elevation.
pub const MIN_WORKABLE_PASS_ELEVATION_DEG: f64 = 10.0;

/// Recommended handheld-yagi threshold; 10–20° passes are "marginal".
pub const RECOMMENDED_PASS_ELEVATION_DEG: f64 = 20.0;

/// Seven days without a single "Heard" report = not workable (FM/digital).
const SILENCE_CUTOFF_SECS: i64 = 7 * 24 * 3_600;

/// Linear/CW capabilities get a month: AMSAT status reports skew heavily
/// toward the FM crowd, so a week of transponder silence mostly measures
/// operator activity, not satellite health — famous dead linear birds are
/// on the derelict list instead.
const LINEAR_SILENCE_CUTOFF_SECS: i64 = 30 * 24 * 3_600;

/// The report-silence window a capability earns before it's hidden.
fn silence_cutoff(category: ModeCategory) -> Duration {
    match category {
        ModeCategory::Linear | ModeCategory::Morse => {
            Duration::seconds(LINEAR_SILENCE_CUTOFF_SECS)
        }
        ModeCategory::VoiceFm | ModeCategory::Digital => Duration::seconds(SILENCE_CUTOFF_SECS),
    }
}

/// The window one AMSAT row earns: the most generous cutoff among the
/// capabilities its tag vouches for; rows with no recognized tag get the
/// default week.
fn row_cutoff(row: &AmsatStatus) -> Duration {
    row.capability_tag()
        .and_then(|tag| categories_for_amsat_tag(&tag))
        .map(|categories| {
            categories.into_iter().map(silence_cutoff).max().unwrap_or_else(|| {
                Duration::seconds(SILENCE_CUTOFF_SECS)
            })
        })
        .unwrap_or_else(|| Duration::seconds(SILENCE_CUTOFF_SECS))
}

/// Long-dead satellites SatNOGS still lists with active transmitters:
/// AO-10 14129, AO-40 26609, AO-85 40967, AO-92 43137, AO-95 43770.
const DERELICT_NORAD_IDS: [u32; 5] = [14_129, 26_609, 40_967, 43_137, 43_770];

/// True for a 10–20° pass: above the floor, below the recommendation.
pub fn is_marginal(peak_elevation_deg: f64) -> bool {
    (MIN_WORKABLE_PASS_ELEVATION_DEG..RECOMMENDED_PASS_ELEVATION_DEG)
        .contains(&peak_elevation_deg)
}

/// True when the satellite should appear anywhere in the app: not on the
/// derelict list, and — when AMSAT tracks it — heard on at least one
/// capability within that capability's silence window (a week for
/// FM/digital, a month for linear/CW). Untracked birds keep the benefit
/// of the doubt; tracked birds with zero positive reports stay hidden.
pub fn is_workable(norad_id: u32, amsat_rows: &[AmsatStatus], now: DateTime<Utc>) -> bool {
    if DERELICT_NORAD_IDS.contains(&norad_id) {
        return false;
    }
    if amsat_rows.is_empty() {
        return true;
    }
    amsat_rows.iter().any(|row| {
        row.last_heard_at
            .map(|last_heard| now - last_heard < row_cutoff(row))
            .unwrap_or(false)
    })
}

/// Filter a satellite's transmitters down to capabilities the AMSAT
/// community still hears. Per capability tag, a mode category AMSAT tracks
/// but hasn't heard in 7 days hides its transmitters; untracked categories
/// keep the benefit of the doubt. If filtering would empty the list —
/// conflicting evidence for a bird that passed the workability gate — the
/// raw list is kept.
pub fn active_transmitters(
    transmitters: &[SatTransmitter],
    amsat_rows: &[AmsatStatus],
    now: DateTime<Utc>,
) -> Vec<SatTransmitter> {
    if amsat_rows.is_empty() {
        return transmitters.to_vec();
    }
    let mut tracked = HashSet::new();
    let mut heard = HashSet::new();
    for row in amsat_rows {
        let Some(categories) = row.capability_tag().and_then(|tag| categories_for_amsat_tag(&tag))
        else {
            continue;
        };
        tracked.extend(categories.iter().copied());
        if let Some(last_heard) = row.last_heard_at {
            for category in categories {
                if now - last_heard < silence_cutoff(category) {
                    heard.insert(category);
                }
            }
        }
    }
    let filtered: Vec<SatTransmitter> = transmitters
        .iter()
        .filter(|transmitter| {
            let category = ModeCategory::for_transmitter(transmitter);
            !tracked.contains(&category) || heard.contains(&category)
        })
        .cloned()
        .collect();
    if filtered.is_empty() {
        transmitters.to_vec()
    } else {
        filtered
    }
}

/// Community signal for ONE capability of a satellite: whether any AMSAT
/// row vouches for the transmitter's mode category, and the most recent
/// positive report across those rows. Drives the per-transmitter
/// heard-today indicator (untracked capabilities show nothing — same
/// benefit-of-the-doubt as the gates above).
pub fn capability_status(
    category: ModeCategory,
    amsat_rows: &[AmsatStatus],
) -> (bool, Option<DateTime<Utc>>) {
    let mut tracked = false;
    let mut last_heard: Option<DateTime<Utc>> = None;
    for row in amsat_rows {
        let Some(categories) = row.capability_tag().and_then(|tag| categories_for_amsat_tag(&tag))
        else {
            continue;
        };
        if !categories.contains(&category) {
            continue;
        }
        tracked = true;
        if let Some(heard) = row.last_heard_at {
            last_heard = Some(last_heard.map_or(heard, |best| best.max(heard)));
        }
    }
    (tracked, last_heard)
}

/// Mode categories an AMSAT capability tag vouches for. `None` when the tag
/// is unrecognized — such rows neither vouch for nor indict any capability.
/// Bare transponder designators ("A", "B", "U/V", "NB") are linear birds,
/// which also carry the CW subpassband.
pub fn categories_for_amsat_tag(tag: &str) -> Option<HashSet<ModeCategory>> {
    let upper = tag.to_uppercase();
    let mut categories = HashSet::new();
    if upper.contains("FM") {
        categories.insert(ModeCategory::VoiceFm);
    }
    if ["SSB", "LINEAR", "TRANSPONDER"].iter().any(|marker| upper.contains(marker)) {
        categories.insert(ModeCategory::Linear);
        categories.insert(ModeCategory::Morse);
    }
    if upper.contains("CW") {
        categories.insert(ModeCategory::Morse);
    }
    if ["APRS", "DIGI", "DATA", "PACKET", "PSK", "GMSK", "SSTV", "BBS"]
        .iter()
        .any(|marker| upper.contains(marker))
    {
        categories.insert(ModeCategory::Digital);
    }
    if categories.is_empty()
        && !upper.is_empty()
        && upper.chars().all(|c| "ABJKLNSUV/".contains(c))
    {
        categories.insert(ModeCategory::Linear);
        categories.insert(ModeCategory::Morse);
    }
    if categories.is_empty() {
        None
    } else {
        Some(categories)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn now() -> DateTime<Utc> {
        Utc.timestamp_opt(1_790_000_000, 0).unwrap()
    }

    fn amsat(name: &str, heard_secs_ago: Option<i64>) -> AmsatStatus {
        AmsatStatus {
            name: name.to_string(),
            norad_id: Some(1),
            last_heard_at: heard_secs_ago.map(|ago| now() - Duration::seconds(ago)),
            last_reported_at: None,
            last_report: None,
            last_callsign: None,
            last_grid: None,
            heard_reports_24h: 0,
            total_reports_24h: 0,
        }
    }

    fn transmitter(mode: &str) -> SatTransmitter {
        SatTransmitter {
            description: mode.to_string(),
            transmitter_type: "Transceiver".to_string(),
            alive: true,
            status: "active".to_string(),
            service: "Amateur".to_string(),
            mode: Some(mode.to_string()),
            uplink_low_hz: Some(145_000_000),
            downlink_low_hz: Some(435_000_000),
            uplink_high_hz: None,
            downlink_high_hz: None,
            invert: false,
            norad_id: Some(1),
        }
    }

    #[test]
    fn derelicts_and_silence_rules() {
        assert!(!is_workable(14_129, &[], now()));
        assert!(is_workable(43_017, &[], now()));
        // Tracked with no positive reports → not workable.
        assert!(!is_workable(43_017, &[amsat("AO-91_[FM]", None)], now()));
        // FM: heard 6 days ago → workable; 8 days → not.
        assert!(is_workable(43_017, &[amsat("AO-91_[FM]", Some(6 * 86_400))], now()));
        assert!(!is_workable(43_017, &[amsat("AO-91_[FM]", Some(8 * 86_400))], now()));
    }

    #[test]
    fn linear_birds_get_the_month_long_window() {
        // Linear transponder heard 20 days ago: silent by the FM rule but
        // inside the linear window → still shown.
        assert!(is_workable(44_909, &[amsat("RS-44_[U/V]", Some(20 * 86_400))], now()));
        // 40 days of silence hides even a linear bird.
        assert!(!is_workable(44_909, &[amsat("RS-44_[U/V]", Some(40 * 86_400))], now()));
        // Any one capability inside its window carries the whole bird:
        // FM silent 8 days + linear heard 20 days ago → workable.
        assert!(is_workable(
            7_530,
            &[amsat("AO-7_[FM]", Some(8 * 86_400)), amsat("AO-7_[B]", Some(20 * 86_400))],
            now()
        ));
        // Unrecognized tags keep the default week.
        assert!(!is_workable(1, &[amsat("X_[XYZ123]", Some(8 * 86_400))], now()));
        assert!(is_workable(1, &[amsat("X_[XYZ123]", Some(6 * 86_400))], now()));
    }

    #[test]
    fn tag_categories_match_swift_table() {
        let linear: HashSet<_> = [ModeCategory::Linear, ModeCategory::Morse].into();
        assert_eq!(categories_for_amsat_tag("B"), Some(linear.clone()));
        assert_eq!(categories_for_amsat_tag("U/V"), Some(linear.clone()));
        assert_eq!(categories_for_amsat_tag("NB"), Some(linear));
        assert_eq!(
            categories_for_amsat_tag("FM"),
            Some([ModeCategory::VoiceFm].into())
        );
        assert_eq!(
            categories_for_amsat_tag("APRS"),
            Some([ModeCategory::Digital].into())
        );
        assert_eq!(categories_for_amsat_tag("XYZ123"), None);
        assert_eq!(categories_for_amsat_tag(""), None);
    }

    #[test]
    fn capability_filter_hides_silent_tracked_modes() {
        let transmitters = [transmitter("FM"), transmitter("CW")];
        // FM tracked + silent for 8 days; CW untracked → only CW survives.
        let rows = [amsat("X_[FM]", Some(8 * 86_400))];
        let filtered = active_transmitters(&transmitters, &rows, now());
        assert_eq!(filtered.len(), 1);
        assert_eq!(filtered[0].mode.as_deref(), Some("CW"));

        // Filtering to empty falls back to the raw list.
        let only_fm = [transmitter("FM")];
        let fallback = active_transmitters(&only_fm, &rows, now());
        assert_eq!(fallback.len(), 1);

        // No AMSAT rows → raw list untouched.
        assert_eq!(active_transmitters(&transmitters, &[], now()).len(), 2);
    }

    #[test]
    fn capability_status_reports_per_mode() {
        let rows = [
            amsat("X_[FM]", Some(3_600)),
            amsat("X_[U/V]", Some(20 * 86_400)),
            amsat("X_[U/V]", Some(2 * 86_400)),
        ];
        // FM tracked, heard an hour ago.
        let (tracked, heard) = capability_status(ModeCategory::VoiceFm, &rows);
        assert!(tracked);
        assert_eq!(heard, Some(now() - Duration::seconds(3_600)));
        // Linear tracked; the FRESHEST of its two rows wins.
        let (tracked, heard) = capability_status(ModeCategory::Linear, &rows);
        assert!(tracked);
        assert_eq!(heard, Some(now() - Duration::seconds(2 * 86_400)));
        // Digital untracked → no signal either way.
        assert_eq!(capability_status(ModeCategory::Digital, &rows), (false, None));
        // Tracked but never heard.
        let silent = [amsat("X_[FM]", None)];
        assert_eq!(capability_status(ModeCategory::VoiceFm, &silent), (true, None));
    }

    #[test]
    fn capability_filter_keeps_linear_within_the_month() {
        let transmitters = [transmitter("FM"), transmitter("USB")];
        // Both tracked; both last heard 20 days ago: FM (7-day window) is
        // hidden, the linear transponder (30-day window) survives.
        let rows =
            [amsat("X_[FM]", Some(20 * 86_400)), amsat("X_[U/V]", Some(20 * 86_400))];
        let filtered = active_transmitters(&transmitters, &rows, now());
        assert_eq!(filtered.len(), 1);
        assert_eq!(filtered[0].mode.as_deref(), Some("USB"));

        // 40 days of silence hides the linear capability too.
        let stale = [amsat("X_[U/V]", Some(40 * 86_400))];
        let hidden = active_transmitters(&[transmitter("USB"), transmitter("FM")], &stale, now());
        assert_eq!(hidden.len(), 1);
        assert_eq!(hidden[0].mode.as_deref(), Some("FM"));
    }
}
