//! UniFFI surface for PSK Reporter spot decoding (`cw_net::pskreporter`).
//!
//! The host owns the HTTP fetch (the PSK Reporter query API); this parses the
//! XML `<receptionReport>` elements and derives the composite ID and
//! frequency-in-kHz so every platform presents reports identically.

use cw_net::pskreporter::{parse, PskReporterSpot};

/// A decoded PSK Reporter reception report with derived display fields.
#[derive(uniffi::Record)]
pub struct FfiPskReporterSpot {
    pub sender_callsign: String,
    pub sender_locator: Option<String>,
    pub receiver_callsign: String,
    pub receiver_locator: Option<String>,
    /// Frequency in Hz, as PSK Reporter returns it.
    pub frequency: i64,
    pub mode: String,
    /// Signal-to-noise ratio, or `None` if absent in the report.
    pub snr: Option<i64>,
    /// Unix epoch seconds for the reception slot start.
    pub flow_start_seconds: i64,
    /// Composite identifier mirroring `PSKReporterSpot.id` in Swift.
    pub id_str: String,
    /// Frequency in kHz (frequency / 1000).
    pub frequency_khz: f64,
}

impl From<PskReporterSpot> for FfiPskReporterSpot {
    fn from(spot: PskReporterSpot) -> Self {
        let id_str = spot.id();
        let frequency_khz = spot.frequency_khz();
        FfiPskReporterSpot {
            sender_callsign: spot.sender_callsign,
            sender_locator: spot.sender_locator,
            receiver_callsign: spot.receiver_callsign,
            receiver_locator: spot.receiver_locator,
            frequency: spot.frequency,
            mode: spot.mode,
            snr: spot.snr.map(i64::from),
            flow_start_seconds: spot.flow_start_seconds,
            id_str,
            frequency_khz,
        }
    }
}

/// Parse a PSK Reporter XML payload into reception reports.
/// Returns `None` on XML parse failure (matching the Swift parser's
/// error-throwing behaviour); returns `Some([])` for valid XML with no reports.
#[uniffi::export]
pub fn decode_psk_reporter_xml(xml: String) -> Option<Vec<FfiPskReporterSpot>> {
    parse(&xml).ok().map(|spots| spots.into_iter().map(Into::into).collect())
}
