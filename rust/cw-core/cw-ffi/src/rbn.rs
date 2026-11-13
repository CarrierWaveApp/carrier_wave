//! UniFFI surface for Reverse Beacon Network spot decoding (`cw_net::rbn`).
//!
//! The host owns the HTTP fetch (the activities-server RBN proxy); this decodes
//! the three response shapes and derives band / MHz / formatted frequency /
//! epoch timestamp so every platform presents spots identically.

use cw_net::rbn::RbnSpot;

/// A decoded RBN spot with derived display fields.
#[derive(uniffi::Record)]
pub struct FfiRbnSpot {
    pub id: i64,
    pub callsign: String,
    /// Frequency in kHz.
    pub frequency: f64,
    pub mode: String,
    pub timestamp: String,
    /// Unix epoch seconds parsed from `timestamp` (for sorting / age), or
    /// `None` if unparseable.
    pub timestamp_epoch_seconds: Option<f64>,
    pub snr: i64,
    pub wpm: Option<i64>,
    pub spotter: String,
    pub spotter_grid: Option<String>,
    pub frequency_mhz: f64,
    pub band: String,
    pub formatted_frequency: String,
}

impl From<RbnSpot> for FfiRbnSpot {
    fn from(spot: RbnSpot) -> Self {
        let frequency_mhz = spot.frequency_mhz();
        let band = spot.band();
        let formatted_frequency = spot.formatted_frequency();
        let timestamp_epoch_seconds = spot.timestamp_epoch_seconds();
        FfiRbnSpot {
            id: spot.id,
            callsign: spot.callsign,
            frequency: spot.frequency,
            mode: spot.mode,
            timestamp: spot.timestamp,
            timestamp_epoch_seconds,
            snr: spot.snr,
            wpm: spot.wpm,
            spotter: spot.spotter,
            spotter_grid: spot.spotter_grid,
            frequency_mhz,
            band,
            formatted_frequency,
        }
    }
}

/// Decode an RBN response body, trying the callsign-echo, total-count, and
/// bare-array shapes in order. `None` if the payload matches none of them.
#[uniffi::export]
pub fn decode_rbn_response(json: String) -> Option<Vec<FfiRbnSpot>> {
    RbnSpot::parse_response(&json).map(|spots| spots.into_iter().map(Into::into).collect())
}
