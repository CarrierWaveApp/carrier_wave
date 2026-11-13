//! UniFFI surface for SOTA spot decoding (`cw_net::sota`).
//!
//! The host owns the HTTP fetch (the SOTAwatch `/spots/N/all` endpoint); this
//! decodes the bare JSON array and derives frequency / timestamp / summit fields
//! so every platform presents spots identically.

use cw_net::sota::SotaSpot;

/// A decoded SOTAwatch spot with derived display fields.
#[derive(uniffi::Record)]
pub struct FfiSotaSpot {
    pub id: i64,
    pub user_id: i64,
    pub activator_callsign: String,
    pub activator_name: String,
    /// The spotter's callsign (JSON key "callsign", remapped by the Swift CodingKeys).
    pub spotter_callsign: String,
    /// Association code, e.g. "W4C".
    pub association_code: String,
    /// Summit code within the association, e.g. "CM-001".
    pub summit_code: String,
    /// Free-text summit details, e.g. "Mount Mitchell, 2037m, 10 points".
    pub summit_details: String,
    /// Frequency in MHz as a string, e.g. "14.062".
    pub frequency: String,
    pub mode: String,
    pub comments: Option<String>,
    pub highlight_color: Option<String>,
    /// ISO-8601 timestamp without timezone (UTC), e.g. "2026-02-26T17:51:41".
    pub time_stamp: String,
    /// Frequency in MHz, or `None` if the frequency string is unparseable.
    pub frequency_mhz: Option<f64>,
    /// Frequency in kHz, or `None` if the frequency string is unparseable.
    pub frequency_khz: Option<f64>,
    /// Unix epoch seconds parsed from `time_stamp`, or `None` if unparseable.
    pub timestamp_epoch_seconds: Option<f64>,
    /// Combined summit reference, e.g. "W4C/CM-001".
    pub full_summit_reference: String,
    /// Points value extracted from `summit_details` (0 when not found).
    pub points: u32,
    /// Summit name extracted from `summit_details` (text before first comma).
    pub summit_name: String,
}

impl From<SotaSpot> for FfiSotaSpot {
    fn from(spot: SotaSpot) -> Self {
        let frequency_mhz = spot.frequency_mhz();
        let frequency_khz = spot.frequency_khz();
        let timestamp_epoch_seconds = spot.timestamp_epoch_seconds();
        let full_summit_reference = spot.full_summit_reference();
        let points = spot.points();
        let summit_name = spot.summit_name().to_string();
        FfiSotaSpot {
            id: spot.id,
            // Nullable upstream; keep the FFI record shape stable (0 / "").
            user_id: spot.user_id.unwrap_or(0),
            activator_callsign: spot.activator_callsign,
            activator_name: spot.activator_name.unwrap_or_default(),
            spotter_callsign: spot.spotter_callsign,
            association_code: spot.association_code,
            summit_code: spot.summit_code,
            summit_details: spot.summit_details,
            frequency: spot.frequency,
            mode: spot.mode,
            comments: spot.comments,
            highlight_color: spot.highlight_color,
            time_stamp: spot.time_stamp,
            frequency_mhz,
            frequency_khz,
            timestamp_epoch_seconds,
            full_summit_reference,
            points,
            summit_name,
        }
    }
}

/// Decode a SOTAwatch spots response body (bare JSON array).
/// Returns `None` if the body is not valid JSON or not a SOTA spot array.
#[uniffi::export]
pub fn decode_sota_response(json: String) -> Option<Vec<FfiSotaSpot>> {
    SotaSpot::parse_response(&json).map(|spots| spots.into_iter().map(Into::into).collect())
}
