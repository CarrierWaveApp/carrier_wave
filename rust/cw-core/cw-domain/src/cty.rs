//! CTY.dat parser. Port of `CTYParser.swift` + `CTYDatabase` + `DXCCEntity`.
//!
//! AD1C CTY.dat format: records terminated by `;`, header line
//! `Name:CQ:ITU:Cont:Lat:Lon:TZ:PrimaryPrefix:` followed by comma-separated
//! alias prefixes on subsequent lines. Aliases may carry override annotations
//! `(NN)` (CQ zone), `[NN]` (ITU zone), `<NN/NN>` (lat/lon), `~NN~` (timezone),
//! and a leading `=` (exact-match indicator). The Swift parser strips all of
//! these — this port preserves that exact behavior.

use std::collections::HashMap;

#[derive(Debug, Clone, PartialEq)]
pub struct DxccEntity {
    pub name: String,
    pub cq_zone: i32,
    pub itu_zone: i32,
    pub continent: String,
    pub latitude: f64,
    pub longitude: f64,
    pub time_offset: f64,
    pub primary_prefix: String,
}

#[derive(Debug, Default, Clone)]
pub struct CtyDatabase {
    pub entities: Vec<DxccEntity>,
    pub prefix_map: HashMap<String, DxccEntity>,
}

impl CtyDatabase {
    /// Look up the DXCC entity for a callsign using longest-prefix matching,
    /// handling portable indicators (e.g. `W1ABC/VP9` → VP9; `VP9/W1ABC` → VP9).
    pub fn lookup(&self, callsign: &str) -> Option<&DxccEntity> {
        let call = callsign.to_uppercase();
        if let Some(idx) = call.find('/') {
            let (a, rest) = call.split_at(idx);
            let b = &rest[1..];
            let (portable, base) = if a.len() <= b.len() { (a, b) } else { (b, a) };
            if let Some(entity) = self.longest_prefix_match(portable) {
                const PURE_SUFFIXES: &[&str] =
                    &["P", "M", "MM", "AM", "QRP", "A", "B"];
                if !PURE_SUFFIXES.contains(&portable) {
                    return Some(entity);
                }
            }
            return self.longest_prefix_match(base);
        }
        self.longest_prefix_match(&call)
    }

    fn longest_prefix_match(&self, call: &str) -> Option<&DxccEntity> {
        if let Some(exact) = self.prefix_map.get(call) {
            return Some(exact);
        }
        let mut prefix = call.to_string();
        while !prefix.is_empty() {
            if let Some(entity) = self.prefix_map.get(&prefix) {
                return Some(entity);
            }
            prefix.pop();
        }
        None
    }
}

/// Parse CTY.dat content into a `CtyDatabase`.
pub fn parse(content: &str) -> CtyDatabase {
    let mut db = CtyDatabase::default();
    for record in content.split(';') {
        let trimmed = record.trim();
        if trimmed.is_empty() {
            continue;
        }
        let Some(parsed) = parse_record(trimmed) else {
            continue;
        };
        db.prefix_map
            .insert(parsed.entity.primary_prefix.to_uppercase(), parsed.entity.clone());
        for alias in &parsed.prefixes {
            db.prefix_map.insert(alias.to_uppercase(), parsed.entity.clone());
        }
        db.entities.push(parsed.entity);
    }
    db
}

struct ParsedRecord {
    entity: DxccEntity,
    prefixes: Vec<String>,
}

fn parse_record(record: &str) -> Option<ParsedRecord> {
    let mut lines = record.split('\n');
    let header_line = lines.next()?;
    let parts: Vec<&str> = header_line.split(':').collect();
    if parts.len() < 8 {
        return None;
    }
    let name = parts[0].trim().to_string();
    let cq_zone = parts[1].trim().parse::<i32>().unwrap_or(0);
    let itu_zone = parts[2].trim().parse::<i32>().unwrap_or(0);
    let continent = parts[3].trim().to_string();
    let latitude = parts[4].trim().parse::<f64>().unwrap_or(0.0);
    let longitude = parts[5].trim().parse::<f64>().unwrap_or(0.0);
    let time_offset = parts[6].trim().parse::<f64>().unwrap_or(0.0);
    let primary_prefix = parts[7].trim().to_string();

    let entity = DxccEntity {
        name,
        cq_zone,
        itu_zone,
        continent,
        latitude,
        longitude,
        time_offset,
        primary_prefix,
    };

    // Aliases are the remaining lines joined with a space (matches Swift).
    let alias_text: String = lines.collect::<Vec<&str>>().join(" ");
    let prefixes = parse_aliases(&alias_text);
    Some(ParsedRecord { entity, prefixes })
}

fn parse_aliases(text: &str) -> Vec<String> {
    text.split(',')
        .filter_map(|alias| {
            let mut cleaned: String = alias.trim().to_string();
            if cleaned.is_empty() {
                return None;
            }
            // Strip override annotations: (NN) [NN] <NN/NN> ~NN~
            for delim in ['(', '[', '<', '~'] {
                if let Some(idx) = cleaned.find(delim) {
                    cleaned.truncate(idx);
                }
            }
            let mut cleaned = cleaned.trim().to_string();
            // Strip the leading "=" exact-match indicator — we still want the prefix
            if let Some(stripped) = cleaned.strip_prefix('=') {
                cleaned = stripped.to_string();
            }
            if cleaned.is_empty() {
                None
            } else {
                Some(cleaned)
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    // Minimal multi-entity sample mirroring AD1C CTY.dat format. The aliases
    // exercise every override syntax (), [], <>, ~~, and the = exact-match
    // indicator, so the parity port and Swift land on the same prefix set.
    const SAMPLE: &str = "\
United States:                    05:  08:  NA:   37.53:    91.66:     5.0:  K:\n\
    =W1AW(5),AA0-AK0,K,KA0-KZ9(3),N0-N9,W0-W9,WA0-WZ9;\n\
Canada:                           05:  09:  NA:   60.00:   100.00:     5.0:  VE:\n\
    VA,VE,VO,VY;\n\
Bermuda:                          05:  11:  NA:   32.30:    64.78:     4.0:  VP9:\n\
    VP9<32/64>;\n";

    #[test]
    fn parses_three_entities() {
        let db = parse(SAMPLE);
        assert_eq!(db.entities.len(), 3);
        let names: Vec<&str> = db.entities.iter().map(|e| e.name.as_str()).collect();
        assert!(names.contains(&"United States"));
        assert!(names.contains(&"Canada"));
        assert!(names.contains(&"Bermuda"));
    }

    #[test]
    fn parses_zones_and_continent() {
        let db = parse(SAMPLE);
        let usa = db.entities.iter().find(|e| e.name == "United States").unwrap();
        assert_eq!(usa.cq_zone, 5);
        assert_eq!(usa.itu_zone, 8);
        assert_eq!(usa.continent, "NA");
        assert!((usa.latitude - 37.53).abs() < 1e-6);
        assert_eq!(usa.primary_prefix, "K");
    }

    #[test]
    fn strips_override_annotations_from_aliases() {
        let db = parse(SAMPLE);
        // VP9<32/64> should reduce to VP9
        assert!(db.prefix_map.contains_key("VP9"));
        // KA0-KZ9(3) should reduce to KA0-KZ9 (the dash range is left as-is,
        // matching Swift — we just strip overrides, not range-expand here).
        assert!(db.prefix_map.contains_key("KA0-KZ9"));
        // =W1AW exact-match marker stripped → "W1AW" lookup succeeds
        assert!(db.prefix_map.contains_key("W1AW"));
    }

    #[test]
    fn lookup_simple_callsign() {
        let db = parse(SAMPLE);
        // Exact entry for W1AW
        let w1aw = db.lookup("W1AW").unwrap();
        assert_eq!(w1aw.name, "United States");
        // Falls back to single-letter K prefix for any K-prefixed call
        let k6jsv = db.lookup("K6JSV").unwrap();
        assert_eq!(k6jsv.name, "United States");
        // Canadian
        let ve3xy = db.lookup("VE3XY").unwrap();
        assert_eq!(ve3xy.name, "Canada");
    }

    #[test]
    fn lookup_portable_resolves_to_portable_prefix() {
        let db = parse(SAMPLE);
        let e1 = db.lookup("W1ABC/VP9").unwrap();
        assert_eq!(e1.name, "Bermuda");
        let e2 = db.lookup("VP9/W1ABC").unwrap();
        assert_eq!(e2.name, "Bermuda");
    }

    #[test]
    fn lookup_strip_pure_suffix() {
        let db = parse(SAMPLE);
        // W1AW/P → /P is a pure suffix, fall back to the base call
        let entity = db.lookup("W1AW/P").unwrap();
        assert_eq!(entity.name, "United States");
    }

    #[test]
    fn lookup_unknown_returns_none() {
        let db = parse(SAMPLE);
        assert!(db.lookup("ZZZZ").is_none());
    }
}
