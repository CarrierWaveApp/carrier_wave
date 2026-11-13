//! Emits a browser test fixture: an escrow envelope + a sealed journal blob,
//! both produced by the real Rust seal path, so a browser can prove the WASM
//! `open_escrow` + `decrypt_blob` reverse them. Run: `cargo run --example gen_fixture`.

use base64::Engine as _;
use flate2::write::GzEncoder;
use flate2::Compression;
use std::io::Write as _;

fn main() {
    let passphrase = "test-passphrase-42";
    let (blob, data_key) = cw_crypto::create_escrow(passphrase).unwrap();

    // A minimal JournalPayload with two UpsertQso ops (camelCase, matching the
    // SyncQso wire shape the viewer parses).
    let payload = r#"{"id":"J-fixture","deviceId":"dev-1","timestamp":1720000000,"sequenceNumber":1,"operations":[{"op":"UpsertQso","id":"q1","callsign":"W1AW","band":"20m","mode":"FT8","frequency":14074.0,"timestamp":1719990000,"myCallsign":"W6JY","qrzConfirmed":false,"lotwConfirmed":false,"isHidden":false,"isActivityLogQSO":false,"importSource":"manual","notesUserAuthored":false},{"op":"UpsertQso","id":"q2","callsign":"K6ABC","band":"40m","mode":"CW","frequency":7030.0,"timestamp":1719995000,"myCallsign":"W6JY","qrzConfirmed":true,"lotwConfirmed":false,"isHidden":false,"isActivityLogQSO":false,"importSource":"manual","notesUserAuthored":false}]}"#;

    let mut enc = GzEncoder::new(Vec::new(), Compression::default());
    enc.write_all(payload.as_bytes()).unwrap();
    let gzipped = enc.finish().unwrap();
    let ciphertext = cw_crypto::aead::seal(&data_key, &gzipped);

    let b64 = base64::engine::general_purpose::STANDARD;
    let fixture = serde_json::json!({
        "passphrase": passphrase,
        "kdfParams": blob.kdf,
        "wrappedKey": b64.encode(&blob.wrapped_key),
        "ciphertextB64": b64.encode(&ciphertext),
        "expectedPayload": payload,
    });
    println!("{}", serde_json::to_string(&fixture).unwrap());
}
