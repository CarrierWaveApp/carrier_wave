//! Reference-data CSV parsers — POTA parks (`all_parks_ext.csv`), SOTA
//! summits (`summitslist.csv`), and the WWFF directory
//! (`wwff_directory.csv`). Ports of `POTAParksCache.parseCSV`,
//! `SOTASummitsCache+Parsing.parseCSV`, and
//! `WWFFReferencesCache+Parsing.parseCSV` (all sharing the Swift
//! `CSVLineParser`).
//!
//! Download / persistence stay in cw-net / cw-store; this module owns the
//! line format only.

use serde::{Deserialize, Serialize};

/// One POTA park row. Field set mirrors the Swift `POTAPark` (and the
/// cw-store `pota_park` table).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PotaParkRow {
    pub reference: String,
    pub name: String,
    /// Region string, e.g. "US-WY" or multi-state "US-WY,US-MT".
    pub location_desc: String,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    pub grid: Option<String>,
    pub entity_id: i64,
    pub is_active: bool,
}

/// One SOTA summit row. Field set mirrors the Swift `SOTASummit`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SotaSummitRow {
    /// "W4C/CM-001".
    pub code: String,
    pub name: String,
    pub association_name: String,
    pub region_name: String,
    pub altitude_m: i64,
    pub altitude_ft: i64,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    pub points: i64,
    pub bonus_points: i64,
    pub activation_count: i64,
    /// "dd/MM/yyyy" from the CSV, verbatim.
    pub last_activation_date: Option<String>,
    pub last_activation_call: Option<String>,
    /// Maidenhead locator when one is embedded in the grid-ref columns.
    pub grid: Option<String>,
}

/// One WWFF directory row. Field set mirrors the Swift `WWFFReference`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WwffReferenceRow {
    /// "KFF-1234".
    pub reference: String,
    pub name: String,
    /// Program prefix, e.g. "KFF".
    pub program: String,
    /// Lowercased, e.g. "active".
    pub status: String,
    pub continent: Option<String>,
    pub iota: Option<String>,
    pub grid: Option<String>,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    pub iucn_category: Option<String>,
    pub country: Option<String>,
    pub region: Option<String>,
    pub dxcc_entity: Option<i64>,
}

/// Split one CSV line into trimmed fields, dropping quote characters —
/// byte-for-byte the Swift `CSVLineParser.parseCSVLine`.
pub fn parse_csv_line(line: &str) -> Vec<String> {
    let mut fields = Vec::new();
    let mut current = String::new();
    let mut in_quotes = false;

    for ch in line.chars() {
        if ch == '"' {
            in_quotes = !in_quotes;
        } else if ch == ',' && !in_quotes {
            fields.push(current.trim().to_string());
            current.clear();
        } else {
            current.push(ch);
        }
    }
    fields.push(current.trim().to_string());
    fields
}

/// Parse `all_parks_ext.csv`. Columns (0-indexed): reference, name,
/// active (1/true), entityId, locationDesc, latitude, longitude, grid.
/// Skips the header, blank lines, short rows, and rows missing a
/// reference or name. Later duplicates of a reference win (dictionary
/// semantics in the Swift port).
pub fn parse_pota_parks_csv(csv: &str) -> Vec<PotaParkRow> {
    let mut rows: Vec<PotaParkRow> = Vec::new();
    for line in csv.split('\n').skip(1) {
        if line.is_empty() {
            continue;
        }
        let fields = parse_csv_line(line);
        if fields.len() < 8 {
            continue;
        }
        let reference = fields[0].to_uppercase();
        let name = fields[1].clone();
        if reference.is_empty() || name.is_empty() {
            continue;
        }
        let active_raw = fields[2].to_lowercase();
        rows.push(PotaParkRow {
            reference,
            name,
            location_desc: fields[4].clone(),
            latitude: fields[5].parse().ok(),
            longitude: fields[6].parse().ok(),
            grid: non_empty(&fields[7]),
            entity_id: fields[3].parse().unwrap_or(0),
            is_active: active_raw == "1" || active_raw == "true",
        });
    }
    dedup_by_key(rows, |row| row.reference.clone())
}

/// Parse `summitslist.csv`. 17 columns (0-indexed): SummitCode,
/// AssociationName, RegionName, SummitName, AltM, AltFt, GridRef1,
/// GridRef2, Longitude, Latitude, Points, BonusPoints, ValidFrom,
/// ValidTo, ActivationCount, ActivationDate, ActivationCall.
///
/// Expired summits (ValidTo before `today_dmy`, a "dd/MM/yyyy" date for
/// *today* in UTC) are dropped. Deliberate deviation from the Swift port:
/// iOS compares the raw "dd/MM/yyyy" strings lexicographically (day field
/// first), which mis-keeps some expired summits; here the comparison is
/// chronological.
pub fn parse_sota_summits_csv(csv: &str, today_dmy: &str) -> Vec<SotaSummitRow> {
    let today_key = dmy_sort_key(today_dmy);
    let mut rows: Vec<SotaSummitRow> = Vec::new();
    for line in csv.split('\n').skip(1) {
        if line.is_empty() {
            continue;
        }
        let fields = parse_csv_line(line);
        if fields.len() < 15 {
            continue;
        }
        let code = fields[0].to_uppercase();
        let name = fields[3].clone();
        if code.is_empty() || name.is_empty() {
            continue;
        }
        let valid_to = &fields[13];
        if !valid_to.is_empty() {
            if let (Some(expiry), Some(today)) = (dmy_sort_key(valid_to), today_key) {
                if expiry < today {
                    continue;
                }
            }
        }
        rows.push(SotaSummitRow {
            code,
            name,
            association_name: fields[1].clone(),
            region_name: fields[2].clone(),
            altitude_m: fields[4].parse().unwrap_or(0),
            altitude_ft: fields[5].parse().unwrap_or(0),
            latitude: fields[9].parse().ok(),
            longitude: fields[8].parse().ok(),
            points: fields[10].parse().unwrap_or(0),
            bonus_points: fields[11].parse().unwrap_or(0),
            activation_count: fields[14].parse().unwrap_or(0),
            last_activation_date: fields.get(15).and_then(|value| non_empty(value)),
            last_activation_call: fields.get(16).and_then(|value| non_empty(value)),
            grid: maidenhead_from_grid_refs(&fields[6], &fields[7]),
        });
    }
    dedup_by_key(rows, |row| row.code.clone())
}

/// Parse `wwff_directory.csv`. Uses columns (0-indexed): reference[0],
/// status[1], name[2], program[3], continent[7], iota[8], grid[9],
/// latitude[10], longitude[11], IUCNcat[12], country[21], region[22],
/// dxccEnum[23]. Empty and "-" optional values become `None`. All
/// statuses are kept (active-only filtering happens at query time).
pub fn parse_wwff_directory_csv(csv: &str) -> Vec<WwffReferenceRow> {
    let mut rows: Vec<WwffReferenceRow> = Vec::new();
    for line in csv.split('\n').skip(1) {
        if line.is_empty() {
            continue;
        }
        let fields = parse_csv_line(line);
        if fields.len() < 12 {
            continue;
        }
        let reference = fields[0].to_uppercase();
        let name = fields[2].clone();
        if reference.is_empty() || name.is_empty() {
            continue;
        }
        rows.push(WwffReferenceRow {
            reference,
            name,
            program: fields[3].clone(),
            status: fields[1].to_lowercase(),
            continent: fields.get(7).and_then(|value| clean_field(value)),
            iota: fields.get(8).and_then(|value| clean_field(value)),
            grid: fields.get(9).and_then(|value| clean_field(value)),
            latitude: fields[10].parse().ok(),
            longitude: fields[11].parse().ok(),
            iucn_category: fields.get(12).and_then(|value| clean_field(value)),
            country: fields.get(21).and_then(|value| clean_field(value)),
            region: fields.get(22).and_then(|value| clean_field(value)),
            dxcc_entity: fields.get(23).and_then(|value| value.parse().ok()),
        });
    }
    dedup_by_key(rows, |row| row.reference.clone())
}

/// Reject downloads that are HTML challenge pages instead of CSV — the
/// guard iOS applies in `ReferenceCacheDiskIO.downloadAndSaveCSV`.
pub fn looks_like_html(body: &str) -> bool {
    let trimmed = body.trim_start();
    trimmed.starts_with("<!") || trimmed.starts_with("<html")
}

/// Extract a Maidenhead locator from the SOTA grid-ref columns (prefer
/// GridRef2): ≥4 chars, two letters then two digits. SOTA usually carries
/// OS/Irish grid refs, which fail the check and yield `None`.
fn maidenhead_from_grid_refs(grid_ref1: &str, grid_ref2: &str) -> Option<String> {
    let reference = if grid_ref2.is_empty() { grid_ref1 } else { grid_ref2 };
    let trimmed = reference.trim();
    let chars: Vec<char> = trimmed.chars().collect();
    if chars.len() >= 4
        && chars[0].is_alphabetic()
        && chars[1].is_alphabetic()
        && chars[2].is_ascii_digit()
        && chars[3].is_ascii_digit()
    {
        Some(trimmed.to_string())
    } else {
        None
    }
}

/// "dd/MM/yyyy" → (year, month, day) for chronological ordering.
fn dmy_sort_key(dmy: &str) -> Option<(i32, u32, u32)> {
    let mut parts = dmy.split('/');
    let day: u32 = parts.next()?.parse().ok()?;
    let month: u32 = parts.next()?.parse().ok()?;
    let year: i32 = parts.next()?.parse().ok()?;
    Some((year, month, day))
}

fn non_empty(value: &str) -> Option<String> {
    if value.is_empty() {
        None
    } else {
        Some(value.to_string())
    }
}

/// Empty or "-" → `None` (Swift `cleanField`).
fn clean_field(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() || trimmed == "-" {
        None
    } else {
        Some(trimmed.to_string())
    }
}

/// Keep the *last* row per key — the Swift parsers build dictionaries, so a
/// later duplicate silently replaces an earlier one.
fn dedup_by_key<T, K: std::hash::Hash + Eq>(rows: Vec<T>, key: impl Fn(&T) -> K) -> Vec<T> {
    let mut seen = std::collections::HashMap::new();
    for (index, row) in rows.iter().enumerate() {
        seen.insert(key(row), index);
    }
    let mut keep: Vec<usize> = seen.into_values().collect();
    keep.sort_unstable();
    let mut keep_iter = keep.into_iter().peekable();
    rows.into_iter()
        .enumerate()
        .filter_map(|(index, row)| {
            if keep_iter.peek() == Some(&index) {
                keep_iter.next();
                Some(row)
            } else {
                None
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn csv_line_handles_quotes_and_trim() {
        let fields = parse_csv_line(r#"US-0001, "Acadia, National Park" ,1,291"#);
        assert_eq!(fields, vec!["US-0001", "Acadia, National Park", "1", "291"]);
    }

    #[test]
    fn pota_parses_and_skips_bad_rows() {
        let csv = "reference,name,active,entityId,locationDesc,latitude,longitude,grid\n\
                   us-0001,Acadia,1,291,US-ME,44.35,-68.21,FN54vi\n\
                   ,Missing Ref,1,291,US-ME,44.35,-68.21,FN54\n\
                   US-0002,No Coords,true,291,US-NH,,,\n\
                   US-0003,Short,1\n";
        let parks = parse_pota_parks_csv(csv);
        assert_eq!(parks.len(), 2);
        assert_eq!(parks[0].reference, "US-0001");
        assert_eq!(parks[0].grid.as_deref(), Some("FN54vi"));
        assert!(parks[0].is_active);
        assert_eq!(parks[1].reference, "US-0002");
        assert!(parks[1].is_active);
        assert_eq!(parks[1].latitude, None);
        assert_eq!(parks[1].grid, None);
    }

    #[test]
    fn sota_filters_expired_and_detects_grid() {
        let header = "SummitCode,AssociationName,RegionName,SummitName,AltM,AltFt,GridRef1,GridRef2,Longitude,Latitude,Points,BonusPoints,ValidFrom,ValidTo,ActivationCount,ActivationDate,ActivationCall\n";
        let csv = format!(
            "{header}\
             w4c/cm-001,USA - NC,Western NC,Mount Mitchell,2037,6684,,EM85: ,-82.27,35.76,10,3,01/01/2010,31/12/2099,120,15/03/2024,W6JY\n\
             W1/AM-999,USA - NH,White Mtns,Expired Peak,1000,3280,,,-71.0,44.0,4,0,01/01/2010,10/03/2020,5,,\n"
        );
        let summits = parse_sota_summits_csv(&csv, "06/07/2026");
        assert_eq!(summits.len(), 1);
        let summit = &summits[0];
        assert_eq!(summit.code, "W4C/CM-001");
        assert_eq!(summit.grid.as_deref(), Some("EM85:"));
        assert_eq!(summit.latitude, Some(35.76));
        assert_eq!(summit.longitude, Some(-82.27));
        assert_eq!(summit.last_activation_call.as_deref(), Some("W6JY"));
    }

    #[test]
    fn sota_expiry_is_chronological_not_lexicographic() {
        // "10/03/2020" > "06/07/2026" as a string — the Swift port would
        // keep it. Chronologically it is expired and must be dropped.
        let header = "code,assoc,region,name,altm,altft,g1,g2,lon,lat,pts,bonus,from,to,count\n";
        let csv =
            format!("{header}W1/X-1,A,R,Peak,1,3,,,-71.0,44.0,1,0,01/01/2010,10/03/2020,0\n");
        assert!(parse_sota_summits_csv(&csv, "06/07/2026").is_empty());
    }

    #[test]
    fn wwff_cleans_dash_fields() {
        let header = "reference,status,name,program,dxcc,state,county,continent,iota,grid,latitude,longitude,iucn,validFrom,validTo,notes,lastMod,changeLog,reviewFlag,specialFlags,website,country,region,dxccEnum,qsoCount,lastAct\n";
        let csv = format!(
            "{header}\
             kff-0059,active,Yellowstone NP,KFF,US,WY,-,NA,-,DN44,44.6,-110.5,II,,,,,,,,,United States,Wyoming,291,100,2024\n\
             KFF-9999,deleted,Old Area,KFF,US,,,-,-, -,,, ,,,,,,,,,-,-,,0,\n"
        );
        let refs = parse_wwff_directory_csv(&csv);
        assert_eq!(refs.len(), 2);
        let yellowstone = &refs[0];
        assert_eq!(yellowstone.reference, "KFF-0059");
        assert_eq!(yellowstone.status, "active");
        assert_eq!(yellowstone.continent.as_deref(), Some("NA"));
        assert_eq!(yellowstone.iota, None);
        assert_eq!(yellowstone.dxcc_entity, Some(291));
        let deleted = &refs[1];
        assert_eq!(deleted.status, "deleted");
        assert_eq!(deleted.grid, None);
        assert_eq!(deleted.country, None);
        assert_eq!(deleted.latitude, None);
    }

    #[test]
    fn later_duplicate_reference_wins() {
        let csv = "reference,name,active,entityId,locationDesc,latitude,longitude,grid\n\
                   US-0001,Old Name,1,291,US-ME,44.0,-68.0,\n\
                   US-0001,New Name,1,291,US-ME,44.35,-68.21,FN54\n";
        let parks = parse_pota_parks_csv(csv);
        assert_eq!(parks.len(), 1);
        assert_eq!(parks[0].name, "New Name");
    }

    #[test]
    fn html_guard() {
        assert!(looks_like_html("  <!DOCTYPE html><html>…"));
        assert!(looks_like_html("<html><body>challenge</body>"));
        assert!(!looks_like_html("reference,name\nUS-1,Park"));
    }
}
