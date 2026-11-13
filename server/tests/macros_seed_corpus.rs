//! Seed macros corpus check (CAR-271 T8).
//!
//! Every file under `server/seed_macros/` must parse as an
//! `AdminMacroPayload` and pass the verifier with no errors. CI fails on
//! either drift, so an unintentional schema break (or a starter that
//! references an undeclared opcode) is caught at PR time, not on deploy.

#![cfg(test)]

use activities_server::macros::band_plan;
use activities_server::macros::slug as slug_v;
use activities_server::macros::spec::{RadioMacroArg, RadioMacroSpec};
use activities_server::macros::tag_vocabulary;
use activities_server::macros::verifier::{self, Severity};
use activities_server::macros::verifier_generated::{CapabilityBits, RadioMacroStep};
use serde::Deserialize;
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Deserialize)]
struct SeedDoc {
    slug: String,
    name: String,
    #[serde(default)]
    tags: Vec<String>,
    #[serde(default, rename = "appliesTo")]
    applies_to: Vec<String>,
    #[serde(default)]
    capabilities: CapabilityBits,
    #[serde(default)]
    args: Vec<RadioMacroArg>,
    steps: Vec<RadioMacroStep>,
    author_callsign: Option<String>,
}

fn seed_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("seed_macros")
}

fn load_seed_files() -> Vec<(PathBuf, SeedDoc)> {
    let dir = seed_dir();
    let mut out = Vec::new();
    for entry in fs::read_dir(&dir).expect("seed_macros dir exists") {
        let path = entry.unwrap().path();
        if path.extension().and_then(|s| s.to_str()) != Some("cwmacro") {
            continue;
        }
        let data = fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
        let doc: SeedDoc = serde_json::from_str(&data)
            .unwrap_or_else(|e| panic!("parse {}: {e}", path.display()));
        out.push((path, doc));
    }
    out.sort_by(|a, b| a.0.cmp(&b.0));
    out
}

#[test]
fn every_seed_macro_passes_verifier() {
    let seeds = load_seed_files();
    assert!(!seeds.is_empty(), "expected at least one .cwmacro under server/seed_macros");
    let mut failures = Vec::new();
    for (path, doc) in &seeds {
        slug_v::validate(&doc.slug, doc.author_callsign.as_deref(), true)
            .unwrap_or_else(|e| failures.push(format!("{}: slug {e}", path.display())));
        tag_vocabulary::validate_set(&doc.tags)
            .unwrap_or_else(|e| {
                failures.push(format!("{}: tags {e}", path.display()));
                vec![]
            });
        band_plan::validate(&doc.args)
            .unwrap_or_else(|e| failures.push(format!("{}: band-plan {e}", path.display())));

        let spec = RadioMacroSpec {
            id: uuid::Uuid::nil(),
            name: doc.name.clone(),
            applies_to: doc.applies_to.clone(),
            capabilities: doc.capabilities.clone(),
            args: doc.args.clone(),
            steps: doc.steps.clone(),
        };
        let issues = verifier::verify(&spec);
        for issue in &issues {
            if issue.severity == Severity::Error {
                failures.push(format!(
                    "{} ({}): verifier {}: {}",
                    path.display(),
                    doc.slug,
                    match issue.severity {
                        Severity::Error => "error",
                        Severity::Warning => "warning",
                    },
                    issue.message
                ));
            }
        }
    }
    if !failures.is_empty() {
        panic!("{} seed macros failed:\n - {}", failures.len(), failures.join("\n - "));
    }
}

#[test]
fn seed_corpus_has_nine_files() {
    // Pinning the count so accidental deletions show up loud. Adjust this
    // when you intentionally add or remove starter macros.
    assert_eq!(load_seed_files().len(), 9);
}
