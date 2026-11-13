//! WASM bindings over `cw-crypto` for the browser logbook viewer.
//!
//! The sync server is E2E-blind: it stores opaque ciphertext blobs and an
//! escrowed *wrapped* key. To display a user's logs in a browser we must do the
//! decryption client-side, and we reuse the exact Rust crypto so there is zero
//! risk of wire-format drift versus the iOS/Android clients.
//!
//! Two operations cross the WASM boundary:
//!
//! - [`open_escrow`] — recover the 32-byte data key from the passphrase and the
//!   escrow envelope (`GET /v1/sync/key` → `wrappedKey` + `kdfParams`).
//! - [`decrypt_blob`] — open a sealed journal blob and gunzip it back to the
//!   JSON of a `JournalPayload` (mirrors `HttpSyncTransport::pull`).
//!
//! Mirrors `cw-ffi/src/sync_transport.rs` (`sync_open_escrow`) and the
//! `decompress`/`aead::open` step in `cw-sync/src/http_transport.rs`.

use base64::Engine as _;
use wasm_bindgen::prelude::*;

mod logbook;
mod sdr;
pub use logbook::LogbookIndex;
pub use sdr::{
    kiwi_check_server_error, kiwi_parse_msg_value, kiwi_tune_command, parse_kiwi_directory,
    rank_receivers_near, KiwiAudioDecoder, KiwiFrameEvent,
};

/// gzip magic bytes — used to tell a compressed payload from legacy raw JSON.
const GZIP_MAGIC: [u8; 2] = [0x1f, 0x8b];

/// Recover the 32-byte data key from `passphrase` + the escrow envelope.
///
/// `kdf_params_json` is the JSON object stored under `kdfParams` by the server
/// (`{"salt":[..16..],"m_cost":..,"t_cost":..,"p_cost":..}`); `wrapped_key_b64`
/// is the base64 `wrappedKey`. Fails on a wrong passphrase (the wrapped key does
/// not authenticate under the derived KEK).
#[wasm_bindgen]
pub fn open_escrow(
    passphrase: &str,
    kdf_params_json: &str,
    wrapped_key_b64: &str,
) -> Result<Vec<u8>, JsError> {
    let kdf: cw_crypto::KdfParams = serde_json::from_str(kdf_params_json)
        .map_err(|e| JsError::new(&format!("bad kdfParams: {e}")))?;
    let wrapped_key = base64::engine::general_purpose::STANDARD
        .decode(wrapped_key_b64.as_bytes())
        .map_err(|e| JsError::new(&format!("bad wrappedKey base64: {e}")))?;
    let blob = cw_crypto::EscrowBlob { kdf, wrapped_key };
    let data_key = cw_crypto::open_escrow(passphrase, &blob)
        .map_err(|_| JsError::new("wrong passphrase"))?;
    Ok(data_key.to_vec())
}

/// Open a sealed journal blob and return the plaintext `JournalPayload` JSON.
///
/// `data_key` must be the 32 bytes from [`open_escrow`]; `ciphertext` is the raw
/// blob body downloaded from the presigned R2 URL. Decrypts with
/// ChaCha20Poly1305, then gunzips (legacy blobs are raw JSON with no gzip
/// header, so those pass through unchanged).
#[wasm_bindgen]
pub fn decrypt_blob(data_key: &[u8], ciphertext: &[u8]) -> Result<String, JsError> {
    let key: [u8; 32] = data_key
        .try_into()
        .map_err(|_| JsError::new("data key must be exactly 32 bytes"))?;
    let sealed = cw_crypto::aead::open(&key, ciphertext)
        .map_err(|_| JsError::new("decrypt failed (wrong key or tampered blob)"))?;
    let json = decompress(&sealed).map_err(|e| JsError::new(&e))?;
    String::from_utf8(json).map_err(|e| JsError::new(&format!("payload not UTF-8: {e}")))
}

/// Seal a plaintext `JournalPayload` JSON into a journal blob.
///
/// The inverse of [`decrypt_blob`]: gzip the JSON, then ChaCha20Poly1305-seal
/// it under `data_key`. The returned bytes are exactly what the presigned R2
/// upload URL expects. Mirrors the `compress`/`aead::seal` step in
/// `cw-sync/src/http_transport.rs::push`.
#[wasm_bindgen]
pub fn seal_blob(data_key: &[u8], payload_json: &str) -> Result<Vec<u8>, JsError> {
    let key: [u8; 32] = data_key
        .try_into()
        .map_err(|_| JsError::new("data key must be exactly 32 bytes"))?;
    let compressed = compress(payload_json.as_bytes()).map_err(|e| JsError::new(&e))?;
    Ok(cw_crypto::aead::seal(&key, &compressed))
}

/// gzip `json` before it's sealed. Matches `http_transport::compress`
/// (`flate2` default compression), so the ciphertext is byte-compatible with
/// what the iOS/Android clients produce.
fn compress(json: &[u8]) -> Result<Vec<u8>, String> {
    use std::io::Write as _;
    let mut encoder =
        flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
    encoder.write_all(json).map_err(|e| format!("gzip failed: {e}"))?;
    encoder.finish().map_err(|e| format!("gzip finish failed: {e}"))
}

/// Inverse of the client's gzip step. Legacy blobs are raw JSON (no gzip
/// header), so fall through to the bytes as-is when the magic isn't present.
fn decompress(plaintext: &[u8]) -> Result<Vec<u8>, String> {
    if !plaintext.starts_with(&GZIP_MAGIC) {
        return Ok(plaintext.to_vec());
    }
    use std::io::Read as _;
    let mut decoder = flate2::read::GzDecoder::new(plaintext);
    let mut out = Vec::new();
    decoder
        .read_to_end(&mut out)
        .map_err(|e| format!("gunzip failed: {e}"))?;
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use flate2::write::GzEncoder;
    use flate2::Compression;
    use std::io::Write as _;

    // Reproduce the client seal path (escrow → seal(gzip(json))) then prove the
    // WASM-exposed functions round-trip it back to the original JSON.
    #[test]
    fn escrow_then_decrypt_round_trips() {
        let passphrase = "correct horse battery staple";
        let (blob, data_key) = cw_crypto::create_escrow(passphrase).unwrap();

        let kdf_params_json = serde_json::to_string(&blob.kdf).unwrap();
        let wrapped_key_b64 =
            base64::engine::general_purpose::STANDARD.encode(&blob.wrapped_key);

        let recovered = open_escrow(passphrase, &kdf_params_json, &wrapped_key_b64).unwrap();
        assert_eq!(recovered, data_key.to_vec());

        let payload_json = r#"{"id":"J1","deviceId":"d","timestamp":1,"sequenceNumber":1,"operations":[]}"#;
        let mut enc = GzEncoder::new(Vec::new(), Compression::default());
        enc.write_all(payload_json.as_bytes()).unwrap();
        let gzipped = enc.finish().unwrap();
        let ciphertext = cw_crypto::aead::seal(&data_key, &gzipped);

        let out = decrypt_blob(&recovered, &ciphertext).unwrap();
        assert_eq!(out, payload_json);
    }

    // seal_blob is the inverse of decrypt_blob: sealing then decrypting must
    // return the original JSON, and the ciphertext must carry the gzip magic
    // once decrypted's outer AEAD layer is peeled — i.e. it round-trips through
    // the exact same path the pull side uses.
    #[test]
    fn seal_then_decrypt_round_trips() {
        let (_, data_key) = cw_crypto::create_escrow("pw").unwrap();
        let payload_json = r#"{"id":"J1","deviceId":"web","timestamp":9,"sequenceNumber":3,"operations":[{"op":"Delete","entity_type":"qso","id":"q9"}]}"#;
        let ciphertext = seal_blob(data_key.as_ref(), payload_json).unwrap();
        let out = decrypt_blob(data_key.as_ref(), &ciphertext).unwrap();
        assert_eq!(out, payload_json);
    }

    // Asserts on the underlying primitive rather than the wasm wrapper: building
    // a `JsError` (the wrapper's Err type) panics on non-wasm test targets, so we
    // verify the delegation target directly. The wrapper only maps its error.
    #[test]
    fn wrong_passphrase_is_rejected() {
        let (blob, _) = cw_crypto::create_escrow("right").unwrap();
        assert!(cw_crypto::open_escrow("wrong", &blob).is_err());
    }
}
