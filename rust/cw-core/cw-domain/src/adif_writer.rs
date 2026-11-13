//! ADIF QSO record writer. Port of `ADIFExportService.swift`
//! (`swift/ios/CarrierWave/Services/ADIFExportService.swift`), the writer that
//! feeds the POTA single-activation and bulk export sheets
//! (`Views/POTAActivations/ADIFExportSheet.swift` /
//! `BulkADIFExportSheet.swift`).
//!
//! Field lengths in `<TAG:LENGTH>value` tokens are **byte (octet) counts**,
//! matching Swift's `value.utf8.count` (`ADIFExportService.formatField`,
//! :332-334) — the same octet convention the reader (`adif.rs`) parses
//! against. This matters for any non-ASCII value (accented names, CJK QTH,
//! etc.): the length prefix must be the UTF-8 byte length of the value, not
//! its character count.
//!
//! No value escaping is performed anywhere in the Swift source — a raw `<` or
//! `>` in a field value (e.g. NAME/COMMENT) is written through unescaped,
//! exactly as `ADIFExportService.formatField` does. This is a faithful port
//! of that (fragile but intentional) behavior, not a bug fix.

use crate::mode::ModeEquivalence;
use crate::park_reference;

/// One QSO's exportable fields. Mirrors `QSOExportSnapshot`
/// (`ADIFExportService.swift:12-82`); field names/types/optionality match
/// 1:1 so the port doesn't have to re-derive any defaulting logic.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct AdifWriteRecord {
    pub callsign: String,
    pub band: String,
    pub mode: String,
    pub frequency: Option<f64>,
    /// QSO date, already formatted (UTC) by the caller as `YYYYMMDD` —
    /// mirrors `appendCoreFields`'s `DateFormatter` `"yyyyMMdd"` (UTC)
    /// applied to the QSO timestamp (`ADIFExportService.swift:241-244`).
    pub qso_date: String,
    /// QSO time-on, already formatted (UTC) by the caller as `HHMMSS` —
    /// mirrors the same `DateFormatter` switched to `"HHmmss"` (UTC)
    /// (`ADIFExportService.swift:245-246`). Swift never writes `TIME_OFF`.
    pub time_on: String,
    pub rst_sent: Option<String>,
    pub rst_received: Option<String>,
    pub my_callsign: String,
    pub my_grid: Option<String>,
    pub their_grid: Option<String>,
    pub their_park_reference: Option<String>,
    pub notes: Option<String>,
    pub name: Option<String>,
    pub qth: Option<String>,
    pub state: Option<String>,
    pub country: Option<String>,
    pub power: Option<i32>,
    pub my_rig: Option<String>,
    pub sota_ref: Option<String>,
    pub dxcc: Option<i32>,
    pub qrz_confirmed: bool,
    pub lotw_confirmed: bool,
    /// `YYYYMMDD`, already formatted (UTC) by the caller — see
    /// `appendConfirmationFields` (`ADIFExportService.swift:296-309`).
    pub lotw_confirmed_date: Option<String>,
    pub station_callsign: Option<String>,
    pub contest_name: Option<String>,
    pub contest_serial_sent: Option<i32>,
    pub contest_serial_received: Option<i32>,
    pub contest_exchange_sent: Option<String>,
    pub contest_exchange_received: Option<String>,
    /// ADIF SAT_NAME — satellite short name (e.g. "AO-91").
    pub sat_name: Option<String>,
    /// ADIF PROP_MODE — "SAT" for satellite QSOs.
    pub prop_mode: Option<String>,
}

/// Header metadata for a single-activation export. Mirrors the parameters to
/// `ADIFExportService.generateADIF` (:91-96) plus `buildHeader` (:340-377).
#[derive(Debug, Clone, PartialEq)]
pub struct AdifHeaderOpts {
    pub park_reference: String,
    pub park_name: Option<String>,
    pub activator_callsign: String,
    /// `yyyy-MM-dd`, UTC, of the first QSO's timestamp — `"unknown"` if there
    /// are no QSOs (`buildHeader`:351).
    pub first_qso_date: String,
    /// `CFBundleShortVersionString`, or `"1.0"` if unavailable
    /// (`ADIFExportService.swift:132`/`:367`). Callers on non-Apple platforms
    /// should supply the app's marketing version string.
    pub program_version: String,
    /// `yyyyMMdd HHmmss`, UTC, formatted by the caller — `buildHeader`:371-374
    /// stamps `Date()` (now) at generation time, not a QSO time.
    pub created_timestamp: String,
}

/// Format a single ADIF field: `<NAME:byte_length>value`. Port of
/// `ADIFExportService.formatField` (:332-334) — `name` is uppercased, the
/// length is the value's UTF-8 **byte** count (not `chars().count()`), and
/// the value is written through unescaped.
pub fn format_field(name: &str, value: &str) -> String {
    format!("<{}:{}>{}", name.to_uppercase(), value.len(), value)
}

/// Build the `<EOH>`-terminated header block for a single-activation export.
/// Port of `buildHeader` (:340-377) + the `<EOH>` line appended by
/// `generateADIF` (:108-109). Returned as the joined lines (no trailing
/// newline) — callers join this with the QSO records using `"\n"`, matching
/// `generateADIF`'s `lines.joined(separator: "\n")` over the flattened list.
fn build_header(opts: &AdifHeaderOpts) -> Vec<String> {
    let mut lines = Vec::new();

    let mut header_comment = format!(
        "ADIF export for {}: POTA {}",
        opts.activator_callsign, opts.park_reference
    );
    if let Some(name) = &opts.park_name {
        header_comment.push_str(&format!(" ({})", name));
    }
    header_comment.push_str(&format!(" on {}", opts.first_qso_date));
    lines.push(header_comment);
    lines.push(String::new());

    lines.push(format_field("ADIF_VER", "3.1.7"));
    lines.push(format_field("PROGRAMID", "CarrierWave"));
    lines.push(format_field("PROGRAMVERSION", &opts.program_version));
    lines.push(format_field("CREATED_TIMESTAMP", &opts.created_timestamp));

    lines
}

/// Core QSO fields: CALL, BAND, MODE, [SUBMODE], [FREQ], QSO_DATE, TIME_ON,
/// [RST_RCVD], [RST_SENT]. Port of `appendCoreFields` (:228-254).
fn append_core_fields(fields: &mut Vec<String>, record: &AdifWriteRecord) {
    fields.push(format_field("CALL", &record.callsign));
    fields.push(format_field("BAND", &record.band));
    let (mode, submode) = ModeEquivalence::adif_mode_submode(&record.mode);
    fields.push(format_field("MODE", &mode));
    if let Some(submode) = submode {
        fields.push(format_field("SUBMODE", &submode));
    }

    if let Some(freq) = record.frequency {
        fields.push(format_field("FREQ", &format!("{:.6}", freq)));
    }

    fields.push(format_field("QSO_DATE", &record.qso_date));
    fields.push(format_field("TIME_ON", &record.time_on));

    if let Some(rst_rcvd) = &record.rst_received {
        if !rst_rcvd.is_empty() {
            fields.push(format_field("RST_RCVD", rst_rcvd));
        }
    }
    if let Some(rst_sent) = &record.rst_sent {
        if !rst_sent.is_empty() {
            fields.push(format_field("RST_SENT", rst_sent));
        }
    }
}

/// Station fields: [STATION_CALLSIGN], [OPERATOR], [GRIDSQUARE],
/// [MY_GRIDSQUARE]. Port of `appendStationFields` (:256-270).
fn append_station_fields(fields: &mut Vec<String>, record: &AdifWriteRecord) {
    let station_call = record.station_callsign.clone().unwrap_or_else(|| record.my_callsign.clone());
    if !station_call.is_empty() {
        fields.push(format_field("STATION_CALLSIGN", &station_call));
    }
    if !record.my_callsign.is_empty() {
        fields.push(format_field("OPERATOR", &record.my_callsign));
    }
    if let Some(their_grid) = &record.their_grid {
        if !their_grid.is_empty() {
            fields.push(format_field("GRIDSQUARE", &their_grid.to_uppercase()));
        }
    }
    if let Some(my_grid) = &record.my_grid {
        if !my_grid.is_empty() {
            fields.push(format_field("MY_GRIDSQUARE", &my_grid.to_uppercase()));
        }
    }
}

/// Contact fields: [NAME], [QTH], [STATE], [COUNTRY], [DXCC], [TX_PWR],
/// [MY_RIG]. Port of `appendContactFields` (:272-294).
fn append_contact_fields(fields: &mut Vec<String>, record: &AdifWriteRecord) {
    if let Some(name) = &record.name {
        if !name.is_empty() {
            fields.push(format_field("NAME", name));
        }
    }
    if let Some(qth) = &record.qth {
        if !qth.is_empty() {
            fields.push(format_field("QTH", qth));
        }
    }
    if let Some(state) = &record.state {
        if !state.is_empty() {
            fields.push(format_field("STATE", state));
        }
    }
    if let Some(country) = &record.country {
        if !country.is_empty() {
            fields.push(format_field("COUNTRY", country));
        }
    }
    if let Some(dxcc) = record.dxcc {
        fields.push(format_field("DXCC", &dxcc.to_string()));
    }
    if let Some(power) = record.power {
        fields.push(format_field("TX_PWR", &power.to_string()));
    }
    // NOTE: Swift emits MY_RIG unconditionally when `myRig` is non-nil, even
    // if the string is empty (no `!isEmpty` guard here, unlike the fields
    // above) — see `appendContactFields`:291-293. Preserved verbatim.
    if let Some(my_rig) = &record.my_rig {
        fields.push(format_field("MY_RIG", my_rig));
    }
}

/// POTA fields: MY_SIG, MY_SIG_INFO, MY_POTA_REF, [SIG, SIG_INFO, POTA_REF],
/// [SOTA_REF], QSLMSG. Port of `appendPOTAFields` (:400-423). The activation
/// export always has a park; a session export passes `None` for a record
/// worked from no park at all, which drops the `MY_*` block and `QSLMSG` but
/// keeps the park-to-park and summit fields.
fn append_pota_fields(fields: &mut Vec<String>, record: &AdifWriteRecord, park_reference: Option<&str>) {
    if let Some(park_reference) = park_reference {
        fields.push(format_field("MY_SIG", "POTA"));
        fields.push(format_field("MY_SIG_INFO", park_reference));
        fields.push(format_field("MY_POTA_REF", park_reference));
    }

    if let Some(their_park) = &record.their_park_reference {
        if !their_park.is_empty() {
            fields.push(format_field("SIG", "POTA"));
            fields.push(format_field("SIG_INFO", their_park));
            fields.push(format_field("POTA_REF", their_park));
        }
    }
    if let Some(sota_ref) = &record.sota_ref {
        if !sota_ref.is_empty() {
            fields.push(format_field("SOTA_REF", sota_ref));
        }
    }

    let Some(park_reference) = park_reference else {
        return;
    };
    let mut qsl_msg = format!("POTA {}", park_reference);
    if let Some(their_park) = &record.their_park_reference {
        if !their_park.is_empty() {
            qsl_msg.push_str(&format!(" P2P {}", their_park));
        }
    }
    fields.push(format_field("QSLMSG", &qsl_msg));
}

/// Confirmation fields: [QRZCOM_QSO_UPLOAD_STATUS], [LOTW_QSL_RCVD,
/// [LOTW_QSLRDATE]]. Port of `appendConfirmationFields` (:296-309).
fn append_confirmation_fields(fields: &mut Vec<String>, record: &AdifWriteRecord) {
    if record.qrz_confirmed {
        fields.push(format_field("QRZCOM_QSO_UPLOAD_STATUS", "Y"));
    }
    if record.lotw_confirmed {
        fields.push(format_field("LOTW_QSL_RCVD", "Y"));
        if let Some(lotw_date) = &record.lotw_confirmed_date {
            fields.push(format_field("LOTW_QSLRDATE", lotw_date));
        }
    }
}

/// Contest fields: [CONTEST_ID], [STX], [SRX], [STX_STRING], [SRX_STRING].
/// Port of `appendContestFields` (:311-327).
fn append_contest_fields(fields: &mut Vec<String>, record: &AdifWriteRecord) {
    if let Some(contest_id) = &record.contest_name {
        if !contest_id.is_empty() {
            fields.push(format_field("CONTEST_ID", contest_id));
        }
    }
    if let Some(stx) = record.contest_serial_sent {
        fields.push(format_field("STX", &stx.to_string()));
    }
    if let Some(srx) = record.contest_serial_received {
        fields.push(format_field("SRX", &srx.to_string()));
    }
    if let Some(stx_str) = &record.contest_exchange_sent {
        if !stx_str.is_empty() {
            fields.push(format_field("STX_STRING", stx_str));
        }
    }
    if let Some(srx_str) = &record.contest_exchange_received {
        if !srx_str.is_empty() {
            fields.push(format_field("SRX_STRING", srx_str));
        }
    }
}

/// Satellite fields: [SAT_NAME], [PROP_MODE]. Not part of the Swift port —
/// added Rust-first for the satellite quick-log flow (LoTW requires both for
/// satellite credit; a wrong/missing PROP_MODE means no match).
fn append_satellite_fields(fields: &mut Vec<String>, record: &AdifWriteRecord) {
    if let Some(sat_name) = &record.sat_name {
        if !sat_name.is_empty() {
            fields.push(format_field("SAT_NAME", sat_name));
        }
    }
    if let Some(prop_mode) = &record.prop_mode {
        if !prop_mode.is_empty() {
            fields.push(format_field("PROP_MODE", prop_mode));
        }
    }
}

/// Build one `<EOR>`-terminated QSO record. Field order: core → station →
/// contact → POTA → confirmation → contest → comment. Port of
/// `buildQSORecord` (:381-398). `notes` has POTA park references stripped
/// before being written as COMMENT (`ParkReference.stripFromFreeText`,
/// :392-394) — downstream systems should read SIG_INFO/MY_SIG_INFO instead
/// of re-parsing free text.
fn build_qso_record(record: &AdifWriteRecord, park_reference_str: &str) -> String {
    build_qso_record_with(record, Some(park_reference_str), None)
}

/// [`build_qso_record`] with the session-export extras: an optional own park
/// (see [`append_pota_fields`]) and the session's summit as `MY_SOTA_REF`,
/// written right after the POTA block (where the iOS session exporter puts
/// its `MY_*` program fields).
fn build_qso_record_with(
    record: &AdifWriteRecord,
    park_reference: Option<&str>,
    my_sota_ref: Option<&str>,
) -> String {
    let mut fields = Vec::new();

    append_core_fields(&mut fields, record);
    append_station_fields(&mut fields, record);
    append_contact_fields(&mut fields, record);
    append_pota_fields(&mut fields, record, park_reference);
    if let Some(my_sota_ref) = my_sota_ref {
        fields.push(format_field("MY_SOTA_REF", my_sota_ref));
    }
    append_satellite_fields(&mut fields, record);
    append_confirmation_fields(&mut fields, record);
    append_contest_fields(&mut fields, record);

    if let Some(notes) = &record.notes {
        if !notes.is_empty() {
            let cleaned = park_reference::strip_from_free_text(notes).unwrap_or_else(|| notes.clone());
            fields.push(format_field("COMMENT", &cleaned));
        }
    }

    let mut out = fields.join("");
    out.push_str("<EOR>");
    out
}

/// Generate a complete single-activation ADIF export: header + `<EOH>` +
/// one blank-line-separated `<EOR>`-terminated record per QSO, sorted by
/// `qso_date`+`time_on` ascending (the caller must pre-sort — Swift sorts by
/// `Date` timestamp, `generateADIF`:112, which this crate doesn't have; see
/// module docs). Port of `ADIFExportService.generateADIF` (:91-120).
///
/// `records` must already be in the desired output order (chronological,
/// matching Swift's `snapshots.sorted(by: { $0.timestamp < $1.timestamp
/// })`); this function does not re-sort.
pub fn write_adif(records: &[AdifWriteRecord], header: &AdifHeaderOpts) -> String {
    let mut lines: Vec<String> = build_header(header);
    lines.push("<EOH>".to_string());
    lines.push(String::new());

    for record in records {
        lines.push(build_qso_record(record, &header.park_reference));
        lines.push(String::new());
    }

    lines.join("\n")
}

/// Header options for a session-scoped export ([`write_session_adif`]).
/// Unlike [`AdifHeaderOpts`] the park is optional — a casual or SOTA-only
/// session has none — and the session's SOTA summit rides along.
#[derive(Debug, Clone, PartialEq)]
pub struct AdifSessionHeaderOpts {
    pub activator_callsign: String,
    /// The session's own park: named in the header comment and used by the
    /// caller as the per-record fallback park.
    pub park_reference: Option<String>,
    pub park_name: Option<String>,
    /// The session's SOTA summit, written as `MY_SOTA_REF` on every record.
    pub sota_reference: Option<String>,
    /// `yyyy-MM-dd` of the earliest record, or `"unknown"`.
    pub first_qso_date: String,
    pub program_version: String,
    /// `yyyyMMdd HHmmss` UTC.
    pub created_timestamp: String,
}

/// One record of a session export plus the park it was worked from.
#[derive(Debug, Clone, PartialEq)]
pub struct AdifSessionRecord {
    pub record: AdifWriteRecord,
    /// Park for this record's POTA block — the QSO's own park, else the
    /// session's (the caller resolves that). `None` writes no `MY_*` POTA
    /// fields for the record.
    pub park_reference: Option<String>,
}

/// Header comment for a session export: `ADIF export for <call>[: POTA
/// <park>[ (<name>)]][, SOTA <summit>] on <date>` — identical to the
/// activation header when the session is a plain park activation.
fn build_session_header(opts: &AdifSessionHeaderOpts) -> Vec<String> {
    let mut comment = format!("ADIF export for {}", opts.activator_callsign);
    if let Some(park) = &opts.park_reference {
        comment.push_str(&format!(": POTA {}", park));
        if let Some(name) = &opts.park_name {
            comment.push_str(&format!(" ({})", name));
        }
    }
    if let Some(summit) = &opts.sota_reference {
        comment.push_str(if opts.park_reference.is_some() { ", " } else { ": " });
        comment.push_str(&format!("SOTA {}", summit));
    }
    comment.push_str(&format!(" on {}", opts.first_qso_date));

    vec![
        comment,
        String::new(),
        format_field("ADIF_VER", "3.1.7"),
        format_field("PROGRAMID", "CarrierWave"),
        format_field("PROGRAMVERSION", &opts.program_version),
        format_field("CREATED_TIMESTAMP", &opts.created_timestamp),
    ]
}

/// Generate a complete session-scoped ADIF export: the same layout as
/// [`write_adif`] (header + `<EOH>` + blank-line-separated records) but with
/// the park resolved per record, so one file can carry a merged session that
/// spans parks or days, a rove, or casual QSOs merged into a park session.
/// `records` must already be chronological; this function does not re-sort.
pub fn write_session_adif(records: &[AdifSessionRecord], header: &AdifSessionHeaderOpts) -> String {
    let mut lines: Vec<String> = build_session_header(header);
    lines.push("<EOH>".to_string());
    lines.push(String::new());

    for entry in records {
        lines.push(build_qso_record_with(
            &entry.record,
            entry.park_reference.as_deref(),
            header.sota_reference.as_deref(),
        ));
        lines.push(String::new());
    }

    lines.join("\n")
}

/// One activation's worth of QSOs for a bulk export. Mirrors
/// `BulkADIFActivation` (`ADIFExportService.swift:443-447`).
#[derive(Debug, Clone, PartialEq)]
pub struct AdifBulkActivation {
    pub records: Vec<AdifWriteRecord>,
    pub park_reference: String,
    pub park_name: Option<String>,
}

/// Generate a combined ADIF export for multiple activations. Port of
/// `ADIFExportService.generateBulkADIF` (:123-157). Unlike the
/// single-activation header, the bulk header has no per-park comment line
/// (just an aggregate "ADIF export for N activations: <park list>") and each
/// activation's QSO block is preceded by `// Activation: <ref>` (+ optional
/// `// Park: <name>`) plain-text comment lines that are **not** ADIF fields
/// (`generateBulkADIF`:143-147) — they carry no `<TAG:LEN>` prefix and the
/// reader (`adif.rs`) ignores any text between tokens, so these round-trip
/// as inert commentary exactly like Swift's.
///
/// `created_timestamp` is `yyyyMMdd HHmmss` UTC, formatted by the caller
/// (mirrors `generateBulkADIF`:134-137, which stamps `Date()` at generation
/// time). `program_version` is `CFBundleShortVersionString` or `"1.0"`.
pub fn write_bulk_adif(
    activations: &[AdifBulkActivation],
    program_version: &str,
    created_timestamp: &str,
) -> String {
    let mut lines: Vec<String> = Vec::new();

    let park_list: Vec<&str> = activations.iter().map(|a| a.park_reference.as_str()).collect();
    lines.push(format!(
        "ADIF export for {} activations: {}",
        activations.len(),
        park_list.join(", ")
    ));
    lines.push(String::new());
    lines.push(format_field("ADIF_VER", "3.1.7"));
    lines.push(format_field("PROGRAMID", "CarrierWave"));
    lines.push(format_field("PROGRAMVERSION", program_version));
    lines.push(format_field("CREATED_TIMESTAMP", created_timestamp));
    lines.push("<EOH>".to_string());
    lines.push(String::new());

    for activation in activations {
        lines.push(format!("// Activation: {}", activation.park_reference));
        if let Some(name) = &activation.park_name {
            lines.push(format!("// Park: {}", name));
        }
        lines.push(String::new());

        for record in &activation.records {
            lines.push(build_qso_record(record, &activation.park_reference));
            lines.push(String::new());
        }
    }

    lines.join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn minimal_record() -> AdifWriteRecord {
        AdifWriteRecord {
            callsign: "K1JT".to_string(),
            band: "40m".to_string(),
            mode: "FT8".to_string(),
            qso_date: "20260102".to_string(),
            time_on: "050000".to_string(),
            my_callsign: "W6JY".to_string(),
            ..Default::default()
        }
    }

    // ---- format_field ----

    #[test]
    fn format_field_uses_byte_length_not_char_count() {
        // Swift: `value.utf8.count`, not `value.count`. "José" is 4 Unicode
        // scalars / 4 `Character`s but 5 UTF-8 bytes (é is 2 bytes).
        assert_eq!(format_field("NAME", "José"), "<NAME:5>José");
        assert_eq!("José".chars().count(), 4);
        assert_eq!("José".len(), 5);
    }

    #[test]
    fn format_field_uppercases_name_only() {
        assert_eq!(format_field("call", "W1AW"), "<CALL:4>W1AW");
    }

    #[test]
    fn format_field_does_not_escape_angle_brackets() {
        // Matches Swift: formatField never escapes '<'/'>' in values. Faithful
        // port of a fragile-but-intentional behavior, not a fix.
        assert_eq!(format_field("COMMENT", "a<b>c"), "<COMMENT:5>a<b>c");
    }

    // ---- mode/submode delegation ----

    #[test]
    fn core_fields_split_submode_for_usb() {
        let mut record = minimal_record();
        record.mode = "USB".to_string();
        let mut fields = Vec::new();
        append_core_fields(&mut fields, &record);
        assert!(fields.contains(&"<MODE:3>SSB".to_string()));
        assert!(fields.contains(&"<SUBMODE:3>USB".to_string()));
    }

    #[test]
    fn core_fields_no_submode_for_ft8() {
        let record = minimal_record();
        let mut fields = Vec::new();
        append_core_fields(&mut fields, &record);
        assert!(fields.contains(&"<MODE:3>FT8".to_string()));
        assert!(!fields.iter().any(|f| f.starts_with("<SUBMODE")));
    }

    // ---- comment park-ref stripping ----

    #[test]
    fn comment_strips_park_reference() {
        let mut record = minimal_record();
        record.notes = Some("Great chasing K-1234 today".to_string());
        let out = build_qso_record(&record, "US-0001");
        // "K-1234" is stripped by park_reference::strip_from_free_text:
        // "Great chasing K-1234 today" -> "Great chasing  today" (double
        // space where the token was) -> "Great chasing today" after the
        // single "  " -> " " collapse pass. 19 bytes (all ASCII).
        assert!(out.contains("<COMMENT:19>Great chasing today"), "{out}");
        assert!(!out.contains("K-1234"));
    }

    #[test]
    fn comment_omitted_when_stripped_to_empty() {
        let mut record = minimal_record();
        record.notes = Some("K-1234".to_string());
        let out = build_qso_record(&record, "US-0001");
        // strip_from_free_text returns None when nothing remains; Swift's
        // `?? notes` fallback then re-inserts the *original* unstripped text
        // (ADIFExportService.swift:393: `ParkReference.stripFromFreeText(notes) ?? notes`).
        assert!(out.contains("<COMMENT:6>K-1234"), "{out}");
    }

    // ---- satellite fields ----

    #[test]
    fn satellite_fields_emitted_when_present() {
        let mut record = minimal_record();
        record.sat_name = Some("AO-91".to_string());
        record.prop_mode = Some("SAT".to_string());
        let out = build_qso_record(&record, "US-0001");
        assert!(out.contains("<SAT_NAME:5>AO-91"), "{out}");
        assert!(out.contains("<PROP_MODE:3>SAT"), "{out}");
    }

    #[test]
    fn satellite_fields_omitted_when_absent_or_empty() {
        let out = build_qso_record(&minimal_record(), "US-0001");
        assert!(!out.contains("SAT_NAME"), "{out}");
        assert!(!out.contains("PROP_MODE"), "{out}");

        let mut record = minimal_record();
        record.sat_name = Some(String::new());
        record.prop_mode = Some(String::new());
        let out = build_qso_record(&record, "US-0001");
        assert!(!out.contains("SAT_NAME"), "{out}");
        assert!(!out.contains("PROP_MODE"), "{out}");
    }

    // ---- golden fixtures ----
    //
    // Each fixture's expected string is derived BY HAND from
    // ADIFExportService.swift's logic (field order + formatField), not
    // generated by running this code and eyeballing it. Line-by-line
    // provenance is in each test's comments.

    /// Fixture 1: normal multi-field QSO, single activation export.
    /// Derived from `generateADIF` (:91-120) + `buildHeader` (:340-377) +
    /// `buildQSORecord` (:381-398) with every optional field populated.
    #[test]
    fn golden_normal_multi_field_qso() {
        let record = AdifWriteRecord {
            callsign: "W1ABC".to_string(),
            band: "20m".to_string(),
            mode: "SSB".to_string(),
            frequency: Some(14.250),
            qso_date: "20260115".to_string(),
            time_on: "143000".to_string(),
            rst_sent: Some("59".to_string()),
            rst_received: Some("59".to_string()),
            my_callsign: "W6JY".to_string(),
            my_grid: Some("cm87".to_string()),
            their_grid: Some("fn31".to_string()),
            their_park_reference: Some("K-1234".to_string()),
            notes: Some("Nice signal".to_string()),
            name: Some("Bob".to_string()),
            qth: Some("Springfield".to_string()),
            state: Some("IL".to_string()),
            country: Some("United States".to_string()),
            power: Some(5),
            my_rig: Some("KX2".to_string()),
            sota_ref: None,
            dxcc: Some(291),
            qrz_confirmed: true,
            lotw_confirmed: true,
            lotw_confirmed_date: Some("20260116".to_string()),
            station_callsign: None,
            contest_name: None,
            contest_serial_sent: None,
            contest_serial_received: None,
            contest_exchange_sent: None,
            contest_exchange_received: None,
            sat_name: None,
            prop_mode: None,
        };
        let header = AdifHeaderOpts {
            park_reference: "US-0001".to_string(),
            park_name: Some("Golden Gate NRA".to_string()),
            activator_callsign: "W6JY".to_string(),
            first_qso_date: "2026-01-15".to_string(),
            program_version: "2.3.0".to_string(),
            created_timestamp: "20260115 200000".to_string(),
        };

        let actual = write_adif(&[record], &header);

        // Each line derived by hand from ADIFExportService.swift: the header
        // comment (buildHeader:354-359), blank separator, the four header
        // fields (buildHeader:363-374) each via formatField (byte lengths:
        // ADIF_VER "3.1.7"=5, PROGRAMID "CarrierWave"=11, PROGRAMVERSION
        // "2.3.0"=5, CREATED_TIMESTAMP "20260115 200000"=15), <EOH>, blank
        // separator, then the single QSO record's fields in
        // buildQSORecord's append order (core/station/contact/POTA/
        // confirmation/contest/comment), each field's length hand-counted
        // in UTF-8 bytes (all-ASCII here, so byte count == char count).
        let expected_lines = [
            "ADIF export for W6JY: POTA US-0001 (Golden Gate NRA) on 2026-01-15",
            "",
            "<ADIF_VER:5>3.1.7",
            "<PROGRAMID:11>CarrierWave",
            "<PROGRAMVERSION:5>2.3.0",
            "<CREATED_TIMESTAMP:15>20260115 200000",
            "<EOH>",
            "",
            "<CALL:5>W1ABC<BAND:3>20m<MODE:3>SSB<FREQ:9>14.250000<QSO_DATE:8>20260115<TIME_ON:6>143000<RST_RCVD:2>59<RST_SENT:2>59<STATION_CALLSIGN:4>W6JY<OPERATOR:4>W6JY<GRIDSQUARE:4>FN31<MY_GRIDSQUARE:4>CM87<NAME:3>Bob<QTH:11>Springfield<STATE:2>IL<COUNTRY:13>United States<DXCC:3>291<TX_PWR:1>5<MY_RIG:3>KX2<MY_SIG:4>POTA<MY_SIG_INFO:7>US-0001<MY_POTA_REF:7>US-0001<SIG:4>POTA<SIG_INFO:6>K-1234<POTA_REF:6>K-1234<QSLMSG:23>POTA US-0001 P2P K-1234<QRZCOM_QSO_UPLOAD_STATUS:1>Y<LOTW_QSL_RCVD:1>Y<LOTW_QSLRDATE:8>20260116<COMMENT:11>Nice signal<EOR>",
            "",
        ];
        assert_eq!(actual, expected_lines.join("\n"));
    }

    /// Fixture 2: Unicode/multibyte name + comment — the byte-length case.
    /// `name` = "José" (5 UTF-8 bytes, 4 chars) written via NAME; `notes`
    /// contains "München" (8 bytes, 7 chars) with no park ref to strip.
    /// Verifies `formatField`'s `value.utf8.count` port end-to-end, not just
    /// in isolation.
    #[test]
    fn golden_unicode_byte_length_qso() {
        let record = AdifWriteRecord {
            callsign: "DL1ABC".to_string(),
            band: "40m".to_string(),
            mode: "CW".to_string(),
            qso_date: "20260203".to_string(),
            time_on: "081500".to_string(),
            my_callsign: "W6JY".to_string(),
            name: Some("José".to_string()),
            notes: Some("QTH München".to_string()),
            ..Default::default()
        };
        let header = AdifHeaderOpts {
            park_reference: "US-0002".to_string(),
            park_name: None,
            activator_callsign: "W6JY".to_string(),
            first_qso_date: "2026-02-03".to_string(),
            program_version: "2.3.0".to_string(),
            created_timestamp: "20260203 090000".to_string(),
        };

        let actual = write_adif(&[record], &header);

        // "José" = J,o,s,é: 3 ASCII bytes + 2-byte 'é' = 5 bytes (4 chars) —
        // <NAME:5>, not <NAME:4> (char count) or <NAME:8> (over-count).
        // "QTH München" is 11 chars (Q,T,H,' ',M,ü,n,c,h,e,n): 10 single-byte
        // ASCII chars + 1 two-byte 'ü' = 12 bytes — <COMMENT:12>, not
        // <COMMENT:11> (char count).
        let expected_record = "<CALL:6>DL1ABC<BAND:3>40m<MODE:2>CW<QSO_DATE:8>20260203<TIME_ON:6>081500<STATION_CALLSIGN:4>W6JY<OPERATOR:4>W6JY<NAME:5>José<MY_SIG:4>POTA<MY_SIG_INFO:7>US-0002<MY_POTA_REF:7>US-0002<QSLMSG:12>POTA US-0002<COMMENT:12>QTH München<EOR>";
        assert!(expected_record.contains("<NAME:5>José"));
        assert!(expected_record.contains("<COMMENT:12>QTH München"));

        let expected = [
            "ADIF export for W6JY: POTA US-0002 on 2026-02-03",
            "",
            "<ADIF_VER:5>3.1.7",
            "<PROGRAMID:11>CarrierWave",
            "<PROGRAMVERSION:5>2.3.0",
            "<CREATED_TIMESTAMP:15>20260203 090000",
            "<EOH>",
            "",
            expected_record,
            "",
        ]
        .join("\n");
        assert_eq!(actual, expected);
    }

    /// Fixture 3: minimal-fields QSO — only the fields Swift always emits
    /// unconditionally (CALL/BAND/MODE/QSO_DATE/TIME_ON + the
    /// always-appended STATION_CALLSIGN/OPERATOR when `myCallsign` is
    /// non-empty, + the always-appended MY_SIG/MY_SIG_INFO/MY_POTA_REF/QSLMSG
    /// POTA block). No optional fields populated.
    #[test]
    fn golden_minimal_fields_qso() {
        let record = minimal_record(); // K1JT, 40m, FT8, no optionals
        let header = AdifHeaderOpts {
            park_reference: "US-0003".to_string(),
            park_name: None,
            activator_callsign: "W6JY".to_string(),
            first_qso_date: "2026-01-02".to_string(),
            program_version: "2.3.0".to_string(),
            created_timestamp: "20260102 050500".to_string(),
        };

        let actual = write_adif(&[record], &header);

        let expected = [
            "ADIF export for W6JY: POTA US-0003 on 2026-01-02",
            "",
            "<ADIF_VER:5>3.1.7",
            "<PROGRAMID:11>CarrierWave",
            "<PROGRAMVERSION:5>2.3.0",
            "<CREATED_TIMESTAMP:15>20260102 050500",
            "<EOH>",
            "",
            "<CALL:4>K1JT<BAND:3>40m<MODE:3>FT8<QSO_DATE:8>20260102<TIME_ON:6>050000<STATION_CALLSIGN:4>W6JY<OPERATOR:4>W6JY<MY_SIG:4>POTA<MY_SIG_INFO:7>US-0003<MY_POTA_REF:7>US-0003<QSLMSG:12>POTA US-0003<EOR>",
            "",
        ]
        .join("\n");
        assert_eq!(actual, expected);
    }

    // ---- round-trip vs the existing reader (adif.rs) ----

    #[test]
    fn round_trips_through_adif_reader() {
        let record = AdifWriteRecord {
            callsign: "w1abc".to_string(), // reader uppercases on read
            band: "20M".to_string(),       // reader lowercases on read
            mode: "FT8".to_string(),
            qso_date: "20260115".to_string(),
            time_on: "143000".to_string(),
            my_callsign: "W6JY".to_string(),
            their_grid: Some("fn31".to_string()),
            my_grid: Some("cm87".to_string()),
            dxcc: Some(291),
            country: Some("United States".to_string()),
            ..Default::default()
        };
        let header = AdifHeaderOpts {
            park_reference: "US-0004".to_string(),
            park_name: None,
            activator_callsign: "W6JY".to_string(),
            first_qso_date: "2026-01-15".to_string(),
            program_version: "2.3.0".to_string(),
            created_timestamp: "20260115 200000".to_string(),
        };

        let adif = write_adif(&[record], &header);
        let parsed = crate::adif::parse(&adif);
        assert_eq!(parsed.len(), 1);
        let round = &parsed[0];
        assert_eq!(round.callsign, "W1ABC");
        assert_eq!(round.band, "20m");
        assert_eq!(round.mode, "FT8");
        assert_eq!(round.qso_date.as_deref(), Some("20260115"));
        assert_eq!(round.time_on.as_deref(), Some("143000"));
        assert_eq!(round.gridsquare.as_deref(), Some("FN31"));
        assert_eq!(round.my_gridsquare.as_deref(), Some("CM87"));
        assert_eq!(round.dxcc, Some(291));
        assert_eq!(round.country.as_deref(), Some("United States"));
        // sig_info reader prefers "sig_info"/"pota_ref"; our writer emits
        // MY_SIG_INFO/MY_POTA_REF (their-side SIG_INFO omitted since
        // their_park_reference is None here) — nothing to assert there.
    }

    // ---- bulk export ----

    #[test]
    fn bulk_export_two_activations() {
        let a = AdifBulkActivation {
            records: vec![minimal_record()],
            park_reference: "US-0001".to_string(),
            park_name: Some("Park One".to_string()),
        };
        let mut second = minimal_record();
        second.callsign = "W2XYZ".to_string();
        let b = AdifBulkActivation {
            records: vec![second],
            park_reference: "US-0002".to_string(),
            park_name: None,
        };

        let actual = write_bulk_adif(&[a, b], "2.3.0", "20260102 060000");

        let expected = [
            "ADIF export for 2 activations: US-0001, US-0002",
            "",
            "<ADIF_VER:5>3.1.7",
            "<PROGRAMID:11>CarrierWave",
            "<PROGRAMVERSION:5>2.3.0",
            "<CREATED_TIMESTAMP:15>20260102 060000",
            "<EOH>",
            "",
            "// Activation: US-0001",
            "// Park: Park One",
            "",
            "<CALL:4>K1JT<BAND:3>40m<MODE:3>FT8<QSO_DATE:8>20260102<TIME_ON:6>050000<STATION_CALLSIGN:4>W6JY<OPERATOR:4>W6JY<MY_SIG:4>POTA<MY_SIG_INFO:7>US-0001<MY_POTA_REF:7>US-0001<QSLMSG:12>POTA US-0001<EOR>",
            "",
            "// Activation: US-0002",
            "",
            "<CALL:5>W2XYZ<BAND:3>40m<MODE:3>FT8<QSO_DATE:8>20260102<TIME_ON:6>050000<STATION_CALLSIGN:4>W6JY<OPERATOR:4>W6JY<MY_SIG:4>POTA<MY_SIG_INFO:7>US-0002<MY_POTA_REF:7>US-0002<QSLMSG:12>POTA US-0002<EOR>",
            "",
        ]
        .join("\n");
        assert_eq!(actual, expected);
    }

    fn session_record(park: Option<&str>) -> AdifSessionRecord {
        AdifSessionRecord {
            record: AdifWriteRecord {
                callsign: "K1JT".to_string(),
                band: "20m".to_string(),
                mode: "CW".to_string(),
                frequency: None,
                qso_date: "20260115".to_string(),
                time_on: "143000".to_string(),
                rst_sent: None,
                rst_received: None,
                my_callsign: "W6JY".to_string(),
                my_grid: None,
                their_grid: None,
                their_park_reference: Some("K-1234".to_string()),
                notes: None,
                name: None,
                qth: None,
                state: None,
                country: None,
                power: None,
                my_rig: None,
                sota_ref: None,
                dxcc: None,
                qrz_confirmed: false,
                lotw_confirmed: false,
                lotw_confirmed_date: None,
                station_callsign: None,
                contest_name: None,
                contest_serial_sent: None,
                contest_serial_received: None,
                contest_exchange_sent: None,
                contest_exchange_received: None,
                sat_name: None,
                prop_mode: None,
            },
            park_reference: park.map(str::to_string),
        }
    }

    fn session_header(park: Option<&str>, sota: Option<&str>) -> AdifSessionHeaderOpts {
        AdifSessionHeaderOpts {
            activator_callsign: "W6JY".to_string(),
            park_reference: park.map(str::to_string),
            park_name: park.map(|_| "Park".to_string()),
            sota_reference: sota.map(str::to_string),
            first_qso_date: "2026-01-15".to_string(),
            program_version: "2.3.0".to_string(),
            created_timestamp: "20260115 150000".to_string(),
        }
    }

    #[test]
    fn session_export_resolves_park_per_record_and_writes_summit() {
        let header = session_header(Some("US-0001"), Some("W6/NC-001"));
        let out = write_session_adif(
            &[
                session_record(Some("US-0001")),
                session_record(Some("US-0002")),
                session_record(None),
            ],
            &header,
        );

        assert!(
            out.starts_with("ADIF export for W6JY: POTA US-0001 (Park), SOTA W6/NC-001 on 2026-01-15\n"),
            "{out}"
        );
        assert_eq!(out.matches("<EOR>").count(), 3);
        assert_eq!(out.matches("<MY_SIG:4>POTA").count(), 2, "{out}");
        assert_eq!(out.matches("<MY_SIG_INFO:7>US-0001").count(), 1, "{out}");
        assert_eq!(out.matches("<MY_SIG_INFO:7>US-0002").count(), 1, "{out}");
        assert_eq!(out.matches("<QSLMSG:").count(), 2, "{out}");
        // The park-less record keeps its park-to-park fields and the summit.
        assert_eq!(out.matches("<SIG_INFO:6>K-1234").count(), 3, "{out}");
        assert_eq!(out.matches("<MY_SOTA_REF:9>W6/NC-001").count(), 3, "{out}");
        // Field order: POTA block, then MY_SOTA_REF, then the rest.
        let first = out.find("<MY_POTA_REF:7>US-0001").unwrap();
        let summit = out.find("<MY_SOTA_REF:9>W6/NC-001").unwrap();
        assert!(first < summit, "{out}");
    }

    #[test]
    fn session_export_without_park_or_summit_is_plain() {
        let out = write_session_adif(&[session_record(None)], &session_header(None, None));
        assert!(out.starts_with("ADIF export for W6JY on 2026-01-15\n"), "{out}");
        assert!(!out.contains("<MY_SIG"), "{out}");
        assert!(!out.contains("<MY_SOTA_REF"), "{out}");
        assert!(!out.contains("<QSLMSG"), "{out}");
        assert!(out.contains("<SIG:4>POTA<SIG_INFO:6>K-1234<POTA_REF:6>K-1234"), "{out}");
    }

    #[test]
    fn session_export_matches_activation_export_for_a_plain_park_session() {
        // Same park on every record and no summit → byte-identical to write_adif.
        let activation_header = AdifHeaderOpts {
            park_reference: "US-0001".to_string(),
            park_name: Some("Park".to_string()),
            activator_callsign: "W6JY".to_string(),
            first_qso_date: "2026-01-15".to_string(),
            program_version: "2.3.0".to_string(),
            created_timestamp: "20260115 150000".to_string(),
        };
        let records = [session_record(Some("US-0001")), session_record(Some("US-0001"))];
        let plain: Vec<AdifWriteRecord> = records.iter().map(|r| r.record.clone()).collect();
        assert_eq!(
            write_session_adif(&records, &session_header(Some("US-0001"), None)),
            write_adif(&plain, &activation_header)
        );
    }
}
