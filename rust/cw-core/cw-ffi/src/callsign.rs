//! UniFFI surface for callsign extraction / primary detection + edit distance
//! (`cw_domain::callsign_detector` + `cw_domain::callsign_edit_distance`).
//!
//! Free functions mirroring the Swift `CallsignDetector` and
//! `CallsignEditDistance` enums. The `CWTextElement` rendering path stays on the
//! Swift side (UI-only); everything regex / context / Levenshtein based lives
//! here and is shared with `android/`.

use cw_domain::callsign_detector::{self, CallsignContext, DetectedCallsign};
use cw_domain::callsign_edit_distance;

/// Where a detected callsign sat in the transcript, mirroring Swift's
/// `DetectedCallsign.CallsignContext`.
#[derive(uniffi::Enum)]
pub enum FfiCallsignContext {
    CqCall,
    DeIdentifier,
    Response,
    Unknown,
}

impl From<CallsignContext> for FfiCallsignContext {
    fn from(context: CallsignContext) -> Self {
        match context {
            CallsignContext::CqCall => FfiCallsignContext::CqCall,
            CallsignContext::DeIdentifier => FfiCallsignContext::DeIdentifier,
            CallsignContext::Response => FfiCallsignContext::Response,
            CallsignContext::Unknown => FfiCallsignContext::Unknown,
        }
    }
}

/// A primary callsign detected in a CW transcript with its surrounding context.
#[derive(uniffi::Record)]
pub struct FfiDetectedCallsign {
    pub callsign: String,
    pub context: FfiCallsignContext,
}

impl From<DetectedCallsign> for FfiDetectedCallsign {
    fn from(detected: DetectedCallsign) -> Self {
        FfiDetectedCallsign {
            callsign: detected.callsign,
            context: detected.context.into(),
        }
    }
}

/// A near-match candidate callsign and its edit distance from the query.
#[derive(uniffi::Record)]
pub struct FfiNearMatch {
    pub callsign: String,
    pub distance: u32,
}

/// Unique callsigns appearing in `text`, in source order, uppercased.
#[uniffi::export]
pub fn callsign_extract_callsigns(text: String) -> Vec<String> {
    callsign_detector::extract_callsigns(&text)
}

/// Most likely "other station" callsign from a CW transcript, using
/// surrounding-word context (`de` > `cq` > `response` > `unknown`; last wins
/// within a tier). `None` if no valid callsign is present.
#[uniffi::export]
pub fn callsign_detect_primary(text: String) -> Option<FfiDetectedCallsign> {
    callsign_detector::detect_primary_callsign(&text).map(Into::into)
}

/// Case-insensitive Levenshtein distance between two strings.
#[uniffi::export]
pub fn callsign_distance(s1: String, s2: String) -> u32 {
    callsign_edit_distance::distance(&s1, &s2) as u32
}

/// Candidates within `max_distance` of `callsign` (exact matches excluded),
/// uppercased and sorted by distance ascending.
#[uniffi::export]
pub fn callsign_find_near_matches(
    callsign: String,
    max_distance: u32,
    candidates: Vec<String>,
) -> Vec<FfiNearMatch> {
    callsign_edit_distance::find_near_matches(
        &callsign,
        max_distance as usize,
        candidates.iter().map(|s| s.as_str()),
    )
    .into_iter()
    .map(|(callsign, distance)| FfiNearMatch { callsign, distance: distance as u32 })
    .collect()
}
