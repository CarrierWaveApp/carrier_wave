//! Parity gate for the FT8 decoder port — runs the same ft8_lib WAV fixtures
//! the Swift `FT8DecoderTests` use, against the same expected-output text files
//! sourced from kgoba/ft8_lib's `test/wav/` directory.
//!
//! Acceptance bar: at least half the expected messages appear in the decoder
//! output (matches Swift's threshold). Bit-for-bit equality with the Swift
//! output is not required and would be brittle — both implementations call
//! the same C decoder, but float rounding in candidate scoring can perturb
//! the dedup ordering. The shared ft8_lib has already certified the message
//! text format, so message-set parity against the same `.txt` truth files is
//! what we gate on.

use std::path::PathBuf;

use cw_ft8::decode_default;

const FIXTURES_RELATIVE: &str =
    "../../../swift/packages/CarrierWaveCore/Tests/CarrierWaveCoreTests/Resources/ft8-samples";

fn fixtures_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(FIXTURES_RELATIVE)
}

fn load_samples(name: &str) -> Vec<f32> {
    let path = fixtures_dir()
        .join("ft8_lib_test_vectors")
        .join(format!("{name}.wav"));
    cw_ft8::load_wav(&path).unwrap_or_else(|err| panic!("load {}: {err}", path.display()))
}

fn load_expected_messages(name: &str) -> Vec<String> {
    let path = fixtures_dir()
        .join("ft8_lib_test_vectors")
        .join(format!("{name}.txt"));
    let raw = std::fs::read_to_string(&path).unwrap_or_else(|err| panic!("read {}: {err}", path.display()));
    raw.lines()
        .filter(|line| !line.trim().is_empty())
        .filter_map(extract_message_text)
        .collect()
}

// Lines look like: `110615  -2  1.0  431 ~  VK4BLE OH8JK R-17`
// The "~" delimiter separates metadata from the message text. Swift's test
// uses the same trick.
fn extract_message_text(line: &str) -> Option<String> {
    let (_, rest) = line.split_once("~ ")?;
    let text = rest.trim();
    // The trailing column on some lines is a free-form country annotation
    // ("Italy", "Germany") — keep just the message text by collapsing internal
    // whitespace and dropping the trailing token if it looks like a label.
    let mut tokens: Vec<&str> = text.split_whitespace().collect();
    if let Some(last) = tokens.last() {
        // Heuristic: a trailing token of all letters longer than 4 chars is
        // the annotation. Real callsigns/grids are shorter or have digits.
        if last.chars().all(|c| c.is_alphabetic()) && last.len() > 4 {
            tokens.pop();
        }
    }
    Some(tokens.join(" "))
}

fn assert_message_set_parity(fixture: &str) {
    let samples = load_samples(fixture);
    assert!(
        samples.len() >= 180_000,
        "fixture {fixture} too short: {} samples",
        samples.len()
    );
    let results = decode_default(&samples);
    assert!(
        results.len() >= 10,
        "{fixture} decoded {} messages; expected ≥ 10",
        results.len()
    );

    let decoded: std::collections::HashSet<&str> =
        results.iter().map(|r| r.raw_text.as_str()).collect();
    let expected = load_expected_messages(fixture);
    let matches = expected.iter().filter(|exp| decoded.contains(exp.as_str())).count();
    assert!(
        matches >= expected.count_div_2(),
        "{fixture}: matched {matches}/{} expected messages; decoded {} unique messages",
        expected.len(),
        decoded.len()
    );
}

// Tiny helper so the assertion message reads cleanly above; an inherent
// method on Vec keeps the call site terse.
trait Count {
    fn count_div_2(&self) -> usize;
}
impl<T> Count for Vec<T> {
    fn count_div_2(&self) -> usize {
        self.len() / 2
    }
}

#[test]
fn decode_191111_110615_matches_expected() {
    assert_message_set_parity("191111_110615");
}

#[test]
fn decode_191111_110630_matches_expected() {
    assert_message_set_parity("191111_110630");
}

#[test]
fn decode_191111_110645_matches_expected() {
    assert_message_set_parity("191111_110645");
}

#[test]
fn decode_websdr_test5_matches_expected() {
    assert_message_set_parity("websdr_test5");
}

#[test]
fn empty_buffer_returns_empty() {
    assert!(decode_default(&[]).is_empty());
}

#[test]
fn short_buffer_returns_empty() {
    let short = vec![0f32; 1_000];
    assert!(decode_default(&short).is_empty());
}
