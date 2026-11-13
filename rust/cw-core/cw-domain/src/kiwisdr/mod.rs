//! KiwiSDR domain logic: modes/passbands, IMA ADPCM decode, wire-protocol
//! parsing, public-directory parsing, `/status` parsing, and Tune-In receiver
//! selection. Ports of the pure halves of the Swift
//! `Services/WebSDR/` stack (`KiwiSDRTypes`, `KiwiSDRADPCM`, `KiwiSDRClient`
//! parsing, `WebSDRDirectory`, `KiwiSDRStatusFetcher`, `TuneInManager`
//! selection + smart features). Transport lives in `cw-net`; the FFI surface
//! is `cw-ffi::sdr_api`.

pub mod adpcm;
pub mod directory;
pub mod mode;
pub mod protocol;
pub mod selection;
pub mod status;

pub use adpcm::AdpcmState;
pub use directory::{find_nearby, haversine_km, KiwiSdrReceiver};
pub use mode::KiwiSdrMode;
pub use protocol::{
    check_for_server_error, classify_stream_text, is_snd_frame, parse_msg_value,
    parse_redirect_target, parse_snd_frame, tune_command, ServerError, SndFrame, StreamTextEvent,
};
pub use selection::{
    detect_qsy, filter_available, suggest_better_receiver, CandidateAccumulator, QsyObservation,
    ReceiverSuggestion, TuneInSpot, TuneInStrategy,
};
pub use status::{parse_status_response, ReceiverStatus};
