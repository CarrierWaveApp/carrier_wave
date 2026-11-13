//! UniFFI surface for POTA spot decoding (`cw_net::pota`).
//!
//! The host owns the HTTP fetch (the POTA `/spot/activator` endpoint); this
//! decodes the bare JSON array and derives frequency / timestamp / state so
//! every platform presents spots identically.

use cw_net::pota::PotaSpot;

/// A decoded POTA spot with derived display fields.
#[derive(uniffi::Record)]
pub struct FfiPotaSpot {
    pub spot_id: i64,
    pub activator: String,
    /// Frequency as the API string (kHz, e.g. "14074").
    pub frequency: String,
    pub mode: String,
    /// POTA park reference (e.g. "K-1234").
    pub reference: String,
    pub park_name: Option<String>,
    /// ISO-8601 timestamp without timezone (UTC), e.g. "2026-02-03T20:43:36".
    pub spot_time: String,
    pub spotter: String,
    pub comments: Option<String>,
    /// "RBN" for automated spots, `None` for human-generated.
    pub source: Option<String>,
    pub name: Option<String>,
    /// POTA location descriptor, e.g. "US-WY".
    pub location_desc: Option<String>,
    /// Frequency in kHz parsed from `frequency`, or `None` if unparseable.
    pub frequency_khz: Option<f64>,
    /// `true` when `source` is "RBN" (automated CW/digital decoder).
    pub is_automated_spot: bool,
    /// `true` when the spot is human-generated (i.e. not RBN).
    pub is_human_spot: bool,
    /// Unix epoch seconds parsed from `spot_time`, or `None` if unparseable.
    pub timestamp_epoch_seconds: Option<f64>,
    /// US state parsed from `location_desc` (e.g. "US-WY" → "WY"), or `None`.
    pub parsed_state: Option<String>,
}

impl From<PotaSpot> for FfiPotaSpot {
    fn from(spot: PotaSpot) -> Self {
        let frequency_khz = spot.frequency_khz();
        let is_automated_spot = spot.is_automated_spot();
        let is_human_spot = spot.is_human_spot();
        let timestamp_epoch_seconds = spot.timestamp_epoch_seconds();
        let parsed_state = PotaSpot::parse_state(spot.location_desc.as_deref());
        // The rebuilt POTA API leaves `parkName` null and fills `name` instead.
        let park_name = spot.park_display_name().map(str::to_string);
        FfiPotaSpot {
            spot_id: spot.spot_id,
            activator: spot.activator,
            frequency: spot.frequency,
            mode: spot.mode,
            reference: spot.reference,
            park_name,
            spot_time: spot.spot_time,
            spotter: spot.spotter,
            comments: spot.comments,
            source: spot.source,
            name: spot.name,
            location_desc: spot.location_desc,
            frequency_khz,
            is_automated_spot,
            is_human_spot,
            timestamp_epoch_seconds,
            parsed_state,
        }
    }
}

/// Decode a POTA `/spot/activator` response body (bare JSON array).
/// Returns `None` if the body is not valid JSON or not a POTA spot array.
#[uniffi::export]
pub fn decode_pota_response(json: String) -> Option<Vec<FfiPotaSpot>> {
    PotaSpot::parse_response(&json).map(|spots| spots.into_iter().map(Into::into).collect())
}
