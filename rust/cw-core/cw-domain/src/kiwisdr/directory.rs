//! KiwiSDR public-directory models and parsing. Port of
//! `WebSDRDirectory.swift` (`KiwiSDRReceiver`, Skywavelinux JSON parsing, and
//! the legacy kiwisdr.com HTML fallback). Fetching and caching live in
//! `cw-net`; everything here is pure parsing + geometry.

use regex::Regex;
use serde_json::Value;

/// A KiwiSDR receiver from the public directory.
#[derive(Debug, Clone, PartialEq)]
pub struct KiwiSdrReceiver {
    /// `host:port`.
    pub id: String,
    pub name: String,
    pub host: String,
    pub port: u16,
    pub latitude: f64,
    pub longitude: f64,
    /// Human-readable band coverage, e.g. `0-30 MHz`.
    pub bands: String,
    pub users: i32,
    pub max_users: i32,
    /// e.g. `Portland, OR, USA`.
    pub location: String,
    pub antenna: String,
    /// Distance from a reference point in km (set by [`find_nearby`]).
    pub distance_km: Option<f64>,
    // Enrichment fields from the directory feed or `/status`.
    pub snr_all: Option<i32>,
    pub snr_hf: Option<i32>,
    pub ant_connected: Option<bool>,
    pub grid: Option<String>,
    pub asl: Option<i32>,
    pub enriched_antenna: Option<String>,
}

impl KiwiSdrReceiver {
    /// Whether the receiver has a free channel.
    pub fn is_available(&self) -> bool {
        self.users < self.max_users
    }
}

/// Great-circle distance between two coordinates in km (haversine, mean Earth
/// radius). The Swift port used `CLLocation.distance`; for the 500 km
/// directory radius the difference is well under the ranking granularity.
pub fn haversine_km(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    const EARTH_RADIUS_KM: f64 = 6_371.008_8;
    let d_lat = (lat2 - lat1).to_radians();
    let d_lon = (lon2 - lon1).to_radians();
    let a = (d_lat / 2.0).sin().powi(2)
        + lat1.to_radians().cos() * lat2.to_radians().cos() * (d_lon / 2.0).sin().powi(2);
    2.0 * EARTH_RADIUS_KM * a.sqrt().atan2((1.0 - a).sqrt())
}

/// Filter `receivers` to those within `max_distance_km` of the reference
/// point, annotate `distance_km`, sort nearest-first, and cap at `limit`.
/// With no reference point the list is returned as-is (capped). Port of
/// `WebSDRDirectory.findNearby`'s pure half.
pub fn find_nearby(
    receivers: &[KiwiSdrReceiver],
    reference: Option<(f64, f64)>,
    max_distance_km: f64,
    limit: usize,
) -> Vec<KiwiSdrReceiver> {
    let mut results: Vec<KiwiSdrReceiver> = match reference {
        Some((ref_lat, ref_lon)) => {
            let mut annotated: Vec<KiwiSdrReceiver> = receivers
                .iter()
                .filter_map(|receiver| {
                    let km = haversine_km(
                        ref_lat, ref_lon, receiver.latitude, receiver.longitude,
                    );
                    if km <= max_distance_km {
                        let mut updated = receiver.clone();
                        updated.distance_km = Some(km);
                        Some(updated)
                    } else {
                        None
                    }
                })
                .collect();
            annotated.sort_by(|a, b| {
                let da = a.distance_km.unwrap_or(f64::INFINITY);
                let db = b.distance_km.unwrap_or(f64::INFINITY);
                da.partial_cmp(&db).unwrap_or(std::cmp::Ordering::Equal)
            });
            annotated
        }
        None => receivers.to_vec(),
    };
    results.truncate(limit);
    results
}

/// Parse the Skywavelinux JS mirror (`var kiwisdr_com = [ … ];`) into
/// receivers. Inactive/offline entries are dropped.
pub fn parse_directory_js(js: &str) -> Vec<KiwiSdrReceiver> {
    let Some(bracket) = js.find('[') else {
        return Vec::new();
    };
    let mut json = js[bracket..].trim().to_string();
    if let Some(stripped) = json.strip_suffix(';') {
        json = stripped.trim().to_string();
    }
    // The JS file has trailing commas (`"key": "val",}`) — strip them.
    let trailing_comma = Regex::new(r",\s*([}\]])").expect("static regex");
    let json = trailing_comma.replace_all(&json, "$1");

    let Ok(Value::Array(entries)) = serde_json::from_str::<Value>(&json) else {
        return Vec::new();
    };
    entries.iter().filter_map(parse_json_entry).collect()
}

fn parse_json_entry(entry: &Value) -> Option<KiwiSdrReceiver> {
    if entry.get("status")?.as_str()? != "active" || entry.get("offline")?.as_str()? != "no" {
        return None;
    }

    // Extract host and port from the url field (e.g. `http://host:port`).
    let url = entry.get("url")?.as_str()?;
    let (host, port) = host_port_from_url(url)?;

    let name = str_field(entry, "name").unwrap_or_else(|| host.clone());
    let coords = parse_coordinates(&str_field(entry, "gps").unwrap_or_default());
    let users = int_field(entry, "users", 0);
    let max_users = int_field(entry, "users_max", 4);
    let location = str_field(entry, "loc").unwrap_or_default();
    let antenna = str_field(entry, "antenna").unwrap_or_default();
    let bands = format_bands(&str_field(entry, "bands").unwrap_or_else(|| "0-30000000".into()));
    let grid = str_field(entry, "grid");
    let snr = str_field(entry, "snr");
    let snr_parts: Option<Vec<&str>> = snr.as_deref().map(|s| s.split(',').collect());
    let snr_all = snr_parts.as_ref().and_then(|p| p.first()?.parse().ok());
    let snr_hf = snr_parts.as_ref().and_then(|p| p.last()?.parse().ok());
    let ant_connected = str_field(entry, "ant_connected").map(|v| v == "1");

    Some(KiwiSdrReceiver {
        id: format!("{host}:{port}"),
        name,
        host,
        port,
        latitude: coords.map_or(0.0, |c| c.0),
        longitude: coords.map_or(0.0, |c| c.1),
        bands,
        users,
        max_users,
        location,
        antenna,
        distance_km: None,
        snr_all,
        snr_hf,
        ant_connected,
        grid,
        asl: None,
        enriched_antenna: None,
    })
}

/// Extract `(host, port)` from an `http://host[:port]` URL string; the default
/// KiwiSDR port is 8073.
fn host_port_from_url(url: &str) -> Option<(String, u16)> {
    let rest = url.split("://").nth(1).unwrap_or(url);
    let authority = rest.split('/').next()?;
    if authority.is_empty() {
        return None;
    }
    let mut parts = authority.split(':');
    let host = parts.next()?.to_string();
    if host.is_empty() {
        return None;
    }
    let port = parts.next().and_then(|p| p.parse().ok()).unwrap_or(8_073);
    Some((host, port))
}

fn str_field(entry: &Value, key: &str) -> Option<String> {
    entry.get(key)?.as_str().map(str::to_string)
}

/// Directory feeds encode numbers as either strings or ints.
fn int_field(entry: &Value, key: &str, fallback: i32) -> i32 {
    match entry.get(key) {
        Some(Value::String(text)) => text.parse().unwrap_or(fallback),
        Some(Value::Number(num)) => num.as_i64().map_or(fallback, |v| v as i32),
        _ => fallback,
    }
}

/// Parse the legacy kiwisdr.com HTML directory. Receiver metadata is embedded
/// in HTML comments inside `cl-entry` blocks.
pub fn parse_directory_html(html: &str) -> Vec<KiwiSdrReceiver> {
    let blocks: Vec<&str> = html.split("<div class='cl-entry").collect();
    if blocks.len() <= 1 {
        return Vec::new();
    }

    let comment = Regex::new(r"<!--\s*(\w+)=(.+?)\s*-->").expect("static regex");
    blocks[1..]
        .iter()
        .filter_map(|block| {
            let mut fields = std::collections::HashMap::new();
            for cap in comment.captures_iter(block) {
                fields.insert(cap[1].to_string(), cap[2].trim().to_string());
            }
            build_receiver_from_html(block, &fields)
        })
        .collect()
}

fn build_receiver_from_html(
    block: &str,
    fields: &std::collections::HashMap<String, String>,
) -> Option<KiwiSdrReceiver> {
    if fields.get("status").map(String::as_str) != Some("active") {
        return None;
    }

    let link_start = block.find("href='http://")? + "href='http://".len();
    let link_end = block[link_start..].find('\'')? + link_start;
    let host_port = &block[link_start..link_end];
    let mut parts = host_port.split(':');
    let host = parts.next()?.to_string();
    let port: u16 = parts.next().and_then(|p| p.parse().ok()).unwrap_or(8_073);
    let coords = parse_coordinates(fields.get("gps").map(String::as_str).unwrap_or(""));

    Some(KiwiSdrReceiver {
        id: format!("{host}:{port}"),
        name: fields.get("name").cloned().unwrap_or_else(|| host.clone()),
        host,
        port,
        latitude: coords.map_or(0.0, |c| c.0),
        longitude: coords.map_or(0.0, |c| c.1),
        bands: format_bands(fields.get("bands").map(String::as_str).unwrap_or("0-30000000")),
        users: fields.get("users").and_then(|v| v.parse().ok()).unwrap_or(0),
        max_users: fields.get("users_max").and_then(|v| v.parse().ok()).unwrap_or(4),
        location: fields.get("loc").cloned().unwrap_or_default(),
        antenna: fields.get("antenna").cloned().unwrap_or_default(),
        distance_km: None,
        snr_all: None,
        snr_hf: None,
        ant_connected: None,
        grid: None,
        asl: None,
        enriched_antenna: None,
    })
}

/// Convert a raw band range in Hz (`"0-30000000"`, possibly comma-separated)
/// to a human-readable MHz string.
pub fn format_bands(raw: &str) -> String {
    let first_range = raw.split(',').next().unwrap_or(raw);
    let bounds: Vec<&str> = first_range.split('-').collect();
    if bounds.len() == 2 {
        if let (Ok(low), Ok(high)) = (bounds[0].parse::<f64>(), bounds[1].parse::<f64>()) {
            return format!("{:.0}-{:.0} MHz", low / 1_000_000.0, high / 1_000_000.0);
        }
    }
    raw.to_string()
}

/// Parse a `(lat, lon)` GPS string (with or without parentheses).
pub fn parse_coordinates(raw: &str) -> Option<(f64, f64)> {
    let cleaned = raw.replace(['(', ')'], "");
    let parts: Vec<&str> = cleaned.split(',').map(str::trim).collect();
    if parts.len() != 2 {
        return None;
    }
    Some((parts[0].parse().ok()?, parts[1].parse().ok()?))
}

#[cfg(test)]
mod tests {
    use super::*;

    const DIRECTORY_JS: &str = r#"var kiwisdr_com = [
    {
        "url": "http://kiwi.example.com:8073",
        "name": "Example Kiwi",
        "status": "active",
        "offline": "no",
        "gps": "(45.52, -122.68)",
        "users": "1",
        "users_max": "4",
        "loc": "Portland, OR, USA",
        "antenna": "Wideband dipole",
        "bands": "0-30000000",
        "grid": "CN85",
        "snr": "23,29",
        "ant_connected": "1",
    },
    {
        "url": "http://down.example.com:8073",
        "status": "active",
        "offline": "yes",
    },
    {
        "url": "http://inactive.example.com:8073",
        "status": "retired",
        "offline": "no",
    },
];"#;

    #[test]
    fn parses_js_directory_and_drops_offline() {
        let receivers = parse_directory_js(DIRECTORY_JS);
        assert_eq!(receivers.len(), 1);
        let rx = &receivers[0];
        assert_eq!(rx.id, "kiwi.example.com:8073");
        assert_eq!(rx.name, "Example Kiwi");
        assert_eq!(rx.port, 8_073);
        assert!((rx.latitude - 45.52).abs() < 1e-9);
        assert!((rx.longitude - -122.68).abs() < 1e-9);
        assert_eq!(rx.bands, "0-30 MHz");
        assert_eq!(rx.users, 1);
        assert_eq!(rx.max_users, 4);
        assert!(rx.is_available());
        assert_eq!(rx.snr_all, Some(23));
        assert_eq!(rx.snr_hf, Some(29));
        assert_eq!(rx.ant_connected, Some(true));
        assert_eq!(rx.grid.as_deref(), Some("CN85"));
    }

    #[test]
    fn js_parsing_handles_int_users_and_default_port() {
        let js = r#"var kiwisdr_com = [
            {"url": "http://noport.example.com", "status": "active", "offline": "no",
             "users": 3, "users_max": 3}
        ];"#;
        let receivers = parse_directory_js(js);
        assert_eq!(receivers.len(), 1);
        assert_eq!(receivers[0].port, 8_073);
        assert_eq!(receivers[0].users, 3);
        assert!(!receivers[0].is_available());
    }

    #[test]
    fn js_parsing_tolerates_garbage() {
        assert!(parse_directory_js("not js at all").is_empty());
        assert!(parse_directory_js("var kiwisdr_com = [ {bogus ]").is_empty());
    }

    const DIRECTORY_HTML: &str = r#"
<div class='cl-entry'>
<!-- name=HTML Kiwi -->
<!-- status=active -->
<!-- gps=(51.5, -0.12) -->
<!-- users=0 -->
<!-- users_max=8 -->
<!-- loc=London, UK -->
<!-- antenna=Mini-whip -->
<!-- bands=0-30000000 -->
<a href='http://html.example.com:8074'>link</a>
</div>
<div class='cl-entry'>
<!-- name=Inactive -->
<!-- status=offline -->
<a href='http://dead.example.com:8073'>link</a>
</div>
"#;

    #[test]
    fn parses_html_fallback() {
        let receivers = parse_directory_html(DIRECTORY_HTML);
        assert_eq!(receivers.len(), 1);
        let rx = &receivers[0];
        assert_eq!(rx.name, "HTML Kiwi");
        assert_eq!(rx.host, "html.example.com");
        assert_eq!(rx.port, 8_074);
        assert_eq!(rx.max_users, 8);
        assert_eq!(rx.location, "London, UK");
    }

    #[test]
    fn nearby_filters_sorts_and_annotates() {
        let make = |id: &str, lat: f64, lon: f64| KiwiSdrReceiver {
            id: id.into(),
            name: id.into(),
            host: id.into(),
            port: 8_073,
            latitude: lat,
            longitude: lon,
            bands: String::new(),
            users: 0,
            max_users: 4,
            location: String::new(),
            antenna: String::new(),
            distance_km: None,
            snr_all: None,
            snr_hf: None,
            ant_connected: None,
            grid: None,
            asl: None,
            enriched_antenna: None,
        };
        // Reference: Portland OR. far = Denver (~1,600 km), near = Salem (~70 km).
        let receivers = vec![
            make("far", 39.74, -104.99),
            make("near", 44.94, -123.03),
            make("mid", 47.61, -122.33),
        ];
        let nearby = find_nearby(&receivers, Some((45.52, -122.68)), 500.0, 10);
        assert_eq!(nearby.len(), 2);
        assert_eq!(nearby[0].id, "near");
        assert_eq!(nearby[1].id, "mid");
        assert!(nearby[0].distance_km.unwrap() < nearby[1].distance_km.unwrap());

        let capped = find_nearby(&receivers, Some((45.52, -122.68)), 500.0, 1);
        assert_eq!(capped.len(), 1);

        // No reference point: passthrough capped.
        assert_eq!(find_nearby(&receivers, None, 500.0, 2).len(), 2);
    }

    #[test]
    fn haversine_sanity() {
        // Portland → Seattle is roughly 233 km.
        let km = haversine_km(45.52, -122.68, 47.61, -122.33);
        assert!((km - 233.0).abs() < 5.0, "got {km}");
        assert!(haversine_km(0.0, 0.0, 0.0, 0.0) < 1e-9);
    }

    #[test]
    fn band_and_coordinate_helpers() {
        assert_eq!(format_bands("0-30000000"), "0-30 MHz");
        assert_eq!(format_bands("100000-14000000,20000000-30000000"), "0-14 MHz");
        assert_eq!(format_bands("garbage"), "garbage");
        assert_eq!(parse_coordinates("(1.5, -2.25)"), Some((1.5, -2.25)));
        assert_eq!(parse_coordinates("1.5,-2.25"), Some((1.5, -2.25)));
        assert_eq!(parse_coordinates("bogus"), None);
    }
}
