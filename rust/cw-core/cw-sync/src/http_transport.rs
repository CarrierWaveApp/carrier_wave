//! Production [`SyncTransport`] talking to the E2E-blind Rust sync server.
//!
//! The server is a dumb append-only journal: it stores opaque ciphertext blobs
//! in object storage and only ever sees plaintext metadata (tenant, seq, type,
//! op, size, hash). All encryption happens here, on the client:
//!
//! - **push:** serialize each [`JournalPayload`] → JSON → seal under the local
//!   data key → POST the metadata (incl. content hash + byte size) to
//!   `/v1/sync/push`, then HTTP PUT the ciphertext to each returned presigned
//!   `uploadUrl`.
//! - **pull:** GET `/v1/sync/changes?since=` → for each change, GET the
//!   presigned `downloadUrl` → open (decrypt) the ciphertext → deserialize back
//!   into a [`JournalPayload`], oldest-first.
//!
//! The [`SyncTransport`] trait is synchronous (Swift/Kotlin and the journal
//! engine depend on that shape), but `reqwest` is async, so this type owns a
//! multi-thread Tokio runtime and bridges via `block_on`. The host owns the
//! credentials: both the `bearer` token and the 32-byte `data_key` are passed
//! in at construction and never fetched here.

use std::collections::HashMap;

use base64::Engine as _;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::error::SyncError;
use crate::journal::{JournalEntityType, JournalPayload};
use cw_net::http::{HttpClient, HttpError};

/// HTTPS sync transport. Encrypts locally, uploads ciphertext, downloads and
/// decrypts on pull. See the module docs for the wire flow.
pub struct HttpSyncTransport {
    http: HttpClient,
    base_url: String,
    bearer: String,
    data_key: [u8; 32],
    rt: tokio::runtime::Runtime,
    /// Highest server sequence seen from a push or pull response — the cursor
    /// the host persists so the next pull only fetches genuinely newer entries.
    last_high_water: i64,
}

/// Blob downloads in flight at once during a pull.
const PULL_CONCURRENCY: usize = 8;

impl HttpSyncTransport {
    /// Build a transport against `base_url` (e.g. `https://sync.example.app`),
    /// carrying `bearer` on every request and sealing/opening blobs under
    /// `data_key`. Spins up the multi-thread runtime used to drive `reqwest`.
    pub fn new(
        base_url: impl Into<String>,
        bearer: impl Into<String>,
        data_key: [u8; 32],
    ) -> Result<Self, SyncError> {
        let rt = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .map_err(|e| SyncError::Network(e.to_string()))?;
        let http = HttpClient::new().map_err(|e| SyncError::Network(e.to_string()))?;
        Ok(Self {
            http,
            base_url: base_url.into(),
            bearer: bearer.into(),
            data_key,
            rt,
            last_high_water: 0,
        })
    }

    /// The highest server sequence observed so far (0 until the first response).
    pub fn high_water(&self) -> i64 {
        self.last_high_water
    }

    fn url(&self, path: &str) -> String {
        format!("{}{}", self.base_url.trim_end_matches('/'), path)
    }
}

// ---- Wire types (client side) --------------------------------------------
//
// Mirror the server's `models/sync.rs` (camelCase). We only model the fields
// this transport produces or consumes; serde ignores any extras the server
// adds, so download/upload metadata we don't use is simply dropped.

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct PushEntryReq {
    client_entry_id: String,
    entity_type: String,
    op: String,
    byte_size: i64,
    content_hash: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct PushReq {
    entries: Vec<PushEntryReq>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PushedEntryResp {
    client_entry_id: String,
    upload_url: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PushResp {
    entries: Vec<PushedEntryResp>,
    high_water: i64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ChangeItemResp {
    seq: i64,
    download_url: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ChangesResp {
    entries: Vec<ChangeItemResp>,
    high_water: i64,
}

/// Map any displayable error (HTTP, IO, crypto) into `SyncError::Network`.
fn net_err<E: std::fmt::Display>(e: E) -> SyncError {
    SyncError::Network(e.to_string())
}

/// Statuses worth retrying: rate limiting (the API sits behind a per-IP
/// governor, CAR-143, and a seed upload shares that bucket with the app's
/// other traffic) and transient server errors.
fn is_transient(status: u16) -> bool {
    status == 429 || (500..=599).contains(&status)
}

/// Retry budget for one logical request. Delays double from
/// [`RETRY_BASE_DELAY`]: 600ms → 1.2s → 2.4s (~4.2s worst case), comfortably
/// past the governor's 10 req/s refill.
const RETRY_ATTEMPTS: u32 = 4;
const RETRY_BASE_DELAY: std::time::Duration = std::time::Duration::from_millis(600);

/// Run `op` (a closure that builds a fresh request future each call) up to
/// [`RETRY_ATTEMPTS`] times, backing off on 429/5xx. Safe for every call this
/// transport makes: push is idempotent server-side (`client_entry_id` dedup),
/// blob PUTs overwrite the same key, and pulls are read-only.
async fn with_retry<T, F, Fut>(op: F) -> Result<T, HttpError>
where
    F: Fn() -> Fut,
    Fut: std::future::Future<Output = Result<T, HttpError>>,
{
    let mut delay = RETRY_BASE_DELAY;
    for attempt in 1..=RETRY_ATTEMPTS {
        match op().await {
            Err(HttpError::Http { status, .. }) if is_transient(status) && attempt < RETRY_ATTEMPTS => {
                tokio::time::sleep(delay).await;
                delay *= 2;
            }
            other => return other,
        }
    }
    unreachable!("the final attempt always returns")
}

/// Server `entityType` string for a payload — the camelCase tag the journal
/// enum already serializes to (e.g. `qso`). Falls back to `"qso"`.
fn entity_type_str(ty: JournalEntityType) -> String {
    serde_json::to_value(ty)
        .ok()
        .and_then(|v| v.as_str().map(str::to_string))
        .unwrap_or_else(|| "qso".to_string())
}

/// Base64 of the SHA-256 digest of `bytes` — the server stores this opaquely.
fn content_hash(bytes: &[u8]) -> String {
    let digest = Sha256::digest(bytes);
    base64::engine::general_purpose::STANDARD.encode(digest)
}

/// gzip magic bytes — used to tell a compressed payload from legacy raw JSON.
const GZIP_MAGIC: [u8; 2] = [0x1f, 0x8b];

/// Compress `json` with gzip before it's encrypted. QSO JSON is highly
/// compressible (repeated field names + similar values), typically 5-10x,
/// which is the dominant lever for upload speed on large logs.
fn compress(json: &[u8]) -> Result<Vec<u8>, SyncError> {
    use std::io::Write as _;
    let mut encoder = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
    encoder.write_all(json).map_err(|e| SyncError::Network(e.to_string()))?;
    encoder.finish().map_err(|e| SyncError::Network(e.to_string()))
}

/// Inverse of [`compress`]. Legacy blobs are raw JSON (no gzip header), so fall
/// through to the bytes as-is when the gzip magic isn't present.
fn decompress(plaintext: &[u8]) -> Result<Vec<u8>, SyncError> {
    if !plaintext.starts_with(&GZIP_MAGIC) {
        return Ok(plaintext.to_vec());
    }
    use std::io::Read as _;
    let mut decoder = flate2::read::GzDecoder::new(plaintext);
    let mut out = Vec::new();
    decoder.read_to_end(&mut out).map_err(|e| SyncError::Network(e.to_string()))?;
    Ok(out)
}

impl super::transport::SyncTransport for HttpSyncTransport {
    fn push(&mut self, payloads: &[JournalPayload]) -> Result<(), SyncError> {
        if payloads.is_empty() {
            return Ok(());
        }

        // Seal every payload up front; key the ciphertexts by client_entry_id so
        // we can PUT the matching bytes to each presigned URL the server hands back.
        let mut ciphertexts: HashMap<String, Vec<u8>> = HashMap::with_capacity(payloads.len());
        let mut entries: Vec<PushEntryReq> = Vec::with_capacity(payloads.len());
        for payload in payloads {
            let json = serde_json::to_vec(payload)?;
            let compressed = compress(&json)?;
            let ciphertext = cw_crypto::aead::seal(&self.data_key, &compressed);
            let entity_type = payload
                .operations
                .first()
                .and_then(|op| op.entity_type())
                .map(entity_type_str)
                .unwrap_or_else(|| "qso".to_string());
            entries.push(PushEntryReq {
                client_entry_id: payload.id.clone(),
                entity_type,
                op: "upsert".to_string(),
                byte_size: ciphertext.len() as i64,
                content_hash: content_hash(&ciphertext),
            });
            ciphertexts.insert(payload.id.clone(), ciphertext);
        }

        let req = PushReq { entries };
        let url = self.url("/v1/sync/push");
        let http = self.http.clone();
        let bearer = self.bearer.clone();
        let high_water = self.rt.block_on(async move {
            let resp: PushResp = with_retry(|| http.post_json(&url, &req, Some(&bearer)))
                .await
                .map_err(net_err)?;
            let high_water = resp.high_water;
            for entry in resp.entries {
                if let Some(ciphertext) = ciphertexts.get(&entry.client_entry_id) {
                    with_retry(|| {
                        let request = http.inner().put(&entry.upload_url).body(ciphertext.clone());
                        http.send_bytes(request)
                    })
                    .await
                    .map_err(net_err)?;
                }
            }
            Ok::<i64, SyncError>(high_water)
        })?;
        self.last_high_water = self.last_high_water.max(high_water);
        Ok(())
    }

    fn pull(&mut self, since_sequence: i64) -> Result<Vec<JournalPayload>, SyncError> {
        let url = self.url(&format!("/v1/sync/changes?since={}", since_sequence));
        let http = self.http.clone();
        let bearer = self.bearer.clone();
        let data_key = self.data_key;
        let (out, high_water) = self.rt.block_on(async move {
            let bytes = with_retry(|| http.send_bytes(http.inner().get(&url).bearer_auth(&bearer)))
                .await
                .map_err(net_err)?;
            let changes: ChangesResp = serde_json::from_slice(&bytes)?;
            let high_water = changes.high_water;

            let mut items = changes.entries;
            items.sort_by_key(|item| item.seq);

            // Fetch + open the blobs a few at a time instead of one round trip
            // after another: a first pull replays the whole journal, and each
            // entry is a separate object-store GET. Order is restored by seq
            // below, so apply order is unchanged.
            let mut out: Vec<(i64, JournalPayload)> = Vec::with_capacity(items.len());
            for chunk in items.chunks(PULL_CONCURRENCY) {
                let mut tasks = tokio::task::JoinSet::new();
                for item in chunk {
                    let http = http.clone();
                    let url = item.download_url.clone();
                    let seq = item.seq;
                    tasks.spawn(async move {
                        let ciphertext = with_retry(|| http.send_bytes(http.inner().get(&url)))
                            .await
                            .map_err(net_err)?;
                        // A failed open is a key mismatch, not a transport fault —
                        // surface it as such so hosts can prompt for the passphrase.
                        let sealed = cw_crypto::aead::open(&data_key, &ciphertext)
                            .map_err(|_| SyncError::KeyMismatch)?;
                        let plaintext = decompress(&sealed)?;
                        let payload: JournalPayload = serde_json::from_slice(&plaintext)?;
                        Ok::<(i64, JournalPayload), SyncError>((seq, payload))
                    });
                }
                while let Some(joined) = tasks.join_next().await {
                    let fetched = joined.map_err(|e| SyncError::Network(e.to_string()))??;
                    out.push(fetched);
                }
            }
            out.sort_by_key(|(seq, _)| *seq);
            let out: Vec<JournalPayload> = out.into_iter().map(|(_, payload)| payload).collect();
            Ok::<(Vec<JournalPayload>, i64), SyncError>((out, high_water))
        })?;
        self.last_high_water = self.last_high_water.max(high_water);
        Ok(out)
    }
}

// ---- Escrow key blob (PUT/GET /v1/sync/key) -------------------------------

/// Escrow envelope exchanged on `PUT/GET /v1/sync/key` — mirrors the server's
/// `KeyBlob` model (camelCase). `kdf_params` rides as opaque JSON: the client
/// round-trips whatever `cw_crypto::escrow` serialized.
#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct KeyBlobWire {
    wrapped_key: String,
    kdf_params: serde_json::Value,
}

/// Store the passphrase-escrow envelope server-side (`PUT /v1/sync/key`).
/// Escrow traffic can't hang off [`HttpSyncTransport`] — that requires the
/// 32-byte data key at construction, which is exactly what a fresh device is
/// trying to recover — so these are standalone, key-less calls.
pub fn put_key_blob(
    base_url: &str,
    bearer: &str,
    wrapped_key_b64: &str,
    kdf_params_json: &str,
) -> Result<(), SyncError> {
    let kdf_params: serde_json::Value = serde_json::from_str(kdf_params_json)?;
    let body = KeyBlobWire {
        wrapped_key: wrapped_key_b64.to_string(),
        kdf_params,
    };
    let url = key_url(base_url);
    let rt = key_runtime()?;
    let http = HttpClient::new().map_err(net_err)?;
    rt.block_on(async move {
        let request = http.inner().put(&url).bearer_auth(bearer).json(&body);
        http.send_bytes(request).await.map_err(net_err)?;
        Ok(())
    })
}

/// Fetch the escrow envelope (`GET /v1/sync/key`) as
/// `(wrapped_key_b64, kdf_params_json)`, or `Ok(None)` when the tenant has
/// never stored one (server 404) — the "first device, create a fresh escrow"
/// signal.
pub fn get_key_blob(base_url: &str, bearer: &str) -> Result<Option<(String, String)>, SyncError> {
    let url = key_url(base_url);
    let rt = key_runtime()?;
    let http = HttpClient::new().map_err(net_err)?;
    rt.block_on(async move {
        let request = http.inner().get(&url).bearer_auth(bearer);
        match http.send_bytes(request).await {
            Ok(bytes) => {
                let blob: KeyBlobWire = serde_json::from_slice(&bytes)?;
                let kdf_params_json = serde_json::to_string(&blob.kdf_params)?;
                Ok(Some((blob.wrapped_key, kdf_params_json)))
            }
            Err(cw_net::http::HttpError::Http { status: 404, .. }) => Ok(None),
            Err(e) => Err(net_err(e)),
        }
    })
}

fn key_url(base_url: &str) -> String {
    format!("{}/v1/sync/key", base_url.trim_end_matches('/'))
}

fn key_runtime() -> Result<tokio::runtime::Runtime, SyncError> {
    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .map_err(|e| SyncError::Network(e.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::conflict::SyncQso;
    use crate::journal::JournalOperation;
    use crate::transport::SyncTransport;
    use wiremock::matchers::{method, path};
    use wiremock::{Mock, MockServer, ResponseTemplate};

    const CALLSIGN: &str = "W6JY";
    const CLIENT_ENTRY_ID: &str = "11111111-1111-1111-1111-111111111111";

    fn sample_payload() -> JournalPayload {
        let qso = SyncQso {
            id: "qso-1".into(),
            callsign: CALLSIGN.into(),
            band: "20m".into(),
            mode: "CW".into(),
            frequency: Some(14_050.0),
            timestamp: 1_000,
            my_grid: None,
            their_grid: None,
            park_reference: None,
            notes: None,
            imported_at: None,
            modified_at: Some(1_000),
            qrz_confirmed: false,
            lotw_confirmed: false,
            is_hidden: false,
            ..Default::default()
        };
        JournalPayload::new(
            CLIENT_ENTRY_ID,
            "device-1",
            1_700,
            1,
            vec![JournalOperation::upsert_qso(qso)],
        )
    }

    fn contains_subslice(haystack: &[u8], needle: &[u8]) -> bool {
        !needle.is_empty() && haystack.windows(needle.len()).any(|w| w == needle)
    }

    // wiremock needs a Tokio reactor for the mock server, while HttpSyncTransport
    // owns its OWN runtime and calls block_on. block_on panics if invoked from
    // within a running runtime, so we drive the (sync) transport on a dedicated
    // std::thread, leaving the test's #[tokio::test] runtime free for the server.
    #[tokio::test]
    async fn push_encrypts_then_pull_round_trips() {
        let server = MockServer::start().await;
        let key = cw_crypto::aead::random_data_key();
        let payload = sample_payload();

        let push_body = serde_json::json!({
            "entries": [{
                "clientEntryId": CLIENT_ENTRY_ID,
                "seq": 1,
                "blobKey": "tenant/entries/1.bin",
                "uploadUrl": format!("{}/blob/1", server.uri()),
            }],
            "highWater": 1,
        });
        Mock::given(method("POST"))
            .and(path("/v1/sync/push"))
            .respond_with(ResponseTemplate::new(200).set_body_json(push_body))
            .mount(&server)
            .await;
        Mock::given(method("PUT"))
            .and(path("/blob/1"))
            .respond_with(ResponseTemplate::new(200))
            .mount(&server)
            .await;

        // --- push (on its own thread; owns its runtime) ---
        let base = server.uri();
        let payload_for_push = payload.clone();
        let push_handle = std::thread::spawn(move || {
            let mut transport = HttpSyncTransport::new(base, "test-token", key).unwrap();
            transport.push(&[payload_for_push]).unwrap();
        });
        push_handle.join().unwrap();

        // Inspect what actually went over the wire.
        let requests = server.received_requests().await.unwrap();
        let put_req = requests
            .iter()
            .find(|r| r.method == wiremock::http::Method::PUT && r.url.path() == "/blob/1")
            .expect("ciphertext was PUT to the blob endpoint");
        let ciphertext = put_req.body.clone();

        // THE non-negotiable assertion: the plaintext callsign never appears on
        // the wire — not in the uploaded blob, not in the push metadata body.
        assert!(!ciphertext.is_empty(), "uploaded blob must not be empty");
        assert!(
            !contains_subslice(&ciphertext, CALLSIGN.as_bytes()),
            "uploaded blob must be ciphertext, not plaintext callsign"
        );

        let push_req = requests
            .iter()
            .find(|r| r.method == wiremock::http::Method::POST && r.url.path() == "/v1/sync/push")
            .expect("push metadata was posted");
        let push_text = String::from_utf8_lossy(&push_req.body);
        assert!(
            push_text.contains("contentHash"),
            "push body must carry a contentHash"
        );
        assert!(
            !push_text.contains(CALLSIGN),
            "push metadata must not leak the plaintext callsign"
        );

        // --- pull: serve the captured ciphertext back as the download blob ---
        Mock::given(method("GET"))
            .and(path("/blob/1"))
            .respond_with(ResponseTemplate::new(200).set_body_bytes(ciphertext.clone()))
            .mount(&server)
            .await;
        let changes_body = serde_json::json!({
            "entries": [{
                "seq": 1,
                "entityType": "qso",
                "op": "upsert",
                "blobKey": "tenant/entries/1.bin",
                "byteSize": ciphertext.len(),
                "contentHash": content_hash(&ciphertext),
                "downloadUrl": format!("{}/blob/1", server.uri()),
            }],
            "snapshotSeq": serde_json::Value::Null,
            "snapshotUrl": serde_json::Value::Null,
            "highWater": 1,
        });
        Mock::given(method("GET"))
            .and(path("/v1/sync/changes"))
            .respond_with(ResponseTemplate::new(200).set_body_json(changes_body))
            .mount(&server)
            .await;

        let base = server.uri();
        let pull_handle = std::thread::spawn(move || {
            let mut transport = HttpSyncTransport::new(base, "test-token", key).unwrap();
            transport.pull(0).unwrap()
        });
        let pulled = pull_handle.join().unwrap();

        assert_eq!(pulled.len(), 1, "exactly one payload should come back");
        assert_eq!(
            pulled[0], payload,
            "decrypted payload must equal the original"
        );
    }

    // Same threading rule as above: put/get_key_blob own their runtime, so they
    // run on a dedicated std::thread while wiremock uses the test runtime.
    #[tokio::test]
    async fn key_blob_round_trips_and_missing_is_none() {
        let server = MockServer::start().await;

        // No escrow stored yet → 404 → None. Scoped so the 200 GET below can
        // replace it; the guard must stay alive while the request runs.
        let missing_guard = Mock::given(method("GET"))
            .and(path("/v1/sync/key"))
            .respond_with(ResponseTemplate::new(404))
            .expect(1)
            .mount_as_scoped(&server)
            .await;
        let base = server.uri();
        let missing = std::thread::spawn(move || get_key_blob(&base, "test-token").unwrap())
            .join()
            .unwrap();
        assert!(missing.is_none(), "404 must map to None, not an error");
        drop(missing_guard);

        // PUT accepts the envelope; GET then serves it back verbatim.
        Mock::given(method("PUT"))
            .and(path("/v1/sync/key"))
            .respond_with(ResponseTemplate::new(204))
            .mount(&server)
            .await;
        let stored_body = serde_json::json!({
            "wrappedKey": "d3JhcHBlZA==",
            "kdfParams": {"salt": "c2FsdA==", "mCost": 65536, "tCost": 3},
        });
        Mock::given(method("GET"))
            .and(path("/v1/sync/key"))
            .respond_with(ResponseTemplate::new(200).set_body_json(stored_body))
            .mount(&server)
            .await;

        let base = server.uri();
        let round_trip = std::thread::spawn(move || {
            put_key_blob(
                &base,
                "test-token",
                "d3JhcHBlZA==",
                r#"{"salt":"c2FsdA==","mCost":65536,"tCost":3}"#,
            )
            .unwrap();
            get_key_blob(&base, "test-token").unwrap()
        })
        .join()
        .unwrap();

        let (wrapped, kdf_json) = round_trip.expect("stored envelope must come back");
        assert_eq!(wrapped, "d3JhcHBlZA==");
        let kdf: serde_json::Value = serde_json::from_str(&kdf_json).unwrap();
        assert_eq!(kdf["mCost"], 65536, "kdf params must round-trip as JSON");

        // The PUT body must be the camelCase KeyBlob shape the server expects.
        let requests = server.received_requests().await.unwrap();
        let put_req = requests
            .iter()
            .find(|r| r.method == wiremock::http::Method::PUT && r.url.path() == "/v1/sync/key")
            .expect("envelope was PUT to the key endpoint");
        let put_text = String::from_utf8_lossy(&put_req.body);
        assert!(put_text.contains("wrappedKey"), "camelCase wrappedKey");
        assert!(put_text.contains("kdfParams"), "camelCase kdfParams");
    }

    // The per-IP governor (CAR-143) 429s bursts; one rate-limited response must
    // pause and retry, not abort the whole sync pass.
    #[tokio::test]
    async fn push_retries_past_a_429() {
        let server = MockServer::start().await;
        let key = cw_crypto::aead::random_data_key();

        // First POST is rate-limited; the mock expires after one use and the
        // fallback 200 below takes over for the retry.
        Mock::given(method("POST"))
            .and(path("/v1/sync/push"))
            .respond_with(ResponseTemplate::new(429))
            .up_to_n_times(1)
            .with_priority(1)
            .mount(&server)
            .await;
        let push_body = serde_json::json!({
            "entries": [{
                "clientEntryId": CLIENT_ENTRY_ID,
                "seq": 1,
                "blobKey": "tenant/entries/1.bin",
                "uploadUrl": format!("{}/blob/1", server.uri()),
            }],
            "highWater": 1,
        });
        Mock::given(method("POST"))
            .and(path("/v1/sync/push"))
            .respond_with(ResponseTemplate::new(200).set_body_json(push_body))
            .with_priority(5)
            .mount(&server)
            .await;
        Mock::given(method("PUT"))
            .and(path("/blob/1"))
            .respond_with(ResponseTemplate::new(200))
            .mount(&server)
            .await;

        let base = server.uri();
        let payload = sample_payload();
        std::thread::spawn(move || {
            let mut transport = HttpSyncTransport::new(base, "test-token", key).unwrap();
            transport.push(&[payload]).expect("push must survive one 429");
        })
        .join()
        .unwrap();

        let posts = server
            .received_requests()
            .await
            .unwrap()
            .iter()
            .filter(|r| r.method == wiremock::http::Method::POST && r.url.path() == "/v1/sync/push")
            .count();
        assert_eq!(posts, 2, "the 429'd POST must be retried exactly once");
    }

    // Ciphertext the local key can't open is a key mismatch (stale key after an
    // escrow change / server switch), NOT a network error — hosts key their
    // "re-enter your passphrase" prompt off this variant.
    #[tokio::test]
    async fn pull_with_wrong_key_is_key_mismatch() {
        let server = MockServer::start().await;
        let their_key = cw_crypto::aead::random_data_key();
        let our_key = cw_crypto::aead::random_data_key();
        let ciphertext = cw_crypto::aead::seal(&their_key, b"sealed under a different key");

        let changes_body = serde_json::json!({
            "entries": [{
                "seq": 1,
                "entityType": "qso",
                "op": "upsert",
                "blobKey": "tenant/entries/1.bin",
                "byteSize": ciphertext.len(),
                "contentHash": content_hash(&ciphertext),
                "downloadUrl": format!("{}/blob/1", server.uri()),
            }],
            "snapshotSeq": serde_json::Value::Null,
            "snapshotUrl": serde_json::Value::Null,
            "highWater": 1,
        });
        Mock::given(method("GET"))
            .and(path("/v1/sync/changes"))
            .respond_with(ResponseTemplate::new(200).set_body_json(changes_body))
            .mount(&server)
            .await;
        Mock::given(method("GET"))
            .and(path("/blob/1"))
            .respond_with(ResponseTemplate::new(200).set_body_bytes(ciphertext))
            .mount(&server)
            .await;

        let base = server.uri();
        let err = std::thread::spawn(move || {
            let mut transport = HttpSyncTransport::new(base, "test-token", our_key).unwrap();
            transport.pull(0).expect_err("wrong key must fail the pull")
        })
        .join()
        .unwrap();
        assert!(
            matches!(err, SyncError::KeyMismatch),
            "expected KeyMismatch, got: {err}"
        );
    }
}
