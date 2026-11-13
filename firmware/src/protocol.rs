use prost::Message;

use crate::generated::cwbp::{
    self, bridge_message::Msg, BridgeMessage, CatData, HandshakeRsp, RadioInfo, Status,
};

pub use crate::generated::cwbp::{
    CwAckResult, Ft8State, RadioProtocol, SetResultCode, SetVerifyField, StatusCode,
};

/// Firmware version
pub const FW_VERSION: &str = "1.0.0";
pub const FW_VERSION_SHORT: &str = "v1.0";
pub const PROTOCOL_VERSION: u32 = 2;

/// Capability flags
pub const CAP_USB_HOST: u32 = 1 << 0;
pub const CAP_AUTO_DETECT: u32 = 1 << 1;
pub const CAP_SET_VERIFY: u32 = 1 << 2;
pub const CAP_CW_KEYER: u32 = 1 << 3;
pub const CAP_FT8_CODEC: u32 = 1 << 4;

/// Max payload per BLE notification (conservative, MTU-dependent)
pub const MAX_BLE_PAYLOAD: usize = 240;

/// Decode a protobuf BridgeMessage from raw bytes.
pub fn decode(data: &[u8]) -> Option<BridgeMessage> {
    BridgeMessage::decode(data).ok()
}

/// Encode a HandshakeRsp.
pub fn encode_handshake_rsp() -> Vec<u8> {
    let msg = BridgeMessage {
        msg: Some(Msg::HandshakeRsp(HandshakeRsp {
            protocol_version: PROTOCOL_VERSION,
            firmware_version: FW_VERSION.into(),
            capabilities: CAP_USB_HOST
                | CAP_AUTO_DETECT
                | CAP_SET_VERIFY
                | CAP_CW_KEYER
                | CAP_FT8_CODEC,
        })),
    };
    msg.encode_to_vec()
}

/// Wrap raw CAT bytes in a CatData message.
pub fn encode_cat_data(cat_bytes: &[u8]) -> Vec<u8> {
    let msg = BridgeMessage {
        msg: Some(Msg::CatData(CatData {
            payload: cat_bytes.to_vec(),
        })),
    };
    msg.encode_to_vec()
}

/// Encode a Status message.
pub fn encode_status(code: StatusCode, detail: Option<&str>) -> Vec<u8> {
    let msg = BridgeMessage {
        msg: Some(Msg::Status(Status {
            code: code as i32,
            detail: detail.unwrap_or_default().into(),
        })),
    };
    msg.encode_to_vec()
}

/// Encode a RadioInfo message.
pub fn encode_radio_info(proto: RadioProtocol, baud_rate: u32, id_string: &str) -> Vec<u8> {
    let msg = BridgeMessage {
        msg: Some(Msg::RadioInfo(RadioInfo {
            protocol: proto as i32,
            baud_rate,
            id_string: id_string.into(),
        })),
    };
    msg.encode_to_vec()
}

/// Encode a SetResult message.
pub fn encode_set_result(result: SetResultCode) -> Vec<u8> {
    let msg = BridgeMessage {
        msg: Some(Msg::SetResult(cwbp::SetResult {
            result: result as i32,
        })),
    };
    msg.encode_to_vec()
}

/// Encode a CwSpeed message (firmware → app, e.g. encoder WPM change).
pub fn encode_cw_speed(wpm: u32) -> Vec<u8> {
    let msg = BridgeMessage {
        msg: Some(Msg::CwSpeed(cwbp::CwSpeed { wpm })),
    };
    msg.encode_to_vec()
}

/// Encode a CwAck message.
pub fn encode_cw_ack(result: CwAckResult, buf_depth: u32) -> Vec<u8> {
    let msg = BridgeMessage {
        msg: Some(Msg::CwAck(cwbp::CwAck {
            result: result as i32,
            buf_depth,
        })),
    };
    msg.encode_to_vec()
}

/// Encode a CwProgress message.
pub fn encode_cw_progress(buf_depth: u32, flags: u32) -> Vec<u8> {
    let msg = BridgeMessage {
        msg: Some(Msg::CwProgress(cwbp::CwProgress { buf_depth, flags })),
    };
    msg.encode_to_vec()
}

/// Encode a CwStatusRsp message.
pub fn encode_cw_status_rsp(wpm: u32, buf_depth: u32, flags: u32, slot_count: u32) -> Vec<u8> {
    let msg = BridgeMessage {
        msg: Some(Msg::CwStatusRsp(cwbp::CwStatusRsp {
            wpm,
            buf_depth,
            flags,
            slot_count,
        })),
    };
    msg.encode_to_vec()
}

/// Encode an Ft8EncodeRsp (success).
pub fn encode_ft8_encode_rsp_ok(tones: &[u8]) -> Vec<u8> {
    let msg = BridgeMessage {
        msg: Some(Msg::Ft8EncodeRsp(cwbp::Ft8EncodeRsp {
            ok: true,
            tones: tones.to_vec(),
            error: String::new(),
        })),
    };
    msg.encode_to_vec()
}

/// Encode an Ft8EncodeRsp (failure).
pub fn encode_ft8_encode_rsp_err(err: &str) -> Vec<u8> {
    let msg = BridgeMessage {
        msg: Some(Msg::Ft8EncodeRsp(cwbp::Ft8EncodeRsp {
            ok: false,
            tones: Vec::new(),
            error: err.into(),
        })),
    };
    msg.encode_to_vec()
}

/// Encode a decoded FT8 message.
pub fn encode_ft8_decode(text: &str, snr_db: i32, freq_hz: f32, delta_time_s: f32) -> Vec<u8> {
    let msg = BridgeMessage {
        msg: Some(Msg::Ft8Decode(cwbp::Ft8Decode {
            text: text.into(),
            snr_db,
            frequency_hz: freq_hz,
            delta_time_s,
        })),
    };
    msg.encode_to_vec()
}

/// Encode an Ft8Status message.
pub fn encode_ft8_status(state: Ft8State, detail: Option<&str>) -> Vec<u8> {
    let msg = BridgeMessage {
        msg: Some(Msg::Ft8Status(cwbp::Ft8Status {
            state: state as i32,
            detail: detail.unwrap_or_default().into(),
        })),
    };
    msg.encode_to_vec()
}

/// Encode a JackStatus message.
#[allow(dead_code)] // rev 2 PCB has no jack-detect switches
pub fn encode_jack_status(mic_plugged: bool, phone_plugged: bool) -> Vec<u8> {
    let msg = BridgeMessage {
        msg: Some(Msg::JackStatus(cwbp::JackStatus {
            mic_plugged,
            phone_plugged,
        })),
    };
    msg.encode_to_vec()
}

/// Encode a BatteryStatus message. `present == false` means the reading
/// should be ignored by the client (no LiPo or ADC failure); `mv` and
/// `percent` are still set so the OLED diagnostic screen has something
/// useful to render.
#[allow(dead_code)] // rev 2 PCB has no VBAT sense
pub fn encode_battery_status(present: bool, mv: u32, percent: u32) -> Vec<u8> {
    let msg = BridgeMessage {
        msg: Some(Msg::BatteryStatus(cwbp::BatteryStatus {
            present,
            mv,
            percent,
        })),
    };
    msg.encode_to_vec()
}

/// Extract the Msg variant from a decoded BridgeMessage.
pub fn unwrap_msg(msg: BridgeMessage) -> Option<Msg> {
    msg.msg
}
