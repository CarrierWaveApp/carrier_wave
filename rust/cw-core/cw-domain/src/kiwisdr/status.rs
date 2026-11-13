//! KiwiSDR `/status` endpoint parsing. Port of `KiwiSDRStatusFetcher.swift`
//! (`ReceiverStatus` + `parseStatusResponse`); the HTTP fetch lives in
//! `cw-net`.

use crate::antenna::{parse_antenna_description, ParsedAntenna};

/// Enriched receiver status from the `/status` endpoint.
#[derive(Debug, Clone, PartialEq)]
pub struct ReceiverStatus {
    /// `host:port`.
    pub host_port: String,
    pub antenna: String,
    pub parsed_antenna: ParsedAntenna,
    pub bands_hz: Option<String>,
    pub snr_all: Option<i32>,
    pub snr_hf: Option<i32>,
    pub ant_connected: bool,
    pub grid: Option<String>,
    pub asl: Option<i32>,
    pub users: i32,
    pub users_max: i32,
    pub uptime: Option<i64>,
    pub software_version: Option<String>,
}

impl ReceiverStatus {
    /// The SNR figure used for receiver-quality decisions: HF when present,
    /// otherwise the all-band figure.
    pub fn effective_snr(&self) -> Option<i32> {
        self.snr_hf.or(self.snr_all)
    }
}

/// Parse the plain-text `key=value` lines of a `/status` response.
pub fn parse_status_response(text: &str, host: &str, port: u16) -> ReceiverStatus {
    let mut fields = std::collections::HashMap::new();
    for line in text.lines() {
        if let Some((key, value)) = line.split_once('=') {
            fields.insert(key.trim().to_string(), value.trim().to_string());
        }
    }

    let antenna = fields.get("antenna").cloned().unwrap_or_default();
    let parsed_antenna = parse_antenna_description(&antenna);

    // SNR field: `all,HF`, e.g. `28,32`.
    let snr_raw = fields.get("snr").cloned().unwrap_or_default();
    let snr_parts: Vec<&str> = snr_raw.split(',').collect();
    let snr_all = snr_parts.first().and_then(|v| v.parse().ok());
    let snr_hf = if snr_parts.len() > 1 { snr_parts[1].parse().ok() } else { None };

    let ant_connected = match fields.get("ant_connected") {
        Some(val) => val == "1" || val.eq_ignore_ascii_case("true") || val.eq_ignore_ascii_case("yes"),
        // Assume connected if the field is missing.
        None => true,
    };

    ReceiverStatus {
        host_port: format!("{host}:{port}"),
        antenna,
        parsed_antenna,
        bands_hz: fields.get("bands").cloned(),
        snr_all,
        snr_hf,
        ant_connected,
        grid: fields.get("grid").cloned(),
        asl: fields.get("asl").and_then(|v| v.parse().ok()),
        users: fields.get("users").and_then(|v| v.parse().ok()).unwrap_or(0),
        users_max: fields.get("users_max").and_then(|v| v.parse().ok()).unwrap_or(0),
        uptime: fields.get("uptime").and_then(|v| v.parse().ok()),
        software_version: fields.get("sw_version").cloned(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const STATUS: &str = "status=active\n\
        antenna=80m dipole NE/SW\n\
        snr=28,32\n\
        ant_connected=1\n\
        grid=CN85nn\n\
        asl=120\n\
        users=2\n\
        users_max=4\n\
        uptime=86400\n\
        sw_version=KiwiSDR_v1.690\n\
        bands=0-30000000\n";

    #[test]
    fn parses_full_status() {
        let status = parse_status_response(STATUS, "kiwi.example.com", 8_073);
        assert_eq!(status.host_port, "kiwi.example.com:8073");
        assert_eq!(status.antenna, "80m dipole NE/SW");
        assert_eq!(status.snr_all, Some(28));
        assert_eq!(status.snr_hf, Some(32));
        assert_eq!(status.effective_snr(), Some(32));
        assert!(status.ant_connected);
        assert_eq!(status.grid.as_deref(), Some("CN85nn"));
        assert_eq!(status.asl, Some(120));
        assert_eq!(status.users, 2);
        assert_eq!(status.users_max, 4);
        assert_eq!(status.uptime, Some(86_400));
        assert_eq!(status.software_version.as_deref(), Some("KiwiSDR_v1.690"));
        assert_eq!(status.bands_hz.as_deref(), Some("0-30000000"));
    }

    #[test]
    fn missing_ant_connected_assumes_connected() {
        let status = parse_status_response("users=0", "h", 8_073);
        assert!(status.ant_connected);
        assert_eq!(status.effective_snr(), None);
    }

    #[test]
    fn single_snr_value_populates_all_only() {
        let status = parse_status_response("snr=25", "h", 8_073);
        assert_eq!(status.snr_all, Some(25));
        assert_eq!(status.snr_hf, None);
        assert_eq!(status.effective_snr(), Some(25));
    }

    #[test]
    fn ant_connected_textual_forms() {
        assert!(parse_status_response("ant_connected=true", "h", 1).ant_connected);
        assert!(parse_status_response("ant_connected=YES", "h", 1).ant_connected);
        assert!(!parse_status_response("ant_connected=0", "h", 1).ant_connected);
    }
}
