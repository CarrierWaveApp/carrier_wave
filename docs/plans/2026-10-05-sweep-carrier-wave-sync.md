# CW Sweep: replace iCloud sync with Carrier Wave Sync

Date: 2026-10-05. Status: Phases 0–3 implemented 2026-10-05; live round trip pending.

## Goal

CW Sweep syncs QSOs, logging sessions, session spots and synced config through the
E2E Carrier Wave sync server (`/v1/sync/*`, `sync_run_once` via cw-ffi) instead of
CloudKit. The Rust store (cw-store) becomes Sweep's canonical data store, as it is
on iOS. The CKSyncEngine path is removed from Sweep. iOS behavior is unchanged.

Decisions taken with the user on 2026-10-05:

1. Rust store canonical (`CwStoreQSOMode == .on` on macOS), not a SwiftData reflector.
2. iCloud sync removed from Sweep entirely, not kept behind the seam.
3. Account sign-in by porting the magic-link OAuth flow (Rust `AuthApi`) to Sweep.

## Where things stand

- Server sync already works on iOS and Android. The runner (`sync_run_once`) needs
  a `FieldStore`, base URL, OAuth bearer, 32-byte data key, and the pull cursor.
  The journal carries `Qso`, `LoggingSession`, `SessionSpot`, `SyncedConfig`.
- All of the iOS plumbing is in iOS-only files: `OAuthClient` (124 lines, Rust
  `AuthApi` + PKCE magic link, polls until clicked, no deep link required),
  `ActivitiesClient` (base URL, `syncAuthToken`), `ActivitiesClient+SyncKey`
  (escrow PUT/GET), `SyncKeyService` + `+Background` (enrollment, per-server key
  in Keychain `sync.data.key.<base>`, per-server cursor and seeded flag, escrow
  fingerprint validation, one pass), `SyncProfile`, `ServerSnapshotCoordinator`,
  `SyncPassphraseView`, `KeychainSecureStore`. UIKit use is incidental
  (`UIDevice.current.name`, `import UIKit`).
- Rust-authority write seams are iOS-only too: `SeamWriteBatch` (+ registry) on
  the main actor and `OffMainStoreSeam` for background contexts. Both write
  cw-store first under `.on`, then one mirror-suppressed SwiftData save.
- Sweep: SwiftData canonical, `applyCwStoreMirrorMode` is a no-op (mode `.off`),
  no account session (`MacrosRegistryHolder.authTokenProvider` returns nil),
  `CloudSyncService` is a CKSyncEngine mirror of the old iOS service with ten
  consumers (status bar, indicator, content-area status view, settings tab,
  command palette, vim palette, app, workspace, data tab).
- Sweep SwiftData surface: 18 files read QSO/LoggingSession/SessionSpot via
  `FetchDescriptor`; 11 insert sites (QSO: entry popup, parsed entry, satlog
  ingestor, contest persistence, ADIF import; session: MacSessionManager,
  cold start, contest, remote op; SessionSpot: SpotAggregator; ServicePresence:
  ADIF factory) plus edits/deletes in the table, DXCC, dashboard, palette.

## Phase 0: shared foundations (CarrierWaveData)

Move the iOS-only pieces into the package so both apps run one implementation.
iOS keeps thin wrappers (typealiases / extensions) so its behavior and the
`BGAppRefreshTask` trigger stay as they are.

- `OAuthClient`, `KeychainSecureStore`, a platform-neutral `SyncAccountClient`
  carved out of `ActivitiesClient` (base URL resolution honoring
  `activitiesServerURLOverride`, `syncAuthToken()`, sync-key envelope PUT/GET).
  Device name via a small helper (`UIDevice.current.name` on iOS,
  `Host.current().localizedName` on macOS).
- `SyncKeyService` (+ the headless pass), `SyncProfile`,
  `ServerSnapshotCoordinator`, and `SyncDebugLog` if it is iOS-only.
- `SeamWriteBatch`, `SeamWriteBatchRegistry`, `OffMainStoreSeam` (drop the
  UIKit import).
- Gate: package tests (`swift test`), iOS compile check with
  `-destination 'generic/platform=iOS'`, Sweep build.

## Phase 1: Sweep on the Rust store — DONE 2026-10-05

Decision revised with the user on 2026-10-05: a full read port (every
`FetchDescriptor` site plus the live `LoggingSession`/`QSO` object flows) is a
re-platform of Sweep's data layer, so Sweep keeps reading SwiftData as a
**replica** while cw-store is canonical:

- Writes go cw-store first under `.on` through the shared seams. Sweep's
  explicit save sites route through `CwStoreSeams.save` (main context →
  `SeamWriteBatch`) or `OffMainStoreSeam` (ADIF import, satlog ingest, remote
  op). Autosave-only sites are still covered by the unsuppressed mirror.
- Pulls: `sync_run_pull_detailed` (new cw-ffi export; the existing records are
  untouched so the committed Android bindings stay valid) reports the applied
  keys; `SwiftDataSyncReplica` (installed by Sweep at launch) copies those rows
  into SwiftData with the mirror suppressed and `cloudDirtyFlag` untouched.
  QSO deletes are soft (hidden) upserts; session deletes remove the row.
- `CwStoreReconciler.reconcileAll` is a no-op under `.on`: cw-store-only rows
  are real data there. This also closes a latent iOS bug where CloudKit
  inbound rows routed through `QSOJournalStore` could be pruned.
- Sweep's "delete QSO" became a soft hide (a hard delete never reaches the
  journal, so other devices would keep the row).
- `CwStoreQSOMode.current` defaults to `.on` on macOS as well.
- Still owed: regenerate the committed Android `cw_ffi.kt` (new export), and a
  device check that a QSO logged in Sweep lands dirty in cw-store (exercised by
  the Phase 3 round trip).

## Phase 2: Sweep account sign-in — DONE 2026-10-05 (end-to-end sign-in owed)

- Settings → Account: enter callsign/email, request magic link, poll until the
  link is clicked in a browser, show the signed-in account, sign out. Uses the
  shared `OAuthClient`; tokens in the macOS Keychain through
  `KeychainSecureStore` (Data Protection keychain, so no ACL prompts).
- `MacrosRegistryHolder.authTokenProvider` can return the token afterwards.
- Gate: sign in against staging, token survives relaunch.

## Phase 3: Carrier Wave Sync in Sweep, iCloud sync removed — DONE 2026-10-05 (round trip owed)

- New `ServerSyncService` (`@MainActor @Observable`) in Sweep on top of the
  shared `SyncKeyService`: enrollment (create / unlock passphrase, forget on
  this device), status, last sync, dirty count from the store, Sync Now,
  Upload Full Log, error text. Triggers: one pass at launch when enrolled and
  seeded; every 5 minutes while running and online; debounced 30 s after local
  store changes; on wake.
- Snapshot heuristic (`ServerSnapshotCoordinator`) on session end.
- UI: Sync settings tab becomes Carrier Wave Sync (port `SyncPassphraseView`
  to a macOS form); status bar, `SyncStatusIndicator`, content-area
  `SyncStatusView`, command palette and vim palette move to the new service.
- Remove `CloudSyncService`, the CKSyncEngine journal wiring, the
  `cloudSyncEnabled` default and iCloud toggle, CK remote-notification
  handling. `resetForLocalWipe` becomes a cursor + seeded-flag reset.
  Entitlements are untouched in this phase (KVS still uses iCloud).
- Gate: Mac ↔ iPhone round trip against staging (the user's staging escrow needs
  the original passphrase; never overwrite it), then prod.

## Phase 4: docs and release — CHANGELOG + indexes done 2026-10-05; What's New at next Sweep bump

- CHANGELOG (Unreleased → Changed / Removed), both FILE_INDEX files,
  `docs/architecture.md` sync section, What's New entry at the next Sweep
  version bump, memory note update.

## Risks and open questions

- Reconciler versus pulled rows under `.on`: resolved in Phase 1 (no-op under
  `.on`, tested).
- `ExperimentalFeature.syncServer` gates the iOS UI; Sweep has no Experiments
  surface and will not gate.
- Keychain: use the Data Protection keychain for every new macOS item, or the
  "wants to use your confidential information" prompt returns per build.
- The SwiftData store remains as a follower after this work. Dropping it from
  Sweep entirely is a later project.
- Each phase is independently shippable; Phases 0 and 1 change no user-visible
  behavior until the mode default flips at the end of Phase 1.
