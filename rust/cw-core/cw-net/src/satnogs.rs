//! SatNOGS DB client: bulk TLE + transmitter fetches. Port of the network
//! half of `SatNOGSClient.swift` (the 6 h disk cache moves to
//! `cw-store::satellite_cache`; the cache-through policy lives in
//! `cw-ffi::satellite_api`).

use serde::{Deserialize, Serialize};

use crate::http::{HttpClient, HttpError};
use cw_domain::satellite::display_name;
use cw_domain::satellite::{SatTle, SatTransmitter};

const TLE_URL: &str = "https://db.satnogs.org/api/tle/?format=json";
const TRANSMITTERS_URL: &str = "https://db.satnogs.org/api/transmitters/?format=json";
const SATELLITES_URL: &str = "https://db.satnogs.org/api/satellites/?format=json";

/// One SatNOGS `/api/tle/` row (wire shape). `Serialize` so the cw-store
/// blob cache can persist the fetched rows verbatim.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SatnogsTle {
    pub tle0: String,
    pub tle1: String,
    pub tle2: String,
    #[serde(default)]
    pub tle_source: Option<String>,
    #[serde(default)]
    pub sat_id: Option<String>,
    pub norad_cat_id: u32,
    #[serde(default)]
    pub updated: Option<String>,
}

impl From<&SatnogsTle> for SatTle {
    fn from(wire: &SatnogsTle) -> SatTle {
        SatTle {
            name: display_name::from_tle0(&wire.tle0),
            norad_id: wire.norad_cat_id,
            line1: wire.tle1.clone(),
            line2: wire.tle2.clone(),
        }
    }
}

/// One SatNOGS `/api/transmitters/` row (wire shape).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SatnogsTransmitter {
    #[serde(default)]
    pub description: String,
    #[serde(rename = "type", default)]
    pub transmitter_type: String,
    #[serde(default)]
    pub alive: bool,
    #[serde(default)]
    pub status: String,
    #[serde(default)]
    pub service: String,
    #[serde(default)]
    pub mode: Option<String>,
    #[serde(default)]
    pub uplink_low: Option<i64>,
    #[serde(default)]
    pub downlink_low: Option<i64>,
    #[serde(default)]
    pub uplink_high: Option<i64>,
    #[serde(default)]
    pub downlink_high: Option<i64>,
    /// Inverting linear transponder: the uplink passband maps onto the
    /// downlink in reverse, so a dial move up on the downlink is a move
    /// down on the uplink.
    #[serde(default)]
    pub invert: bool,
    #[serde(default)]
    pub norad_cat_id: Option<u32>,
}

impl From<&SatnogsTransmitter> for SatTransmitter {
    fn from(wire: &SatnogsTransmitter) -> SatTransmitter {
        SatTransmitter {
            description: wire.description.clone(),
            transmitter_type: wire.transmitter_type.clone(),
            alive: wire.alive,
            status: wire.status.clone(),
            service: wire.service.clone(),
            mode: wire.mode.clone(),
            uplink_low_hz: wire.uplink_low,
            downlink_low_hz: wire.downlink_low,
            uplink_high_hz: wire.uplink_high,
            downlink_high_hz: wire.downlink_high,
            invert: wire.invert,
            norad_id: wire.norad_cat_id,
        }
    }
}

/// One SatNOGS `/api/satellites/` row (wire shape). The catalog names here
/// are canonical ("CAS-6 (TO-108)") where the TLE `tle0` line often carries
/// launch placeholders ("0 OBJECT C"); `names` holds newline-separated
/// aliases (e.g. "FO-29" for the satellite named "JAS-2").
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SatnogsSatellite {
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub names: Option<String>,
    #[serde(default)]
    pub norad_cat_id: Option<u32>,
    #[serde(default)]
    pub status: Option<String>,
}

pub struct SatnogsClient {
    http: HttpClient,
}

impl SatnogsClient {
    pub fn new(http: HttpClient) -> Self {
        Self { http }
    }

    /// Bulk TLE fetch. An empty array is an error (port of
    /// `SatNOGSClientError.emptyResponse`); SatNOGS answers 401/403 when it
    /// starts requiring an API key for bulk endpoints — surfaced in the
    /// error body text by the shared HttpClient.
    pub async fn fetch_tles(&self) -> Result<Vec<SatnogsTle>, HttpError> {
        let tles: Vec<SatnogsTle> = self.http.get_json(TLE_URL).await?;
        if tles.is_empty() {
            return Err(HttpError::Parse("SatNOGS returned no TLEs".to_string()));
        }
        Ok(tles)
    }

    /// Bulk transmitter fetch; empty is an error like the TLE path.
    pub async fn fetch_transmitters(&self) -> Result<Vec<SatnogsTransmitter>, HttpError> {
        let rows: Vec<SatnogsTransmitter> = self.http.get_json(TRANSMITTERS_URL).await?;
        if rows.is_empty() {
            return Err(HttpError::Parse("SatNOGS returned no transmitters".to_string()));
        }
        Ok(rows)
    }

    /// Bulk satellite-catalog fetch (canonical names); empty is an error.
    pub async fn fetch_satellites(&self) -> Result<Vec<SatnogsSatellite>, HttpError> {
        let rows: Vec<SatnogsSatellite> = self.http.get_json(SATELLITES_URL).await?;
        if rows.is_empty() {
            return Err(HttpError::Parse("SatNOGS returned no satellites".to_string()));
        }
        Ok(rows)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_tle_wire_shape() {
        let json = r#"[{"tle0":"0 ISS (ZARYA)",
            "tle1":"1 25544U 98067A   26262.30395647  .00006211  00000-0  12007-3 0  9998",
            "tle2":"2 25544  51.6308 194.2901 0004815 157.3949 202.7252 15.49175317586346",
            "tle_source":"Space-Track.org",
            "sat_id":"XSKZ-5603-1870-9019-3066",
            "norad_cat_id":25544,
            "updated":"2026-09-19T17:22:10.589047Z"}]"#;
        let rows: Vec<SatnogsTle> = serde_json::from_str(json).expect("decodes");
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].norad_cat_id, 25_544);
        let domain = SatTle::from(&rows[0]);
        assert_eq!(domain.name, "ISS (ZARYA)");
        assert!(domain.line1.starts_with("1 25544U"));
    }

    #[test]
    fn decodes_transmitter_wire_shape() {
        let json = r#"[{"description":"Mode U/V Linear Transponder",
            "type":"Transponder","alive":true,"status":"active",
            "service":"Amateur","mode":"SSB",
            "uplink_low":435030000,"uplink_high":435050000,
            "downlink_low":145980000,"downlink_high":145960000,"invert":true,
            "norad_cat_id":44909}]"#;
        let rows: Vec<SatnogsTransmitter> = serde_json::from_str(json).expect("decodes");
        let domain = SatTransmitter::from(&rows[0]);
        assert!(domain.is_amateur());
        assert!(domain.is_active());
        assert_eq!(domain.downlink_low_hz, Some(145_980_000));
        assert_eq!(domain.uplink_high_hz, Some(435_050_000));
        assert_eq!(domain.downlink_high_hz, Some(145_960_000));
        assert!(domain.invert);
        assert_eq!(domain.norad_id, Some(44_909));
    }

    #[test]
    fn decodes_satellite_wire_shape() {
        let json = r#"[{"name":"CAS-6 (TO-108)","names":"2019-093C",
            "norad_cat_id":44881,"status":"in orbit"},
            {"name":"JAS-2","names":"FO-29","norad_cat_id":24278,"status":"in orbit"},
            {"name":"Unlaunched","norad_cat_id":null}]"#;
        let rows: Vec<SatnogsSatellite> = serde_json::from_str(json).expect("decodes");
        assert_eq!(rows.len(), 3);
        assert_eq!(rows[0].norad_cat_id, Some(44_881));
        assert_eq!(rows[1].names.as_deref(), Some("FO-29"));
        assert_eq!(rows[2].norad_cat_id, None);
    }

    #[test]
    fn tolerates_missing_optional_fields() {
        let json = r#"[{"tle0":"X","tle1":"1","tle2":"2","norad_cat_id":7}]"#;
        let rows: Vec<SatnogsTle> = serde_json::from_str(json).expect("decodes");
        assert_eq!(rows[0].norad_cat_id, 7);
        let json = r#"[{"norad_cat_id":7,"service":"Amateur","status":"active"}]"#;
        let rows: Vec<SatnogsTransmitter> = serde_json::from_str(json).expect("decodes");
        assert!(SatTransmitter::from(&rows[0]).is_amateur());
    }
}
