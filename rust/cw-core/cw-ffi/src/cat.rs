//! UniFFI surface for the CAT radio-control protocols (`cw_domain::civ`,
//! `cw_domain::kenwood`, `cw_domain::yaesu`).
//!
//! The host owns the serial/BLE transport; this exposes the wire codecs so
//! every platform builds and parses CI-V / Kenwood / Yaesu frames identically.
//! Byte buffers cross as `Vec<u8>` (Foundation.Data in Swift); ASCII commands
//! cross as `String`. The mode enums keep their wire encoding on the Swift side
//! (CI-V byte, Kenwood digit, Yaesu protocol char) and delegate the canonical
//! Carrier Wave mode-string mappings here.

use cw_domain::civ;
use cw_domain::civ::{CivFrame, CivMode};
use cw_domain::kenwood;
use cw_domain::kenwood::KenwoodMode;
use cw_domain::yaesu;
use cw_domain::yaesu::{YaesuInformation, YaesuMode};

// ====================== CI-V (Icom / Xiegu) ======================

/// A parsed CI-V frame: `FE FE <to> <from> <cmd> [<data>…] FD`.
#[derive(uniffi::Record)]
pub struct FfiCivFrame {
    pub to: u8,
    pub from: u8,
    pub command: u8,
    pub data: Vec<u8>,
}

impl From<CivFrame> for FfiCivFrame {
    fn from(frame: CivFrame) -> Self {
        FfiCivFrame { to: frame.to, from: frame.from, command: frame.command, data: frame.data }
    }
}

/// Result of [`civ_extract_frames`]: the complete frames plus the number of
/// bytes consumed (the caller retains `buffer[consumed..]`).
#[derive(uniffi::Record)]
pub struct FfiCivExtractResult {
    pub frames: Vec<FfiCivFrame>,
    pub consumed: u64,
}

/// Build a CI-V command frame.
#[uniffi::export]
pub fn civ_build_frame(to: u8, from: u8, command: u8, data: Vec<u8>) -> Vec<u8> {
    civ::build_frame(to, from, command, &data)
}

/// Extract complete CI-V frames from a byte buffer (streaming reassembly).
#[uniffi::export]
pub fn civ_extract_frames(buffer: Vec<u8>) -> FfiCivExtractResult {
    let (frames, consumed) = civ::extract_frames(&buffer);
    FfiCivExtractResult {
        frames: frames.into_iter().map(FfiCivFrame::from).collect(),
        consumed: consumed as u64,
    }
}

/// Parse 5 LSB-first BCD bytes into Hz. `None` if too short or any nibble > 9.
#[uniffi::export]
pub fn civ_parse_bcd_frequency(data: Vec<u8>) -> Option<u64> {
    civ::parse_bcd_frequency(&data)
}

/// Encode Hz to 5-byte BCD, LSB-first.
#[uniffi::export]
pub fn civ_encode_bcd_frequency(frequency_hz: u64) -> Vec<u8> {
    civ::encode_bcd_frequency(frequency_hz).to_vec()
}

/// Convert Hz to MHz.
#[uniffi::export]
pub fn civ_hz_to_mhz(hz: u64) -> f64 {
    civ::hz_to_mhz(hz)
}

/// Convert MHz to Hz.
#[uniffi::export]
pub fn civ_mhz_to_hz(mhz: f64) -> u64 {
    civ::mhz_to_hz(mhz)
}

/// Whether a CI-V command byte is an ACK (0xFB).
#[uniffi::export]
pub fn civ_frame_is_ack(command: u8) -> bool {
    CivFrame { to: 0, from: 0, command, data: Vec::new() }.is_ack()
}

/// Whether a CI-V command byte is a NAK (0xFA).
#[uniffi::export]
pub fn civ_frame_is_nak(command: u8) -> bool {
    CivFrame { to: 0, from: 0, command, data: Vec::new() }.is_nak()
}

/// Carrier Wave canonical mode string for a CI-V mode byte, or `None` if the
/// byte is not a known mode.
#[uniffi::export]
pub fn civ_mode_carrier_wave_mode(byte: u8) -> Option<String> {
    CivMode::from_byte(byte).map(|mode| mode.carrier_wave_mode().to_string())
}

/// Human-readable display name for a CI-V mode byte (`CW-R`, `WFM`, …).
#[uniffi::export]
pub fn civ_mode_display_name(byte: u8) -> Option<String> {
    CivMode::from_byte(byte).map(|mode| mode.display_name().to_string())
}

/// CI-V mode byte for a Carrier Wave mode string, or `None` if unmapped.
#[uniffi::export]
pub fn civ_mode_byte_from_carrier_wave_mode(mode: String) -> Option<u8> {
    CivMode::from_carrier_wave_mode(&mode).map(|mode| mode as u8)
}

// ====================== Kenwood / Elecraft ======================

/// Result of [`kenwood_extract_responses`] / [`yaesu_extract_responses`]: the
/// complete `;`-terminated responses (terminator stripped) plus bytes consumed.
#[derive(uniffi::Record)]
pub struct FfiTextExtractResult {
    pub responses: Vec<String>,
    pub consumed: u64,
}

// ---------- builders ----------

#[uniffi::export]
pub fn kenwood_set_frequency(hz: u64) -> String {
    kenwood::set_frequency(hz)
}

#[uniffi::export]
pub fn kenwood_read_frequency() -> String {
    kenwood::read_frequency().to_string()
}

#[uniffi::export]
pub fn kenwood_set_mode(mode_raw: i32) -> String {
    let mode = KenwoodMode::from_raw(mode_raw).expect("valid Kenwood mode digit");
    kenwood::set_mode(mode)
}

#[uniffi::export]
pub fn kenwood_read_mode() -> String {
    kenwood::read_mode().to_string()
}

#[uniffi::export]
pub fn kenwood_set_xit(on: bool) -> String {
    kenwood::set_xit(on)
}

#[uniffi::export]
pub fn kenwood_read_xit() -> String {
    kenwood::read_xit().to_string()
}

#[uniffi::export]
pub fn kenwood_set_rit_xit_offset(hz: i32) -> String {
    kenwood::set_rit_xit_offset(hz)
}

#[uniffi::export]
pub fn kenwood_read_rit() -> String {
    kenwood::read_rit().to_string()
}

#[uniffi::export]
pub fn kenwood_read_rit_xit_offset() -> String {
    kenwood::read_rit_xit_offset().to_string()
}

#[uniffi::export]
pub fn kenwood_clear_rit_xit() -> String {
    kenwood::clear_rit_xit().to_string()
}

#[uniffi::export]
pub fn kenwood_set_power_level(watts: u8) -> String {
    kenwood::set_power_level(watts)
}

#[uniffi::export]
pub fn kenwood_read_power_level() -> String {
    kenwood::read_power_level().to_string()
}

// ---------- parsers ----------

#[uniffi::export]
pub fn kenwood_parse_frequency_response(response: String) -> Option<u64> {
    kenwood::parse_frequency_response(&response)
}

/// Parsed Kenwood mode digit, or `None`. Swift rebuilds `KenwoodMode(rawValue:)`.
#[uniffi::export]
pub fn kenwood_parse_mode_response(response: String) -> Option<i32> {
    kenwood::parse_mode_response(&response).map(|mode| mode.raw_value())
}

#[uniffi::export]
pub fn kenwood_parse_xit_response(response: String) -> Option<bool> {
    kenwood::parse_xit_response(&response)
}

#[uniffi::export]
pub fn kenwood_parse_rit_response(response: String) -> Option<bool> {
    kenwood::parse_rit_response(&response)
}

#[uniffi::export]
pub fn kenwood_parse_rit_xit_offset_response(response: String) -> Option<i32> {
    kenwood::parse_rit_xit_offset_response(&response)
}

#[uniffi::export]
pub fn kenwood_parse_power_level_response(response: String) -> Option<u8> {
    kenwood::parse_power_level_response(&response)
}

#[uniffi::export]
pub fn kenwood_extract_responses(buffer: String) -> FfiTextExtractResult {
    let (responses, consumed) = kenwood::parse_responses(&buffer);
    FfiTextExtractResult { responses, consumed: consumed as u64 }
}

// ---------- mode mappings ----------

/// Carrier Wave canonical mode string for a Kenwood mode digit.
#[uniffi::export]
pub fn kenwood_mode_carrier_wave_mode(mode_raw: i32) -> Option<String> {
    KenwoodMode::from_raw(mode_raw).map(|mode| mode.carrier_wave_mode().to_string())
}

/// Kenwood mode digit for a Carrier Wave mode string, or `None` if unmapped.
#[uniffi::export]
pub fn kenwood_mode_raw_from_carrier_wave_mode(mode: String) -> Option<i32> {
    KenwoodMode::from_carrier_wave_mode(&mode).map(|mode| mode.raw_value())
}

// ====================== Yaesu ======================

/// Parsed Yaesu IF (information) response. `mode` is the protocol char string
/// (Swift rebuilds `YaesuMode(protocolChar:)`), or `None` if unrecognized.
#[derive(uniffi::Record)]
pub struct FfiYaesuInformation {
    pub frequency_hz: u64,
    pub clarifier_offset: i32,
    pub rx_clarifier: bool,
    pub tx_clarifier: bool,
    pub mode: Option<String>,
}

impl From<YaesuInformation> for FfiYaesuInformation {
    fn from(info: YaesuInformation) -> Self {
        FfiYaesuInformation {
            frequency_hz: info.frequency_hz,
            clarifier_offset: info.clarifier_offset,
            rx_clarifier: info.rx_clarifier,
            tx_clarifier: info.tx_clarifier,
            mode: info.mode.map(|mode| mode.protocol_char().to_string()),
        }
    }
}

// ---------- builders ----------

#[uniffi::export]
pub fn yaesu_set_frequency(hz: u64) -> String {
    yaesu::set_frequency(hz)
}

#[uniffi::export]
pub fn yaesu_read_frequency() -> String {
    yaesu::read_frequency().to_string()
}

/// Build a set-mode command. `protocol_char` is the mode's Yaesu wire char.
#[uniffi::export]
pub fn yaesu_set_mode(protocol_char: String, band: i32) -> String {
    let mode = protocol_char
        .chars()
        .next()
        .and_then(YaesuMode::from_protocol_char)
        .expect("valid Yaesu mode protocol char");
    yaesu::set_mode(mode, band)
}

#[uniffi::export]
pub fn yaesu_read_mode(band: i32) -> String {
    yaesu::read_mode(band)
}

#[uniffi::export]
pub fn yaesu_read_information() -> String {
    yaesu::read_information().to_string()
}

#[uniffi::export]
pub fn yaesu_set_ptt(on: bool) -> String {
    yaesu::set_ptt(on)
}

#[uniffi::export]
pub fn yaesu_read_ptt() -> String {
    yaesu::read_ptt().to_string()
}

#[uniffi::export]
pub fn yaesu_set_rit(on: bool) -> String {
    yaesu::set_rit(on)
}

#[uniffi::export]
pub fn yaesu_read_rit() -> String {
    yaesu::read_rit().to_string()
}

#[uniffi::export]
pub fn yaesu_set_xit(on: bool) -> String {
    yaesu::set_xit(on)
}

#[uniffi::export]
pub fn yaesu_read_xit() -> String {
    yaesu::read_xit().to_string()
}

#[uniffi::export]
pub fn yaesu_clear_clarifier() -> String {
    yaesu::clear_clarifier().to_string()
}

#[uniffi::export]
pub fn yaesu_clarifier_up(hz: i32) -> String {
    yaesu::clarifier_up(hz)
}

#[uniffi::export]
pub fn yaesu_clarifier_down(hz: i32) -> String {
    yaesu::clarifier_down(hz)
}

#[uniffi::export]
pub fn yaesu_send_cw(text: String) -> String {
    yaesu::send_cw(&text)
}

// ---------- parsers ----------

#[uniffi::export]
pub fn yaesu_parse_frequency_response(response: String) -> Option<u64> {
    yaesu::parse_frequency_response(&response)
}

/// Parsed Yaesu mode as its protocol char string, or `None`.
#[uniffi::export]
pub fn yaesu_parse_mode_response(response: String) -> Option<String> {
    yaesu::parse_mode_response(&response).map(|mode| mode.protocol_char().to_string())
}

#[uniffi::export]
pub fn yaesu_parse_tx_response(response: String) -> Option<bool> {
    yaesu::parse_tx_response(&response)
}

#[uniffi::export]
pub fn yaesu_parse_rit_response(response: String) -> Option<bool> {
    yaesu::parse_rit_response(&response)
}

#[uniffi::export]
pub fn yaesu_parse_xit_response(response: String) -> Option<bool> {
    yaesu::parse_xit_response(&response)
}

#[uniffi::export]
pub fn yaesu_parse_information_response(response: String) -> Option<FfiYaesuInformation> {
    yaesu::parse_information_response(&response).map(FfiYaesuInformation::from)
}

#[uniffi::export]
pub fn yaesu_extract_responses(buffer: String) -> FfiTextExtractResult {
    let (responses, consumed) = yaesu::parse_responses(&buffer);
    FfiTextExtractResult { responses, consumed: consumed as u64 }
}

// ---------- mode mappings ----------

/// Carrier Wave canonical mode string for a Yaesu mode protocol char.
#[uniffi::export]
pub fn yaesu_mode_carrier_wave_mode(protocol_char: String) -> Option<String> {
    protocol_char
        .chars()
        .next()
        .and_then(YaesuMode::from_protocol_char)
        .map(|mode| mode.carrier_wave_mode().to_string())
}

/// Yaesu mode protocol char for a Carrier Wave mode string, or `None`.
#[uniffi::export]
pub fn yaesu_mode_char_from_carrier_wave_mode(mode: String) -> Option<String> {
    YaesuMode::from_carrier_wave_mode(&mode).map(|mode| mode.protocol_char().to_string())
}
