# cw-store passphrase recovery + never-delete

Date: 2026-07-08
Status: shipped (D1 + D2 built, verified, deployed to theseus)

## Shipped

- **D1 (device unblock):** `CwStoreProvider.isUnopenableStoreError/reset/
  moveOrphanedStoreAside` (never deletes), `CwStoreRecoveryService` (probe +
  rebuild-from-SwiftData), External Data recovery banner + "Rebuild from
  Logbook", app wires the service with the container.
- **D2 (offline passphrase recovery):** `cw_crypto::wrap_key_escrow` +
  `create_key_escrow` FFI (wrap the EXISTING at-rest key — normal open path
  unchanged, zero migration risk), `Store::rekey`/`FieldStore::rekey`,
  xcframework regenerated. Swift `CwStoreKeyRecovery` (provision on passphrase
  capture → App Group sidecar `cw-store.recovery.json`; offline `recover` via
  `open_sync_escrow` → restore key → reopen). Hooked into `SyncKeyService`
  create/unlock. `CwStoreRecoverySheet` passphrase UI, shown when a recovery
  blob exists. All Rust tests + clippy + iOS build clean.

Note: the design landed as "wrap the existing random key" (lower risk) rather
than "rekey to an escrow data key" — the store key never changes, so existing
working installs can't be orphaned by a migration. `rekey` shipped but is
reserved for a future passphrase-rotation-with-new-key path.

## Problem

The Rust `cw-store` (SQLCipher, App Group `cw-store.db`) at-rest key is a random,
device-local value in the Keychain (`KeychainHelper.Keys.cwStoreEncryptionKey`).
`CwStoreProvider.localEncryptionKey()` used `try?` on the Keychain read and, on
*any* failure other than "item not found" (notably `errSecInteractionNotAllowed`
on a locked / pre-first-unlock background launch), silently **regenerated and
overwrote** the key — permanently orphaning the existing store, which then fails
to open with SQLCipher `file is not a database`.

Only the External Data downloads (POTA/SOTA/WWFF/FCC/zones/equipment) surface the
error, because after the "rust move" (`de2a150c` / `a34a3e6c`) they are the one
data class with **no** local fallback — every other cw-store consumer uses `try?`
and silently falls back to SwiftData. So the app looks healthy while downloads
fail.

Today the cw-store at-rest key and the E2E **sync passphrase** data key
(`SyncKeyService`, Argon2id → wrapped key escrowed on the server) are entirely
independent. The documented cw-store recovery model is literally "regenerate +
re-seed from SwiftData" — i.e. destroy-and-rebuild.

## Decisions (confirmed with user, 2026-07-08)

1. **Never delete a DB.** An unopenable store is preserved (moved aside, never
   removed). Re-seeding a fresh store is **user-initiated only**, never automatic.
2. **Recovery-by-password requires a sync passphrase** (reused — no separate
   "database recovery passphrase"). Users without one keep the random device key
   and simply have no password recovery (the app still works via SwiftData
   fallback).
3. **`PRAGMA rekey` migration**: the first time the passphrase is captured and the
   store is openable on the legacy random key, rekey it in place to the escrow
   data key. No re-encrypt-by-copy, no delete.
4. **Recovery must work OFFLINE** (2026-07-08). The wrapped key blob + KDF
   params/salt are cached **locally** (App Group), so recovery never contacts the
   server. The server escrow (for cross-device sync) is an orthogonal extra copy,
   not a dependency of DB recovery.

Accepted limitation: **this device's already-orphaned file cannot be recovered
by passphrase** — its old random key is gone and was never passphrase-wrapped.
SwiftData still holds the log, so a user-initiated rebuild loses nothing, and the
orphaned file is preserved (not deleted) for the record.

## Key model (going forward)

The cw-store at-rest key is the **escrow data key** (a stable random 32-byte
value minted by `create_sync_escrow`), NOT a value derived live from the
passphrase — so passphrase rotation only re-wraps the blob, never rekeys the DB.

- **Passphrase captured** (user creates/enters the sync passphrase): mint escrow
  `{data_key, wrapped_key_b64, kdf_params_json}` locally; `rekey` the open store
  from the legacy random key to `data_key`; store `data_key` in the Keychain
  (fast offline launches); cache the wrapped blob + KDF params **locally in the
  App Group** (`cw-store.recovery.json` sidecar) for offline recovery.
- **No passphrase** → existing random `cwStoreEncryptionKey`, no recovery blob,
  no recovery (unchanged behaviour).

Normal launch reads the raw key from the Keychain (offline, no prompt). The
passphrase is the **recovery** path only. Never regenerate on a Keychain read
error (already fixed: `localEncryptionKey` only generates on
`KeychainError.itemNotFound` and propagates all other errors).

## Offline recovery flow

User enters the sync passphrase → `open_sync_escrow(passphrase,
wrapped_key_b64, kdf_params_json)` using the **locally cached** sidecar (no
network) → data key → `FieldStore.open(existing_path, data_key)`. On success,
restore the key to the Keychain. Reuses the reviewed `cw-crypto` escrow crypto;
no new server surface.

## Open / recovery flow (`CwStoreProvider`)

1. Resolve preferred key (escrowed if available, else random).
2. Open at canonical path.
3. On success: if opened on the random key but an escrowed key is now available →
   `rekey` to the escrowed key (migration #3); record which key family is in use.
4. On `file is not a database` (do **not** delete):
   - If an escrowed key exists and wasn't the one tried, retry open with it.
   - If still failing → mark state `needsRecovery`; FFI features run degraded
     (SwiftData fallback). Reference data stays unavailable until the user acts.
5. Recovery UI (Settings, OFFLINE): user re-enters the sync passphrase →
   `open_sync_escrow(passphrase, <local sidecar blob>)` → data key → open the
   preserved file. On success, adopt it (restore key to Keychain) — never deletes
   anything, never contacts the server.
6. Rebuild option (Settings, explicit): move the orphaned file aside
   (`cw-store.orphaned-<ts>.db`, rename — not delete), create a fresh store keyed
   with the escrowed-or-random key, reset `cwStoreImportCompletedVersion` so the
   SwiftData→cw-store seed re-runs.

## Work items

### Rust (cw-core) — additive, land ahead of Swift
- [x] `Store::rekey(&self, new_key)` → `PRAGMA rekey` (cw-store/src/lib.rs) + test
      (`rekey_reencrypts_in_place`; cargo test + clippy clean).
- [x] `FieldStore::rekey(new_key)` FFI export (cw-ffi/src/lib.rs; builds).
- [x] Escrow crypto is already exported and reusable offline:
      `create_sync_escrow` / `open_sync_escrow` (cw-ffi/sync_transport.rs, pure
      local Argon2id wrap/unwrap; server only stores the blob). No new Rust
      needed for the crypto.
- [ ] Open-failure classification so Swift can distinguish "not a database"
      (wrong key / corrupt) from other errors without brittle string matching —
      dedicated `CwError` variant or a `FieldStore::open_state(path,key)` probe.
- [ ] Regenerate the Apple xcframework (`build-xcframework.sh`) + Kotlin FFI
      (only needed for the new `rekey` export / any classifier).

### Swift (CarrierWaveData)
- [ ] `CwStoreProvider`: key resolver (escrow data key from Keychain vs legacy
      random), preserve-on-failure (never delete), rekey-on-passphrase-capture,
      `needsRecovery` state, recovery + rebuild entry points.
- [ ] Local recovery sidecar: write `{wrapped_key_b64, kdf_params_json}` to the
      App Group when the passphrase is captured; read it for OFFLINE
      `open_sync_escrow` recovery. Hook capture into `SyncKeyService`
      create/unlock (that's the only place the raw passphrase is known).
- [ ] Bookkeeping for which key family a given file uses (UserDefaults/kv), so we
      know when to rekey and which key recovery should try.

### iOS UI
- [ ] Settings "Database recovery" screen: shows `needsRecovery`, passphrase
      entry (reuses `SyncKeyService.unlock`), and an explicit "Rebuild from
      SwiftData" action. Wire into External Data error state.

### Done already (separate, shipped in this session)
- [x] `localEncryptionKey` hardening — stop silent key regeneration (root cause).
- [x] Equipment section download button + load-on-appear
      (`ExternalDataView+EquipmentSection.swift`).

## Notes
- Normal launches must stay offline/fast: read the derived key from the Keychain;
  the passphrase/escrow is the **recovery** path when the local key is missing or
  won't open the file, not a per-launch prompt.
- FFI regen requires a build; do it locally (see cw-ffi build-xcframework.sh).

## Hardening pass (2026-07-08) — holes found + closed

Closed in code:
1. **Provision could cache a useless envelope.** If the store was already
   orphaned when the user set a passphrase, `provision` wrapped the *stale*
   Keychain key. Now it first confirms `CwStoreProvider.store()` opens (the key
   is real) before wrapping.
2. **Rebuild left the live mirror inactive until relaunch** — QSOs logged in the
   gap hit SwiftData but never the fresh cw-store, and the seed marker meant they
   were never back-filled. Rebuild now posts `didRebuildNotification`; the app
   re-runs `applyQSOMirrorMode` to re-establish the follower live.
3. **`recover` persisted the key before proving it works.** Now it verifies with
   a throwaway `FieldStore.open` first, so the Keychain is never overwritten with
   a non-opening key.
4. **Brittle orphan detection.** `isUnopenableStoreError` now matches several
   SQLCipher/SQLite signatures (NOTADB, encrypted, malformed/corrupt), not one
   substring.
5. **Orphan archives** are uniquified on collision and marked
   `isExcludedFromBackup` (re-derivable dead weight; never delete but never bloat
   backups either).
6. **`rekey` crash-safety** documented (PRAGMA rekey is not crash-atomic); it
   stays unused (we wrap the existing key, never change it).

Open holes (NOT code-fixable now — guardrails / follow-ups):
- **Authority-flip time bomb.** Recovery is gated on a sync passphrase, and
  cw-store is only recoverable because SwiftData is still authoritative. BEFORE
  the [[sync-server]] Phase-7 authority flip, recovery must become guaranteed —
  require a passphrase (or a local recovery secret) and a valid envelope, or an
  orphaning becomes permanent QSO loss. Add a runtime guard that refuses to flip
  authority unless a verified recovery envelope exists.
- **Provisioning coverage gap.** Users who set a passphrase *before* this feature
  shipped have no envelope until they next create/unlock (we only hold the
  passphrase at those moments). A one-time "protect your database" nudge would
  close it.
- **Android has no recovery flow** — shared core is ready + proven; the
  provisioning/sidecar/UI are iOS-only.
