//! Server-side mirror of Swift `RadioMacroSpec` and `RadioMacroArg`.
//!
//! Step kinds and `CapabilityBits` live in [`verifier_generated`](super::verifier_generated)
//! (codegen output). Everything else is hand-written here so the verifier
//! has a typed input.

use crate::macros::verifier_generated::{CapabilityBits, RadioMacroStep};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RadioMacroSpec {
    pub id: Uuid,
    pub name: String,
    pub applies_to: Vec<String>,
    #[serde(default)]
    pub capabilities: CapabilityBits,
    #[serde(default)]
    pub args: Vec<RadioMacroArg>,
    pub steps: Vec<RadioMacroStep>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RadioMacroArg {
    pub name: String,
    #[serde(rename = "type")]
    pub arg_type: ArgType,
    pub min: Option<i64>,
    pub max: Option<i64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ArgType {
    Frequency,
    Integer,
    String,
    Bool,
    Mode,
}

impl CapabilityBits {
    /// Returns `true` if `self` declares every capability bit that `other`
    /// has set. Mirror of the Swift `RadioMacroCapabilities.dominates` check.
    pub fn dominates(&self, other: &CapabilityBits) -> bool {
        (!other.transmits || self.transmits)
            && (!other.changesFrequency || self.changesFrequency)
            && (!other.changesMode || self.changesMode)
            && (!other.changesPower || self.changesPower)
            && (!other.usesRawBytes || self.usesRawBytes)
    }

    /// Union — bit-wise OR of every flag. Used to combine step contributions
    /// and opcode-table matches.
    pub fn union(&self, other: &CapabilityBits) -> CapabilityBits {
        CapabilityBits {
            transmits: self.transmits || other.transmits,
            changesFrequency: self.changesFrequency || other.changesFrequency,
            changesMode: self.changesMode || other.changesMode,
            changesPower: self.changesPower || other.changesPower,
            usesRawBytes: self.usesRawBytes || other.usesRawBytes,
        }
    }
}
