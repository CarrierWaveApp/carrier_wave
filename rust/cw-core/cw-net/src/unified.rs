//! Source-spot → [`UnifiedSpot`] mappings for all nine spot sources. Port
//! of Sweep's `UnifiedSpot` factory extensions (`UnifiedSpot.swift`),
//! `DXClusterSpot.toUnifiedSpot`, and iOS's `PSKReporterSpot.toUnifiedSpot`
//! (`SpotMonitoringService+HunterFetch.swift`).
//!
//! Mappings that need a clock (`now`, unix seconds) take it as a parameter:
//! DXHeat/DXWatch fall back to `now` for unparseable timestamps (Swift's
//! `?? Date()`), and DXWatch needs the current year.

use cw_domain::spots::cluster_parser::{parse_split_info, DxClusterSpot};
use cw_domain::spots::model::{guess_mode, SpotSource, UnifiedSpot};

use crate::dxheat::DxHeatSpot;
use crate::dxsummit::DxSummitSpot;
use crate::dxwatch::{DxWatchCallInfo, DxWatchSpot};
use crate::pota::PotaSpot;
use crate::pskreporter::PskReporterSpot;
use crate::rbn::RbnSpot;
use crate::sota::SotaSpot;
use crate::wwff::WwffSpot;

/// RBN spot → unified. Returns `None` when the timestamp is unparseable
/// (Swift's decoder would have rejected the row).
pub fn from_rbn(spot: &RbnSpot) -> Option<UnifiedSpot> {
    let timestamp = spot.timestamp_epoch_seconds()? as i64;
    let mut unified = UnifiedSpot::base(
        format!("rbn-{}", spot.id),
        spot.callsign.clone(),
        spot.frequency,
        spot.mode.clone(),
        timestamp,
        SpotSource::Rbn,
    );
    unified.snr = Some(spot.snr as i32);
    unified.wpm = spot.wpm.map(|wpm| wpm as i32);
    unified.spotter = Some(spot.spotter.clone());
    unified.spotter_grid = spot.spotter_grid.clone();
    Some(unified)
}

/// POTA spot → unified. `None` when frequency or timestamp fail to parse.
pub fn from_pota(spot: &PotaSpot) -> Option<UnifiedSpot> {
    let freq_khz = spot.frequency_khz()?;
    let timestamp = spot.timestamp_epoch_seconds()? as i64;
    let mut unified = UnifiedSpot::base(
        format!("pota-{}", spot.spot_id),
        spot.activator.clone(),
        freq_khz,
        spot.mode.clone(),
        timestamp,
        SpotSource::Pota,
    );
    unified.spotter = Some(spot.spotter.clone());
    unified.park_ref = Some(spot.reference.clone());
    unified.park_name = spot.park_display_name().map(str::to_string);
    unified.comments = spot.comments.clone();
    unified.pota_source = spot.source.clone();
    unified.location_desc = spot.location_desc.clone();
    unified.state_abbr = PotaSpot::parse_state(spot.location_desc.as_deref());
    Some(unified)
}

/// SOTA spot → unified. `None` when frequency or timestamp fail to parse.
pub fn from_sota(spot: &SotaSpot) -> Option<UnifiedSpot> {
    let freq_khz = spot.frequency_khz()?;
    let timestamp = spot.timestamp_epoch_seconds()? as i64;
    let mut unified = UnifiedSpot::base(
        format!("sota-{}", spot.id),
        spot.activator_callsign.clone(),
        freq_khz,
        spot.mode.clone(),
        timestamp,
        SpotSource::Sota,
    );
    unified.spotter = Some(spot.spotter_callsign.clone());
    unified.comments = spot.comments.clone();
    unified.summit_code = Some(spot.full_summit_reference());
    unified.summit_name = Some(spot.summit_name().to_string());
    unified.summit_points = Some(spot.points() as i32);
    Some(unified)
}

/// WWFF spot → unified. `None` when frequency or timestamp fail to parse.
pub fn from_wwff(spot: &WwffSpot) -> Option<UnifiedSpot> {
    let freq_khz = spot.frequency_khz()?;
    let timestamp = spot.parsed_timestamp()?.timestamp();
    let mut unified = UnifiedSpot::base(
        format!("wwff-{}", spot.id),
        spot.activator.clone(),
        freq_khz,
        spot.mode.clone(),
        timestamp,
        SpotSource::Wwff,
    );
    unified.spotter = Some(spot.spotter.clone());
    unified.comments = spot.comments.clone();
    unified.wwff_ref = Some(spot.reference.clone());
    unified.wwff_name = spot.reference_info.clone();
    Some(unified)
}

/// DX Summit spot → unified. Mode is guessed from the comment + band
/// position; split info parsed from the comment.
pub fn from_dxsummit(spot: &DxSummitSpot, now: i64) -> UnifiedSpot {
    let mode = guess_mode(spot.info.as_deref(), spot.frequency);
    let mut unified = UnifiedSpot::base(
        format!("dxs-{}", spot.id),
        spot.dx_call.clone(),
        spot.frequency,
        mode.to_string(),
        spot.timestamp_epoch_seconds().unwrap_or(now),
        SpotSource::DxSummit,
    );
    unified.spotter = Some(spot.de_call.clone());
    unified.comments = spot.info.clone();
    unified.split_info = parse_split_info(spot.info.as_deref());
    unified.location_desc = spot.dx_country.clone();
    unified
}

/// DXHeat spot → unified. `None` when the frequency string fails to parse.
pub fn from_dxheat(spot: &DxHeatSpot, now: i64) -> Option<UnifiedSpot> {
    let freq_khz = spot.frequency_khz()?;
    let comment = spot.decoded_comment();
    let mode = spot
        .mode
        .clone()
        .unwrap_or_else(|| guess_mode(Some(&comment), freq_khz).to_string());
    let mut unified = UnifiedSpot::base(
        format!("dxh-{}", spot.nr),
        spot.dx_call.clone(),
        freq_khz,
        mode,
        spot.timestamp_epoch_seconds().unwrap_or(now),
        SpotSource::DxHeat,
    );
    unified.spotter = Some(spot.spotter.clone());
    unified.comments = if comment.is_empty() { None } else { Some(comment.clone()) };
    unified.dx_grid = spot.dx_locator.clone();
    unified.continent = spot.continent_dx.clone();
    unified.split_info = parse_split_info(Some(&comment));
    unified.lotw_user = spot.lotw;
    Some(unified)
}

/// DXWatch spot (+ optional call info) → unified.
pub fn from_dxwatch(
    spot: &DxWatchSpot,
    call_info: Option<&DxWatchCallInfo>,
    now: i64,
) -> UnifiedSpot {
    let mode = guess_mode(spot.comment.as_deref(), spot.frequency);
    let mut unified = UnifiedSpot::base(
        format!("dxw-{}", spot.id),
        spot.dx_call.clone(),
        spot.frequency,
        mode.to_string(),
        spot.timestamp_epoch_seconds(now).unwrap_or(now),
        SpotSource::DxWatch,
    );
    unified.spotter = Some(spot.spotter.clone());
    unified.comments = spot.comment.clone();
    unified.split_info = parse_split_info(spot.comment.as_deref());
    if let Some(info) = call_info {
        unified.dx_grid = info.grid.clone();
        unified.continent = info.continent.clone();
        unified.dxcc_prefix = info.prefix.clone();
        unified.cq_zone = info.cq_zone.map(|z| z as i32);
        unified.iota_ref = info.iota_ref.clone();
        unified.location_desc = info.entity_name.clone();
    }
    unified
}

/// DX cluster spot → unified. Mode/WPM come from the comment parse (Swift's
/// `parsedMode` / `cwSpeed`). The Swift original ids rows with a fresh UUID;
/// here the id derives from the line content so mapping stays pure —
/// uniqueness only matters until the dedup key collapses duplicates anyway.
pub fn from_cluster(spot: &DxClusterSpot) -> UnifiedSpot {
    use cw_domain::spots::cluster_parser::{parse_cw_speed, parse_mode};
    let mode = parse_mode(&spot.comment)
        .map(str::to_string)
        .unwrap_or_else(|| guess_mode(None, spot.frequency_khz).to_string());
    let mut unified = UnifiedSpot::base(
        format!(
            "cluster-{}-{}-{}-{}",
            spot.spotter,
            spot.callsign,
            (spot.frequency_khz * 10.0).round() as i64,
            spot.timestamp
        ),
        spot.callsign.clone(),
        spot.frequency_khz,
        mode,
        spot.timestamp,
        SpotSource::Cluster,
    );
    unified.wpm = parse_cw_speed(&spot.comment);
    unified.spotter = Some(spot.spotter.clone());
    unified.comments = if spot.comment.is_empty() { None } else { Some(spot.comment.clone()) };
    unified.split_info = parse_split_info(Some(&spot.comment));
    unified
}

/// PSK Reporter spot → unified (iOS hunter feed mapping).
pub fn from_pskr(spot: &PskReporterSpot) -> UnifiedSpot {
    let mut unified = UnifiedSpot::base(
        format!("pskr-{}", spot.id()),
        spot.sender_callsign.clone(),
        spot.frequency_khz(),
        spot.mode.clone(),
        spot.timestamp().timestamp(),
        SpotSource::Pskr,
    );
    unified.snr = spot.snr;
    unified.spotter = Some(spot.receiver_callsign.clone());
    unified.spotter_grid = spot.receiver_locator.clone();
    unified
}

#[cfg(test)]
mod tests {
    use super::*;

    const NOW: i64 = 1_751_468_000;

    #[test]
    fn rbn_mapping() {
        let json = r#"{"id": 7, "callsign": "JA1ABC", "frequency": 14040.5, "mode": "CW", "timestamp": "2026-02-03T20:43:36Z", "snr": 24, "wpm": 28, "spotter": "W3LPL", "spotter_grid": "FM19"}"#;
        let spot: RbnSpot = serde_json::from_str(json).unwrap();
        let unified = from_rbn(&spot).unwrap();
        assert_eq!(unified.id, "rbn-7");
        assert_eq!(unified.source, SpotSource::Rbn);
        assert_eq!(unified.snr, Some(24));
        assert_eq!(unified.wpm, Some(28));
        assert_eq!(unified.spotter_grid.as_deref(), Some("FM19"));
        assert_eq!(unified.band(), "20m");
    }

    #[test]
    fn pota_mapping_parses_state() {
        let json = r#"{"spotId": 12, "activator": "W6JY", "frequency": "14285", "mode": "SSB", "reference": "US-1234", "parkName": "Some Park", "spotTime": "2026-02-03T20:43:36", "spotter": "K1ABC", "comments": "QRT soon", "locationDesc": "US-WY"}"#;
        let spot: PotaSpot = serde_json::from_str(json).unwrap();
        let unified = from_pota(&spot).unwrap();
        assert_eq!(unified.id, "pota-12");
        assert_eq!(unified.park_ref.as_deref(), Some("US-1234"));
        assert_eq!(unified.state_abbr.as_deref(), Some("WY"));
        assert_eq!(unified.park_name.as_deref(), Some("Some Park"));
    }

    #[test]
    fn pota_mapping_uses_name_when_park_name_is_null() {
        let json = r#"{"spotId": 13, "activator": "W6JY", "frequency": "14285", "mode": "SSB", "reference": "US-1234", "parkName": null, "name": "Some Park", "spotTime": "2026-02-03T20:43:36", "spotter": "K1ABC", "locationDesc": "US-WY"}"#;
        let spot: PotaSpot = serde_json::from_str(json).unwrap();
        let unified = from_pota(&spot).unwrap();
        assert_eq!(unified.park_name.as_deref(), Some("Some Park"));
    }

    #[test]
    fn dxsummit_mapping_guesses_mode_and_split() {
        let spot = DxSummitSpot {
            id: 5,
            dx_call: "EA5EE".to_string(),
            de_call: "M7BYF".to_string(),
            frequency: 14_040.0,
            time: "2026-07-02T15:27:39".to_string(),
            info: Some("up 2 tnx".to_string()),
            dx_country: Some("Spain".to_string()),
            dx_latitude: None,
            dx_longitude: None,
            de_latitude: None,
            de_longitude: None,
        };
        let unified = from_dxsummit(&spot, NOW);
        assert_eq!(unified.id, "dxs-5");
        // 14040 < 20m digital boundary → CW.
        assert_eq!(unified.mode, "CW");
        assert_eq!(unified.split_info.as_deref(), Some("UP 2"));
        assert_eq!(unified.location_desc.as_deref(), Some("Spain"));

        // Unparseable time → now fallback.
        let mut bad = spot.clone();
        bad.time = "garbage".to_string();
        assert_eq!(from_dxsummit(&bad, NOW).timestamp, NOW);
    }

    #[test]
    fn dxheat_mapping_uses_api_mode_and_decodes_comment() {
        let json = r#"[{"Nr": 9, "Spotter": "IU0IBY", "Frequency": "7101.0", "DXCall": "IR0WWA", "Time": "15:27", "Date": "02/07/26", "Comment": "it&#x27;s loud", "Mode": "LSB", "Continent_dx": "EU", "DXLocator": "JN61GV", "LOTW": true}]"#;
        let spots = DxHeatSpot::parse_response(json).unwrap();
        let unified = from_dxheat(&spots[0], NOW).unwrap();
        assert_eq!(unified.id, "dxh-9");
        assert_eq!(unified.mode, "LSB");
        assert_eq!(unified.comments.as_deref(), Some("it's loud"));
        assert_eq!(unified.dx_grid.as_deref(), Some("JN61GV"));
        assert_eq!(unified.lotw_user, Some(true));

        // Unparseable frequency → None.
        let mut bad = spots[0].clone();
        bad.frequency = "abc".to_string();
        assert!(from_dxheat(&bad, NOW).is_none());
    }

    #[test]
    fn dxwatch_mapping_merges_call_info() {
        let spot = DxWatchSpot {
            id: "60924348".to_string(),
            spotter: "YB5NVE".to_string(),
            frequency: 14_269.0,
            dx_call: "SN0WWA".to_string(),
            comment: Some("59 QSX 14275".to_string()),
            time_string: "1527z 02 Jul".to_string(),
            band_code: 22,
            flag: 1,
        };
        let info = DxWatchCallInfo {
            prefix: Some("SP".to_string()),
            entity_name: Some("Poland".to_string()),
            continent: Some("EU".to_string()),
            cq_zone: Some(28),
            grid: Some("KO02MG".to_string()),
            iota_ref: None,
            ..DxWatchCallInfo::default()
        };
        let unified = from_dxwatch(&spot, Some(&info), NOW);
        assert_eq!(unified.id, "dxw-60924348");
        assert_eq!(unified.dxcc_prefix.as_deref(), Some("SP"));
        assert_eq!(unified.cq_zone, Some(28));
        assert_eq!(unified.dx_grid.as_deref(), Some("KO02MG"));
        assert_eq!(unified.location_desc.as_deref(), Some("Poland"));
        assert_eq!(unified.split_info.as_deref(), Some("QSX 14275"));
        // 14269 ≥ 20m SSB boundary → SSB guess.
        assert_eq!(unified.mode, "SSB");
    }

    #[test]
    fn cluster_mapping_parses_mode_and_wpm() {
        let spot = DxClusterSpot {
            spotter: "K3LR".to_string(),
            frequency_khz: 7_005.5,
            callsign: "W1AW".to_string(),
            comment: "CW 28 WPM".to_string(),
            timestamp: NOW,
        };
        let unified = from_cluster(&spot);
        assert_eq!(unified.source, SpotSource::Cluster);
        assert_eq!(unified.mode, "CW");
        assert_eq!(unified.wpm, Some(28));
        assert!(unified.id.starts_with("cluster-K3LR-W1AW-70055-"));

        // Empty comment → band-position mode guess, no comments field.
        let bare = DxClusterSpot {
            spotter: "K3LR".to_string(),
            frequency_khz: 14_200.0,
            callsign: "W1AW".to_string(),
            comment: String::new(),
            timestamp: NOW,
        };
        let unified = from_cluster(&bare);
        assert_eq!(unified.mode, "SSB");
        assert_eq!(unified.comments, None);
    }
}
