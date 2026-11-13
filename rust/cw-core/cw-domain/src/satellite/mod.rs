//! Satellite tracking domain: SGP4 propagation, observer look angles, pass
//! prediction, workability rules, and alert planning.
//!
//! Rust-first port of the iOS satellite services (each submodule's header
//! names the Swift file it mirrors). The orbital engine is the `sgp4` crate
//! (validated against the official Vallado test vectors) plus a
//! TEME→ECEF→topocentric conversion layer in [`propagator`] — the one piece
//! with no Swift analogue, since SatelliteKit did those frames internally.
//!
//! Everything here is pure: time instants are injected, nothing reads the
//! clock, no I/O. Fetching lives in `cw-net`, caching in `cw-store`, and the
//! host-facing surface in `cw-ffi::satellite_api`.

pub mod alert_planner;
pub mod amsat;
pub mod catalog;
pub mod display_name;
pub mod doppler_schedule;
pub mod mode_category;
pub mod mutual;
pub mod pass_predictor;
pub mod polarization;
pub mod propagator;
pub mod tracker;
pub mod workability;

/// An observer site (geodetic, altitude in meters — always 0 today, matching
/// the Swift `LatLonAlt(lat, lon, 0)` call sites).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Observer {
    pub lat_deg: f64,
    pub lon_deg: f64,
    pub alt_m: f64,
}

impl Observer {
    pub fn new(lat_deg: f64, lon_deg: f64) -> Self {
        Observer { lat_deg, lon_deg, alt_m: 0.0 }
    }
}

/// One two-line element set as fetched from SatNOGS. Mirrors `SatNOGSTLE`
/// (`SatNOGSClient.swift`) minus the fetch metadata.
#[derive(Debug, Clone, PartialEq)]
pub struct SatTle {
    /// Display name with any leading `"0 "` line-zero marker already handled
    /// by [`display_name::from_tle0`].
    pub name: String,
    pub norad_id: u32,
    pub line1: String,
    pub line2: String,
}

/// One SatNOGS transmitter row. Mirrors `SatNOGSTransmitter`
/// (`SatNOGSClient.swift`), including its computed properties.
#[derive(Debug, Clone, PartialEq)]
pub struct SatTransmitter {
    pub description: String,
    pub transmitter_type: String,
    pub alive: bool,
    pub status: String,
    pub service: String,
    pub mode: Option<String>,
    pub uplink_low_hz: Option<i64>,
    pub downlink_low_hz: Option<i64>,
    /// Upper passband edges (linear transponders); `None` for single-channel
    /// transmitters and beacons.
    pub uplink_high_hz: Option<i64>,
    pub downlink_high_hz: Option<i64>,
    /// Inverting transponder (SatNOGS `invert`): tuning up on the downlink
    /// means tuning down on the uplink.
    pub invert: bool,
    pub norad_id: Option<u32>,
}

impl SatTransmitter {
    /// `service == "Amateur" || "Amateur-satellite"`.
    pub fn is_amateur(&self) -> bool {
        self.service == "Amateur" || self.service == "Amateur-satellite"
    }

    /// SatNOGS `status == "active"`.
    pub fn is_active(&self) -> bool {
        self.status == "active"
    }
}
