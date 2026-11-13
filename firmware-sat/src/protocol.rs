use prost::Message;

use crate::generated::cwbp::{
    self, bridge_message::Msg, BridgeMessage, CatData, HandshakeRsp, RadioInfo, Status,
};

pub use crate::generated::cwbp::{
    RadioProtocol, SatAckResult, SatRunState, SetResultCode, SetVerifyField, StatusCode,
};

/// Firmware version
pub const FW_VERSION: &str = "0.1.0";
pub const PROTOCOL_VERSION: u32 = 2;

/// Capability flags (shared bit assignments with the S3 bridge firmware).
pub const CAP_USB_HOST: u32 = 1 << 0;
pub const CAP_AUTO_DETECT: u32 = 1 << 1;
pub const CAP_SET_VERIFY: u32 = 1 << 2;
pub const CAP_SAT_DOPPLER: u32 = 1 << 5;

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
            capabilities: CAP_USB_HOST | CAP_AUTO_DETECT | CAP_SET_VERIFY | CAP_SAT_DOPPLER,
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

/// Encode a SatScheduleAck. `seq == u32::MAX` acks the SatScheduleBegin.
pub fn encode_sat_ack(
    schedule_id: u32,
    seq: u32,
    result: SatAckResult,
    steps_loaded: u32,
) -> Vec<u8> {
    let msg = BridgeMessage {
        msg: Some(Msg::SatAck(cwbp::SatScheduleAck {
            schedule_id,
            seq,
            result: result as i32,
            steps_loaded,
        })),
    };
    msg.encode_to_vec()
}

/// Encode a SatStatus push.
#[allow(clippy::too_many_arguments)]
pub fn encode_sat_status(
    state: SatRunState,
    schedule_id: u32,
    step_index: u32,
    downlink_hz: u64,
    uplink_hz: u64,
    t_ms: i64,
    detail: &str,
) -> Vec<u8> {
    let msg = BridgeMessage {
        msg: Some(Msg::SatStatus(cwbp::SatStatus {
            state: state as i32,
            schedule_id,
            step_index,
            downlink_hz,
            uplink_hz,
            t_ms,
            detail: detail.into(),
        })),
    };
    msg.encode_to_vec()
}

/// Extract the Msg variant from a decoded BridgeMessage.
pub fn unwrap_msg(msg: BridgeMessage) -> Option<Msg> {
    msg.msg
}
