//! KiwiSDR wire-protocol parsing: `MSG key=value` text messages, `SND` binary
//! audio frames, server-error classification, and redirect targets. Port of
//! the parsing halves of `KiwiSDRClient.swift` and
//! `WebSDRSession+Internals.swift` (`parseRedirectTarget`).
//!
//! Everything here is pure — the websocket transport lives in `cw-net`.

use super::adpcm::{self, AdpcmState};

/// Extract a value for `key` from a `MSG key=value key2=value2` message.
/// Mirrors `KiwiSDRClient.parseMSGValue` (split on `key=`, take up to the next
/// space).
pub fn parse_msg_value<'a>(message: &'a str, key: &str) -> Option<&'a str> {
    let marker = format!("{key}=");
    let start = message.find(&marker)? + marker.len();
    let rest = &message[start..];
    Some(rest.split(' ').next().unwrap_or(rest))
}

/// Server-reported conditions that abort a connection attempt or an active
/// stream. Mirrors the throwing cases of `KiwiSDRClient.checkForServerError`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ServerError {
    /// `badp=<nonzero>` — bad password.
    AuthenticationFailed,
    /// `too_busy=<slots>` with slots > 0. **`too_busy=0` is informational
    /// ("not busy") and must NOT be treated as an error.**
    TooBusy(i32),
    /// `MSG down` — server marked down.
    ServerDown,
    /// `redirect=<target>` — connect to another host instead.
    Redirect(String),
}

/// Check a handshake-phase server message for error conditions.
pub fn check_for_server_error(message: &str) -> Result<(), ServerError> {
    if let Some(code) = parse_msg_value(message, "badp").and_then(|val| val.parse::<i32>().ok()) {
        if code != 0 {
            return Err(ServerError::AuthenticationFailed);
        }
    }

    if let Some(slots) =
        parse_msg_value(message, "too_busy").and_then(|val| val.parse::<i32>().ok())
    {
        if slots > 0 {
            return Err(ServerError::TooBusy(slots));
        }
    }

    if message.contains("MSG down") {
        return Err(ServerError::ServerDown);
    }

    if let Some(redirect) = parse_msg_value(message, "redirect") {
        return Err(ServerError::Redirect(redirect.to_string()));
    }

    Ok(())
}

/// Events surfaced from a mid-stream text message. Mirrors
/// `KiwiSDRClient.processTextMessage`.
#[derive(Debug, Clone, PartialEq)]
pub enum StreamTextEvent {
    /// `audio_adpcm_state=index,predictor` — reset the decoder state.
    AdpcmReset { step_index: i32, predictor: i32 },
    /// `redirect=` mid-stream — finish so the session layer can reconnect.
    Redirect,
    /// Server-initiated disconnect: `too_busy>0`, `MSG down`, or
    /// `MSG inactivity_timeout`. Carries the raw message for the error text.
    Disconnected(String),
    /// Nothing actionable.
    None,
}

/// Classify a mid-stream text message. `too_busy=0` is informational and does
/// not disconnect.
pub fn classify_stream_text(text: &str) -> StreamTextEvent {
    if let Some(state) = parse_msg_value(text, "audio_adpcm_state") {
        let parts: Vec<&str> = state.split(',').collect();
        if parts.len() == 2 {
            if let (Ok(index), Ok(prev)) = (parts[0].parse::<i32>(), parts[1].parse::<i32>()) {
                return StreamTextEvent::AdpcmReset { step_index: index, predictor: prev };
            }
        }
    }

    if parse_msg_value(text, "redirect").is_some() {
        return StreamTextEvent::Redirect;
    }

    let is_too_busy = parse_msg_value(text, "too_busy")
        .and_then(|val| val.parse::<i32>().ok())
        .is_some_and(|slots| slots > 0);
    if is_too_busy || text.contains("MSG down") || text.contains("MSG inactivity_timeout") {
        return StreamTextEvent::Disconnected(text.to_string());
    }

    StreamTextEvent::None
}

/// A decoded `SND` audio frame.
#[derive(Debug, Clone, PartialEq)]
pub struct SndFrame {
    pub samples: Vec<i16>,
    /// Big-endian u16 S-meter reading at frame offset 8.
    pub s_meter: u16,
}

/// Whether a binary websocket payload is an `SND` audio frame. KiwiSDR sends
/// MSG text inside *binary* frames too, so non-`SND` binary payloads must be
/// decoded as UTF-8 text by the transport.
pub fn is_snd_frame(data: &[u8]) -> bool {
    data.len() >= 3 && data[0] == 0x53 && data[1] == 0x4E && data[2] == 0x44
}

/// Parse a `SND` frame: header "SND" (3) + flags (1) + sequence (4) +
/// s-meter (2, big-endian) + audio payload. Returns `None` for short frames,
/// IQ frames (mono only, like the Swift port), and empty payloads.
pub fn parse_snd_frame(data: &[u8], adpcm_state: &mut AdpcmState) -> Option<SndFrame> {
    if data.len() < 10 || !is_snd_frame(data) {
        return None;
    }

    let flags = data[3];
    let is_compressed = flags & 0x10 != 0;
    let is_little_endian = flags & 0x80 != 0;
    let is_iq = flags & 0x08 != 0;

    if is_iq {
        return None;
    }

    let s_meter = u16::from(data[8]) << 8 | u16::from(data[9]);

    let audio = &data[10..];
    if audio.is_empty() {
        return None;
    }

    let samples = if is_compressed {
        adpcm::decode(audio, adpcm_state)
    } else {
        parse_pcm(audio, is_little_endian)
    };

    if samples.is_empty() {
        return None;
    }

    Some(SndFrame { samples, s_meter })
}

/// Parse raw PCM Int16 samples honoring the frame's endianness flag.
fn parse_pcm(data: &[u8], little_endian: bool) -> Vec<i16> {
    data.chunks_exact(2)
        .map(|pair| {
            if little_endian {
                i16::from_le_bytes([pair[0], pair[1]])
            } else {
                i16::from_be_bytes([pair[0], pair[1]])
            }
        })
        .collect()
}

/// Parse a KiwiSDR redirect target into `(host, port)`. Handles
/// `http://host:port`, `host:port`, and bare `host` forms; the default KiwiSDR
/// port is 8073. Port of `WebSDRSession.parseRedirectTarget`.
pub fn parse_redirect_target(redirect: &str) -> Option<(String, u16)> {
    let mut cleaned = redirect;
    if let Some(pos) = cleaned.find("://") {
        cleaned = &cleaned[pos + 3..];
    }
    if let Some(slash) = cleaned.find('/') {
        cleaned = &cleaned[..slash];
    }
    let mut parts = cleaned.split(':');
    let host = parts.next().unwrap_or("");
    if host.is_empty() {
        return None;
    }
    let port = parts.next().and_then(|val| val.parse::<u16>().ok()).unwrap_or(8_073);
    Some((host.to_string(), port))
}

/// Build the `SET mod=` tune command for a frequency (kHz) and mode. The
/// carrier is offset below the operating frequency for CW so the signal lands
/// mid-passband. Port of `KiwiSDRClient.tune`.
pub fn tune_command(frequency_khz: f64, mode: super::mode::KiwiSdrMode) -> String {
    let carrier_khz = frequency_khz - mode.carrier_offset_khz();
    format!(
        "SET mod={} low_cut={} high_cut={} freq={:.3}",
        mode.kiwi_name(),
        mode.low_cut(),
        mode.high_cut(),
        carrier_khz
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::kiwisdr::mode::KiwiSdrMode;

    #[test]
    fn msg_value_extraction() {
        assert_eq!(parse_msg_value("MSG sample_rate=12001.15 foo=bar", "sample_rate"), Some("12001.15"));
        assert_eq!(parse_msg_value("MSG foo=bar", "sample_rate"), None);
        assert_eq!(parse_msg_value("MSG audio_adpcm_state=3,-42", "audio_adpcm_state"), Some("3,-42"));
    }

    #[test]
    fn server_error_classification() {
        assert_eq!(check_for_server_error("MSG badp=1"), Err(ServerError::AuthenticationFailed));
        assert_eq!(check_for_server_error("MSG badp=0"), Ok(()));
        assert_eq!(check_for_server_error("MSG too_busy=4"), Err(ServerError::TooBusy(4)));
        // too_busy=0 is informational, NOT an error (memory: kiwisdr-too-busy).
        assert_eq!(check_for_server_error("MSG too_busy=0"), Ok(()));
        assert_eq!(check_for_server_error("MSG down"), Err(ServerError::ServerDown));
        assert_eq!(
            check_for_server_error("MSG redirect=http://other:8074"),
            Err(ServerError::Redirect("http://other:8074".into()))
        );
    }

    #[test]
    fn stream_text_classification() {
        assert_eq!(
            classify_stream_text("MSG audio_adpcm_state=5,-100"),
            StreamTextEvent::AdpcmReset { step_index: 5, predictor: -100 }
        );
        assert_eq!(classify_stream_text("MSG redirect=x"), StreamTextEvent::Redirect);
        assert_eq!(classify_stream_text("MSG too_busy=0"), StreamTextEvent::None);
        assert!(matches!(classify_stream_text("MSG too_busy=2"), StreamTextEvent::Disconnected(_)));
        assert!(matches!(classify_stream_text("MSG inactivity_timeout"), StreamTextEvent::Disconnected(_)));
        assert_eq!(classify_stream_text("MSG stats=ok"), StreamTextEvent::None);
    }

    fn snd_frame(flags: u8, smeter: u16, payload: &[u8]) -> Vec<u8> {
        let mut frame = b"SND".to_vec();
        frame.push(flags);
        frame.extend_from_slice(&[0, 0, 0, 0]); // sequence
        frame.extend_from_slice(&smeter.to_be_bytes());
        frame.extend_from_slice(payload);
        frame
    }

    #[test]
    fn snd_header_detection() {
        assert!(is_snd_frame(b"SNDxxxx"));
        assert!(!is_snd_frame(b"MSG hello"));
        assert!(!is_snd_frame(b"SN"));
    }

    #[test]
    fn parses_uncompressed_big_endian_pcm() {
        let mut state = AdpcmState::default();
        let frame = snd_frame(0x00, 0x1234, &[0x01, 0x00, 0xFF, 0x00]);
        let parsed = parse_snd_frame(&frame, &mut state).unwrap();
        assert_eq!(parsed.s_meter, 0x1234);
        assert_eq!(parsed.samples, vec![0x0100, -256]);
    }

    #[test]
    fn parses_uncompressed_little_endian_pcm() {
        let mut state = AdpcmState::default();
        let frame = snd_frame(0x80, 0, &[0x01, 0x00]);
        let parsed = parse_snd_frame(&frame, &mut state).unwrap();
        assert_eq!(parsed.samples, vec![1]);
    }

    #[test]
    fn decodes_compressed_frames_with_carried_state() {
        let mut state = AdpcmState::default();
        let frame = snd_frame(0x10, 0, &[0x17, 0x9C]);
        let parsed = parse_snd_frame(&frame, &mut state).unwrap();
        // Same fixture as the adpcm parity test.
        assert_eq!(parsed.samples, vec![11, 17, 2, -4]);
        assert_eq!(state.step_index, 8);
    }

    #[test]
    fn rejects_iq_short_and_empty_frames() {
        let mut state = AdpcmState::default();
        assert!(parse_snd_frame(&snd_frame(0x08, 0, &[1, 2]), &mut state).is_none(), "IQ");
        assert!(parse_snd_frame(b"SND\x00\x00", &mut state).is_none(), "short");
        assert!(parse_snd_frame(&snd_frame(0x00, 0, &[]), &mut state).is_none(), "empty");
    }

    #[test]
    fn redirect_target_forms() {
        assert_eq!(parse_redirect_target("http://other.host:8074/foo"), Some(("other.host".into(), 8_074)));
        assert_eq!(parse_redirect_target("other.host:8074"), Some(("other.host".into(), 8_074)));
        assert_eq!(parse_redirect_target("other.host"), Some(("other.host".into(), 8_073)));
        assert_eq!(parse_redirect_target("http://other.host:bogus"), Some(("other.host".into(), 8_073)));
        assert_eq!(parse_redirect_target("://"), None);
    }

    #[test]
    fn tune_command_applies_cw_carrier_offset() {
        assert_eq!(
            tune_command(14_060.0, KiwiSdrMode::Cw),
            "SET mod=cw low_cut=300 high_cut=800 freq=14059.450"
        );
        assert_eq!(
            tune_command(14_200.0, KiwiSdrMode::Usb),
            "SET mod=usb low_cut=300 high_cut=2700 freq=14200.000"
        );
    }
}
