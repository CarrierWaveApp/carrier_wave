# Logbook Web Viewer (E2E sync server) — Plan

Date: 2026-07-01
Status: In progress

## Goal

A standalone, user-facing web app to browse the logs a user has stored on the
new E2E-blind sync server. Read-only QSO table with search/filter and ADIF
export. Because the server is E2E-blind, **all decryption happens in the
browser** — the web app reuses the exact Rust crypto (`cw-crypto`) compiled to
WASM so there is zero risk of wire-format drift.

## Locked decisions (from user)

1. **Decryption:** in-browser via WASM, reusing `cw-crypto` (Argon2id +
   ChaCha20Poly1305). No JS crypto reimplementation.
2. **Home:** a new standalone web app, but **served same-origin by the Rust
   activities-server** (like the existing admin SPA at `web/dist`). Same-origin
   ⇒ no API CORS needed.
3. **Login:** full email magic-link + PKCE, reusing the iOS account flow
   (`/v1/auth/verify/start` → poll `/v1/auth/verify/poll` → JWT access+refresh).
4. **v1 scope:** QSO table + search/filter + ADIF export.

## Architecture recap (verified in code)

- Blob wire shape: `ChaCha20Poly1305_seal(data_key, gzip(JSON(JournalPayload)))`.
  `JournalPayload` = `{ id, deviceId, timestamp, sequenceNumber, operations[] }`;
  each op is `UpsertQso(SyncQso)` or `Delete{entityType,id}`.
- Data key recovery: `GET /v1/sync/key` → `{ wrappedKey(base64), kdfParams }`
  → `open_escrow(passphrase, {kdf, wrappedKey})` (Argon2id KEK → unwrap).
- Blob listing: `GET /v1/sync/bootstrap` → `{ snapshotUrl?, snapshotSeq?,
  entries[], highWater }`; each entry has a presigned R2 `downloadUrl`.
  Incremental: `GET /v1/sync/changes?since=`.
- Blob bytes are fetched **cross-origin from Cloudflare R2** via presigned GET.
- Auth: `/v1/sync/*` behind `require_auth`, accepts Phase-5 OAuth JWT.

## Hard external dependency (NOT code)

**Cloudflare R2 `cwlogs` bucket needs a CORS policy** allowing browser `GET`
(and `OPTIONS` preflight) from the web app origin, exposing whatever headers the
presigned GET returns. Without it, every blob download fails in the browser.
Track as an infra task (ansible/terraform or manual R2 dashboard).

## Build steps

### 1. WASM crypto crate — `rust/cw-core/cw-web-crypto`  (foundational)
- New `cdylib` crate, `wasm-bindgen`, depends on `cw-crypto` + `base64` +
  `flate2` (gzip) + `serde_json`.
- Exports:
  - `open_escrow(passphrase: &str, kdf_params_json: &str, wrapped_key_b64: &str)
    -> Result<Uint8Array(32)>` — Argon2id + unwrap ⇒ raw data key.
  - `decrypt_blob(data_key: &[u8], ciphertext: &[u8]) -> Result<String>` —
    `aead::open` + gunzip ⇒ JSON string of a `JournalPayload`.
- `getrandom` with `js` feature (links even though decrypt path draws no RNG).
- NOT added to the cw-core workspace `members` (wasm cdylib + host build differ);
  standalone crate built with `wasm-pack build --target web`.
- Toolchain: `rustup target add wasm32-unknown-unknown`; install `wasm-pack`.
- Gate: `wasm-pack build` succeeds; a tiny Rust unit test round-trips
  escrow→decrypt against a known blob before trusting the JS side.

### 2. Frontend app — `server/logbook-web/`  (Vite + React + TS + Tailwind)
Mirror the existing `server/web` stack (React 18, react-router, Tailwind).
- **Auth (`src/auth/`):** PKCE (S256, WebCrypto) → `verify/start` → poll
  `verify/poll` → store access+refresh (sessionStorage). Refresh on 401.
- **Sync client (`src/sync/`):** `getKey()`, `bootstrap()`, fetch each
  `downloadUrl` (R2), `decrypt_blob` via WASM, JSON.parse → fold operations
  (upserts + deletes, last-writer-wins by `modifiedAt`) into a QSO map.
- **Passphrase gate:** modal to enter the sync passphrase; runs `open_escrow`;
  hold data key in memory only (never persisted).
- **Table (`src/pages/Logbook.tsx`):** sortable columns (time, call, band, mode,
  freq, RST, grid, park). Search by callsign; filter band/mode/date range.
- **ADIF export:** build ADIF from `SyncQso` fields client-side; download blob.
- Vite `base: '/logbook/'`, dev proxy `/v1` → localhost:8080.

### 3. Server static route
- Add `ServeDir::new("logbook-web/dist")` nested/served at `/logbook`
  (alongside the existing `web/dist` fallback + `/contests`), with SPA
  fallback to `logbook-web/dist/index.html`.
- Update `server/Dockerfile` to build+include `logbook-web/dist`.

### 4. Infra
- R2 CORS policy for the web origin (see dependency above).
- Note in `project_sync-server` memory + activities-server release notes.

## Risks / open items

- **R2 CORS** is the top risk — verify with a real presigned GET from the
  browser early (before building the whole UI).
- **Snapshot format**: RESOLVED — the client `HttpSyncTransport` does not
  implement snapshot upload (snapshot isn't in the `SyncTransport` trait), so no
  snapshots are written today and `/changes?since=0` returns the full journal.
  v1 uses the changes-only path; handle a non-null `snapshotUrl` defensively
  (surface an error rather than silently drop state).
- Wire-parity: WASM reuses the Rust decode, but `SyncQso` camelCase field names
  must match what the table/ADIF exporter reads. Derive from `conflict.rs`.
</content>
</invoke>
