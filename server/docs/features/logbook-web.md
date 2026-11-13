# Logbook Web Viewer

A browser viewer for the logs a user has stored on the E2E-blind sync server.
Served same-origin by activities-server at **`/logbook`**. All decryption happens
**in the browser** — the server stays blind. Source: `server/logbook-web/`.

## How it works

1. **Login** — email magic-link + PKCE, the same account flow the iOS app uses
   (`/v1/auth/verify/start` → poll `/v1/auth/verify/poll` → JWT access+refresh).
2. **Unlock** — `GET /v1/sync/key` returns the passphrase-escrow envelope. The
   user enters their sync passphrase; the WASM module (`cw-web-crypto`, compiled
   from the same Rust `cw-crypto` the apps use) runs Argon2id + unwraps the
   32-byte data key. The passphrase and key never leave the tab's memory.
3. **Load** — `GET /v1/sync/bootstrap` lists journal entries with presigned R2
   download URLs. The browser downloads each blob, `ChaCha20Poly1305`-decrypts +
   gunzips it (WASM), parses the `JournalPayload`, and folds upserts/deletes (in
   server-sequence order) into the current set of QSOs.
4. **View** — sortable/filterable, **paginated** QSO table (100/page) + ADIF
   export, all client-side.
5. **Deduplicate (writes back)** — the one non-read-only surface. "Find
   duplicates" scans the log for repeated call/band/mode within a time window
   and soft-deletes the ones the user confirms by pushing `Delete` journal
   entries back to the sync server (see *Deduplication* below).

## WASM crypto module

`rust/cw-core/cw-web-crypto` — a `wasm-bindgen` crate over `cw-crypto` exposing
`open_escrow`, `decrypt_blob`, and `seal_blob` (the encrypt inverse used by the
dedupe delete writer: gzip → `ChaCha20Poly1305` seal, byte-compatible with the
apps' `cw-sync` push). It is its **own** cargo workspace (not part of
`cw-core`) because it enables getrandom's `js` feature, which only builds for
wasm32. Rebuild with:

```bash
cd rust/cw-core/cw-web-crypto
wasm-pack build --target web --out-dir pkg
cp -R pkg/* ../../../server/logbook-web/vendor/cw-web-crypto/   # re-vendor
```

The built `pkg` is vendored into `server/logbook-web/vendor/cw-web-crypto` (and
committed) so the frontend's `file:` dependency resolves offline in CI/Docker.

## REQUIRED: Cloudflare R2 CORS policy

Blob bytes are fetched **cross-origin** from the R2 `cwlogs` bucket via presigned
GET URLs. Without a bucket CORS policy the browser blocks reading every blob and
the viewer shows a "blob download failed … CORS" error. The **dedupe delete**
feature additionally **PUTs** ciphertext to presigned upload URLs, so the policy
must allow `PUT` too, or deletes fail in-browser with a CORS error. Set on the
bucket:

```json
[
  {
    "AllowedOrigins": [
      "https://activities.carrierwave.app",
      "https://staging.carrierwave.app",
      "http://localhost:5173"
    ],
    "AllowedMethods": ["GET", "PUT"],
    "AllowedHeaders": ["*"],
    "MaxAgeSeconds": 3600
  }
]
```

The origin is the **activities-server host** (which serves `/logbook` same-origin)
— prod `activities.carrierwave.app` and staging `staging.carrierwave.app`, per
`infra/ansible/roles/activities_server{,_staging}/defaults/main.yml`. Scheme+host
only (no path, no trailing slash). Apply via the Cloudflare dashboard (R2 → cwlogs
→ Settings → CORS Policy) or the S3 API (`PutBucketCors`). Staging and prod share
the `cwlogs` bucket, so include both. `http://localhost:5173` is only for local
`vite dev` — drop it if you don't want a dev origin on the prod bucket.

## Deduplication (the write-back path)

The viewer is read-only **except** for duplicate deletion. "Find duplicates"
(`components/DedupePane.tsx`) scans the decrypted log with
`logbook/dedupe.ts::findDuplicateGroups`: QSOs are grouped by
callsign + band + mode, then clustered when consecutive timestamps fall within
the window (default **±15 min**, user-adjustable). Each cluster keeps one QSO —
the *keeper*, chosen by confirmed-status → completeness → earliest time — and
pre-selects the rest for deletion. A group always keeps ≥1 QSO.

Confirming a deletion calls `sync/writeClient.ts::pushDeletes`, which mirrors the
Rust client's push exactly:

- Build `JournalPayload`(s) of `Delete` ops (≤100 ops/entry). **Wire keys are
  snake_case** (`device_id`, `sequence_number`, and the tagged
  `{op:"Delete",entity_type:"qso",id}`) because the Rust `JournalPayload` /
  `JournalOperation` have no `serde(rename_all)`. Getting these wrong makes the
  apps fail to deserialize the blob on pull; `cw-sync`'s
  `browser_delete_wire_json_deserializes` test guards the contract.
- Seal each payload (`sealBlob` = gzip + AEAD), `POST /v1/sync/push` with
  `{clientEntryId, entityType:"qso", op:"upsert", byteSize, contentHash}`
  (`contentHash` = **base64**(SHA-256(ciphertext))), then **PUT** each ciphertext
  to the returned presigned R2 URL (needs the `PUT` CORS rule above).
- The entry id is a content-addressed UUIDv5 over the ops, so a retry after a
  partial upload re-uses the same id (the server dedups on `client_entry_id`).
- The browser mints its own persisted `device_id` (`web-<uuid>`) + sequence in
  `localStorage`; neither is used on inbound replay, so it can't collide with a
  real device.

Deletes are **soft** (`is_hidden = true`) on every client — nothing is hard
removed — and the viewer already filters hidden QSOs out. Deleted rows are
dropped from the in-memory set optimistically so the table updates without a
reload.

## Spots page + KiwiSDR listening

`/logbook` (route `/spots`, login required, no data key needed) shows the active
spots from **`GET /v1/spots`** — same-origin, since the activities server both
owns that endpoint and serves this app — refreshing every 60 s. Each spot has a
**Listen** button that streams live audio from a nearby public KiwiSDR.

All protocol logic is the shared Rust (`cw-domain::kiwisdr`) compiled into
`cw-web-crypto` (`src/sdr.rs`): `KiwiAudioDecoder` (IMA ADPCM + SND frame
parsing + stream-text classification, including `audio_adpcm_state` resets and
the `too_busy=0`-is-not-a-disconnect rule), handshake helpers, the
mode/passband `tune_command`, directory parsing, and `find_nearby` ranking. The
browser owns only the transport (JS WebSocket) and playback (AudioWorklet ring
buffer; the AudioContext is opened at the receiver's sample rate, with a linear
resample fallback when the browser clamps it).

Because the directory, receiver status, and the receiver websocket are all
unreachable from a browser (CORS / mixed content), the server proxies them:

- `GET /v1/websdr/directory` — Skywavelinux `kiwisdr_com.js`, fetched
  server-side, cached in memory ~1 h, returned as the **raw JS text** (the
  browser parses it with the shared WASM parser).
- `GET /v1/websdr/status?host=&port=` — one `/status` probe, 5 s timeout.
- `GET /v1/websdr/stream?host=&port=` — transparent WebSocket byte bridge to
  `ws://host:port/{unix_ts}/SND`; the browser speaks the KiwiSDR protocol
  through it (auth → sample-rate wait → `SET AR OK`/ident/compression → tune →
  AGC → 5 s keepalives).

Targets are SSRF-validated (`handlers/websdr.rs`): hostname syntax, a sane-port
allowlist (80/443/≥1024), and DNS resolution must yield only public unicast
addresses (loopback/private/link-local/CGNAT/documentation/reserved ranges are
refused; IPv6 literals rejected).

Receivers are ranked near the **spotter's Maidenhead grid** (spots carry no
station coordinates), within 2 000 km, availability flagged; gridless spots get
the unranked directory head. One listen session at a time.

## Local development

```bash
cd server/logbook-web
npm install
npm run dev        # http://localhost:5173/logbook, proxies /v1 → localhost:8080
```

Run activities-server locally (`cargo run`) for the API; R2 CORS must include the
dev origin for blob downloads to work.

## Deployment

Built into the release tarball (`logbook-web/dist`) by
`.github/workflows/release-server.yml` and copied into the Docker image. Ansible
unarchives it alongside `web/dist`; the server serves it from its working dir.
No new ansible variables. **The R2 CORS policy is the only manual step.**
