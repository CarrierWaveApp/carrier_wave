use thiserror::Error;

#[derive(Debug, Error)]
pub enum SyncError {
    #[error("serialization error: {0}")]
    Serde(#[from] serde_json::Error),

    #[error("transport error: {0}")]
    Transport(String),

    #[error("network: {0}")]
    Network(String),

    /// Pulled ciphertext that the local data key can't open. Not a network
    /// problem: the device's key doesn't match the key that encrypted the
    /// account's data (e.g. the escrow was recreated on another device, or
    /// this device still holds a key recovered from a different server).
    #[error(
        "sync key mismatch: this device's encryption key can't decrypt the \
         account's sync data — re-enter your sync passphrase"
    )]
    KeyMismatch,
}
