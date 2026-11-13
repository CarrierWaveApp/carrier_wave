//! QRZ XML callbook lookup client.
//!
//! Faithful port of the QRZ XML half of the iOS
//! `CallsignLookupService+QRZ`: exchange username/password for a session key
//! (`?username=&password=&agent=` → `<Key>`), then look a callsign up
//! (`?s=key&callsign=` → callbook fields). Credentials and the session-key
//! cache live in the host secure store; this client is handed them per call by
//! the FFI `QrzApi`.
//!
//! Tags are matched with the same simple `<tag>…</tag>` scan the Swift code
//! uses — QRZ's XML is flat and unprefixed, so this is sufficient and avoids a
//! full XML dependency.

use crate::http::{HttpClient, HttpError};

const QRZ_XML_URL: &str = "https://xmldata.qrz.com/xml/current/";

#[derive(Debug, thiserror::Error)]
pub enum QrzError {
    /// Bad username/password (or QRZ refused the session request).
    #[error("QRZ authentication failed: {0}")]
    Auth(String),
    /// The session key expired — the caller should re-authenticate and retry.
    #[error("QRZ session expired")]
    SessionExpired,
    #[error(transparent)]
    Http(#[from] HttpError),
}

/// A parsed QRZ callbook record — the enrichment-relevant subset of the fields
/// the iOS lookup extracts.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct QrzLookup {
    /// Canonical callsign QRZ resolved to (may differ from the queried call when
    /// an old/alias call forwards to the current holder).
    pub call: String,
    pub first_name: Option<String>,
    pub last_name: Option<String>,
    pub nickname: Option<String>,
    pub grid: Option<String>,
    /// City (`addr2`).
    pub qth: Option<String>,
    pub state: Option<String>,
    pub country: Option<String>,
    pub license_class: Option<String>,
    pub previous_callsign: Option<String>,
    pub lat: Option<f64>,
    pub lon: Option<f64>,
}

impl QrzLookup {
    /// "First Last", "First", or "Last" — whichever parts are present.
    pub fn full_name(&self) -> Option<String> {
        match (&self.first_name, &self.last_name) {
            (Some(first), Some(last)) => Some(format!("{first} {last}")),
            (Some(first), None) => Some(first.clone()),
            (None, Some(last)) => Some(last.clone()),
            (None, None) => None,
        }
    }
}

/// QRZ XML callbook client. Build one per `HttpClient`; it is stateless (the
/// session key is owned by the caller).
#[derive(Debug, Clone)]
pub struct QrzClient {
    http: HttpClient,
    base_url: String,
}

impl QrzClient {
    pub fn new(http: HttpClient) -> Self {
        Self {
            http,
            base_url: QRZ_XML_URL.to_string(),
        }
    }

    pub fn with_base_url(mut self, base: impl Into<String>) -> Self {
        self.base_url = base.into();
        self
    }

    /// Exchange username/password for a session key.
    pub async fn session_key(&self, username: &str, password: &str) -> Result<String, QrzError> {
        let query = url::form_urlencoded::Serializer::new(String::new())
            .append_pair("username", username)
            .append_pair("password", password)
            .append_pair("agent", "CarrierWave")
            .finish();
        let url = format!("{}?{}", self.base_url, query);
        let xml = self.http.get_text(&url, "application/xml").await?;
        // QRZ can return a Key *and* a non-fatal notice; a present Key wins.
        if let Some(key) = parse_xml_value(&xml, "Key") {
            return Ok(key);
        }
        let message = parse_xml_value(&xml, "Error").unwrap_or_else(|| "no session key".into());
        Err(QrzError::Auth(message))
    }

    /// Look `callsign` up with a session key. `Ok(None)` means QRZ has no record;
    /// [`QrzError::SessionExpired`] tells the caller to re-auth and retry once.
    pub async fn lookup(
        &self,
        session_key: &str,
        callsign: &str,
    ) -> Result<Option<QrzLookup>, QrzError> {
        let query = url::form_urlencoded::Serializer::new(String::new())
            .append_pair("s", session_key)
            .append_pair("callsign", callsign)
            .finish();
        let url = format!("{}?{}", self.base_url, query);
        let xml = self.http.get_text(&url, "application/xml").await?;

        // Callbook data first — QRZ can include a non-fatal Error alongside it.
        if let Some(found) = parse_lookup(&xml, callsign) {
            return Ok(Some(found));
        }
        if let Some(message) = parse_xml_value(&xml, "Error") {
            let lower = message.to_lowercase();
            if lower.contains("session") || lower.contains("timeout") || lower.contains("invalid") {
                return Err(QrzError::SessionExpired);
            }
            if lower.contains("not found") {
                return Ok(None);
            }
            return Err(QrzError::Auth(message));
        }
        Ok(None)
    }
}

/// Extract the trimmed text of `<tag>…</tag>`, or `None` if absent/empty.
fn parse_xml_value(xml: &str, tag: &str) -> Option<String> {
    let open = format!("<{tag}>");
    let close = format!("</{tag}>");
    let start = xml.find(&open)? + open.len();
    let rest = &xml[start..];
    let end = rest.find(&close)?;
    let value = rest[..end].trim();
    if value.is_empty() {
        None
    } else {
        Some(value.to_string())
    }
}

/// Parse a callbook record. Mirrors `parseCallsignInfoFromXML`: requires at least
/// a name, grid, or city to count as a hit, and resolves the canonical call.
fn parse_lookup(xml: &str, queried: &str) -> Option<QrzLookup> {
    let call = parse_xml_value(xml, "call")
        .unwrap_or_else(|| queried.to_string())
        .to_uppercase();
    let first_name = parse_xml_value(xml, "fname");
    let last_name = parse_xml_value(xml, "name");
    let grid = parse_xml_value(xml, "grid");
    let qth = parse_xml_value(xml, "addr2");

    if first_name.is_none() && last_name.is_none() && grid.is_none() && qth.is_none() {
        return None;
    }

    let previous_callsign =
        parse_xml_value(xml, "p_call").or_else(|| previous_from_aliases(xml, &call));

    let lat = parse_xml_value(xml, "lat").and_then(|v| v.parse::<f64>().ok());
    let lon = parse_xml_value(xml, "lon").and_then(|v| v.parse::<f64>().ok());

    Some(QrzLookup {
        call,
        first_name,
        last_name,
        nickname: parse_xml_value(xml, "nickname"),
        grid,
        qth,
        state: parse_xml_value(xml, "state"),
        country: parse_xml_value(xml, "country"),
        license_class: parse_xml_value(xml, "class"),
        previous_callsign,
        lat,
        lon,
    })
}

/// First alias that isn't the current call or a portable variant (e.g. `DL/AA7BQ`).
fn previous_from_aliases(xml: &str, call: &str) -> Option<String> {
    let aliases = parse_xml_value(xml, "aliases")?;
    let upper = call.to_uppercase();
    aliases
        .split(',')
        .map(|alias| alias.trim().to_uppercase())
        .find(|alias| !alias.is_empty() && *alias != upper && !alias.contains('/'))
}

#[cfg(test)]
mod tests {
    use super::*;

    const SESSION_XML: &str = r#"<?xml version="1.0"?>
        <QRZDatabase version="1.34"><Session><Key>abc123sessionkey</Key>
        <Count>123</Count><SubExp>Wed Dec 31 2025</SubExp></Session></QRZDatabase>"#;

    const LOOKUP_XML: &str = r#"<?xml version="1.0"?>
        <QRZDatabase version="1.34"><Callsign>
        <call>AA7BQ</call><fname>Fred</fname><name>Lloyd</name>
        <nickname>Fred</nickname><addr2>Scottsdale</addr2><state>AZ</state>
        <country>United States</country><grid>DM43</grid><class>E</class>
        <aliases>N6WS,AA7BQ/7</aliases><lat>33.747</lat><lon>-112.246</lon></Callsign>
        <Session><Key>abc123</Key></Session></QRZDatabase>"#;

    #[test]
    fn parses_session_key() {
        assert_eq!(parse_xml_value(SESSION_XML, "Key").as_deref(), Some("abc123sessionkey"));
    }

    #[test]
    fn parses_full_lookup() {
        let found = parse_lookup(LOOKUP_XML, "aa7bq").expect("record");
        assert_eq!(found.call, "AA7BQ");
        assert_eq!(found.full_name().as_deref(), Some("Fred Lloyd"));
        assert_eq!(found.qth.as_deref(), Some("Scottsdale"));
        assert_eq!(found.state.as_deref(), Some("AZ"));
        assert_eq!(found.grid.as_deref(), Some("DM43"));
        assert_eq!(found.license_class.as_deref(), Some("E"));
        // First non-portable, non-self alias becomes the previous call.
        assert_eq!(found.previous_callsign.as_deref(), Some("N6WS"));
    }

    #[test]
    fn empty_record_is_none() {
        let xml = "<QRZDatabase><Callsign><call>W1AW</call></Callsign></QRZDatabase>";
        assert!(parse_lookup(xml, "w1aw").is_none(), "no name/grid/qth → not a hit");
    }

    #[test]
    fn p_call_wins_over_aliases() {
        let xml = "<Callsign><call>K1ABC</call><fname>Joe</fname>\
            <p_call>KZ9ZZZ</p_call><aliases>N6WS</aliases></Callsign>";
        let found = parse_lookup(xml, "k1abc").expect("record");
        assert_eq!(found.previous_callsign.as_deref(), Some("KZ9ZZZ"));
    }

    #[test]
    fn full_name_handles_partial() {
        let only_first = QrzLookup { first_name: Some("Fred".into()), ..Default::default() };
        assert_eq!(only_first.full_name().as_deref(), Some("Fred"));
        let only_last = QrzLookup { last_name: Some("Lloyd".into()), ..Default::default() };
        assert_eq!(only_last.full_name().as_deref(), Some("Lloyd"));
        assert_eq!(QrzLookup::default().full_name(), None);
    }

    #[test]
    fn parses_lat_lon() {
        let found = parse_lookup(LOOKUP_XML, "aa7bq").expect("record");
        assert_eq!(found.lat, Some(33.747));
        assert_eq!(found.lon, Some(-112.246));
    }

    #[test]
    fn missing_lat_lon_is_none() {
        let xml = "<Callsign><call>W1AW</call><fname>H</fname></Callsign>";
        let found = parse_lookup(xml, "w1aw").expect("record");
        assert_eq!(found.lat, None);
        assert_eq!(found.lon, None);
    }
}
