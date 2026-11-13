//! Opaque rotating refresh tokens — Phase 5 OAuth overhaul (D4).
//!
//! Refresh tokens are high-entropy (~256-bit) opaque secrets stored only as a
//! SHA-256 hash. A fast hash is correct here: there is no offline-guessing
//! surface against 256 random bits, so argon2/salting buys nothing (security
//! review: confirmed sound). The plaintext is returned to the client once.
//!
//! Rotation, family chains, and reuse detection are DB-bound and live in
//! `db::auth`; this module is the pure crypto/format layer.
//!
//! Design: docs/plans/2026-06-21-phase5-oauth-overhaul.md (§5).

use rand::RngCore;
use sha2::{Digest, Sha256};
use subtle::ConstantTimeEq;

/// Prefix identifying a Carrier Wave refresh token (replaces the legacy `fd_`).
/// Makes secret-scanners and log filters trivial.
pub const REFRESH_PREFIX: &str = "cwr_";

/// Entropy in bytes for the random portion (256 bits).
const REFRESH_ENTROPY_BYTES: usize = 32;

/// Refresh-token sliding lifetime.
pub const REFRESH_TTL_DAYS: i64 = 60;

/// Absolute family lifetime — forces full re-auth/re-verification even with
/// continuous refreshing (F12).
pub const FAMILY_MAX_AGE_DAYS: i64 = 180;

/// Window in which re-presenting a just-rotated token returns its successor
/// instead of tripping reuse detection (F4 — avoids self-DoS from concurrent
/// or retried refreshes across app/widget/watch).
pub const ROTATION_GRACE_SECS: i64 = 60;

/// Generate a new opaque refresh token: `cwr_` + 64 hex chars.
pub fn generate_refresh_token() -> String {
    let mut bytes = [0u8; REFRESH_ENTROPY_BYTES];
    rand::thread_rng().fill_bytes(&mut bytes);
    format!("{}{}", REFRESH_PREFIX, hex::encode(bytes))
}

/// SHA-256 of the token plaintext, as raw bytes (stored in `token_hash BYTEA`).
pub fn hash_token(token: &str) -> Vec<u8> {
    let mut hasher = Sha256::new();
    hasher.update(token.as_bytes());
    hasher.finalize().to_vec()
}

/// Constant-time equality of two token hashes (defense-in-depth; lookups are by
/// hash, but any direct comparison must not leak via timing).
pub fn hashes_eq(a: &[u8], b: &[u8]) -> bool {
    a.ct_eq(b).unwrap_u8() == 1
}

/// Generate a high-entropy magic-link code: 32 hex chars (128 bits). Embedded
/// in the email link; stored only as a SHA-256 hash.
pub fn generate_verification_code() -> String {
    let mut bytes = [0u8; 16];
    rand::thread_rng().fill_bytes(&mut bytes);
    hex::encode(bytes)
}

/// Prefix identifying a Carrier Wave poll token (O4 polling return path).
pub const POLL_PREFIX: &str = "cwp_";

/// Generate an opaque poll token: `cwp_` + 64 hex chars (256 bits). Returned to
/// the app by verify/start; the app presents it (with its PKCE verifier) to
/// verify/poll. Stored only as a SHA-256 hash, like the refresh token.
pub fn generate_poll_token() -> String {
    let mut bytes = [0u8; REFRESH_ENTROPY_BYTES];
    rand::thread_rng().fill_bytes(&mut bytes);
    format!("{}{}", POLL_PREFIX, hex::encode(bytes))
}

/// PKCE challenge derivation (F8 device binding). We use an S256 variant with
/// hex output (not base64url) to avoid a base64 dependency — our app is the only
/// client, so the encoding is private to us. `challenge = hex(sha256(verifier))`.
pub fn pkce_challenge_for(verifier: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(verifier.as_bytes());
    hex::encode(hasher.finalize())
}

/// Constant-time check that `verifier` matches a stored `challenge`.
pub fn verify_pkce(verifier: &str, challenge: &str) -> bool {
    let computed = pkce_challenge_for(verifier);
    computed.as_bytes().ct_eq(challenge.as_bytes()).unwrap_u8() == 1
}

/// SHA-256 of a verification code (stored in `code_hash BYTEA`).
pub fn hash_code(code: &str) -> Vec<u8> {
    hash_token(code)
}

/// Cheap format check before a DB lookup.
pub fn looks_like_refresh(token: &str) -> bool {
    if let Some(suffix) = token.strip_prefix(REFRESH_PREFIX) {
        suffix.len() == REFRESH_ENTROPY_BYTES * 2 && suffix.bytes().all(|b| b.is_ascii_hexdigit())
    } else {
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generated_token_has_expected_shape() {
        let t = generate_refresh_token();
        assert!(t.starts_with(REFRESH_PREFIX));
        assert_eq!(t.len(), REFRESH_PREFIX.len() + REFRESH_ENTROPY_BYTES * 2);
        assert!(looks_like_refresh(&t));
    }

    #[test]
    fn tokens_are_unique() {
        assert_ne!(generate_refresh_token(), generate_refresh_token());
    }

    #[test]
    fn hash_is_stable_and_distinct() {
        let t = generate_refresh_token();
        assert_eq!(hash_token(&t), hash_token(&t));
        assert_ne!(hash_token(&t), hash_token(&generate_refresh_token()));
        assert_eq!(hash_token(&t).len(), 32);
    }

    #[test]
    fn constant_time_compare() {
        let a = hash_token("cwr_aaaa");
        let b = hash_token("cwr_aaaa");
        let c = hash_token("cwr_bbbb");
        assert!(hashes_eq(&a, &b));
        assert!(!hashes_eq(&a, &c));
    }

    #[test]
    fn pkce_roundtrip() {
        let verifier = "the-app-generated-this-random-verifier";
        let challenge = pkce_challenge_for(verifier);
        assert!(verify_pkce(verifier, &challenge));
        assert!(!verify_pkce("wrong-verifier", &challenge));
    }

    #[test]
    fn verification_code_is_high_entropy_hex() {
        let c = generate_verification_code();
        assert_eq!(c.len(), 32);
        assert!(c.bytes().all(|b| b.is_ascii_hexdigit()));
        assert_ne!(c, generate_verification_code());
    }

    #[test]
    fn format_check_rejects_junk() {
        assert!(!looks_like_refresh("fd_abc"));
        assert!(!looks_like_refresh("cwr_short"));
        assert!(!looks_like_refresh("cwr_zzzz")); // non-hex
        assert!(looks_like_refresh(&generate_refresh_token()));
    }
}
