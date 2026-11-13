//! SKCC (Straight Key Century Club) roster parsing. Port of the parsing half
//! of `SKCCMembershipStore.swift` + `SKCCMember.swift`.
//!
//! The download / disk caching / refresh scheduling stays in the Swift/Kotlin
//! app layer; this crate owns the pipe-delimited roster parser, award
//! resolution, and the by-callsign index used for spot enrichment.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

/// Highest SKCC award level achieved by a member.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SkccAward {
    Member,
    Centurion,
    Tribune,
    Senator,
}

impl SkccAward {
    /// Single-character suffix appended to the member number (e.g. `12345T`).
    /// Plain members display no suffix.
    pub fn suffix_character(self) -> &'static str {
        match self {
            SkccAward::Member => "",
            SkccAward::Centurion => "C",
            SkccAward::Tribune => "T",
            SkccAward::Senator => "S",
        }
    }

    /// Full display name for inspectors and tooltips.
    pub fn display_name(self) -> &'static str {
        match self {
            SkccAward::Member => "Member",
            SkccAward::Centurion => "Centurion",
            SkccAward::Tribune => "Tribune",
            SkccAward::Senator => "Senator",
        }
    }
}

/// A single SKCC roster entry with the highest award level the member earned.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SkccMember {
    pub number: i64,
    pub callsign: String,
    pub name: Option<String>,
    pub spc: Option<String>,
    pub award: SkccAward,
    pub tribune_multiplier: Option<i64>,
    pub other_callsigns: Vec<String>,
}

impl SkccMember {
    /// Pretty roster badge, e.g. `12345T`, `67890Tx5`, `23456C`, `99999S`.
    pub fn badge(&self) -> String {
        match (self.award, self.tribune_multiplier) {
            (SkccAward::Tribune, Some(mult)) if mult > 1 => format!("{}Tx{}", self.number, mult),
            _ => format!("{}{}", self.number, self.award.suffix_character()),
        }
    }

    /// Long-form description used in the spot inspector.
    pub fn summary(&self) -> String {
        let mut parts: Vec<String> = vec![self.badge()];
        if let Some(name) = self.name.as_deref().filter(|s| !s.is_empty()) {
            parts.push(name.to_string());
        }
        if let Some(spc) = self.spc.as_deref().filter(|s| !s.is_empty()) {
            parts.push(spc.to_string());
        }
        parts.join(" · ")
    }
}

/// Normalize a callsign: uppercase, drop any `/`-suffix.
pub fn normalize(callsign: &str) -> String {
    let upper = callsign.to_uppercase();
    match upper.find('/') {
        Some(idx) => upper[..idx].to_string(),
        None => upper,
    }
}

/// Parse a roster file body into `SkccMember` records. The file uses `|` as a
/// delimiter and may include a single header line.
pub fn parse_roster(body: &str) -> Vec<SkccMember> {
    let normalized = body.replace("\r\n", "\n").replace('\r', "\n");
    normalized
        .split('\n')
        .filter(|line| !line.is_empty())
        .filter_map(|line| {
            let trimmed = line.trim();
            // Skip the header: any line whose first field doesn't begin with an
            // ASCII digit cannot be a member record.
            let first = trimmed.chars().next()?;
            if !(first.is_ascii() && first.is_ascii_digit()) {
                return None;
            }
            parse_member_line(trimmed)
        })
        .collect()
}

/// Parse a single roster line, returning `None` if it cannot be parsed.
pub fn parse_member_line(line: &str) -> Option<SkccMember> {
    let fields: Vec<String> = line.split('|').map(|f| f.trim().to_string()).collect();
    if fields.len() < 2 {
        return None;
    }

    // Some roster snapshots place a suffixed number ("12345T") in column 0 and
    // a plain integer in a later column. Strip the suffix so we always store an
    // i64, then derive the award from whichever marker is present.
    let raw_number = &fields[0];
    let plain_number: String = raw_number.chars().take_while(|c| c.is_ascii_digit()).collect();
    let number: i64 = plain_number.parse().ok()?;
    if number <= 0 {
        return None;
    }

    let callsign = normalize(&fields[1]);
    if callsign.is_empty() {
        return None;
    }

    let name = field(&fields, 2);
    let spc = field(&fields, 4);
    let other_callsigns = fields.get(5).map(|raw| split_other_callsigns(raw)).unwrap_or_default();

    let suffix_from_number: String =
        raw_number.chars().skip_while(|c| c.is_ascii_digit()).collect::<String>().to_uppercase();
    let c_date = field(&fields, 8);
    let t_date = field(&fields, 9);
    let tx8_date = field(&fields, 10);
    let s_date = field(&fields, 11);

    let (award, multiplier) = resolve_award(
        &suffix_from_number,
        c_date.as_deref(),
        t_date.as_deref(),
        tx8_date.as_deref(),
        s_date.as_deref(),
    );

    Some(SkccMember {
        number,
        callsign,
        name,
        spc,
        award,
        tribune_multiplier: multiplier,
        other_callsigns,
    })
}

/// Build the `by_callsign` index used for lookups. Current calls win over
/// other-call references.
pub fn build_index(members: &[SkccMember]) -> HashMap<String, SkccMember> {
    let mut index: HashMap<String, SkccMember> = HashMap::with_capacity(members.len() * 2);
    for member in members {
        index.insert(member.callsign.clone(), member.clone());
        for other in &member.other_callsigns {
            index.entry(other.clone()).or_insert_with(|| member.clone());
        }
    }
    index
}

fn field(fields: &[String], idx: usize) -> Option<String> {
    fields.get(idx).filter(|value| !value.is_empty()).cloned()
}

fn split_other_callsigns(raw: &str) -> Vec<String> {
    raw.split(|ch: char| ch == ',' || ch == '|' || ch.is_whitespace())
        .map(normalize)
        .filter(|call| !call.is_empty())
        .collect()
}

fn resolve_award(
    suffix: &str,
    c_date: Option<&str>,
    t_date: Option<&str>,
    tx8_date: Option<&str>,
    s_date: Option<&str>,
) -> (SkccAward, Option<i64>) {
    // Date columns are authoritative when present.
    if s_date.is_some() {
        return (SkccAward::Senator, None);
    }
    if let Some(tx8) = tx8_date {
        if !tx8.is_empty() {
            // Tx8 column only marks the milestone — actual multiplier may be
            // higher and is encoded in the suffix ("Tx9", "Tx10").
            let multiplier = parse_tribune_multiplier(suffix).unwrap_or(8);
            return (SkccAward::Tribune, Some(multiplier));
        }
    }
    if t_date.is_some() {
        return (SkccAward::Tribune, parse_tribune_multiplier(suffix));
    }
    if c_date.is_some() {
        return (SkccAward::Centurion, None);
    }

    // Fall back to suffix-only parsing for older roster snapshots.
    if suffix.starts_with('S') {
        return (SkccAward::Senator, None);
    }
    if suffix.starts_with('T') {
        return (SkccAward::Tribune, parse_tribune_multiplier(suffix));
    }
    if suffix.starts_with('C') {
        return (SkccAward::Centurion, None);
    }
    (SkccAward::Member, None)
}

fn parse_tribune_multiplier(suffix: &str) -> Option<i64> {
    let upper = suffix.to_uppercase();
    if !upper.starts_with("TX") {
        return None;
    }
    upper[2..].parse().ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    // Mirrors SKCCMembershipStoreTests.swift.

    #[test]
    fn parses_plain_member_line() {
        let member = parse_member_line("12345|W1AW|Hiram|Newington|CT||12345|2010-01-15").unwrap();
        assert_eq!(member.number, 12_345);
        assert_eq!(member.callsign, "W1AW");
        assert_eq!(member.name.as_deref(), Some("Hiram"));
        assert_eq!(member.spc.as_deref(), Some("CT"));
        assert_eq!(member.award, SkccAward::Member);
        assert_eq!(member.tribune_multiplier, None);
        assert_eq!(member.badge(), "12345");
    }

    #[test]
    fn parses_centurion_from_c_date_column() {
        let member = parse_member_line("23456|K1JT|Joe|Princeton|NJ||23456|2008-03-01|2009-04-12").unwrap();
        assert_eq!(member.award, SkccAward::Centurion);
        assert_eq!(member.badge(), "23456C");
    }

    #[test]
    fn parses_tribune_with_suffix_multiplier() {
        let member = parse_member_line("67890Tx5|N0AX|Ward||WA||67890|2007-01-01|2008-04-01|2010-06-15").unwrap();
        assert_eq!(member.number, 67_890);
        assert_eq!(member.award, SkccAward::Tribune);
        assert_eq!(member.tribune_multiplier, Some(5));
        assert_eq!(member.badge(), "67890Tx5");
    }

    #[test]
    fn parses_plain_tribune_when_no_multiplier() {
        let member = parse_member_line("11111T|K9LA|Carl||IN||11111|2005-01-01|2006-04-01|2009-12-01").unwrap();
        assert_eq!(member.award, SkccAward::Tribune);
        assert_eq!(member.tribune_multiplier, None);
        assert_eq!(member.badge(), "11111T");
    }

    #[test]
    fn parses_senator_from_s_date_column() {
        let member =
            parse_member_line("22222S|W3LPL|Frank||MD||22222|2001-01-01|2002-04-01|2004-12-01|2006-06-01|2010-01-01")
                .unwrap();
        assert_eq!(member.award, SkccAward::Senator);
        assert_eq!(member.badge(), "22222S");
    }

    #[test]
    fn parse_roster_skips_header() {
        let body = "NUMBER|CURRENT_CALL|NAME|CITY|SPC|OTHER_CALLS|PLAIN_NUMBER|JOIN_DATE\n\
                    12345|W1AW|Hiram|Newington|CT||12345|2010-01-15\n\
                    23456|K1JT|Joe|Princeton|NJ||23456|2008-03-01|2009-04-12";
        let members = parse_roster(body);
        assert_eq!(members.len(), 2);
        assert_eq!(members[0].callsign, "W1AW");
        assert_eq!(members[1].award, SkccAward::Centurion);
    }

    #[test]
    fn parse_roster_tolerates_blank_lines_and_crlf() {
        let body = "12345|W1AW|Hiram|Newington|CT\r\n\r\n23456|K1JT|Joe||NJ||23456|2008|2009\r\n";
        assert_eq!(parse_roster(body).len(), 2);
    }

    #[test]
    fn build_index_includes_other_callsigns() {
        let member = parse_member_line("34567|N6TR|Larry|||K0RF,W7TR|34567|2001-01-01|2003-04-01").unwrap();
        let index = build_index(&[member]);
        assert_eq!(index.get("N6TR").map(|m| m.number), Some(34_567));
        assert_eq!(index.get("K0RF").map(|m| m.number), Some(34_567));
        assert_eq!(index.get("W7TR").map(|m| m.number), Some(34_567));
        assert!(!index.contains_key("XXXXX"));
    }

    #[test]
    fn build_index_prefers_current_call_over_older_entry() {
        let member_a = parse_member_line("100|N6TR|Larry|||OLDCALL|100|2001-01-01").unwrap();
        let member_b = parse_member_line("200|OLDCALL|Other||||200|2005-01-01").unwrap();
        let index = build_index(&[member_a, member_b]);
        assert_eq!(index.get("OLDCALL").map(|m| m.number), Some(200));
        assert_eq!(index.get("N6TR").map(|m| m.number), Some(100));
    }

    #[test]
    fn badge_formats_all_award_levels() {
        let make = |number, award, mult| SkccMember {
            number,
            callsign: "X".into(),
            name: None,
            spc: None,
            award,
            tribune_multiplier: mult,
            other_callsigns: vec![],
        };
        assert_eq!(make(1, SkccAward::Member, None).badge(), "1");
        assert_eq!(make(2, SkccAward::Centurion, None).badge(), "2C");
        assert_eq!(make(3, SkccAward::Tribune, None).badge(), "3T");
        assert_eq!(make(4, SkccAward::Tribune, Some(5)).badge(), "4Tx5");
        assert_eq!(make(5, SkccAward::Senator, None).badge(), "5S");
    }
}
