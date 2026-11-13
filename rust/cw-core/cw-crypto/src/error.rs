use thiserror::Error;

/// Errors surfaced by the client-side E2E crypto primitives.
#[derive(Debug, Error)]
pub enum CryptoError {
    /// Key-derivation failure (bad params, hashing error).
    #[error("kdf error: {0}")]
    Kdf(String),

    /// AEAD seal/open failure (decryption/authentication failed).
    #[error("aead error")]
    Aead,

    /// Malformed input (blob too short, bad wrapped-key length, etc.).
    #[error("format error")]
    Format,
}
