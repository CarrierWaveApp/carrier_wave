//! Macro run-event telemetry helpers (CAR-271 T6).
//!
//! ## Privacy
//!
//! Run events store `device_hash`, never the raw `device_token`. The hash
//! rotates daily and per-slug — two devices that both ran "qsy-to-spot"
//! on the same day get the same `device_hash` (per-slug), but the same
//! device's runs across different slugs hash differently. This gives
//! aggregators a stable per-(slug, day) bucket without ever surfacing
//! individual device identities.
//!
//! ## Key rotation
//!
//! The HMAC key is `TELEMETRY_HMAC_KEY_<YYYY-MM-DD>`. Production should
//! prepend a per-install secret (via `MACROS_TELEMETRY_SECRET` env var)
//! so the hash is unguessable; the dev default is a fixed string so
//! tests can pin expected values.

use chrono::NaiveDate;
use hmac::{Hmac, Mac};
use sha2::Sha256;

type HmacSha256 = Hmac<Sha256>;

/// Daily+per-slug HMAC of a device token. Returns lowercase hex.
pub fn device_hash(date: NaiveDate, secret: &str, device_token: &str, slug: &str) -> String {
    let key = format!(
        "TELEMETRY_HMAC_KEY_{}_{}",
        date.format("%Y-%m-%d"),
        secret
    );
    let mut mac = HmacSha256::new_from_slice(key.as_bytes())
        .expect("HMAC-SHA256 accepts any key length");
    mac.update(format!("{device_token}:{slug}").as_bytes());
    hex::encode(mac.finalize().into_bytes())
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::NaiveDate;

    fn date() -> NaiveDate {
        NaiveDate::from_ymd_opt(2026, 5, 24).unwrap()
    }

    #[test]
    fn same_inputs_produce_same_hash() {
        let a = device_hash(date(), "secret", "token-1", "qsy-to-spot");
        let b = device_hash(date(), "secret", "token-1", "qsy-to-spot");
        assert_eq!(a, b);
        assert_eq!(a.len(), 64); // SHA-256 hex = 64 chars
    }

    #[test]
    fn different_slug_changes_hash() {
        let a = device_hash(date(), "secret", "token-1", "qsy-to-spot");
        let b = device_hash(date(), "secret", "token-1", "k3-tuner-cycle");
        assert_ne!(a, b);
    }

    #[test]
    fn different_day_changes_hash() {
        let a = device_hash(
            NaiveDate::from_ymd_opt(2026, 5, 24).unwrap(),
            "secret",
            "token-1",
            "qsy",
        );
        let b = device_hash(
            NaiveDate::from_ymd_opt(2026, 5, 25).unwrap(),
            "secret",
            "token-1",
            "qsy",
        );
        assert_ne!(a, b);
    }

    #[test]
    fn different_secret_changes_hash() {
        let a = device_hash(date(), "secret-a", "token-1", "qsy");
        let b = device_hash(date(), "secret-b", "token-1", "qsy");
        assert_ne!(a, b);
    }
}
