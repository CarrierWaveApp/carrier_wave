//! CI-V protocol encoding/decoding for Icom + Xiegu radios. Port of
//! `CIVProtocol.swift`. Frames: `FE FE <to> <from> <cmd> [<sub>] [<data>…] FD`;
//! frequencies are 5-byte BCD, LSB-first, 1 Hz resolution.

pub const PREAMBLE: u8 = 0xFE;
pub const TERMINATOR: u8 = 0xFD;
pub const CONTROLLER_ADDRESS: u8 = 0xE0;

pub const CMD_READ_FREQ: u8 = 0x03;
pub const CMD_READ_MODE: u8 = 0x04;
pub const CMD_SET_FREQ: u8 = 0x05;
pub const CMD_SET_MODE: u8 = 0x06;
pub const CMD_LEVEL: u8 = 0x14;
pub const SUB_POWER_LEVEL: u8 = 0x0A;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CivFrame {
    pub to: u8,
    pub from: u8,
    pub command: u8,
    pub data: Vec<u8>,
}

impl CivFrame {
    pub fn is_ack(&self) -> bool {
        self.command == 0xFB
    }

    pub fn is_nak(&self) -> bool {
        self.command == 0xFA
    }
}

/// CI-V mode bytes mapped to Carrier Wave canonical mode strings.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CivMode {
    Lsb = 0x00,
    Usb = 0x01,
    Am = 0x02,
    Cw = 0x03,
    Rtty = 0x04,
    Fm = 0x05,
    Wfm = 0x06,
    CwR = 0x07,
    RttyR = 0x08,
}

impl CivMode {
    pub fn from_byte(byte: u8) -> Option<Self> {
        Some(match byte {
            0x00 => Self::Lsb,
            0x01 => Self::Usb,
            0x02 => Self::Am,
            0x03 => Self::Cw,
            0x04 => Self::Rtty,
            0x05 => Self::Fm,
            0x06 => Self::Wfm,
            0x07 => Self::CwR,
            0x08 => Self::RttyR,
            _ => return None,
        })
    }

    pub fn carrier_wave_mode(self) -> &'static str {
        match self {
            Self::Lsb => "LSB",
            Self::Usb => "USB",
            Self::Am => "AM",
            Self::Cw | Self::CwR => "CW",
            Self::Rtty | Self::RttyR => "RTTY",
            Self::Fm | Self::Wfm => "FM",
        }
    }

    pub fn display_name(self) -> &'static str {
        match self {
            Self::Lsb => "LSB",
            Self::Usb => "USB",
            Self::Am => "AM",
            Self::Cw => "CW",
            Self::Rtty => "RTTY",
            Self::Fm => "FM",
            Self::Wfm => "WFM",
            Self::CwR => "CW-R",
            Self::RttyR => "RTTY-R",
        }
    }

    pub fn from_carrier_wave_mode(mode: &str) -> Option<Self> {
        Some(match mode.to_uppercase().as_str() {
            "LSB" => Self::Lsb,
            "USB" | "SSB" => Self::Usb,
            "AM" => Self::Am,
            "CW" => Self::Cw,
            "RTTY" => Self::Rtty,
            "FM" => Self::Fm,
            _ => return None,
        })
    }
}

pub fn build_frame(to: u8, from: u8, command: u8, data: &[u8]) -> Vec<u8> {
    let mut frame = Vec::with_capacity(6 + data.len());
    frame.extend_from_slice(&[PREAMBLE, PREAMBLE, to, from, command]);
    frame.extend_from_slice(data);
    frame.push(TERMINATOR);
    frame
}

/// Extract complete CI-V frames from a byte buffer. Returns `(frames, consumed_bytes)`.
/// Caller retains `buffer[consumed..]` for the next call.
pub fn extract_frames(buffer: &[u8]) -> (Vec<CivFrame>, usize) {
    let mut frames = Vec::new();
    let mut consumed = 0usize;
    let mut pos = 0usize;

    while pos < buffer.len() {
        let Some(start) = find_preamble(buffer, pos) else {
            break;
        };
        // Need at least FE FE to from cmd FD = 6 bytes
        if start + 5 >= buffer.len() {
            break;
        }
        // Scan for terminator after the command byte.
        let Some(end_idx) = buffer[(start + 4)..]
            .iter()
            .position(|&b| b == TERMINATOR)
            .map(|i| i + start + 4)
        else {
            break;
        };
        let to = buffer[start + 2];
        let from = buffer[start + 3];
        let command = buffer[start + 4];
        let data = buffer[(start + 5)..end_idx].to_vec();
        frames.push(CivFrame { to, from, command, data });
        consumed = end_idx + 1;
        pos = consumed;
    }

    (frames, consumed)
}

fn find_preamble(buffer: &[u8], start: usize) -> Option<usize> {
    let mut i = start;
    while i + 1 < buffer.len() {
        if buffer[i] == PREAMBLE && buffer[i + 1] == PREAMBLE {
            // Some radios send extra preamble bytes — skip them to land on the
            // last preamble before the address bytes.
            let mut actual = i;
            while actual + 2 < buffer.len() && buffer[actual + 2] == PREAMBLE {
                actual += 1;
            }
            return Some(actual);
        }
        i += 1;
    }
    None
}

/// Parse 5 LSB-first BCD bytes into Hz. Returns `None` if any nibble is > 9.
pub fn parse_bcd_frequency(data: &[u8]) -> Option<u64> {
    if data.len() < 5 {
        return None;
    }
    let mut freq: u64 = 0;
    let mut multiplier: u64 = 1;
    for byte in &data[..5] {
        let lo = u64::from(byte & 0x0F);
        let hi = u64::from((byte >> 4) & 0x0F);
        if lo > 9 || hi > 9 {
            return None;
        }
        freq += lo * multiplier;
        multiplier *= 10;
        freq += hi * multiplier;
        multiplier *= 10;
    }
    Some(freq)
}

/// Encode Hz to 5-byte BCD, LSB-first.
pub fn encode_bcd_frequency(frequency_hz: u64) -> [u8; 5] {
    let mut hz = frequency_hz;
    let mut bytes = [0u8; 5];
    for byte in &mut bytes {
        let lo = (hz % 10) as u8;
        hz /= 10;
        let hi = (hz % 10) as u8;
        hz /= 10;
        *byte = (hi << 4) | lo;
    }
    bytes
}

pub fn hz_to_mhz(hz: u64) -> f64 {
    hz as f64 / 1_000_000.0
}

pub fn mhz_to_hz(mhz: f64) -> u64 {
    (mhz * 1_000_000.0) as u64
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bcd_round_trip() {
        // 14.074.000 Hz → 00 40 07 14 00 (LSB first)
        let encoded = encode_bcd_frequency(14_074_000);
        assert_eq!(encoded, [0x00, 0x40, 0x07, 0x14, 0x00]);
        assert_eq!(parse_bcd_frequency(&encoded), Some(14_074_000));
        // Zero
        assert_eq!(encode_bcd_frequency(0), [0; 5]);
        assert_eq!(parse_bcd_frequency(&[0; 5]), Some(0));
    }

    #[test]
    fn bcd_rejects_invalid_nibble() {
        assert!(parse_bcd_frequency(&[0xAB, 0, 0, 0, 0]).is_none());
        assert!(parse_bcd_frequency(&[0, 0, 0, 0]).is_none()); // too short
    }

    #[test]
    fn build_set_freq_frame() {
        // Set 14.074 MHz on radio at address 0x94 (IC-705)
        let data = encode_bcd_frequency(14_074_000);
        let frame = build_frame(0x94, CONTROLLER_ADDRESS, CMD_SET_FREQ, &data);
        assert_eq!(frame[0], PREAMBLE);
        assert_eq!(frame[1], PREAMBLE);
        assert_eq!(frame[2], 0x94);
        assert_eq!(frame[3], CONTROLLER_ADDRESS);
        assert_eq!(frame[4], CMD_SET_FREQ);
        assert_eq!(&frame[5..10], &[0x00, 0x40, 0x07, 0x14, 0x00]);
        assert_eq!(*frame.last().unwrap(), TERMINATOR);
    }

    #[test]
    fn extract_single_frame() {
        let mut buf: Vec<u8> = vec![
            0xFE, 0xFE, 0xE0, 0x94, 0x03, 0x00, 0x40, 0x07, 0x14, 0x00, 0xFD,
        ];
        let (frames, consumed) = extract_frames(&buf);
        assert_eq!(consumed, buf.len());
        assert_eq!(frames.len(), 1);
        assert_eq!(frames[0].to, 0xE0);
        assert_eq!(frames[0].from, 0x94);
        assert_eq!(frames[0].command, CMD_READ_FREQ);
        assert_eq!(frames[0].data.len(), 5);
        // Trailing partial frame is left unconsumed
        buf.extend_from_slice(&[0xFE, 0xFE, 0xE0]);
        let (frames, consumed) = extract_frames(&buf);
        assert_eq!(frames.len(), 1);
        assert!(consumed < buf.len());
    }

    #[test]
    fn extract_skips_extra_preamble() {
        // Some radios send FE FE FE (3 preambles)
        let buf = vec![0xFE, 0xFE, 0xFE, 0xE0, 0x94, 0xFB, 0xFD];
        let (frames, consumed) = extract_frames(&buf);
        assert_eq!(consumed, buf.len());
        assert_eq!(frames.len(), 1);
        assert!(frames[0].is_ack());
    }

    #[test]
    fn mode_round_trip() {
        for byte in [0x00u8, 0x01, 0x02, 0x03, 0x05] {
            let mode = CivMode::from_byte(byte).unwrap();
            let cw_mode = mode.carrier_wave_mode();
            assert!(CivMode::from_carrier_wave_mode(cw_mode).is_some());
        }
        assert_eq!(CivMode::CwR.carrier_wave_mode(), "CW");
        assert_eq!(CivMode::from_byte(0xFF), None);
    }

    #[test]
    fn ack_nak_detection() {
        let ack = CivFrame { to: 0xE0, from: 0x94, command: 0xFB, data: vec![] };
        let nak = CivFrame { to: 0xE0, from: 0x94, command: 0xFA, data: vec![] };
        assert!(ack.is_ack() && !ack.is_nak());
        assert!(nak.is_nak() && !nak.is_ack());
    }
}
