//! Passphrase-escrow envelope — the wire shape for `sync_key_blob`.
//!
//! The per-tenant data key is random and never derived from the passphrase
//! directly. Instead we derive a KEK from the passphrase (Argon2id) and wrap
//! the data key under it. The resulting [`EscrowBlob`] (KDF params + wrapped
//! key) is what the server stores; recovering the data key requires the
//! passphrase. Rotating the passphrase re-wraps the same data key.

use serde::{Deserialize, Serialize};

use crate::aead::{random_data_key, unwrap_key, wrap_key};
use crate::kdf::{derive_kek, random_params, KdfParams};
use crate::CryptoError;

/// Serializable escrow envelope: the KDF params and the wrapped data key.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EscrowBlob {
    pub kdf: KdfParams,
    pub wrapped_key: Vec<u8>,
}

/// Generate a fresh random data key, derive a KEK from `passphrase`, and wrap
/// the data key. Returns the escrow blob (to persist) plus the live data key
/// (to hold in the platform keychain).
pub fn create_escrow(passphrase: &str) -> Result<(EscrowBlob, [u8; 32]), CryptoError> {
    let kdf = random_params();
    let kek = derive_kek(passphrase, &kdf)?;
    let data_key = random_data_key();
    let wrapped_key = wrap_key(&kek, &data_key);
    Ok((EscrowBlob { kdf, wrapped_key }, data_key))
}

/// Wrap an EXISTING 32-byte key under a passphrase-derived KEK, rather than
/// minting a fresh one. Used to make an already-provisioned at-rest key
/// (e.g. the cw-store SQLCipher key) recoverable by passphrase *without
/// changing the key* — the blob is cached locally so recovery is offline.
/// Recover with [`open_escrow`], which returns the same 32 bytes.
pub fn wrap_key_escrow(passphrase: &str, key: &[u8; 32]) -> Result<EscrowBlob, CryptoError> {
    let kdf = random_params();
    let kek = derive_kek(passphrase, &kdf)?;
    let wrapped_key = wrap_key(&kek, key);
    Ok(EscrowBlob { kdf, wrapped_key })
}

/// Recover the data key from an [`EscrowBlob`] using `passphrase`. Fails if the
/// passphrase is wrong (KEK does not authenticate the wrapped key).
pub fn open_escrow(passphrase: &str, blob: &EscrowBlob) -> Result<[u8; 32], CryptoError> {
    let kek = derive_kek(passphrase, &blob.kdf)?;
    unwrap_key(&kek, &blob.wrapped_key)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn escrow_round_trips_with_passphrase() {
        let (blob, data_key) = create_escrow("correct horse").unwrap();
        let recovered = open_escrow("correct horse", &blob).unwrap();
        assert_eq!(recovered, data_key);
    }

    #[test]
    fn wrong_passphrase_fails() {
        let (blob, _) = create_escrow("correct horse").unwrap();
        assert!(open_escrow("battery staple", &blob).is_err());
    }

    #[test]
    fn wrap_existing_key_round_trips() {
        let key = [7u8; 32];
        let blob = wrap_key_escrow("hunter2", &key).unwrap();
        assert_eq!(open_escrow("hunter2", &blob).unwrap(), key);
        assert!(open_escrow("wrong", &blob).is_err());
    }

    #[test]
    fn escrow_blob_serde_round_trips() {
        let (blob, _) = create_escrow("pw").unwrap();
        let json = serde_json::to_string(&blob).unwrap();
        let back: EscrowBlob = serde_json::from_str(&json).unwrap();
        assert_eq!(back, blob);
    }
}
