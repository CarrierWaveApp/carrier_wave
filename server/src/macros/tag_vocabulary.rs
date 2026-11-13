//! Tag vocabulary + per-macro tag rules (CAR-271 T4).
//!
//! Per the design spec ("Description rendering"):
//! - Max 8 tags per macro.
//! - Each tag is NFKC-normalised and lowercased on save.
//! - Curated vocabulary below covers the common cases; free-form tags
//!   pass through if they meet the length/charset check.
//!
//! Free-form rules:
//! - 2..=24 ASCII characters after normalisation.
//! - Lowercase letters, digits, and `-` only.
//! - No leading/trailing/double `-`.

use unicode_normalization::UnicodeNormalization;

const MAX_TAGS_PER_MACRO: usize = 8;
const FREE_FORM_MIN: usize = 2;
const FREE_FORM_MAX: usize = 24;

/// Curated vocabulary — common surfaces, modes, and use-cases. New entries
/// land here when at least three independent macros use a tag in the wild.
pub const CURATED_TAGS: &[&str] = &[
    // Modes
    "cw",
    "ssb",
    "fm",
    "am",
    "rtty",
    "ft8",
    "ft4",
    "digital",
    // Surfaces / use-cases
    "hunter",
    "activator",
    "contest",
    "pota",
    "sota",
    "wwff",
    "qsy",
    "ptt",
    "tuner",
    "voice-memory",
    "voice-keyer",
    "cw-keyer",
    // Equipment / vendors
    "icom",
    "kenwood",
    "yaesu",
    "elecraft",
    "ic-705",
    "ic-7300",
    "ic-7610",
    "ic-9700",
    "k3",
    "kx2",
    "kx3",
    "ft-991a",
    "ft-818",
    "ts-590",
    "ts-890",
    // Common features
    "gps",
    "rit",
    "xit",
    "memory",
    "mobile",
    "portable",
    "power",
    "battery",
];

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TagError {
    TooMany,
    Empty,
    TooShort,
    TooLong,
    InvalidCharacter(char),
    LeadingHyphen,
    TrailingHyphen,
    DoubleHyphen,
}

impl std::fmt::Display for TagError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::TooMany => write!(f, "macros may carry at most {MAX_TAGS_PER_MACRO} tags"),
            Self::Empty => write!(f, "tag is empty"),
            Self::TooShort => write!(f, "tag is shorter than {FREE_FORM_MIN} characters"),
            Self::TooLong => write!(f, "tag is longer than {FREE_FORM_MAX} characters"),
            Self::InvalidCharacter(c) => write!(f, "tag contains invalid character `{c}`"),
            Self::LeadingHyphen => write!(f, "tag must not start with `-`"),
            Self::TrailingHyphen => write!(f, "tag must not end with `-`"),
            Self::DoubleHyphen => write!(f, "tag must not contain `--`"),
        }
    }
}

impl std::error::Error for TagError {}

/// NFKC-normalise + lowercase a single tag. Used before either validating
/// or storing.
pub fn normalise(tag: &str) -> String {
    tag.nfkc().collect::<String>().to_lowercase()
}

/// Validate the full set of tags for a macro. Normalises each entry in
/// place — caller should write back the returned `Vec<String>` rather
/// than the original input.
pub fn validate_set(tags: &[String]) -> Result<Vec<String>, TagError> {
    if tags.len() > MAX_TAGS_PER_MACRO {
        return Err(TagError::TooMany);
    }
    let mut out = Vec::with_capacity(tags.len());
    for tag in tags {
        let normalised = normalise(tag);
        validate_one(&normalised)?;
        out.push(normalised);
    }
    Ok(out)
}

fn validate_one(tag: &str) -> Result<(), TagError> {
    if CURATED_TAGS.iter().any(|t| *t == tag) {
        // Curated entries skip free-form length/charset checks (they were
        // hand-vetted on entry). Length/charset still applies in practice
        // — every curated tag is already lowercase ASCII + hyphen.
        return Ok(());
    }
    if tag.is_empty() {
        return Err(TagError::Empty);
    }
    if tag.chars().count() < FREE_FORM_MIN {
        return Err(TagError::TooShort);
    }
    if tag.chars().count() > FREE_FORM_MAX {
        return Err(TagError::TooLong);
    }
    if tag.starts_with('-') {
        return Err(TagError::LeadingHyphen);
    }
    if tag.ends_with('-') {
        return Err(TagError::TrailingHyphen);
    }
    if tag.contains("--") {
        return Err(TagError::DoubleHyphen);
    }
    for c in tag.chars() {
        if !(c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-') {
            return Err(TagError::InvalidCharacter(c));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn curated_tags_pass() {
        validate_set(&["cw".into(), "pota".into(), "ic-705".into()]).unwrap();
    }

    #[test]
    fn free_form_passes() {
        let out = validate_set(&["my-rig".into()]).unwrap();
        assert_eq!(out, vec!["my-rig"]);
    }

    #[test]
    fn nfkc_normalises_full_width() {
        // U+FF21 'A' (FULLWIDTH) -> 'A' under NFKC; then lowercased.
        let out = validate_set(&["\u{FF21}\u{FF22}\u{FF23}".into()]).unwrap();
        assert_eq!(out, vec!["abc"]);
    }

    #[test]
    fn lowercasing_normalises_mixed_case() {
        let out = validate_set(&["CW".into()]).unwrap();
        assert_eq!(out, vec!["cw"]);
    }

    #[test]
    fn too_many_tags_rejected() {
        let too_many: Vec<String> = (0..9).map(|i| format!("tag{i}")).collect();
        assert_eq!(validate_set(&too_many), Err(TagError::TooMany));
    }

    #[test]
    fn punctuation_rejected() {
        match validate_set(&["pota!".into()]) {
            Err(TagError::InvalidCharacter('!')) => {}
            other => panic!("wrong error: {other:?}"),
        }
    }

    #[test]
    fn too_short_rejected() {
        assert_eq!(validate_set(&["a".into()]), Err(TagError::TooShort));
    }
}
