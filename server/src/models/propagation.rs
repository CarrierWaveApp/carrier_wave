//! Request and response models for the HF propagation proxy endpoints.
//!
//! These mirror `server/propagation/app/schemas.py` — field names and JSON
//! shapes must stay aligned. Keep this file and that Python module in sync.

use serde::{Deserialize, Serialize};

// MARK: - Point-to-point

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct PointToPointRequest {
    pub tx_lat: f64,
    pub tx_lon: f64,
    pub rx_lat: f64,
    pub rx_lon: f64,
    pub month: u32,
    pub utc_hour: f64,
    pub ssn: f64,
    #[serde(default = "default_power_w")]
    pub tx_power_w: f64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub frequencies_mhz: Option<Vec<f64>>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct BandPrediction {
    pub freq_mhz: f64,
    pub hop_count: Option<u32>,
    pub tx_elevation_deg: Option<f64>,
    pub total_loss_db: Option<f64>,
    pub snr_db: Option<f64>,
    pub reliability: Option<f64>,
    pub service_prob: Option<f64>,
    pub multipath_prob: Option<f64>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct PathGeometry {
    pub distance_km: f64,
    pub bearing_deg: f64,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct PointToPointResponse {
    pub muf_mhz: Option<f64>,
    pub path: PathGeometry,
    pub bands: Vec<BandPrediction>,
}

// MARK: - Wheel

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct WheelRequest {
    pub lat: f64,
    pub lon: f64,
    pub month: u32,
    pub utc_hour: f64,
    pub ssn: f64,
    #[serde(default = "default_power_w")]
    pub tx_power_w: f64,
    #[serde(default = "default_radius_km")]
    pub radius_km: f64,
    #[serde(default = "default_azimuth_step_deg")]
    pub azimuth_step_deg: f64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub frequencies_mhz: Option<Vec<f64>>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct WheelSpoke {
    pub azimuth_deg: f64,
    pub rx_lat: f64,
    pub rx_lon: f64,
    pub bands: Vec<BandPrediction>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct WheelResponse {
    pub centre_lat: f64,
    pub centre_lon: f64,
    pub radius_km: f64,
    pub spokes: Vec<WheelSpoke>,
}

// MARK: - Defaults

fn default_power_w() -> f64 {
    100.0
}

fn default_radius_km() -> f64 {
    5000.0
}

fn default_azimuth_step_deg() -> f64 {
    15.0
}
