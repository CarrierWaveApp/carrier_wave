//! Server-side mirror of Swift `MacroVerifier`.
//!
//! Static analysis pass over a `RadioMacroSpec`. Produces a flat list of
//! [`VerifierIssue`]s — errors and warnings. The server's POST/PUT admin
//! handlers reject any spec with at least one error. The behaviour here
//! must match Swift exactly; the shared fixture corpus catches drift.

use crate::macros::opcodes::{self, OpcodeTable};
use crate::macros::spec::{ArgType, RadioMacroSpec};
use crate::macros::verifier_generated::{CapabilityBits, RadioMacroStep};
use serde::Serialize;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Severity {
    Error,
    Warning,
}

#[derive(Debug, Clone, Serialize)]
pub struct VerifierIssue {
    pub severity: Severity,
    pub step_index: Option<usize>,
    pub message: String,
}

impl VerifierIssue {
    fn error(message: impl Into<String>) -> Self {
        Self {
            severity: Severity::Error,
            step_index: None,
            message: message.into(),
        }
    }

    fn error_at(index: usize, message: impl Into<String>) -> Self {
        Self {
            severity: Severity::Error,
            step_index: Some(index),
            message: message.into(),
        }
    }
}

/// Run the static analysis pass. Returns issues in encounter order
/// (capabilities mismatch, then per-step, then per-arg).
pub fn verify(spec: &RadioMacroSpec) -> Vec<VerifierIssue> {
    let mut issues = Vec::new();

    // 1. Inferred-vs-declared capabilities. Declared bits must cover inferred.
    let inferred = infer_capabilities(&spec.steps, &spec.applies_to);
    if !spec.capabilities.dominates(&inferred) {
        let parts = format!(
            "transmits={}, changesFrequency={}, changesMode={}, changesPower={}, usesRawBytes={}",
            inferred.transmits,
            inferred.changesFrequency,
            inferred.changesMode,
            inferred.changesPower,
            inferred.usesRawBytes,
        );
        issues.push(VerifierIssue::error(format!(
            "Declared capabilities do not cover inferred: {parts}"
        )));
    }

    // 2. Per-step checks.
    for (index, step) in spec.steps.iter().enumerate() {
        verify_step(step, index, &mut issues);
    }

    // 3. Per-arg checks — frequency args need min/max bounds.
    for arg in &spec.args {
        if arg.arg_type == ArgType::Frequency && (arg.min.is_none() || arg.max.is_none()) {
            issues.push(VerifierIssue::error(format!(
                "Frequency arg '{}' must declare min/max bounds",
                arg.name
            )));
        }
    }

    issues
}

/// Infer the capability bits the step list actually exercises. Mirrors the
/// Swift implementation — includes the opcode-table decoder pass that
/// floors unknown `.rawBytes` payloads at `transmits=true, usesRawBytes=true`.
pub fn infer_capabilities(steps: &[RadioMacroStep], _applies_to: &[String]) -> CapabilityBits {
    let mut caps = CapabilityBits::default();
    for step in steps {
        caps = caps.union(&step.capability_contribution());
        if let RadioMacroStep::RawBytes { protocol_, bytes } = step {
            let table = OpcodeTable::load(protocol_);
            if let Some(parsed) = opcodes::parse_hex(bytes) {
                caps = caps.union(&table.capabilities(&parsed));
                if !table.any_recognized(&parsed) {
                    caps.transmits = true;
                    caps.usesRawBytes = true;
                }
            } else {
                // Malformed payload — also floor at transmit-capable.
                caps.transmits = true;
                caps.usesRawBytes = true;
            }
        }
    }
    caps
}

fn verify_step(step: &RadioMacroStep, index: usize, issues: &mut Vec<VerifierIssue>) {
    match step {
        RadioMacroStep::Delay { durationMs } => {
            if *durationMs > 30_000 {
                issues.push(VerifierIssue::error_at(
                    index,
                    "Delay exceeds 30000 ms cap",
                ));
            }
        }
        RadioMacroStep::WaitUntil { timeoutMs, .. } => {
            if *timeoutMs > 30_000 {
                issues.push(VerifierIssue::error_at(
                    index,
                    "waitUntil timeout exceeds 30000 ms cap",
                ));
            }
        }
        RadioMacroStep::SendCW { text } => {
            if !text.chars().all(|c| c.is_ascii()) {
                issues.push(VerifierIssue::error_at(index, "sendCW requires ASCII text"));
            }
        }
        _ => {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::macros::spec::RadioMacroArg;
    use uuid::Uuid;

    fn spec_with_steps(steps: Vec<RadioMacroStep>) -> RadioMacroSpec {
        RadioMacroSpec {
            id: Uuid::nil(),
            name: "t".to_string(),
            applies_to: vec!["civ".to_string()],
            capabilities: CapabilityBits::default(),
            args: vec![],
            steps,
        }
    }

    #[test]
    fn delay_under_cap_passes() {
        let issues = verify(&spec_with_steps(vec![RadioMacroStep::Delay {
            durationMs: 10_000,
        }]));
        assert!(issues.is_empty());
    }

    #[test]
    fn delay_over_cap_errors() {
        let issues = verify(&spec_with_steps(vec![RadioMacroStep::Delay {
            durationMs: 31_000,
        }]));
        assert_eq!(issues.len(), 1);
        assert!(issues[0].message.contains("30000"));
    }

    #[test]
    fn send_cw_non_ascii_errors() {
        let mut spec = spec_with_steps(vec![RadioMacroStep::SendCW {
            text: "CQ — DE W6JY".to_string(),
        }]);
        spec.capabilities.transmits = true;
        let issues = verify(&spec);
        assert!(issues.iter().any(|i| i.message.contains("ASCII")));
    }

    #[test]
    fn frequency_arg_without_bounds_errors() {
        let mut spec = spec_with_steps(vec![RadioMacroStep::SetFrequency { hz: 7032000 }]);
        spec.capabilities.changesFrequency = true;
        spec.args.push(RadioMacroArg {
            name: "f".to_string(),
            arg_type: ArgType::Frequency,
            min: None,
            max: None,
        });
        let issues = verify(&spec);
        assert!(issues.iter().any(|i| i.message.contains("min/max")));
    }

    #[test]
    fn unknown_raw_bytes_floors_transmits() {
        let mut spec = spec_with_steps(vec![RadioMacroStep::RawBytes {
            protocol_: "civ".to_string(),
            bytes: "FE FE 94 E0 AA BB CC FD".to_string(),
        }]);
        // Author claims non-transmit; verifier should error.
        spec.capabilities.usesRawBytes = true;
        let issues = verify(&spec);
        assert!(issues
            .iter()
            .any(|i| i.message.contains("transmits") && i.severity == Severity::Error));
    }

    // -----------------------------------------------------------------
    // Shared fixture corpus.
    //
    // `macro-verifier-cases.json` is the single source of truth shared
    // between Swift `MacroVerifierTests` and the Rust verifier. CI fails
    // if a case the Swift side accepts is rejected here (or vice versa).
    // -----------------------------------------------------------------

    #[derive(serde::Deserialize)]
    struct Fixture {
        cases: Vec<FixtureCase>,
    }

    #[derive(serde::Deserialize)]
    struct FixtureCase {
        name: String,
        spec: RadioMacroSpec,
        expect: FixtureExpect,
    }

    #[derive(serde::Deserialize)]
    struct FixtureExpect {
        issues: Vec<FixtureIssue>,
    }

    #[derive(serde::Deserialize)]
    struct FixtureIssue {
        severity: String,
        #[serde(rename = "messageContains")]
        message_contains: String,
    }

    fn matches(issue: &VerifierIssue, expected: &FixtureIssue) -> bool {
        let want = match expected.severity.as_str() {
            "error" => Severity::Error,
            "warning" => Severity::Warning,
            _ => return false,
        };
        issue.severity == want && issue.message.contains(&expected.message_contains)
    }

    #[test]
    fn shared_fixture_corpus() {
        let path = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("swift/packages/CarrierWaveData/Tests/CarrierWaveDataTests/Macros/Fixtures/macro-verifier-cases.json");
        let data = std::fs::read(&path)
            .unwrap_or_else(|e| panic!("failed reading {path:?}: {e}"));
        let fixture: Fixture = serde_json::from_slice(&data).expect("fixture JSON decodes");

        let mut failures = Vec::new();
        for case in &fixture.cases {
            let issues = verify(&case.spec);
            if case.expect.issues.is_empty() {
                let errors: Vec<_> = issues
                    .iter()
                    .filter(|i| i.severity == Severity::Error)
                    .collect();
                if !errors.is_empty() {
                    failures.push(format!(
                        "case `{}` expected no errors but got: {errors:?}",
                        case.name
                    ));
                }
            } else {
                for expected in &case.expect.issues {
                    if !issues.iter().any(|i| matches(i, expected)) {
                        failures.push(format!(
                            "case `{}` missing expected issue (severity={}, contains=\"{}\"); got {issues:?}",
                            case.name, expected.severity, expected.message_contains
                        ));
                    }
                }
            }
        }

        if !failures.is_empty() {
            panic!(
                "{} fixture case(s) failed:\n - {}",
                failures.len(),
                failures.join("\n - ")
            );
        }
    }
}
