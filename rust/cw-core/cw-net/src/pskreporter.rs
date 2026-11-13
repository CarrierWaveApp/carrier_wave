//! PSK Reporter reception-report model + XML parser. Port of
//! `PSKReporterClient.swift`'s `PSKReporterSpot` + `PSKReporterXMLParser`.
//!
//! The wire format is XML where each `<receptionReport>` element carries the
//! data as attributes — `senderCallsign`, `receiverCallsign`, `frequency`,
//! `mode`, `sNR`, `flowStartSeconds`, and the locator pair. The Swift parser
//! is a SAX-style scan; we mirror that with `quick-xml`.

use chrono::{DateTime, Utc};
use quick_xml::events::Event;
use quick_xml::Reader;
use thiserror::Error;

/// A single PSK Reporter reception report.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct PskReporterSpot {
    pub sender_callsign: String,
    pub sender_locator: Option<String>,
    pub receiver_callsign: String,
    pub receiver_locator: Option<String>,
    /// Frequency in Hz, as PSK Reporter returns it.
    pub frequency: i64,
    pub mode: String,
    pub snr: Option<i32>,
    /// Unix epoch seconds for the slot start.
    pub flow_start_seconds: i64,
}

impl PskReporterSpot {
    /// Composite ID matching `PSKReporterSpot.id`.
    pub fn id(&self) -> String {
        format!(
            "{}-{}-{}-{}",
            self.sender_callsign, self.receiver_callsign, self.frequency, self.flow_start_seconds
        )
    }

    pub fn frequency_khz(&self) -> f64 {
        self.frequency as f64 / 1_000.0
    }

    pub fn timestamp(&self) -> DateTime<Utc> {
        DateTime::<Utc>::from_timestamp(self.flow_start_seconds, 0)
            .unwrap_or_else(|| DateTime::<Utc>::from_timestamp(0, 0).expect("epoch"))
    }
}

#[derive(Debug, Error)]
pub enum PskReporterParseError {
    #[error("XML parse error: {0}")]
    Xml(String),
}

/// Parse a PSK Reporter XML payload into spots. Rows missing any required
/// attribute (callsign pair, frequency, mode, flow-start) are silently
/// dropped, matching the Swift parser.
pub fn parse(xml: &str) -> Result<Vec<PskReporterSpot>, PskReporterParseError> {
    let mut reader = Reader::from_str(xml);
    reader.config_mut().trim_text(true);

    let mut spots = Vec::new();
    let mut buf = Vec::new();
    loop {
        match reader.read_event_into(&mut buf) {
            Ok(Event::Start(start)) | Ok(Event::Empty(start)) => {
                if start.name().as_ref() != b"receptionReport" {
                    continue;
                }
                let mut sender_call: Option<String> = None;
                let mut sender_loc: Option<String> = None;
                let mut receiver_call: Option<String> = None;
                let mut receiver_loc: Option<String> = None;
                let mut frequency: Option<i64> = None;
                let mut mode: Option<String> = None;
                let mut snr: Option<i32> = None;
                let mut flow_start: Option<i64> = None;

                for attr in start.attributes().with_checks(false).flatten() {
                    let key = attr.key.as_ref();
                    let value = match attr.unescape_value() {
                        Ok(cow) => cow.into_owned(),
                        Err(_) => continue,
                    };
                    match key {
                        b"senderCallsign" => sender_call = Some(value),
                        b"senderLocator" => sender_loc = Some(value),
                        b"receiverCallsign" => receiver_call = Some(value),
                        b"receiverLocator" => receiver_loc = Some(value),
                        b"frequency" => frequency = value.parse::<i64>().ok(),
                        b"mode" => mode = Some(value),
                        b"sNR" => snr = value.parse::<i32>().ok(),
                        b"flowStartSeconds" => flow_start = value.parse::<i64>().ok(),
                        _ => {}
                    }
                }

                if let (Some(sc), Some(rc), Some(freq), Some(mode), Some(flow)) = (
                    sender_call,
                    receiver_call,
                    frequency,
                    mode,
                    flow_start,
                ) {
                    spots.push(PskReporterSpot {
                        sender_callsign: sc,
                        sender_locator: sender_loc,
                        receiver_callsign: rc,
                        receiver_locator: receiver_loc,
                        frequency: freq,
                        mode,
                        snr,
                        flow_start_seconds: flow,
                    });
                }
            }
            Ok(Event::Eof) => break,
            Err(err) => return Err(PskReporterParseError::Xml(err.to_string())),
            _ => {}
        }
        buf.clear();
    }
    Ok(spots)
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = r##"
        <receptionReports>
            <receptionReport
                senderCallsign="W6JY"
                senderLocator="CM87"
                receiverCallsign="K2ABC"
                receiverLocator="FN20"
                frequency="14074000"
                mode="FT8"
                sNR="-10"
                flowStartSeconds="1735000000"/>
            <receptionReport
                senderCallsign="N0CALL"
                receiverCallsign="K3XYZ"
                frequency="7074000"
                mode="FT8"
                flowStartSeconds="1735000005"/>
            <receptionReport
                senderCallsign="MISSING_FREQ"
                receiverCallsign="K3XYZ"
                mode="FT8"
                flowStartSeconds="1735000010"/>
        </receptionReports>
    "##;

    #[test]
    fn parses_attributes_and_drops_incomplete_rows() {
        let spots = parse(SAMPLE).unwrap();
        assert_eq!(spots.len(), 2);

        let first = &spots[0];
        assert_eq!(first.sender_callsign, "W6JY");
        assert_eq!(first.sender_locator.as_deref(), Some("CM87"));
        assert_eq!(first.receiver_callsign, "K2ABC");
        assert_eq!(first.frequency, 14_074_000);
        assert_eq!(first.snr, Some(-10));
        assert_eq!(first.flow_start_seconds, 1_735_000_000);
        assert_eq!(first.frequency_khz(), 14_074.0);
        assert_eq!(
            first.id(),
            "W6JY-K2ABC-14074000-1735000000".to_string()
        );

        let second = &spots[1];
        assert!(second.sender_locator.is_none());
        assert!(second.snr.is_none());
    }

    #[test]
    fn malformed_xml_is_an_error() {
        let err = parse("<not-closed").unwrap_err();
        let PskReporterParseError::Xml(_) = err;
    }
}
