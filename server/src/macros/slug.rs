//! Macro slug validation (CAR-271 T4).
//!
//! Rules from the design spec (`docs/superpowers/specs/2026-05-23-radio-macros-design.md`,
//! "Slug rules"):
//!
//! - Slugs are permanent — once a slug exists in `macros`, it never returns
//!   to free pool, even after withdrawal/tombstoning. Enforcement is at the
//!   DB level via the slug-conflict bump in `db::macros::upsert_macro`.
//! - Lowercase ASCII letters, digits, and `-` only. Max 64 chars. Not
//!   empty. No leading/trailing/repeated `-`.
//! - **Reserved prefixes** — `admin-`, `system-`, `carrier-wave-`, `cw-`
//!   reject non-admin submissions.
//! - **Callsign-shaped slugs** — slugs that look like a callsign after
//!   upper-casing (loose `[A-Z]{1,2}\d{1,4}[A-Z]{1,4}` pattern, with an
//!   optional `/portable` suffix) require the author's verified callsign
//!   to match. Phase 1 enforces this at admin sync time; Phase 2 will
//!   validate against the authenticated user's account.

const RESERVED_PREFIXES: &[&str] = &["admin-", "system-", "carrier-wave-", "cw-"];
const MAX_LEN: usize = 64;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SlugError {
    Empty,
    TooLong,
    InvalidCharacter(char),
    LeadingHyphen,
    TrailingHyphen,
    DoubleHyphen,
    ReservedPrefix(&'static str),
    /// The slug looks like a callsign but the author's `author_callsign`
    /// doesn't match it (case-insensitively). Phase 1 admins must edit
    /// the `.cwmacro` to either use a non-callsign slug or set the
    /// matching callsign.
    CallsignMismatch {
        slug: String,
        author: Option<String>,
    },
}

impl std::fmt::Display for SlugError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Empty => write!(f, "slug is empty"),
            Self::TooLong => write!(f, "slug exceeds {MAX_LEN} characters"),
            Self::InvalidCharacter(c) => write!(f, "slug contains invalid character `{c}`"),
            Self::LeadingHyphen => write!(f, "slug must not start with `-`"),
            Self::TrailingHyphen => write!(f, "slug must not end with `-`"),
            Self::DoubleHyphen => write!(f, "slug must not contain `--`"),
            Self::ReservedPrefix(p) => write!(f, "slug uses reserved prefix `{p}`"),
            Self::CallsignMismatch { slug, author } => write!(
                f,
                "callsign-shaped slug `{slug}` requires author_callsign to match; got {author:?}"
            ),
        }
    }
}

impl std::error::Error for SlugError {}

/// Phase 1 admin sync entry point. Verifies character/length rules and the
/// callsign-shape constraint against `author_callsign`. Reserved-prefix
/// rejection is bypassed when `allow_reserved_prefix` is true (e.g. for
/// admin-authored seed macros that *do* use a reserved prefix on purpose).
pub fn validate(
    slug: &str,
    author_callsign: Option<&str>,
    allow_reserved_prefix: bool,
) -> Result<(), SlugError> {
    validate_charset(slug)?;
    if !allow_reserved_prefix {
        if let Some(prefix) = RESERVED_PREFIXES.iter().find(|p| slug.starts_with(*p)) {
            return Err(SlugError::ReservedPrefix(prefix));
        }
    }
    if let Some(callsign_form) = callsign_shape(slug) {
        let matches = author_callsign
            .map(|c| c.trim().eq_ignore_ascii_case(&callsign_form))
            .unwrap_or(false);
        if !matches {
            return Err(SlugError::CallsignMismatch {
                slug: slug.to_string(),
                author: author_callsign.map(str::to_string),
            });
        }
    }
    Ok(())
}

fn validate_charset(slug: &str) -> Result<(), SlugError> {
    if slug.is_empty() {
        return Err(SlugError::Empty);
    }
    if slug.len() > MAX_LEN {
        return Err(SlugError::TooLong);
    }
    if slug.starts_with('-') {
        return Err(SlugError::LeadingHyphen);
    }
    if slug.ends_with('-') {
        return Err(SlugError::TrailingHyphen);
    }
    if slug.contains("--") {
        return Err(SlugError::DoubleHyphen);
    }
    for c in slug.chars() {
        if !(c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-') {
            return Err(SlugError::InvalidCharacter(c));
        }
    }
    Ok(())
}

/// Returns the upper-cased canonical form of `slug` if (and only if) it
/// looks like an amateur callsign — `[A-Z]{1,2}\d{1,4}[A-Z]{1,4}` with an
/// optional `/portable` suffix. The upper form is what the author's
/// `author_callsign` must match against.
fn callsign_shape(slug: &str) -> Option<String> {
    let upper = slug.to_ascii_uppercase();
    // Split off optional /PORTABLE suffix.
    let (core, _suffix) = match upper.split_once('/') {
        Some((core, suffix)) => (core, Some(suffix)),
        None => (upper.as_str(), None),
    };
    if !looks_like_callsign(core) {
        return None;
    }
    Some(upper)
}

fn looks_like_callsign(core: &str) -> bool {
    // Pattern: 1-2 letters, 1-4 digits, 1-4 letters.
    let bytes = core.as_bytes();
    if bytes.is_empty() {
        return false;
    }
    let mut i = 0;
    let mut letters = 0;
    while i < bytes.len() && bytes[i].is_ascii_uppercase() && letters < 2 {
        letters += 1;
        i += 1;
    }
    if letters == 0 {
        return false;
    }
    let mut digits = 0;
    while i < bytes.len() && bytes[i].is_ascii_digit() && digits < 4 {
        digits += 1;
        i += 1;
    }
    if digits == 0 {
        return false;
    }
    let mut suffix_letters = 0;
    while i < bytes.len() && bytes[i].is_ascii_uppercase() && suffix_letters < 4 {
        suffix_letters += 1;
        i += 1;
    }
    if suffix_letters == 0 {
        return false;
    }
    i == bytes.len()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn happy_path() {
        validate("qsy-to-spot", None, false).unwrap();
        validate("ic705-gps-quick-tx", None, false).unwrap();
    }

    #[test]
    fn empty_rejected() {
        assert_eq!(validate("", None, false), Err(SlugError::Empty));
    }

    #[test]
    fn uppercase_rejected() {
        match validate("QSY-Hunter", None, false).unwrap_err() {
            SlugError::InvalidCharacter('Q') => {}
            other => panic!("wrong error: {other:?}"),
        }
    }

    #[test]
    fn double_hyphen_rejected() {
        assert_eq!(validate("a--b", None, false), Err(SlugError::DoubleHyphen));
    }

    #[test]
    fn leading_hyphen_rejected() {
        assert_eq!(validate("-x", None, false), Err(SlugError::LeadingHyphen));
    }

    #[test]
    fn too_long_rejected() {
        let s = "a".repeat(65);
        assert_eq!(validate(&s, None, false), Err(SlugError::TooLong));
    }

    #[test]
    fn reserved_prefix_blocked_for_non_admins() {
        assert!(matches!(
            validate("admin-something", None, false),
            Err(SlugError::ReservedPrefix("admin-"))
        ));
    }

    #[test]
    fn reserved_prefix_allowed_for_admin_sync() {
        // Admin seed macros may use reserved prefixes intentionally.
        validate("cw-default-cq", None, true).unwrap();
    }

    #[test]
    fn callsign_shape_requires_matching_author() {
        // No author_callsign — reject.
        assert!(matches!(
            validate("w6jy", None, false),
            Err(SlugError::CallsignMismatch { .. })
        ));
        // Matching author — accept.
        validate("w6jy", Some("W6JY"), false).unwrap();
        // Mismatched author — reject.
        assert!(matches!(
            validate("w6jy", Some("K2ABC"), false),
            Err(SlugError::CallsignMismatch { .. })
        ));
    }

    #[test]
    fn callsign_with_portable_suffix() {
        validate("w6jy-portable", Some("W6JY/PORTABLE"), false).unwrap_or_else(|e| {
            panic!("expected portable suffix to be accepted, got {e:?}")
        });
    }

    #[test]
    fn non_callsign_shapes_unaffected() {
        // "qsy-cq" looks like a callsign for "QSY"? Q-S-Y doesn't match
        // <letters><digits><letters>, so it's not callsign-shaped.
        validate("qsy", None, false).unwrap();
        validate("pota-hunter", None, false).unwrap();
    }
}
