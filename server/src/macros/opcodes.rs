//! Server-side mirror of `RadioMacroOpcodeTable`.
//!
//! Per-protocol opcode-pattern tables consulted by the verifier when
//! inferring capabilities from a `.rawBytes` step. Patterns are loaded
//! at compile time from the **same** JSON files the Swift package ships,
//! via `include_str!` — there is one canonical source of truth.

use crate::macros::verifier_generated::CapabilityBits;
use serde::Deserialize;

const CIV_JSON: &str = include_str!(
    "../../../swift/packages/CarrierWaveData/Sources/CarrierWaveData/Resources/macro-opcodes/civ.json"
);
const KENWOOD_JSON: &str = include_str!(
    "../../../swift/packages/CarrierWaveData/Sources/CarrierWaveData/Resources/macro-opcodes/kenwood.json"
);

#[derive(Debug, Deserialize)]
struct OpcodeFile {
    #[serde(rename = "protocol")]
    _protocol: String,
    opcodes: Vec<OpcodeEntry>,
}

#[derive(Debug, Deserialize)]
struct OpcodeEntry {
    #[serde(rename = "match")]
    match_: String,
    capabilities: OpcodeCapsFragment,
}

#[derive(Debug, Default, Deserialize)]
#[serde(default)]
#[allow(non_snake_case)]
struct OpcodeCapsFragment {
    transmits: bool,
    changesFrequency: bool,
    changesMode: bool,
    changesPower: bool,
    usesRawBytes: bool,
}

impl OpcodeCapsFragment {
    fn into_bits(self) -> CapabilityBits {
        CapabilityBits {
            transmits: self.transmits,
            changesFrequency: self.changesFrequency,
            changesMode: self.changesMode,
            changesPower: self.changesPower,
            usesRawBytes: self.usesRawBytes,
        }
    }
}

#[derive(Debug, Clone)]
struct Pattern {
    /// `0xFF` for "must equal pattern[i]"; `0x00` for "wildcard".
    mask: Vec<u8>,
    pattern: Vec<u8>,
    caps: CapabilityBits,
}

#[derive(Debug, Clone)]
pub struct OpcodeTable {
    patterns: Vec<Pattern>,
}

impl OpcodeTable {
    /// Build a table for a named protocol. Unknown protocols yield an
    /// empty table — callers (the verifier) treat that as "everything
    /// unrecognized" and floor capabilities at transmit-capable.
    pub fn load(protocol: &str) -> Self {
        let src = match protocol {
            "civ" => Some(CIV_JSON),
            "kenwood" => Some(KENWOOD_JSON),
            _ => None,
        };
        let Some(json) = src else {
            return Self { patterns: vec![] };
        };
        let Ok(file): Result<OpcodeFile, _> = serde_json::from_str(json) else {
            return Self { patterns: vec![] };
        };
        let patterns = file
            .opcodes
            .into_iter()
            .filter_map(|entry| {
                let (mask, pattern) = parse_match(&entry.match_)?;
                Some(Pattern {
                    mask,
                    pattern,
                    caps: entry.capabilities.into_bits(),
                })
            })
            .collect();
        Self { patterns }
    }

    /// Union of capability bits contributed by every pattern that matches
    /// somewhere inside `bytes`. Empty table -> all bits false.
    pub fn capabilities(&self, bytes: &[u8]) -> CapabilityBits {
        let mut combined = CapabilityBits::default();
        for entry in &self.patterns {
            if matches(entry, bytes) {
                combined = combined.union(&entry.caps);
            }
        }
        combined
    }

    /// `true` if at least one pattern matched. Callers use the negation
    /// ("unknown payload") to apply the floor-at-transmit safety rule.
    pub fn any_recognized(&self, bytes: &[u8]) -> bool {
        self.patterns.iter().any(|p| matches(p, bytes))
    }
}

/// Parses a space-separated hex string with `??` wildcards into a
/// (mask, pattern) pair. Returns `None` on malformed tokens.
fn parse_match(source: &str) -> Option<(Vec<u8>, Vec<u8>)> {
    let mut mask = Vec::new();
    let mut pattern = Vec::new();
    for token in source.split_whitespace() {
        if token == "??" {
            mask.push(0x00);
            pattern.push(0x00);
        } else {
            let byte = u8::from_str_radix(token, 16).ok()?;
            mask.push(0xFF);
            pattern.push(byte);
        }
    }
    Some((mask, pattern))
}

/// Sliding-window match — at any offset, every byte that is set in `mask`
/// must equal the corresponding byte in `pattern`.
fn matches(p: &Pattern, bytes: &[u8]) -> bool {
    let plen = p.pattern.len();
    if plen == 0 || bytes.len() < plen {
        return false;
    }
    'outer: for offset in 0..=bytes.len() - plen {
        for index in 0..plen {
            if (bytes[offset + index] & p.mask[index]) != p.pattern[index] {
                continue 'outer;
            }
        }
        return true;
    }
    false
}

/// Parse the space-separated hex string format used in `RawBytes.bytes`
/// (e.g. `"FE FE 94 E0 1C 00 01 FD"`). Strict — any non-hex token or
/// non-byte width fails. Whitespace is the only allowed separator.
pub fn parse_hex(hex: &str) -> Option<Vec<u8>> {
    let mut out = Vec::new();
    for token in hex.split_whitespace() {
        if token.len() != 2 {
            return None;
        }
        let byte = u8::from_str_radix(token, 16).ok()?;
        out.push(byte);
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn civ_ptt_on_pattern_recognised() {
        let table = OpcodeTable::load("civ");
        let bytes = parse_hex("FE FE 94 E0 1C 00 01 FD").unwrap();
        assert!(table.any_recognized(&bytes));
        let caps = table.capabilities(&bytes);
        assert!(caps.transmits);
    }

    #[test]
    fn civ_garbage_payload_is_unknown() {
        let table = OpcodeTable::load("civ");
        let bytes = parse_hex("FE FE 94 E0 AA BB CC FD").unwrap();
        assert!(!table.any_recognized(&bytes));
    }

    #[test]
    fn kenwood_tx_recognised() {
        let table = OpcodeTable::load("kenwood");
        // 'TX;' = 54 58 3B
        let bytes = parse_hex("54 58 3B").unwrap();
        assert!(table.any_recognized(&bytes));
        assert!(table.capabilities(&bytes).transmits);
    }

    #[test]
    fn unknown_protocol_empty_table() {
        let table = OpcodeTable::load("imaginary");
        assert!(!table.any_recognized(&[0xFF; 8]));
    }

    #[test]
    fn parse_hex_strict() {
        assert_eq!(parse_hex("01 02 FF").unwrap(), vec![0x01, 0x02, 0xFF]);
        assert!(parse_hex("01 0").is_none()); // not 2-char wide
        assert!(parse_hex("0G").is_none()); // not hex
    }
}
