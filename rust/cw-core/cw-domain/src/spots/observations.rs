//! Spot observation / spotter row projection for the scope SQL schema.
//! Port of Sweep's `SpotObservationMapper.swift`.
//!
//! `obs_id` is caller-supplied (the FFI layer generates UUIDs) so this
//! module stays pure.

use crate::cty::DxccEntity;
use crate::maidenhead;
use crate::spots::model::{SpotSource, UnifiedSpot};

/// One per-skimmer observation row (`scope.spot_observations`).
#[derive(Debug, Clone, PartialEq)]
pub struct SpotObservationRow {
    pub obs_id: String,
    pub spot_id: String,
    pub callsign: String,
    pub band: String,
    pub mode: String,
    pub freq_hz: i64,
    pub source: String,
    pub spotter: Option<String>,
    pub spot_lat: Option<f64>,
    pub spot_lon: Option<f64>,
    pub snr_db: Option<i32>,
    pub speed_wpm: Option<i32>,
    pub comment: Option<String>,
    /// Unix epoch seconds.
    pub received_at: i64,
    pub priority: i32,
    // Enrichment carried through to the `scope.spots` projection (not
    // stored on the observation row itself): lets profile SQL filter on
    // entity/park/grid without host-side joins.
    pub dxcc_entity: Option<String>,
    pub continent: Option<String>,
    pub cq_zone: Option<i64>,
    pub itu_zone: Option<i64>,
    pub grid: Option<String>,
    pub park_ref: Option<String>,
}

/// Spotter location index row (`scope.spotters`).
#[derive(Debug, Clone, PartialEq)]
pub struct SpotterRow {
    pub callsign: String,
    pub grid: Option<String>,
    pub lat: Option<f64>,
    pub lon: Option<f64>,
    pub dxcc_entity: Option<String>,
    pub continent: Option<String>,
    pub is_skimmer: bool,
}

/// Build an observation row from a unified spot. Coordinates resolve for
/// the *spotted* (DX) callsign: grid centre when known (DXHeat / DXWatch /
/// call-info enrichment populate `dx_grid`), else the DXCC entity centroid
/// — country-level, but free and synchronous.
pub fn observation_row(
    spot: &UnifiedSpot,
    priority: i32,
    dx_entity: Option<&DxccEntity>,
    obs_id: String,
) -> SpotObservationRow {
    let coords = spot
        .dx_grid
        .as_deref()
        .and_then(maidenhead::coordinate_from_grid)
        .map(|coord| (coord.latitude, coord.longitude))
        .or_else(|| dx_entity.map(|entity| (entity.latitude, entity.longitude)));

    SpotObservationRow {
        obs_id,
        spot_id: spot.id.clone(),
        callsign: spot.callsign.to_uppercase(),
        band: spot.band().to_string(),
        mode: spot.mode.clone(),
        freq_hz: (spot.frequency_khz * 1_000.0).round() as i64,
        source: spot.source.raw_value().to_string(),
        spotter: spot.spotter.clone(),
        spot_lat: coords.map(|(lat, _)| lat),
        spot_lon: coords.map(|(_, lon)| lon),
        snr_db: spot.snr,
        speed_wpm: spot.wpm,
        comment: spot.comments.clone(),
        received_at: spot.timestamp,
        priority,
        dxcc_entity: dx_entity.map(|entity| entity.name.clone()),
        continent: spot
            .continent
            .clone()
            .or_else(|| dx_entity.map(|entity| entity.continent.clone())),
        cq_zone: spot
            .cq_zone
            .map(i64::from)
            .or_else(|| dx_entity.map(|entity| i64::from(entity.cq_zone))),
        itu_zone: dx_entity.map(|entity| i64::from(entity.itu_zone)),
        grid: spot.dx_grid.clone(),
        park_ref: spot.park_ref.clone(),
    }
}

/// Build a spotter row with as much location detail as is available
/// synchronously. The caller supplies the spotter's DXCC entity (CTY prefix
/// lookup) for a country-centroid lat/lon and continent; higher-precision
/// grid/lat/lon is filled by an async HamDB pass afterwards.
pub fn spotter_row(spot: &UnifiedSpot, spotter_entity: Option<&DxccEntity>) -> Option<SpotterRow> {
    let spotter = spot.spotter.as_deref()?;
    if spotter.is_empty() {
        return None;
    }
    Some(SpotterRow {
        callsign: spotter.to_uppercase(),
        grid: spot.spotter_grid.clone(),
        lat: spotter_entity.map(|entity| entity.latitude),
        lon: spotter_entity.map(|entity| entity.longitude),
        dxcc_entity: spotter_entity.map(|entity| entity.name.clone()),
        continent: spotter_entity.map(|entity| entity.continent.clone()),
        is_skimmer: spot.source == SpotSource::Rbn,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entity() -> DxccEntity {
        DxccEntity {
            name: "Japan".to_string(),
            cq_zone: 25,
            itu_zone: 45,
            continent: "AS".to_string(),
            latitude: 36.4,
            longitude: -138.38,
            time_offset: -9.0,
            primary_prefix: "JA".to_string(),
        }
    }

    fn spot() -> UnifiedSpot {
        let mut spot = UnifiedSpot::base(
            "rbn-42".to_string(),
            "ja1abc".to_string(),
            14_040.4,
            "CW".to_string(),
            1_700_000_000,
            SpotSource::Rbn,
        );
        spot.spotter = Some("w3lpl".to_string());
        spot.spotter_grid = Some("FM19".to_string());
        spot.snr = Some(24);
        spot.wpm = Some(28);
        spot
    }

    #[test]
    fn observation_row_projects_fields() {
        let row = observation_row(&spot(), 0, Some(&entity()), "obs-1".to_string());
        assert_eq!(row.spot_id, "rbn-42");
        assert_eq!(row.callsign, "JA1ABC");
        assert_eq!(row.band, "20m");
        assert_eq!(row.freq_hz, 14_040_400);
        assert_eq!(row.source, "rbn");
        assert_eq!(row.priority, 0);
        // No dx_grid → entity centroid.
        assert_eq!(row.spot_lat, Some(36.4));
        assert_eq!(row.spot_lon, Some(-138.38));
        // Projection enrichment comes from the entity when the spot
        // carries nothing itself.
        assert_eq!(row.dxcc_entity.as_deref(), Some("Japan"));
        assert_eq!(row.continent.as_deref(), Some("AS"));
        assert_eq!(row.cq_zone, Some(25));
        assert_eq!(row.itu_zone, Some(45));
        assert_eq!(row.grid, None);
        assert_eq!(row.park_ref, None);
    }

    #[test]
    fn observation_row_prefers_dx_grid_over_centroid() {
        let mut s = spot();
        s.dx_grid = Some("PM95".to_string());
        let row = observation_row(&s, 3, Some(&entity()), "obs-2".to_string());
        // PM95 centre, not the entity centroid.
        assert!((row.spot_lat.unwrap() - 35.5).abs() < 1.0);
        assert!(row.spot_lon.unwrap() > 138.0);
    }

    #[test]
    fn observation_row_without_coords() {
        let row = observation_row(&spot(), 0, None, "obs-3".to_string());
        assert_eq!(row.spot_lat, None);
        assert_eq!(row.spot_lon, None);
    }

    #[test]
    fn spotter_row_uppercases_and_flags_skimmer() {
        let row = spotter_row(&spot(), Some(&entity())).unwrap();
        assert_eq!(row.callsign, "W3LPL");
        assert_eq!(row.grid.as_deref(), Some("FM19"));
        assert_eq!(row.dxcc_entity.as_deref(), Some("Japan"));
        assert!(row.is_skimmer);
    }

    #[test]
    fn spotter_row_none_without_spotter() {
        let mut s = spot();
        s.spotter = None;
        assert!(spotter_row(&s, None).is_none());
        s.spotter = Some(String::new());
        assert!(spotter_row(&s, None).is_none());
    }
}
