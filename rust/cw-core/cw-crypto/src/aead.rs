//! ChaCha20Poly1305 AEAD seal/open plus key wrap/unwrap.
//!
//! Sealed blobs are self-describing: `nonce(12) || ciphertext||tag`. A fresh
//! random nonce is drawn from the OS CSPRNG on every [`seal`] call, so the same
//! plaintext encrypts to a different blob each time. Key wrapping is just
//! sealing a 32-byte data key under the KEK.

use chacha20poly1305::aead::{Aead, KeyInit};
use chacha20poly1305::{ChaCha20Poly1305, Key, Nonce};
use rand::rngs::OsRng;
use rand::RngCore;
use zeroize::Zeroize;

use crate::CryptoError;

/// ChaCha20Poly1305 nonce length in bytes.
const NONCE_LEN: usize = 12;
/// Data-key / KEK length in bytes.
const KEY_LEN: usize = 32;

/// Seal `plaintext` under `key`, returning `nonce(12) || ciphertext||tag`.
pub fn seal(key: &[u8; 32], plaintext: &[u8]) -> Vec<u8> {
    let cipher = ChaCha20Poly1305::new(Key::from_slice(key));
    let mut nonce_bytes = [0u8; NONCE_LEN];
    OsRng.fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);
    // Encryption only fails on >256GiB payloads; treat as unreachable for our blobs.
    let ciphertext = cipher
        .encrypt(nonce, plaintext)
        .expect("ChaCha20Poly1305 encryption cannot fail for in-memory payloads");
    let mut out = Vec::with_capacity(NONCE_LEN + ciphertext.len());
    out.extend_from_slice(&nonce_bytes);
    out.extend_from_slice(&ciphertext);
    out
}

/// Open a blob produced by [`seal`]. Fails on truncation, wrong key, or tampering.
pub fn open(key: &[u8; 32], blob: &[u8]) -> Result<Vec<u8>, CryptoError> {
    if blob.len() < NONCE_LEN {
        return Err(CryptoError::Format);
    }
    let (nonce_bytes, ciphertext) = blob.split_at(NONCE_LEN);
    let cipher = ChaCha20Poly1305::new(Key::from_slice(key));
    let nonce = Nonce::from_slice(nonce_bytes);
    cipher.decrypt(nonce, ciphertext).map_err(|_| CryptoError::Aead)
}

/// Wrap a 32-byte data key under the KEK (= `seal(kek, data_key)`).
pub fn wrap_key(kek: &[u8; 32], data_key: &[u8; 32]) -> Vec<u8> {
    seal(kek, data_key)
}

/// Unwrap a data key wrapped by [`wrap_key`]. Fails if the KEK is wrong or the
/// recovered plaintext is not exactly 32 bytes.
pub fn unwrap_key(kek: &[u8; 32], wrapped: &[u8]) -> Result<[u8; 32], CryptoError> {
    let mut plain = open(kek, wrapped)?;
    if plain.len() != KEY_LEN {
        plain.zeroize();
        return Err(CryptoError::Format);
    }
    let mut key = [0u8; KEY_LEN];
    key.copy_from_slice(&plain);
    plain.zeroize();
    Ok(key)
}

/// Generate a fresh random 32-byte data key from the OS CSPRNG.
pub fn random_data_key() -> [u8; 32] {
    let mut key = [0u8; KEY_LEN];
    OsRng.fill_bytes(&mut key);
    key
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn seal_open_round_trips() {
        let key = random_data_key();
        let pt = b"the quick brown fox W6JY";
        let blob = seal(&key, pt);
        assert_ne!(&blob[..], &pt[..], "blob must be ciphertext, not plaintext");
        assert_eq!(open(&key, &blob).unwrap(), pt);
    }

    #[test]
    fn tampered_blob_fails_open() {
        let key = random_data_key();
        let mut blob = seal(&key, b"hello");
        let last = blob.len() - 1;
        blob[last] ^= 0xff;
        assert!(open(&key, &blob).is_err());
    }

    #[test]
    fn short_blob_fails_open() {
        let key = random_data_key();
        assert!(open(&key, &[0u8; 4]).is_err());
    }

    #[test]
    fn wrap_unwrap_round_trips() {
        let kek = random_data_key();
        let data_key = random_data_key();
        let wrapped = wrap_key(&kek, &data_key);
        assert_eq!(unwrap_key(&kek, &wrapped).unwrap(), data_key);
    }

    #[test]
    fn wrong_kek_fails_unwrap() {
        let kek = random_data_key();
        let other = random_data_key();
        let data_key = random_data_key();
        let wrapped = wrap_key(&kek, &data_key);
        assert!(unwrap_key(&other, &wrapped).is_err());
    }
}
