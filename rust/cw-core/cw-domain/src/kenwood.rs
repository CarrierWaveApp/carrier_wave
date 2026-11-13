//! Kenwood/Elecraft K3 ASCII command builder + response parser. Port of
//! `KenwoodProtocol.swift`. Commands are terminated by `;`; frequencies are
//! 11-digit Hz; modes are single digits.

use crate::text_protocol::extract_responses;

pub const TERMINATOR: char = ';';

/// Kenwood mode digits (K3 MD command).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KenwoodMode {
    Lsb = 1,
    Usb = 2,
    Cw = 3,
    Fm = 4,
    Am = 5,
    Data = 6,
    CwR = 7,
    DataR = 9,
}

impl KenwoodMode {
    pub fn raw_value(self) -> i32 {
        self as i32
    }

    pub fn from_raw(raw: i32) -> Option<Self> {
        Some(match raw {
            1 => Self::Lsb,
            2 => Self::Usb,
            3 => Self::Cw,
            4 => Self::Fm,
            5 => Self::Am,
            6 => Self::Data,
            7 => Self::CwR,
            9 => Self::DataR,
            _ => return None,
        })
    }

    /// Carrier Wave canonical mode string.
    pub fn carrier_wave_mode(self) -> &'static str {
        match self {
            Self::Lsb => "LSB",
            Self::Usb => "USB",
            Self::Cw | Self::CwR => "CW",
            Self::Fm => "FM",
            Self::Am => "AM",
            Self::Data | Self::DataR => "DATA",
        }
    }

    /// Map from a Carrier Wave mode string (case-insensitive). Returns `None`
    /// for modes without a Kenwood equivalent.
    pub fn from_carrier_wave_mode(mode: &str) -> Option<Self> {
        Some(match mode.to_uppercase().as_str() {
            "LSB" => Self::Lsb,
            "USB" | "SSB" => Self::Usb,
            "CW" => Self::Cw,
            "FM" => Self::Fm,
            "AM" => Self::Am,
            "DATA" | "FT8" | "FT4" | "RTTY" | "JTTY" => Self::Data,
            _ => return None,
        })
    }
}

// ---------- builders ----------

pub fn set_frequency(hz: u64) -> String {
    format!("FA{:011};", hz)
}

pub fn read_frequency() -> &'static str {
    "FA;"
}

pub fn set_mode(mode: KenwoodMode) -> String {
    format!("MD{};", mode.raw_value())
}

pub fn read_mode() -> &'static str {
    "MD;"
}

pub fn set_xit(on: bool) -> String {
    format!("XT{};", if on { 1 } else { 0 })
}

pub fn read_xit() -> &'static str {
    "XT;"
}

pub fn set_rit_xit_offset(hz: i32) -> String {
    let clamped = hz.clamp(-9_999, 9_999);
    let sign = if clamped >= 0 { '+' } else { '-' };
    format!("RO{}{:04};", sign, clamped.unsigned_abs())
}

pub fn read_rit() -> &'static str {
    "RT;"
}

pub fn read_rit_xit_offset() -> &'static str {
    "RO;"
}

pub fn clear_rit_xit() -> &'static str {
    "RC;"
}

pub fn set_power_level(watts: u8) -> String {
    format!("PC{:03};", watts)
}

pub fn read_power_level() -> &'static str {
    "PC;"
}

// ---------- parsers ----------

pub fn parse_frequency_response(response: &str) -> Option<u64> {
    if !response.starts_with("FA") || response.len() < 11 {
        return None;
    }
    response[2..].parse::<u64>().ok()
}

pub fn parse_mode_response(response: &str) -> Option<KenwoodMode> {
    if !response.starts_with("MD") || response.len() < 3 {
        return None;
    }
    let digit: i32 = response[2..].parse().ok()?;
    KenwoodMode::from_raw(digit)
}

pub fn parse_xit_response(response: &str) -> Option<bool> {
    if !response.starts_with("XT") || response.len() < 3 {
        return None;
    }
    Some(&response[2..] == "1")
}

pub fn parse_rit_response(response: &str) -> Option<bool> {
    if !response.starts_with("RT") || response.len() < 3 {
        return None;
    }
    Some(&response[2..] == "1")
}

pub fn parse_rit_xit_offset_response(response: &str) -> Option<i32> {
    if !response.starts_with("RO") || response.len() < 7 {
        return None;
    }
    response[2..].parse::<i32>().ok()
}

pub fn parse_power_level_response(response: &str) -> Option<u8> {
    if !response.starts_with("PC") || response.len() < 5 {
        return None;
    }
    response[2..].parse::<u8>().ok()
}

pub fn parse_responses(buffer: &str) -> (Vec<String>, usize) {
    extract_responses(buffer)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builds_set_frequency() {
        assert_eq!(set_frequency(14_060_000), "FA00014060000;");
        assert_eq!(set_frequency(0), "FA00000000000;");
    }

    #[test]
    fn parses_frequency_round_trip() {
        let cmd = set_frequency(14_060_000);
        // strip terminator
        let response = &cmd[..cmd.len() - 1];
        assert_eq!(parse_frequency_response(response), Some(14_060_000));
    }

    #[test]
    fn builds_and_parses_mode() {
        assert_eq!(set_mode(KenwoodMode::Cw), "MD3;");
        assert_eq!(parse_mode_response("MD3"), Some(KenwoodMode::Cw));
        assert_eq!(parse_mode_response("MD9"), Some(KenwoodMode::DataR));
        assert_eq!(parse_mode_response("MDX"), None);
    }

    #[test]
    fn rit_xit_signed_offset() {
        assert_eq!(set_rit_xit_offset(100), "RO+0100;");
        assert_eq!(set_rit_xit_offset(-50), "RO-0050;");
        assert_eq!(set_rit_xit_offset(99_999), "RO+9999;"); // clamps
        assert_eq!(parse_rit_xit_offset_response("RO+0100"), Some(100));
        assert_eq!(parse_rit_xit_offset_response("RO-0050"), Some(-50));
    }

    #[test]
    fn xit_on_off() {
        assert_eq!(set_xit(true), "XT1;");
        assert_eq!(parse_xit_response("XT1"), Some(true));
        assert_eq!(parse_xit_response("XT0"), Some(false));
        assert_eq!(parse_rit_response("RT1"), Some(true));
    }

    #[test]
    fn power_level_round_trip() {
        assert_eq!(set_power_level(5), "PC005;");
        assert_eq!(parse_power_level_response("PC005"), Some(5));
    }

    #[test]
    fn mode_string_round_trip() {
        assert_eq!(KenwoodMode::from_carrier_wave_mode("LSB"), Some(KenwoodMode::Lsb));
        assert_eq!(KenwoodMode::from_carrier_wave_mode("usb"), Some(KenwoodMode::Usb));
        assert_eq!(KenwoodMode::from_carrier_wave_mode("FT8"), Some(KenwoodMode::Data));
        assert_eq!(KenwoodMode::from_carrier_wave_mode("XYZ"), None);
        assert_eq!(KenwoodMode::Cw.carrier_wave_mode(), "CW");
        assert_eq!(KenwoodMode::CwR.carrier_wave_mode(), "CW");
    }
}
