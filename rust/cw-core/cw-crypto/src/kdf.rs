//! Argon2id passphrase key-derivation.
//!
//! Derives a 32-byte key-encryption key (KEK) from a user passphrase. The KEK
//! is only ever used to wrap/unwrap the random per-tenant data key (see
//! [`crate::escrow`]); it never directly encrypts journal payloads.

use argon2::{Algorithm, Argon2, Params, Version};
use rand::rngs::OsRng;
use rand::RngCore;
use serde::{Deserialize, Serialize};

use crate::CryptoError;

/// OWASP-recommended Argon2id memory cost (KiB).
const DEFAULT_M_COST: u32 = 19_456;
/// OWASP-recommended Argon2id iteration count.
const DEFAULT_T_COST: u32 = 2;
/// OWASP-recommended Argon2id parallelism.
const DEFAULT_P_COST: u32 = 1;
/// Derived key length in bytes.
const KEY_LEN: usize = 32;

/// Tunable Argon2id parameters plus the per-escrow salt.
///
/// Serializable so it can travel inside the escrow envelope and be persisted
/// server-side as opaque metadata.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KdfParams {
    pub salt: [u8; 16],
    pub m_cost: u32,
    pub t_cost: u32,
    pub p_cost: u32,
}

impl Default for KdfParams {
    fn default() -> Self {
        Self {
            salt: [0u8; 16],
            m_cost: DEFAULT_M_COST,
            t_cost: DEFAULT_T_COST,
            p_cost: DEFAULT_P_COST,
        }
    }
}

/// Build a fresh [`KdfParams`] with OWASP defaults and a random 16-byte salt.
pub fn random_params() -> KdfParams {
    let mut salt = [0u8; 16];
    OsRng.fill_bytes(&mut salt);
    KdfParams { salt, ..Default::default() }
}

/// Derive the 32-byte KEK from `passphrase` under `params`.
///
/// Deterministic for a given `(passphrase, params)` pair; changing the salt (or
/// any cost) yields an unrelated key.
pub fn derive_kek(passphrase: &str, params: &KdfParams) -> Result<[u8; 32], CryptoError> {
    let argon_params = Params::new(params.m_cost, params.t_cost, params.p_cost, Some(KEY_LEN))
        .map_err(|e| CryptoError::Kdf(e.to_string()))?;
    let argon = Argon2::new(Algorithm::Argon2id, Version::V0x13, argon_params);
    let mut out = [0u8; KEY_LEN];
    argon
        .hash_password_into(passphrase.as_bytes(), &params.salt, &mut out)
        .map_err(|e| CryptoError::Kdf(e.to_string()))?;
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn kek_is_deterministic_and_salt_sensitive() {
        let p1 = KdfParams { salt: [1u8; 16], ..Default::default() };
        let p2 = KdfParams { salt: [2u8; 16], ..Default::default() };
        assert_eq!(derive_kek("pw", &p1).unwrap(), derive_kek("pw", &p1).unwrap());
        assert_ne!(derive_kek("pw", &p1).unwrap(), derive_kek("pw", &p2).unwrap());
    }

    #[test]
    fn random_params_uses_owasp_defaults_and_random_salt() {
        let a = random_params();
        let b = random_params();
        assert_eq!(a.m_cost, DEFAULT_M_COST);
        assert_eq!(a.t_cost, DEFAULT_T_COST);
        assert_eq!(a.p_cost, DEFAULT_P_COST);
        assert_ne!(a.salt, b.salt, "salts should be random");
    }
}
