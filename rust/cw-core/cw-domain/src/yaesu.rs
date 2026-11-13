//! Yaesu CAT ASCII command builder + response parser. Port of
//! `YaesuProtocol.swift`. Commands terminate with `;`; frequencies are 9-digit
//! Hz; modes encoded as single hex chars 1–F.

use crate::text_protocol::extract_responses;

pub const TERMINATOR: char = ';';

/// Yaesu mode hex characters (CAT MD command).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum YaesuMode {
    Lsb,
    Usb,
    CwU,
    Fm,
    Am,
    RttyL,
    CwL,
    DataL,
    RttyU,
    DataFm,
    FmN,
    DataU,
    AmN,
    Psk,
    DataFmN,
}

impl YaesuMode {
    pub fn protocol_char(self) -> char {
        match self {
            Self::Lsb => '1',
            Self::Usb => '2',
            Self::CwU => '3',
            Self::Fm => '4',
            Self::Am => '5',
            Self::RttyL => '6',
            Self::CwL => '7',
            Self::DataL => '8',
            Self::RttyU => '9',
            Self::DataFm => 'A',
            Self::FmN => 'B',
            Self::DataU => 'C',
            Self::AmN => 'D',
            Self::Psk => 'E',
            Self::DataFmN => 'F',
        }
    }

    pub fn from_protocol_char(ch: char) -> Option<Self> {
        Some(match ch {
            '1' => Self::Lsb,
            '2' => Self::Usb,
            '3' => Self::CwU,
            '4' => Self::Fm,
            '5' => Self::Am,
            '6' => Self::RttyL,
            '7' => Self::CwL,
            '8' => Self::DataL,
            '9' => Self::RttyU,
            'A' => Self::DataFm,
            'B' => Self::FmN,
            'C' => Self::DataU,
            'D' => Self::AmN,
            'E' => Self::Psk,
            'F' => Self::DataFmN,
            _ => return None,
        })
    }

    pub fn carrier_wave_mode(self) -> &'static str {
        match self {
            Self::Lsb => "LSB",
            Self::Usb => "USB",
            Self::CwU | Self::CwL => "CW",
            Self::Fm | Self::FmN => "FM",
            Self::Am | Self::AmN => "AM",
            Self::RttyL | Self::RttyU => "RTTY",
            Self::DataL | Self::DataU | Self::DataFm | Self::DataFmN | Self::Psk => "DATA",
        }
    }

    pub fn from_carrier_wave_mode(mode: &str) -> Option<Self> {
        Some(match mode.to_uppercase().as_str() {
            "LSB" => Self::Lsb,
            "USB" | "SSB" => Self::Usb,
            "CW" => Self::CwU,
            "FM" => Self::Fm,
            "AM" => Self::Am,
            "RTTY" => Self::RttyL,
            "DATA" | "FT8" | "FT4" | "JTTY" => Self::DataU,
            _ => return None,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct YaesuInformation {
    pub frequency_hz: u64,
    pub clarifier_offset: i32,
    pub rx_clarifier: bool,
    pub tx_clarifier: bool,
    pub mode: Option<YaesuMode>,
}

// ---------- builders ----------

pub fn set_frequency(hz: u64) -> String {
    format!("FA{:09};", hz)
}

pub fn read_frequency() -> &'static str {
    "FA;"
}

pub fn set_mode(mode: YaesuMode, band: i32) -> String {
    format!("MD{}{};", band, mode.protocol_char())
}

pub fn read_mode(band: i32) -> String {
    format!("MD{};", band)
}

pub fn read_information() -> &'static str {
    "IF;"
}

pub fn set_ptt(on: bool) -> String {
    format!("TX{};", if on { 1 } else { 0 })
}

pub fn read_ptt() -> &'static str {
    "TX;"
}

pub fn set_rit(on: bool) -> String {
    format!("RT{};", if on { 1 } else { 0 })
}

pub fn read_rit() -> &'static str {
    "RT;"
}

pub fn set_xit(on: bool) -> String {
    format!("XT{};", if on { 1 } else { 0 })
}

pub fn read_xit() -> &'static str {
    "XT;"
}

pub fn clear_clarifier() -> &'static str {
    "RC;"
}

pub fn clarifier_up(hz: i32) -> String {
    let clamped = hz.clamp(0, 9_990);
    format!("RU{:04};", clamped)
}

pub fn clarifier_down(hz: i32) -> String {
    let clamped = hz.clamp(0, 9_990);
    format!("RD{:04};", clamped)
}

pub fn send_cw(text: &str) -> String {
    let truncated: String = text.chars().take(50).collect();
    format!("KM5{};KY5;", truncated)
}

// ---------- parsers ----------

pub fn parse_frequency_response(response: &str) -> Option<u64> {
    // Swift requires `response.count >= 11` even though Yaesu freq is 9 digits
    // — preserve that exact length check for byte-for-byte parity.
    if !response.starts_with("FA") || response.len() < 11 {
        return None;
    }
    response[2..].parse::<u64>().ok()
}

pub fn parse_mode_response(response: &str) -> Option<YaesuMode> {
    if !response.starts_with("MD") || response.len() < 4 {
        return None;
    }
    let mode_char = response.chars().nth(3)?;
    YaesuMode::from_protocol_char(mode_char)
}

pub fn parse_tx_response(response: &str) -> Option<bool> {
    if !response.starts_with("TX") || response.len() < 3 {
        return None;
    }
    let state_char = response.chars().nth(2)?;
    Some(state_char != '0')
}

pub fn parse_rit_response(response: &str) -> Option<bool> {
    if !response.starts_with("RT") || response.len() < 3 {
        return None;
    }
    Some(&response[2..] == "1")
}

pub fn parse_xit_response(response: &str) -> Option<bool> {
    if !response.starts_with("XT") || response.len() < 3 {
        return None;
    }
    Some(&response[2..] == "1")
}

pub fn parse_information_response(response: &str) -> Option<YaesuInformation> {
    if !response.starts_with("IF") || response.len() < 27 {
        return None;
    }
    let chars: Vec<char> = response.chars().collect();
    let freq_str: String = chars[5..=13].iter().collect();
    let freq_hz = freq_str.parse::<u64>().ok()?;
    let clar_str: String = chars[14..=18].iter().collect();
    let clar_offset = clar_str.parse::<i32>().unwrap_or(0);
    let rx_clar = chars[19] == '1';
    let tx_clar = chars[20] == '1';
    let mode = YaesuMode::from_protocol_char(chars[21]);
    Some(YaesuInformation {
        frequency_hz: freq_hz,
        clarifier_offset: clar_offset,
        rx_clarifier: rx_clar,
        tx_clarifier: tx_clar,
        mode,
    })
}

pub fn parse_responses(buffer: &str) -> (Vec<String>, usize) {
    extract_responses(buffer)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builds_set_frequency() {
        assert_eq!(set_frequency(14_250_000), "FA014250000;");
    }

    #[test]
    fn parses_frequency_response() {
        // Yaesu sends 9-digit but the Swift parser asserts len >= 11; pad like
        // FTDX10 responses do (the digits are still 9 wide, but the response
        // string is "FA" + 9 = 11 chars).
        assert_eq!(parse_frequency_response("FA014250000"), Some(14_250_000));
        assert_eq!(parse_frequency_response("FA00"), None);
    }

    #[test]
    fn builds_and_parses_mode() {
        assert_eq!(set_mode(YaesuMode::CwU, 0), "MD03;");
        assert_eq!(parse_mode_response("MD03"), Some(YaesuMode::CwU));
        assert_eq!(parse_mode_response("MD0F"), Some(YaesuMode::DataFmN));
    }

    #[test]
    fn parses_information_response() {
        // Synthesize a well-formed IF response — see FTDX10 reference §IF.
        // Layout (1-indexed cols): IF P1(001) P2(014250000) P3(+0000) P4(0) P5(0) P6(3) ...
        // We only assert the fields the parser surfaces.
        let resp = "IF001014250000+00000031000000";
        let info = parse_information_response(resp).expect("parse");
        assert_eq!(info.frequency_hz, 14_250_000);
        assert_eq!(info.clarifier_offset, 0);
        assert!(!info.rx_clarifier);
        assert!(!info.tx_clarifier);
        assert_eq!(info.mode, Some(YaesuMode::CwU));
    }

    #[test]
    fn clarifier_clamps() {
        assert_eq!(clarifier_up(99_999), "RU9990;");
        assert_eq!(clarifier_down(-1), "RD0000;");
    }

    #[test]
    fn send_cw_truncates_to_50() {
        let long = "A".repeat(80);
        let cmd = send_cw(&long);
        assert!(cmd.starts_with("KM5"));
        assert!(cmd.ends_with(";KY5;"));
        // KM5 + 50 chars + ; + KY5; = 60 chars
        assert_eq!(cmd.len(), 3 + 50 + 1 + 4);
    }
}
