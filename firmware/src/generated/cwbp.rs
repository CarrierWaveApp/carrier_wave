// Generated from proto/cwbp.proto — regenerate with:
//   protoc -I proto --prost_out=firmware/src/generated proto/cwbp.proto

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct BridgeMessage {
    #[prost(
        oneof = "bridge_message::Msg",
        tags = "1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28"
    )]
    pub msg: ::core::option::Option<bridge_message::Msg>,
}

pub mod bridge_message {
    #[derive(Clone, PartialEq, ::prost::Oneof)]
    pub enum Msg {
        #[prost(message, tag = "1")]
        HandshakeReq(super::HandshakeReq),
        #[prost(message, tag = "2")]
        HandshakeRsp(super::HandshakeRsp),
        #[prost(message, tag = "3")]
        CatData(super::CatData),
        #[prost(message, tag = "4")]
        Status(super::Status),
        #[prost(message, tag = "5")]
        RadioInfo(super::RadioInfo),
        #[prost(message, tag = "6")]
        RequestDetect(super::RequestDetect),
        #[prost(message, tag = "7")]
        SetBaud(super::SetBaud),
        #[prost(message, tag = "8")]
        SetVerify(super::SetVerify),
        #[prost(message, tag = "9")]
        SetResult(super::SetResult),
        #[prost(message, tag = "10")]
        CwSend(super::CwSend),
        #[prost(message, tag = "11")]
        CwStop(super::CwStop),
        #[prost(message, tag = "12")]
        CwSpeed(super::CwSpeed),
        #[prost(message, tag = "13")]
        CwSlotPlay(super::CwSlotPlay),
        #[prost(message, tag = "14")]
        CwSlotSet(super::CwSlotSet),
        #[prost(message, tag = "15")]
        CwStatusReq(super::CwStatusReq),
        #[prost(message, tag = "16")]
        CwAck(super::CwAck),
        #[prost(message, tag = "17")]
        CwProgress(super::CwProgress),
        #[prost(message, tag = "18")]
        CwStatusRsp(super::CwStatusRsp),
        #[prost(message, tag = "19")]
        Ft8EncodeReq(super::Ft8EncodeReq),
        #[prost(message, tag = "20")]
        Ft8EncodeRsp(super::Ft8EncodeRsp),
        #[prost(message, tag = "21")]
        Ft8Send(super::Ft8Send),
        #[prost(message, tag = "22")]
        Ft8CapStart(super::Ft8CaptureStart),
        #[prost(message, tag = "23")]
        Ft8CapStop(super::Ft8CaptureStop),
        #[prost(message, tag = "24")]
        Ft8Decode(super::Ft8Decode),
        #[prost(message, tag = "25")]
        Ft8Status(super::Ft8Status),
        #[prost(message, tag = "26")]
        JackStatus(super::JackStatus),
        #[prost(message, tag = "27")]
        BatteryStatus(super::BatteryStatus),
        #[prost(message, tag = "28")]
        StatusReq(super::StatusReq),
    }
}

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct HandshakeReq {
    #[prost(uint32, tag = "1")]
    pub protocol_version: u32,
}

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct HandshakeRsp {
    #[prost(uint32, tag = "1")]
    pub protocol_version: u32,
    #[prost(string, tag = "2")]
    pub firmware_version: ::prost::alloc::string::String,
    #[prost(uint32, tag = "3")]
    pub capabilities: u32,
}

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct CatData {
    #[prost(bytes = "vec", tag = "1")]
    pub payload: ::prost::alloc::vec::Vec<u8>,
}

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct Status {
    #[prost(enumeration = "StatusCode", tag = "1")]
    pub code: i32,
    #[prost(string, tag = "2")]
    pub detail: ::prost::alloc::string::String,
}

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct RadioInfo {
    #[prost(enumeration = "RadioProtocol", tag = "1")]
    pub protocol: i32,
    #[prost(uint32, tag = "2")]
    pub baud_rate: u32,
    #[prost(string, tag = "3")]
    pub id_string: ::prost::alloc::string::String,
}

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct RequestDetect {}

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct StatusReq {}

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct SetBaud {
    #[prost(uint32, tag = "1")]
    pub baud_rate: u32,
}

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct SetVerify {
    #[prost(enumeration = "SetVerifyField", tag = "1")]
    pub field: i32,
    #[prost(bytes = "vec", tag = "2")]
    pub value: ::prost::alloc::vec::Vec<u8>,
}

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct SetResult {
    #[prost(enumeration = "SetResultCode", tag = "1")]
    pub result: i32,
}

// ---------------------------------------------------------------
// CW Keyer Messages
// ---------------------------------------------------------------

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct CwSend {
    #[prost(string, tag = "1")]
    pub text: ::prost::alloc::string::String,
}

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct CwStop {}

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct CwSpeed {
    #[prost(uint32, tag = "1")]
    pub wpm: u32,
}

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct CwSlotPlay {
    #[prost(uint32, tag = "1")]
    pub slot: u32,
    #[prost(map = "string, string", tag = "2")]
    pub context:
        ::std::collections::HashMap<::prost::alloc::string::String, ::prost::alloc::string::String>,
}

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct CwSlotSet {
    #[prost(uint32, tag = "1")]
    pub slot: u32,
    #[prost(string, tag = "2")]
    pub text: ::prost::alloc::string::String,
}

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct CwStatusReq {}

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct CwAck {
    #[prost(enumeration = "CwAckResult", tag = "1")]
    pub result: i32,
    #[prost(uint32, tag = "2")]
    pub buf_depth: u32,
}

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct CwProgress {
    #[prost(uint32, tag = "1")]
    pub buf_depth: u32,
    #[prost(uint32, tag = "2")]
    pub flags: u32,
}

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct CwStatusRsp {
    #[prost(uint32, tag = "1")]
    pub wpm: u32,
    #[prost(uint32, tag = "2")]
    pub buf_depth: u32,
    #[prost(uint32, tag = "3")]
    pub flags: u32,
    #[prost(uint32, tag = "4")]
    pub slot_count: u32,
}

// ---------------------------------------------------------------
// FT8 Messages
// ---------------------------------------------------------------

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct Ft8EncodeReq {
    #[prost(string, tag = "1")]
    pub text: ::prost::alloc::string::String,
    #[prost(uint32, tag = "2")]
    pub base_freq_hz: u32,
}

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct Ft8EncodeRsp {
    #[prost(bool, tag = "1")]
    pub ok: bool,
    #[prost(bytes = "vec", tag = "2")]
    pub tones: ::prost::alloc::vec::Vec<u8>,
    #[prost(string, tag = "3")]
    pub error: ::prost::alloc::string::String,
}

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct Ft8Send {
    #[prost(string, tag = "1")]
    pub text: ::prost::alloc::string::String,
    #[prost(uint32, tag = "2")]
    pub base_freq_hz: u32,
}

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct Ft8CaptureStart {
    #[prost(uint32, tag = "1")]
    pub min_freq_hz: u32,
    #[prost(uint32, tag = "2")]
    pub max_freq_hz: u32,
}

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct Ft8CaptureStop {}

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct Ft8Decode {
    #[prost(string, tag = "1")]
    pub text: ::prost::alloc::string::String,
    #[prost(int32, tag = "2")]
    pub snr_db: i32,
    #[prost(float, tag = "3")]
    pub frequency_hz: f32,
    #[prost(float, tag = "4")]
    pub delta_time_s: f32,
}

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct Ft8Status {
    #[prost(enumeration = "Ft8State", tag = "1")]
    pub state: i32,
    #[prost(string, tag = "2")]
    pub detail: ::prost::alloc::string::String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, ::prost::Enumeration)]
#[repr(i32)]
pub enum Ft8State {
    Idle = 0,
    Transmitting = 1,
    Capturing = 2,
    Error = 3,
}

impl Ft8State {
    pub fn as_str_name(&self) -> &'static str {
        match self {
            Self::Idle => "FT8_IDLE",
            Self::Transmitting => "FT8_TRANSMITTING",
            Self::Capturing => "FT8_CAPTURING",
            Self::Error => "FT8_ERROR",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, ::prost::Enumeration)]
#[repr(i32)]
pub enum CwAckResult {
    Ok = 0,
    Queued = 1,
    Fail = 2,
    Unsupported = 3,
    BadSlot = 4,
    EmptySlot = 5,
}

impl CwAckResult {
    pub fn as_str_name(&self) -> &'static str {
        match self {
            Self::Ok => "CW_OK",
            Self::Queued => "CW_QUEUED",
            Self::Fail => "CW_FAIL",
            Self::Unsupported => "CW_UNSUPPORTED",
            Self::BadSlot => "CW_BAD_SLOT",
            Self::EmptySlot => "CW_EMPTY_SLOT",
        }
    }
}

// ---------------------------------------------------------------
// Existing Enums
// ---------------------------------------------------------------

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, ::prost::Enumeration)]
#[repr(i32)]
pub enum StatusCode {
    Unknown = 0,
    UsbConnected = 1,
    UsbDisconnected = 2,
    Detecting = 3,
    DetectionFailed = 4,
    Error = 5,
    Ready = 6,
}

impl StatusCode {
    pub fn as_str_name(&self) -> &'static str {
        match self {
            Self::Unknown => "STATUS_UNKNOWN",
            Self::UsbConnected => "STATUS_USB_CONNECTED",
            Self::UsbDisconnected => "STATUS_USB_DISCONNECTED",
            Self::Detecting => "STATUS_DETECTING",
            Self::DetectionFailed => "STATUS_DETECTION_FAILED",
            Self::Error => "STATUS_ERROR",
            Self::Ready => "STATUS_READY",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, ::prost::Enumeration)]
#[repr(i32)]
pub enum RadioProtocol {
    Unknown = 0,
    Kenwood = 1,
    Civ = 2,
}

impl RadioProtocol {
    pub fn as_str_name(&self) -> &'static str {
        match self {
            Self::Unknown => "PROTO_UNKNOWN",
            Self::Kenwood => "PROTO_KENWOOD",
            Self::Civ => "PROTO_CIV",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, ::prost::Enumeration)]
#[repr(i32)]
pub enum SetVerifyField {
    Unknown = 0,
    Frequency = 1,
    Mode = 2,
    Ptt = 3,
    Xit = 4,
    Rit = 5,
    RitXitOffset = 6,
    ClearRitXit = 7,
    PowerLevel = 8,
}

impl SetVerifyField {
    pub fn as_str_name(&self) -> &'static str {
        match self {
            Self::Unknown => "FIELD_UNKNOWN",
            Self::Frequency => "FIELD_FREQUENCY",
            Self::Mode => "FIELD_MODE",
            Self::Ptt => "FIELD_PTT",
            Self::Xit => "FIELD_XIT",
            Self::Rit => "FIELD_RIT",
            Self::RitXitOffset => "FIELD_RIT_XIT_OFFSET",
            Self::ClearRitXit => "FIELD_CLEAR_RIT_XIT",
            Self::PowerLevel => "FIELD_POWER_LEVEL",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, ::prost::Enumeration)]
#[repr(i32)]
pub enum SetResultCode {
    Ok = 0,
    Fail = 1,
    Unsupported = 2,
}

impl SetResultCode {
    pub fn as_str_name(&self) -> &'static str {
        match self {
            Self::Ok => "RESULT_OK",
            Self::Fail => "RESULT_FAIL",
            Self::Unsupported => "RESULT_UNSUPPORTED",
        }
    }
}

// ---------------------------------------------------------------
// Hardware Status
// ---------------------------------------------------------------

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct JackStatus {
    #[prost(bool, tag = "1")]
    pub mic_plugged: bool,
    #[prost(bool, tag = "2")]
    pub phone_plugged: bool,
}

#[derive(Clone, PartialEq, ::prost::Message)]
pub struct BatteryStatus {
    #[prost(bool, tag = "1")]
    pub present: bool,
    #[prost(uint32, tag = "2")]
    pub mv: u32,
    #[prost(uint32, tag = "3")]
    pub percent: u32,
}
