//! `cw-crypto` — Carrier Wave client-side end-to-end crypto primitives.
//!
//! Pure, deterministic, infra-free building blocks for the E2E sync layer:
//! an Argon2id passphrase KDF, ChaCha20Poly1305 AEAD seal/open, key
//! wrap/unwrap, and a passphrase-escrow envelope. The server never sees any
//! of this — it only ever stores the opaque ciphertext these functions emit.

pub mod aead;
mod error;
pub mod escrow;
mod kdf;

pub use error::CryptoError;
pub use escrow::{create_escrow, open_escrow, EscrowBlob};
pub use kdf::{derive_kek, random_params, KdfParams};
