//! ADIF record parser. Port of `ADIFParser.swift` and `ADIFRecord`.
//!
//! ADIF (Amateur Data Interchange Format) tokens are `<fieldname:length>value`
//! or `<fieldname:length:type>value`. Records terminate with `<eor>`; an
//! optional `<eoh>` header may precede the records. Field names are case-
//! insensitive (we lowercase on read). The Swift parser uses NSRegularExpression
//! over the same grammar; this port hand-rolls the tokenizer to avoid a regex
//! dependency, but preserves all observable semantics: case-insensitive
//! `<eor>`/`<eoh>`, callsign uppercased, band lowercased, submode preferred
//! over parent mode.

use std::collections::HashMap;

/// One parsed ADIF QSO record.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct AdifRecord {
    pub callsign: String,
    pub band: String,
    pub mode: String,
    pub frequency: Option<f64>,
    pub qso_date: Option<String>,     // YYYYMMDD
    pub time_on: Option<String>,      // HHMM or HHMMSS
    pub rst_sent: Option<String>,
    pub rst_received: Option<String>,
    pub my_callsign: Option<String>,
    pub my_gridsquare: Option<String>,
    pub gridsquare: Option<String>,
    pub sig_info: Option<String>,
    pub my_sig_info: Option<String>,
    pub my_wwff_ref: Option<String>,
    pub wwff_ref: Option<String>,
    pub comment: Option<String>,
    pub dxcc: Option<i32>,
    pub country: Option<String>,
    pub state: Option<String>,
    pub name: Option<String>,
    pub qth: Option<String>,
    pub raw_adif: String,
    pub operator_call: Option<String>,
    pub station_callsign: Option<String>,
    pub sat_name: Option<String>,
    pub prop_mode: Option<String>,
}

/// Find the first `<fieldname:length>` (or `<fieldname:length:type>`) token at
/// or after `start`. Returns `(field_name_lowercased, length, value_offset)`.
fn next_token(s: &str, start: usize) -> Option<(String, usize, usize)> {
    let bytes = s.as_bytes();
    let mut i = start;
    while i < bytes.len() {
        if bytes[i] == b'<' {
            // Find closing '>'
            let mut j = i + 1;
            while j < bytes.len() && bytes[j] != b'>' {
                j += 1;
            }
            if j == bytes.len() {
                return None;
            }
            // Parse token between <...>: name:length[:type]
            let inner = &s[i + 1..j];
            if inner.starts_with('/') {
                // Skip malformed tokens like </field>.
                i = j + 1;
                continue;
            }
            let mut parts = inner.split(':');
            let Some(name) = parts.next().map(str::to_lowercase) else {
                i = j + 1;
                continue;
            };
            let Some(length_str) = parts.next() else {
                // Sentinel tokens like <eor>, <eoh> have no length — skip.
                i = j + 1;
                continue;
            };
            let Ok(length) = length_str.parse::<usize>() else {
                i = j + 1;
                continue;
            };
            return Some((name, length, j + 1));
        }
        i += 1;
    }
    None
}

/// Extract a specific field's value from a raw ADIF string (case-insensitive
/// field name). Mirrors `ADIFParser.extractField`.
pub fn extract_field(field_name: &str, adif: &str) -> Option<String> {
    let target = field_name.to_lowercase();
    let mut pos = 0;
    while let Some((name, length, value_start)) = next_token(adif, pos) {
        if name == target {
            let end = value_start + length;
            if end <= adif.len() {
                return Some(adif[value_start..end].trim().to_string());
            }
            return None;
        }
        // Skip past the value to find the next token.
        let end = value_start + length;
        pos = end.min(adif.len());
    }
    None
}

/// Extract DXCC entity number. Returns `None` if missing or unparseable.
pub fn extract_dxcc(adif: &str) -> Option<i32> {
    extract_field("dxcc", adif).and_then(|v| v.parse::<i32>().ok())
}

/// Parse all fields in a single record into a `field_name → value` map.
/// Field names are lowercased; values are *not* trimmed (matches Swift's
/// `parseFields`, which trims only in extractField).
pub fn extract_fields(record: &str) -> HashMap<String, String> {
    let mut fields = HashMap::new();
    let mut pos = 0;
    while let Some((name, length, value_start)) = next_token(record, pos) {
        let end = value_start + length;
        if end > record.len() {
            break;
        }
        // ADIF `length` is an octet count. Some loggers instead write a
        // character count, so `end` can land mid-UTF-8-char for Unicode values
        // — a plain `record[value_start..end]` str-slice would PANIC there.
        // Slice on a char boundary when possible, else lossily on bytes.
        let value = match record.get(value_start..end) {
            Some(slice) => slice.to_string(),
            None => String::from_utf8_lossy(&record.as_bytes()[value_start..end]).into_owned(),
        };
        fields.insert(name, value);
        pos = end;
    }
    fields
}

/// Parse a full ADIF document into a vector of records. Header (if any) is
/// stripped at `<eoh>`. Records are split on `<eor>` (case-insensitive).
/// Records missing `call`, `band`, or `mode` are skipped, matching Swift.
pub fn parse(content: &str) -> Vec<AdifRecord> {
    let mut records = Vec::new();
    let working: &str = if let Some(end) = find_case_insensitive(content, "<eoh>") {
        &content[end..]
    } else {
        content
    };
    for raw in split_case_insensitive(working, "<eor>") {
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            continue;
        }
        let fields = parse_record_fields(trimmed);
        let (Some(callsign), Some(band), Some(mode)) =
            (fields.get("call"), fields.get("band"), fields.get("mode"))
        else {
            continue;
        };
        let raw_adif = format!("<{}<eor>", trimmed);
        records.push(build_record(callsign, band, mode, &fields, raw_adif));
    }
    records
}

fn build_record(
    callsign: &str,
    band: &str,
    mode: &str,
    fields: &HashMap<String, String>,
    raw_adif: String,
) -> AdifRecord {
    let pick = |key: &str| fields.get(key).cloned();
    let pick_first = |keys: &[&str]| {
        for key in keys {
            if let Some(value) = fields.get(*key) {
                return Some(value.clone());
            }
        }
        None
    };
    // Prefer submode (e.g. USB/LSB) over parent mode (SSB).
    let effective_mode = pick_first(&["submode", "mode"]).unwrap_or_else(|| mode.to_string());

    AdifRecord {
        callsign: callsign.to_uppercase(),
        band: band.to_lowercase(),
        mode: effective_mode.to_uppercase(),
        frequency: pick("freq").and_then(|v| v.parse::<f64>().ok()),
        qso_date: pick("qso_date"),
        time_on: pick("time_on"),
        rst_sent: pick("rst_sent"),
        rst_received: pick("rst_rcvd"),
        my_callsign: pick_first(&["operator", "station_callsign"]),
        my_gridsquare: pick("my_gridsquare"),
        gridsquare: pick("gridsquare"),
        sig_info: pick_first(&["sig_info", "pota_ref"]),
        my_sig_info: pick_first(&["my_sig_info", "my_pota_ref"]),
        my_wwff_ref: pick("my_wwff_ref"),
        wwff_ref: pick("wwff_ref"),
        comment: pick_first(&["comment", "notes"]),
        dxcc: pick("dxcc").and_then(|v| v.parse::<i32>().ok()),
        country: pick("country"),
        state: pick("state"),
        name: pick("name"),
        qth: pick("qth"),
        raw_adif,
        operator_call: pick("operator"),
        station_callsign: pick("station_callsign"),
        sat_name: pick("sat_name"),
        prop_mode: pick("prop_mode"),
    }
}

/// Same as `extract_fields`, but trims whitespace from values to match Swift's
/// `parseFields(from:)` (which calls `.trimmingCharacters(in: .whitespaces)`).
fn parse_record_fields(record: &str) -> HashMap<String, String> {
    let mut fields = HashMap::new();
    let mut pos = 0;
    while let Some((name, length, value_start)) = next_token(record, pos) {
        let end = value_start + length;
        if end > record.len() {
            break;
        }
        fields.insert(name, record[value_start..end].trim().to_string());
        pos = end;
    }
    fields
}

fn find_case_insensitive(haystack: &str, needle: &str) -> Option<usize> {
    let lower = haystack.to_lowercase();
    let key = needle.to_lowercase();
    lower.find(&key).map(|byte_idx| byte_idx + needle.len())
}

fn split_case_insensitive<'a>(input: &'a str, sep: &str) -> Vec<&'a str> {
    let lower = input.to_lowercase();
    let sep_lower = sep.to_lowercase();
    let mut out = Vec::new();
    let mut start = 0;
    let mut idx = 0;
    while idx + sep_lower.len() <= lower.len() {
        if lower[idx..idx + sep_lower.len()] == sep_lower {
            if idx > start {
                out.push(&input[start..idx]);
            }
            idx += sep_lower.len();
            start = idx;
        } else {
            idx += 1;
        }
    }
    if start < input.len() {
        out.push(&input[start..]);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = "ADIF Test File\n\
                          <ADIF_VER:5>3.1.4\n\
                          <PROGRAMID:11>Carrier Wave\n\
                          <eoh>\n\
                          <CALL:5>W1ABC<BAND:3>20m<MODE:3>SSB<SUBMODE:3>USB\
                          <QSO_DATE:8>20260101<TIME_ON:4>1230<RST_SENT:2>59\
                          <RST_RCVD:2>59<MY_GRIDSQUARE:6>FN31pr<GRIDSQUARE:4>EM73\
                          <DXCC:3>291<COUNTRY:13>United States<OPERATOR:5>W6JSV\
                          <STATION_CALLSIGN:5>W6JSV<NOTES:5>nice!<eor>\n\
                          <CALL:4>K1JT<BAND:3>40m<MODE:3>FT8<QSO_DATE:8>20260102\
                          <TIME_ON:4>0500<FREQ:7>7.07400<eor>";

    #[test]
    fn extract_field_finds_single_token() {
        assert_eq!(extract_field("call", SAMPLE).as_deref(), Some("W1ABC"));
        assert_eq!(extract_field("CALL", SAMPLE).as_deref(), Some("W1ABC")); // case-insensitive
        assert_eq!(extract_field("missing", SAMPLE), None);
    }

    #[test]
    fn extract_dxcc_returns_int() {
        assert_eq!(extract_dxcc(SAMPLE), Some(291));
    }

    #[test]
    fn parse_skips_records_missing_required_fields() {
        let missing = "<CALL:4>K1JT<eor>"; // no band/mode
        assert!(parse(missing).is_empty());
    }

    #[test]
    fn extract_fields_handles_utf8_value_with_byte_length() {
        // "José" is 5 bytes (é is 2); a correct octet length lands on a boundary.
        let record = "<name:5>José";
        assert_eq!(extract_fields(record).get("name").map(String::as_str), Some("José"));
    }

    #[test]
    fn extract_fields_does_not_panic_on_mid_char_length() {
        // Length 4 counts "Jos" + only the first byte of the 2-byte 'é',
        // landing mid-UTF-8-char. Must not panic (regression: QRZ sync crash).
        let record = "<name:4>José<eor>";
        let fields = extract_fields(record);
        assert!(fields.contains_key("name"));
    }

    #[test]
    fn parse_picks_satellite_fields() {
        let sat = "<CALL:5>W1ABC<BAND:3>70cm<MODE:2>FM\
                   <SAT_NAME:5>AO-91<PROP_MODE:3>SAT<eor>";
        let records = parse(sat);
        assert_eq!(records.len(), 1);
        assert_eq!(records[0].sat_name.as_deref(), Some("AO-91"));
        assert_eq!(records[0].prop_mode.as_deref(), Some("SAT"));

        // Terrestrial records leave them None.
        let records = parse(SAMPLE);
        assert!(records[0].sat_name.is_none());
        assert!(records[0].prop_mode.is_none());
    }

    #[test]
    fn parse_full_sample() {
        let records = parse(SAMPLE);
        assert_eq!(records.len(), 2);

        let first = &records[0];
        assert_eq!(first.callsign, "W1ABC");
        assert_eq!(first.band, "20m");
        // Submode wins over mode (USB > SSB).
        assert_eq!(first.mode, "USB");
        assert_eq!(first.qso_date.as_deref(), Some("20260101"));
        assert_eq!(first.time_on.as_deref(), Some("1230"));
        assert_eq!(first.rst_sent.as_deref(), Some("59"));
        assert_eq!(first.my_gridsquare.as_deref(), Some("FN31pr"));
        assert_eq!(first.gridsquare.as_deref(), Some("EM73"));
        assert_eq!(first.dxcc, Some(291));
        assert_eq!(first.country.as_deref(), Some("United States"));
        assert_eq!(first.my_callsign.as_deref(), Some("W6JSV"));
        // notes → comment fallback
        assert_eq!(first.comment.as_deref(), Some("nice!"));

        let second = &records[1];
        assert_eq!(second.callsign, "K1JT");
        assert_eq!(second.mode, "FT8");
        assert!(second.frequency.unwrap() - 7.074 < 1e-9);
        // No operator/station_callsign on second record → my_callsign is None.
        assert!(second.my_callsign.is_none());
    }

    #[test]
    fn extract_fields_lowercases_names() {
        let fields = extract_fields("<CALL:4>W1AW<Band:3>20m");
        assert_eq!(fields.get("call").map(String::as_str), Some("W1AW"));
        assert_eq!(fields.get("band").map(String::as_str), Some("20m"));
    }

    #[test]
    fn handles_typed_tokens() {
        // Type suffix is ignored (S for String, N for Number, etc.).
        let r = "<CALL:5:S>W1ABC<BAND:3:S>20m<MODE:3:S>SSB<eor>";
        let parsed = parse(r);
        assert_eq!(parsed.len(), 1);
        assert_eq!(parsed[0].callsign, "W1ABC");
    }

    #[test]
    fn case_insensitive_eor_eoh() {
        let lower = "<eoh><CALL:4>W1AW<BAND:3>40m<MODE:2>CW<eor>";
        let mixed = "<EOH><call:4>K1JT<Band:3>20m<MODE:2>CW<EOR>";
        assert_eq!(parse(lower).len(), 1);
        assert_eq!(parse(mixed).len(), 1);
    }
}
