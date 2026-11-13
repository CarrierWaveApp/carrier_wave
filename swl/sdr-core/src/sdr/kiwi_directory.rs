use regex::Regex;
use tracing::warn;

/// A single entry parsed from the public KiwiSDR directory.
#[derive(Debug, Clone)]
pub struct KiwiDirectoryEntry {
    pub url: String,
    pub name: String,
    pub lat: f64,
    pub lon: f64,
    pub id: String,
    pub users: Option<u32>,
    pub users_max: Option<u32>,
    pub grid: Option<String>,
    pub snr: Option<String>,
    pub antenna: Option<String>,
    pub location: Option<String>,
    pub offline: Option<bool>,
}

/// Bounding-box filter for a country or region.
#[derive(Debug, Clone)]
pub struct CountryFilter {
    pub code: String,
    pub lat_range: (f64, f64),
    pub lon_range: (f64, f64),
}

/// Return built-in country/region filters for the given codes.
///
/// `"*"` means no filtering (all entries pass). Unknown codes are skipped
/// with a warning.
pub fn builtin_filters(codes: &[String]) -> Vec<CountryFilter> {
    if codes.iter().any(|c| c == "*") {
        return vec![];
    }

    let mut filters = Vec::new();
    for code in codes {
        match code.to_uppercase().as_str() {
            "US" => filters.push(CountryFilter {
                code: "US".into(),
                lat_range: (24.5, 49.5),
                lon_range: (-125.0, -66.0),
            }),
            "CA" => filters.push(CountryFilter {
                code: "CA".into(),
                lat_range: (41.0, 84.0),
                lon_range: (-141.0, -52.0),
            }),
            "EU" => filters.push(CountryFilter {
                code: "EU".into(),
                lat_range: (35.0, 72.0),
                lon_range: (-25.0, 45.0),
            }),
            "AS" => filters.push(CountryFilter {
                code: "AS".into(),
                lat_range: (-10.0, 55.0),
                lon_range: (25.0, 180.0),
            }),
            "SA" => filters.push(CountryFilter {
                code: "SA".into(),
                lat_range: (-56.0, 13.0),
                lon_range: (-82.0, -34.0),
            }),
            "OC" => filters.push(CountryFilter {
                code: "OC".into(),
                lat_range: (-50.0, 0.0),
                lon_range: (110.0, 180.0),
            }),
            "AF" => filters.push(CountryFilter {
                code: "AF".into(),
                lat_range: (-35.0, 38.0),
                lon_range: (-18.0, 52.0),
            }),
            other => {
                warn!(code = other, "Unknown KiwiSDR region code, skipping");
            }
        }
    }
    filters
}

/// Fetch the public KiwiSDR directory HTML and parse entries.
pub async fn fetch_kiwisdr_directory(
    client: &reqwest::Client,
) -> Result<Vec<KiwiDirectoryEntry>, String> {
    let html = client
        .get("http://kiwisdr.com/.public/")
        .send()
        .await
        .map_err(|e| format!("HTTP request failed: {e}"))?
        .text()
        .await
        .map_err(|e| format!("Failed to read response body: {e}"))?;

    Ok(parse_kiwisdr_html(&html))
}

/// Parse KiwiSDR directory HTML into entries.
///
/// Each receiver entry contains structured HTML comments and a link:
/// ```text
/// <!-- gps=(lat,lon) -->
/// <!-- name=Station Name -->
/// <!-- id=mac-address -->
/// <a href='http://host:8073' ...>host:8073</a>
/// ```
pub fn parse_kiwisdr_html(html: &str) -> Vec<KiwiDirectoryEntry> {
    let gps_re = Regex::new(r"<!--\s*gps=\(([^,]+),\s*([^)]+)\)\s*-->").unwrap();
    let name_re = Regex::new(r"<!--\s*name=(.+?)\s*-->").unwrap();
    let id_re = Regex::new(r"<!--\s*id=(.+?)\s*-->").unwrap();
    let url_re = Regex::new(r#"<a\s+[^>]*href=['"]?(https?://[^'">\s]+)['"]?"#).unwrap();
    let users_re = Regex::new(r"<!--\s*users=(\d+)\s*-->").unwrap();
    let users_max_re = Regex::new(r"<!--\s*users_max=(\d+)\s*-->").unwrap();
    let grid_re = Regex::new(r"<!--\s*grid=(.+?)\s*-->").unwrap();
    let snr_re = Regex::new(r"<!--\s*snr=(.+?)\s*-->").unwrap();
    let antenna_re = Regex::new(r"<!--\s*antenna=(.+?)\s*-->").unwrap();
    let loc_re = Regex::new(r"<!--\s*loc=(.+?)\s*-->").unwrap();
    let offline_re = Regex::new(r"<!--\s*offline=(.+?)\s*-->").unwrap();

    // Split into blocks. Each receiver is inside a div; we split on a pattern
    // that separates entries. The directory uses `<!-- id=` as a reliable marker
    // for each entry block.
    let blocks: Vec<&str> = html.split("<!-- id=").collect();

    let mut entries = Vec::new();

    for block in blocks.iter().skip(1) {
        // Re-prepend the split delimiter for the id regex to match
        let full_block = format!("<!-- id={block}");

        let id = match id_re.captures(&full_block) {
            Some(cap) => cap[1].trim().to_string(),
            None => continue,
        };

        let (lat, lon) = match gps_re.captures(&full_block) {
            Some(cap) => {
                let lat: f64 = match cap[1].trim().parse() {
                    Ok(v) => v,
                    Err(_) => continue,
                };
                let lon: f64 = match cap[2].trim().parse() {
                    Ok(v) => v,
                    Err(_) => continue,
                };
                (lat, lon)
            }
            None => continue,
        };

        let name = name_re
            .captures(&full_block)
            .map(|cap| cap[1].trim().to_string())
            .unwrap_or_else(|| id.clone());

        let url = match url_re.captures(&full_block) {
            Some(cap) => cap[1].to_string(),
            None => continue,
        };

        let users = users_re
            .captures(&full_block)
            .and_then(|cap| cap[1].trim().parse().ok());
        let users_max = users_max_re
            .captures(&full_block)
            .and_then(|cap| cap[1].trim().parse().ok());
        let grid = grid_re
            .captures(&full_block)
            .map(|cap| cap[1].trim().to_string());
        let snr = snr_re
            .captures(&full_block)
            .map(|cap| cap[1].trim().to_string());
        let antenna = antenna_re
            .captures(&full_block)
            .map(|cap| cap[1].trim().to_string());
        let location = loc_re
            .captures(&full_block)
            .map(|cap| cap[1].trim().to_string());
        let offline = offline_re
            .captures(&full_block)
            .map(|cap| cap[1].trim().eq_ignore_ascii_case("yes"));

        entries.push(KiwiDirectoryEntry {
            url,
            name,
            lat,
            lon,
            id,
            users,
            users_max,
            grid,
            snr,
            antenna,
            location,
            offline,
        });
    }

    entries
}

/// Filter entries by country/region bounding boxes.
///
/// If `filters` is empty (i.e. wildcard `"*"` was specified), all entries pass.
/// Otherwise an entry passes if it falls within *any* filter's bounding box.
pub fn filter_by_countries<'a>(
    entries: &'a [KiwiDirectoryEntry],
    filters: &[CountryFilter],
) -> Vec<&'a KiwiDirectoryEntry> {
    if filters.is_empty() {
        return entries.iter().collect();
    }

    entries
        .iter()
        .filter(|e| {
            filters.iter().any(|f| {
                e.lat >= f.lat_range.0
                    && e.lat <= f.lat_range.1
                    && e.lon >= f.lon_range.0
                    && e.lon <= f.lon_range.1
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_html() -> &'static str {
        r#"
<html><body>
<div class='cl-entry'>
 <a href='http://michigan-kiwi.example.com:8073' target='_blank'> <img class='cl-avatar' src='/kiwi/kiwi-avatar.png'> </a>
 <div class='cl-info'>
  <!-- id=00:1a:2b:3c:4d:5e -->
  <!-- status=active -->
  <!-- offline=no -->
  <!-- name=Michigan KiwiSDR -->
  <!-- gps=(42.35, -83.05) -->
  <!-- grid=EN72 -->
  <!-- users=1 -->
  <!-- users_max=4 -->
  <!-- snr=25,25 -->
  <!-- loc=Michigan, United States -->
  <a href='http://michigan-kiwi.example.com:8073' target='_blank'>http://michigan-kiwi.example.com:8073</a>
 </div>
</div>

<div class='cl-entry'>
 <a href='http://london-kiwi.example.com:8073' target='_blank'> <img class='cl-avatar' src='/kiwi/kiwi-avatar.png'> </a>
 <div class='cl-info'>
  <!-- id=aa:bb:cc:dd:ee:ff -->
  <!-- status=active -->
  <!-- offline=no -->
  <!-- name=London KiwiSDR -->
  <!-- gps=(51.51, -0.13) -->
  <!-- grid=IO91WM -->
  <!-- users=2 -->
  <!-- users_max=4 -->
  <!-- snr=30,30 -->
  <!-- loc=London, United Kingdom -->
  <a href='http://london-kiwi.example.com:8073' target='_blank'>http://london-kiwi.example.com:8073</a>
 </div>
</div>

<div class='cl-entry'>
 <a href='http://sydney-kiwi.example.com:8073' target='_blank'> <img class='cl-avatar' src='/kiwi/kiwi-avatar.png'> </a>
 <div class='cl-info'>
  <!-- id=11:22:33:44:55:66 -->
  <!-- status=active -->
  <!-- offline=yes -->
  <!-- name=Sydney KiwiSDR -->
  <!-- gps=(-33.87, 151.21) -->
  <!-- grid=QF56 -->
  <!-- users=0 -->
  <!-- users_max=3 -->
  <!-- snr=20,20 -->
  <!-- loc=Sydney, Australia -->
  <a href='http://sydney-kiwi.example.com:8073' target='_blank'>http://sydney-kiwi.example.com:8073</a>
 </div>
</div>

<div class='cl-entry'>
 <a href='http://bad.example.com:8073' target='_blank'> <img class='cl-avatar' src='/kiwi/kiwi-avatar.png'> </a>
 <div class='cl-info'>
  <!-- id=bad-entry -->
  <!-- status=active -->
  <!-- name=Bad Entry -->
  <!-- gps=(invalid, data) -->
  <a href='http://bad.example.com:8073' target='_blank'>http://bad.example.com:8073</a>
 </div>
</div>
</body></html>
"#
    }

    #[test]
    fn parse_kiwisdr_html_extracts_entries() {
        let entries = parse_kiwisdr_html(sample_html());
        assert_eq!(entries.len(), 3); // bad entry skipped due to invalid GPS

        let michigan = entries.iter().find(|e| e.id == "00:1a:2b:3c:4d:5e");
        assert!(michigan.is_some());
        let michigan = michigan.unwrap();
        assert_eq!(michigan.name, "Michigan KiwiSDR");
        assert!((michigan.lat - 42.35).abs() < 0.01);
        assert!((michigan.lon - (-83.05)).abs() < 0.01);
        assert_eq!(michigan.url, "http://michigan-kiwi.example.com:8073");
        assert_eq!(michigan.users, Some(1));
        assert_eq!(michigan.users_max, Some(4));
        assert_eq!(michigan.grid.as_deref(), Some("EN72"));
        assert_eq!(michigan.snr.as_deref(), Some("25,25"));
        assert_eq!(
            michigan.location.as_deref(),
            Some("Michigan, United States")
        );
        assert_eq!(michigan.offline, Some(false));

        let london = entries.iter().find(|e| e.id == "aa:bb:cc:dd:ee:ff");
        assert!(london.is_some());
        assert_eq!(london.unwrap().name, "London KiwiSDR");

        let sydney = entries.iter().find(|e| e.id == "11:22:33:44:55:66");
        assert!(sydney.is_some());
        assert_eq!(sydney.unwrap().offline, Some(true));
    }

    #[test]
    fn filter_by_us_includes_michigan_excludes_europe() {
        let entries = parse_kiwisdr_html(sample_html());
        let filters = builtin_filters(&["US".to_string()]);

        let filtered = filter_by_countries(&entries, &filters);
        assert_eq!(filtered.len(), 1);
        assert_eq!(filtered[0].name, "Michigan KiwiSDR");
    }

    #[test]
    fn filter_by_eu_includes_london() {
        let entries = parse_kiwisdr_html(sample_html());
        let filters = builtin_filters(&["EU".to_string()]);

        let filtered = filter_by_countries(&entries, &filters);
        assert_eq!(filtered.len(), 1);
        assert_eq!(filtered[0].name, "London KiwiSDR");
    }

    #[test]
    fn filter_by_oc_includes_sydney() {
        let entries = parse_kiwisdr_html(sample_html());
        let filters = builtin_filters(&["OC".to_string()]);

        let filtered = filter_by_countries(&entries, &filters);
        assert_eq!(filtered.len(), 1);
        assert_eq!(filtered[0].name, "Sydney KiwiSDR");
    }

    #[test]
    fn filter_wildcard_returns_all() {
        let entries = parse_kiwisdr_html(sample_html());
        let filters = builtin_filters(&["*".to_string()]);

        let filtered = filter_by_countries(&entries, &filters);
        assert_eq!(filtered.len(), 3);
    }

    #[test]
    fn filter_multiple_regions() {
        let entries = parse_kiwisdr_html(sample_html());
        let filters = builtin_filters(&["US".to_string(), "EU".to_string()]);

        let filtered = filter_by_countries(&entries, &filters);
        assert_eq!(filtered.len(), 2);
        let names: Vec<&str> = filtered.iter().map(|e| e.name.as_str()).collect();
        assert!(names.contains(&"Michigan KiwiSDR"));
        assert!(names.contains(&"London KiwiSDR"));
    }

    #[test]
    fn builtin_filters_unknown_code_returns_empty() {
        let filters = builtin_filters(&["XX".to_string()]);
        assert!(filters.is_empty());
    }

    #[test]
    fn parse_empty_html() {
        let entries = parse_kiwisdr_html("<html><body></body></html>");
        assert!(entries.is_empty());
    }

    #[test]
    fn parse_real_kiwisdr_html() {
        // Snippet from actual kiwisdr.com/.public/ output
        let html = r#"
<div class='cl-entry snr_all_48 snr_hf_48'>
 <a href='http://g3sdr.com:8077' target='_blank'> <img class='cl-avatar' src='/kiwi/kiwi-avatar.png'> </a>
 <div class='cl-info'>
  <!-- updated=Wednesday, 18-Feb-2026 19:05:04 GMT -->
  <!-- id=78047338d12c -->
  <!-- status=active -->
  <!-- offline=no -->
  <!-- name=G3SDR, 0-32 MHz Kiwi 8077. Weston-super-Mare. -->
  <!-- sdr_hw=KiwiSDR 1 v1.829 -->
  <!-- bands=0-30000000 -->
  <!-- users=2 -->
  <!-- users_max=4 -->
  <!-- gps=(51.317266, -2.950479) -->
  <!-- grid=IO81MI -->
  <!-- loc=Weston-super-Mare, United Kingdom -->
  <!-- snr=48,48 -->
  <div class='cl-name'>G3SDR</div>
  <a href='http://g3sdr.com:8077' target='_blank'>http://g3sdr.com:8077</a> <br>
 </div>
</div>
"#;
        let entries = parse_kiwisdr_html(html);
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].id, "78047338d12c");
        assert_eq!(
            entries[0].name,
            "G3SDR, 0-32 MHz Kiwi 8077. Weston-super-Mare."
        );
        assert!((entries[0].lat - 51.317266).abs() < 0.001);
        assert!((entries[0].lon - (-2.950479)).abs() < 0.001);
        assert_eq!(entries[0].url, "http://g3sdr.com:8077");
        assert_eq!(entries[0].users, Some(2));
        assert_eq!(entries[0].users_max, Some(4));
        assert_eq!(entries[0].grid.as_deref(), Some("IO81MI"));
        assert_eq!(entries[0].snr.as_deref(), Some("48,48"));
        assert_eq!(
            entries[0].location.as_deref(),
            Some("Weston-super-Mare, United Kingdom")
        );
        assert_eq!(entries[0].offline, Some(false));
    }
}
