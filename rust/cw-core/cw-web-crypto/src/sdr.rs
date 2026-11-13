//! WASM bindings over `cw-domain::kiwisdr` for the logbook viewer's Spots
//! page. The browser owns the websocket transport and AudioWorklet playback;
//! everything protocol-shaped — ADPCM decode, SND frame parsing, stream-text
//! classification, mode/passband tables, directory parsing, and receiver
//! ranking — is the exact shared Rust, so it can never drift from the iOS
//! `WebSDR` stack.
//!
//! Surface:
//!
//! - [`KiwiAudioDecoder`] — stateful per-connection decoder. Feed every binary
//!   websocket payload to [`KiwiAudioDecoder::handle_frame`]; SND frames come
//!   back as PCM samples + s-meter, text frames are classified (an
//!   `audio_adpcm_state` reset mutates the internal decoder state;
//!   `too_busy=0` is informational and does NOT disconnect).
//! - [`kiwi_check_server_error`] / [`kiwi_parse_msg_value`] — handshake
//!   helpers (`badp`, `too_busy`, `redirect`, `sample_rate` extraction).
//! - [`kiwi_tune_command`] — `SET mod=` line via
//!   `KiwiSdrMode::from_carrier_wave_mode` (CW carrier offset included).
//! - [`parse_kiwi_directory`] / [`rank_receivers_near`] — Skywavelinux
//!   directory JS → receiver JSON, and `find_nearby` ranking.

use wasm_bindgen::prelude::*;

use cw_domain::kiwisdr::{
    check_for_server_error, classify_stream_text, directory, find_nearby, is_snd_frame,
    parse_msg_value, parse_snd_frame, tune_command, AdpcmState, KiwiSdrMode, KiwiSdrReceiver,
    ServerError, StreamTextEvent,
};

/// One classified websocket payload. `kind` is one of:
///
/// - `"audio"` — `samples` (Int16 PCM) and `sMeter` are set.
/// - `"adpcmReset"` — server reset the ADPCM state (already applied).
/// - `"redirect"` — the receiver wants us elsewhere; reconnect or bail.
/// - `"disconnected"` — server-initiated disconnect (`too_busy>0`, `MSG down`,
///   inactivity timeout); `text` carries the raw message.
/// - `"text"` — non-actionable text (handshake `MSG` lines land here; run
///   [`kiwi_check_server_error`] / [`kiwi_parse_msg_value`] over `text`).
/// - `"none"` — an unusable binary frame (short/IQ/empty SND).
#[wasm_bindgen]
pub struct KiwiFrameEvent {
    kind: &'static str,
    samples: Option<Vec<i16>>,
    s_meter: Option<u16>,
    text: Option<String>,
}

#[wasm_bindgen]
impl KiwiFrameEvent {
    #[wasm_bindgen(getter)]
    pub fn kind(&self) -> String {
        self.kind.to_string()
    }

    /// Decoded Int16 PCM samples for `"audio"` events.
    #[wasm_bindgen(getter)]
    pub fn samples(&self) -> Option<Vec<i16>> {
        self.samples.clone()
    }

    /// Raw s-meter reading for `"audio"` events (dBm = value / 10 − 127).
    #[wasm_bindgen(getter, js_name = sMeter)]
    pub fn s_meter(&self) -> Option<u16> {
        self.s_meter
    }

    /// The UTF-8 text of a non-SND payload (KiwiSDR sends MSG text inside
    /// binary websocket frames).
    #[wasm_bindgen(getter)]
    pub fn text(&self) -> Option<String> {
        self.text.clone()
    }
}

impl KiwiFrameEvent {
    fn bare(kind: &'static str, text: Option<String>) -> Self {
        Self { kind, samples: None, s_meter: None, text }
    }
}

/// Stateful KiwiSDR frame decoder for one websocket connection. Carries the
/// IMA ADPCM state across frames and applies server-sent
/// `audio_adpcm_state=index,predictor` resets.
#[wasm_bindgen]
#[derive(Default)]
pub struct KiwiAudioDecoder {
    state: AdpcmState,
}

#[wasm_bindgen]
impl KiwiAudioDecoder {
    #[wasm_bindgen(constructor)]
    pub fn new() -> KiwiAudioDecoder {
        KiwiAudioDecoder::default()
    }

    /// Classify one binary websocket payload. SND frames decode to PCM
    /// (compressed frames advance the internal ADPCM state); everything else
    /// is treated as UTF-8 text and classified per the stream-text rules.
    #[wasm_bindgen(js_name = handleFrame)]
    pub fn handle_frame(&mut self, data: &[u8]) -> KiwiFrameEvent {
        if is_snd_frame(data) {
            return match parse_snd_frame(data, &mut self.state) {
                Some(frame) => KiwiFrameEvent {
                    kind: "audio",
                    samples: Some(frame.samples),
                    s_meter: Some(frame.s_meter),
                    text: None,
                },
                None => KiwiFrameEvent::bare("none", None),
            };
        }

        let text = String::from_utf8_lossy(data).into_owned();
        match classify_stream_text(&text) {
            StreamTextEvent::AdpcmReset { step_index, predictor } => {
                self.state.reset(step_index, predictor);
                KiwiFrameEvent::bare("adpcmReset", Some(text))
            }
            StreamTextEvent::Redirect => KiwiFrameEvent::bare("redirect", Some(text)),
            StreamTextEvent::Disconnected(message) => {
                KiwiFrameEvent::bare("disconnected", Some(message))
            }
            StreamTextEvent::None => KiwiFrameEvent::bare("text", Some(text)),
        }
    }
}

/// Check a handshake-phase server message. Returns `null` when the message is
/// benign, otherwise a short human-readable error. A redirect is reported as
/// `"redirect:<target>"` so the caller can distinguish it. **`too_busy=0` is
/// informational and returns `null`.**
#[wasm_bindgen(js_name = kiwiCheckServerError)]
pub fn kiwi_check_server_error(message: &str) -> Option<String> {
    match check_for_server_error(message) {
        Ok(()) => None,
        Err(ServerError::AuthenticationFailed) => {
            Some("receiver rejected the connection (password required)".to_string())
        }
        Err(ServerError::TooBusy(slots)) => {
            Some(format!("receiver is full ({slots} channels busy)"))
        }
        Err(ServerError::ServerDown) => Some("receiver reports it is down".to_string()),
        Err(ServerError::Redirect(target)) => Some(format!("redirect:{target}")),
    }
}

/// Extract `key=` from a `MSG key=value` message (e.g. `sample_rate`).
#[wasm_bindgen(js_name = kiwiParseMsgValue)]
pub fn kiwi_parse_msg_value(message: &str, key: &str) -> Option<String> {
    parse_msg_value(message, key).map(str::to_string)
}

/// Build the `SET mod=` tune command for a Carrier Wave mode string.
/// `frequency_mhz` disambiguates SSB (LSB below 10 MHz, USB at or above); the
/// CW carrier offset is applied by the shared mode table.
#[wasm_bindgen(js_name = kiwiTuneCommand)]
pub fn kiwi_tune_command(frequency_khz: f64, mode: &str, frequency_mhz: Option<f64>) -> String {
    tune_command(frequency_khz, KiwiSdrMode::from_carrier_wave_mode(mode, frequency_mhz))
}

/// Wire shape for a receiver crossing the WASM boundary (camelCase JSON).
#[derive(serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct ReceiverDto {
    id: String,
    name: String,
    host: String,
    port: u16,
    latitude: f64,
    longitude: f64,
    bands: String,
    users: i32,
    max_users: i32,
    location: String,
    antenna: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    distance_km: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    snr_all: Option<i32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    snr_hf: Option<i32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    ant_connected: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    grid: Option<String>,
    is_available: bool,
}

impl From<&KiwiSdrReceiver> for ReceiverDto {
    fn from(rx: &KiwiSdrReceiver) -> Self {
        Self {
            id: rx.id.clone(),
            name: rx.name.clone(),
            host: rx.host.clone(),
            port: rx.port,
            latitude: rx.latitude,
            longitude: rx.longitude,
            bands: rx.bands.clone(),
            users: rx.users,
            max_users: rx.max_users,
            location: rx.location.clone(),
            antenna: rx.antenna.clone(),
            distance_km: rx.distance_km,
            snr_all: rx.snr_all,
            snr_hf: rx.snr_hf,
            ant_connected: rx.ant_connected,
            grid: rx.grid.clone(),
            is_available: rx.is_available(),
        }
    }
}

impl From<ReceiverDto> for KiwiSdrReceiver {
    fn from(dto: ReceiverDto) -> Self {
        Self {
            id: dto.id,
            name: dto.name,
            host: dto.host,
            port: dto.port,
            latitude: dto.latitude,
            longitude: dto.longitude,
            bands: dto.bands,
            users: dto.users,
            max_users: dto.max_users,
            location: dto.location,
            antenna: dto.antenna,
            distance_km: dto.distance_km,
            snr_all: dto.snr_all,
            snr_hf: dto.snr_hf,
            ant_connected: dto.ant_connected,
            grid: dto.grid,
            asl: None,
            enriched_antenna: None,
        }
    }
}

fn receivers_to_json(receivers: &[KiwiSdrReceiver]) -> String {
    let dtos: Vec<ReceiverDto> = receivers.iter().map(ReceiverDto::from).collect();
    serde_json::to_string(&dtos).unwrap_or_else(|_| "[]".to_string())
}

/// Parse the Skywavelinux directory JS mirror (`var kiwisdr_com = [ … ];`)
/// into a JSON array of receivers. Inactive/offline entries are dropped;
/// garbage input yields `[]`.
#[wasm_bindgen(js_name = parseKiwiDirectory)]
pub fn parse_kiwi_directory(js_text: &str) -> String {
    receivers_to_json(&directory::parse_directory_js(js_text))
}

/// Rank receivers near a point: filter to `max_km`, annotate `distanceKm`,
/// sort nearest-first, cap at `limit`. With `lat`/`lon` omitted the list is
/// passed through uncapped by distance (just truncated), for spots with no
/// usable coordinates. `receivers_json` is the output of
/// [`parse_kiwi_directory`].
#[wasm_bindgen(js_name = rankReceiversNear)]
pub fn rank_receivers_near(
    receivers_json: &str,
    lat: Option<f64>,
    lon: Option<f64>,
    max_km: f64,
    limit: u32,
) -> Result<String, JsError> {
    let dtos: Vec<ReceiverDto> = serde_json::from_str(receivers_json)
        .map_err(|e| JsError::new(&format!("bad receivers JSON: {e}")))?;
    let receivers: Vec<KiwiSdrReceiver> = dtos.into_iter().map(Into::into).collect();
    let reference = match (lat, lon) {
        (Some(lat), Some(lon)) => Some((lat, lon)),
        _ => None,
    };
    let ranked = find_nearby(&receivers, reference, max_km, limit as usize);
    Ok(receivers_to_json(&ranked))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn snd_frame(flags: u8, smeter: u16, payload: &[u8]) -> Vec<u8> {
        let mut frame = b"SND".to_vec();
        frame.push(flags);
        frame.extend_from_slice(&[0, 0, 0, 0]);
        frame.extend_from_slice(&smeter.to_be_bytes());
        frame.extend_from_slice(payload);
        frame
    }

    // The decoder must carry ADPCM state across frames and honor a server
    // reset in between — the exact fixture from the cw-domain parity test.
    #[test]
    fn decoder_audio_and_adpcm_reset_flow() {
        let mut decoder = KiwiAudioDecoder::new();

        let event = decoder.handle_frame(&snd_frame(0x10, 0x1234, &[0x17, 0x9C]));
        assert_eq!(event.kind(), "audio");
        assert_eq!(event.samples().unwrap(), vec![11, 17, 2, -4]);
        assert_eq!(event.s_meter(), Some(0x1234));

        let event = decoder.handle_frame(b"MSG audio_adpcm_state=0,0");
        assert_eq!(event.kind(), "adpcmReset");
        assert_eq!(decoder.state, AdpcmState::default());

        // After the reset, the same bytes decode identically to a fresh state.
        let event = decoder.handle_frame(&snd_frame(0x10, 0, &[0x17, 0x9C]));
        assert_eq!(event.samples().unwrap(), vec![11, 17, 2, -4]);
    }

    #[test]
    fn decoder_classifies_text_frames() {
        let mut decoder = KiwiAudioDecoder::new();

        // too_busy=0 is informational — must NOT disconnect.
        let event = decoder.handle_frame(b"MSG too_busy=0");
        assert_eq!(event.kind(), "text");

        let event = decoder.handle_frame(b"MSG too_busy=3");
        assert_eq!(event.kind(), "disconnected");
        assert_eq!(event.text().unwrap(), "MSG too_busy=3");

        let event = decoder.handle_frame(b"MSG redirect=http://other:8074");
        assert_eq!(event.kind(), "redirect");

        let event = decoder.handle_frame(b"MSG sample_rate=12001.15");
        assert_eq!(event.kind(), "text");
        assert_eq!(
            kiwi_parse_msg_value(&event.text().unwrap(), "sample_rate").as_deref(),
            Some("12001.15")
        );
    }

    #[test]
    fn decoder_rejects_unusable_snd_frames() {
        let mut decoder = KiwiAudioDecoder::new();
        assert_eq!(decoder.handle_frame(&snd_frame(0x08, 0, &[1, 2])).kind(), "none"); // IQ
        assert_eq!(decoder.handle_frame(&snd_frame(0x00, 0, &[])).kind(), "none"); // empty
    }

    #[test]
    fn server_error_messages() {
        assert_eq!(kiwi_check_server_error("MSG audio_init=0"), None);
        assert_eq!(kiwi_check_server_error("MSG too_busy=0"), None);
        assert!(kiwi_check_server_error("MSG badp=1").unwrap().contains("password"));
        assert!(kiwi_check_server_error("MSG too_busy=4").unwrap().contains("4"));
        assert!(kiwi_check_server_error("MSG down").unwrap().contains("down"));
        assert_eq!(
            kiwi_check_server_error("MSG redirect=other:8074").as_deref(),
            Some("redirect:other:8074")
        );
    }

    #[test]
    fn tune_command_maps_modes() {
        assert_eq!(
            kiwi_tune_command(14_060.0, "CW", Some(14.06)),
            "SET mod=cw low_cut=300 high_cut=800 freq=14059.450"
        );
        // SSB below 10 MHz resolves to LSB via the shared mode table.
        assert_eq!(
            kiwi_tune_command(7_200.0, "SSB", Some(7.2)),
            "SET mod=lsb low_cut=-2700 high_cut=-300 freq=7200.000"
        );
    }

    const DIRECTORY_JS: &str = r#"var kiwisdr_com = [
        {"url": "http://near.example.com:8073", "name": "Near", "status": "active",
         "offline": "no", "gps": "(44.94, -123.03)", "users": "1", "users_max": "4"},
        {"url": "http://far.example.com:8073", "name": "Far", "status": "active",
         "offline": "no", "gps": "(39.74, -104.99)", "users": "4", "users_max": "4"},
        {"url": "http://dead.example.com:8073", "status": "active", "offline": "yes"}
    ];"#;

    #[test]
    fn directory_parse_and_rank_round_trip() {
        let json = parse_kiwi_directory(DIRECTORY_JS);
        let parsed: Vec<ReceiverDto> = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.len(), 2);
        assert!(parsed[0].is_available);
        assert!(!parsed[1].is_available);

        // Rank near Portland OR: only "Near" is within 500 km, annotated.
        let ranked = rank_receivers_near(&json, Some(45.52), Some(-122.68), 500.0, 10).unwrap();
        let ranked: Vec<ReceiverDto> = serde_json::from_str(&ranked).unwrap();
        assert_eq!(ranked.len(), 1);
        assert_eq!(ranked[0].name, "Near");
        assert!(ranked[0].distance_km.unwrap() < 150.0);

        // No reference point: passthrough capped at limit.
        let unranked = rank_receivers_near(&json, None, None, 500.0, 1).unwrap();
        let unranked: Vec<ReceiverDto> = serde_json::from_str(&unranked).unwrap();
        assert_eq!(unranked.len(), 1);
    }
}
