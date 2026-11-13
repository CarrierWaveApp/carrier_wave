# iOS → shared-FFI migration (status + rescoping)

**Date:** 2026-06-30
**Goal:** Move iOS off its Swift/SwiftData implementations onto the shared Rust core
(`cw-ffi`) for every FFI-capable feature, including the CloudKit-synced ones, so the Rust
core is the single source of truth and the Swift duplicates are deleted.

This doc supersedes the per-line scoping in the original plan: on closer inspection only
Friends (0a) and QRZ callbook (0c) were clean mechanical swaps; the rest each need dedicated
scoping because the FFI covers only a **subset** of what the Swift side does (or in a different
shape). Status and findings below.

## Already on FFI (the templates)
- **Clubs** — `ios/CarrierWave/Services/ClubsSyncService.swift` → `ClubsApi` + `FieldStore`
  (no SwiftData `@Model`). The canonical "@Observable @MainActor service over an async `*Api`
  built on `CwStoreProvider.shared.store()`, reads from `FieldStore`" template.
- **OAuth** — `OAuthClient.swift` + `KeychainSecureStore.swift` → `AuthApi`.
- **QRZ callbook** — `QrzCallbookClient.swift` → `QrzApi` (the second `SecureStore`-backed
  facade after OAuth; shows the Keychain cred-namespace bridge). DONE (see 0c).
- **Friends** — DONE (see 0a).
- All stateless parsers/codecs/query (quick-entry, CTY, SCP, ADIF, band/mode, callsign, spot
  decoders, maidenhead, query analysis) via the `CarrierWaveCore` wrappers.

## The hard constraint (drives sync phasing)
iOS CloudKit sync is a hand-rolled Swift `CKSyncEngine` journal
(`packages/CarrierWaveData/.../CloudSync/CloudSyncJournalEngine*.swift`) that reads
`cloudDirtyFlag` off live SwiftData `@Model`s and applies inbound by mutating `ModelContext`.
CloudKit (`CKSyncEngine`/`CKDatabase`) **must** stay Swift. There is **no Rust sync path on
iOS** (`cw-sync` is not exposed over `cw-ffi`). So any CloudKit-synced entity can't go
FFI-authoritative without first re-pointing the journal's store-access half at `FieldStore`.
The realistic approach (confirmed in code): **keep the Swift engine + JSON journal + conflict
resolver; swap only the store-access seam** (`CKRecordMapper+Fields.swift`,
`CloudSyncJournalEngine+Outbound/+Inbound/+MarkAllDirty.swift`, `recordCounts()`) from
`ModelContext` to `FieldStore`. `cw-sync` is a separate future path (CloudKit replacement),
NOT used here.

---

## Phase 0a — Friends → FFI  ✅ DONE
Commit `fcc601f1`. iOS Friends now run entirely on the new `FriendsApi` + `FieldStore`.
- `FriendsSyncService` is now an `@Observable @MainActor` singleton over `FriendsApi`
  (sync/search/request/accept/decline/remove/suggestions/invite); reads from
  `FieldStore.fetch_friendships`. Publishes accepted/incoming/outgoing + an O(1)
  accepted-callsign set.
- `Friendship` is now a value type projected from `FfiFriendship` (no longer a `@Model`).
  `DismissedSuggestion` `@Model` removed; dismissals moved to `UserDefaults`.
- Dropped both from `AppSchema`; rewired ~20 `@Query`/`FetchDescriptor<Friendship>` sites.
- Simulator build green; format/lint/perf gates passed.

**Why it was clean:** `Friendship` was a self-contained model with a 1:1 FFI counterpart and a
narrow blast radius. None of the remaining items have that property.

---

## Phase 0b — Activity feed  ⛔ RESCOPE (not a clean swap)
`ActivityItem` (~38 files) is **not** just the friends feed — it's the local record of the
user's *own* activities, used across the sharing system, session-end flows
(`LoggingSessionManager+SessionActivity`, `EndSessionFlowView`), `ContestParticipationGatherer`,
`TOTAUploadService`, `ActivityReporter`, and dashboard cards. The FFI `FriendsApi.fetch_feed`
is a **remote-only, non-persisted subset** (the friends feed display only).
**Decision needed:** keep `ActivityItem` for the local/own-activity role and only route the
*remote feed display* through `fetch_feed`, vs. a larger redesign that splits own-activity
from feed. Dropping `ActivityItem` persistence also removes the offline feed cache — a
user-facing behavior change. Treat as a dedicated design effort, not a port.

## Phase 0c — QRZ → QrzApi  ✅ DONE
Commit `63c2cf3c`. iOS QRZ callbook lookups now run on the shared Rust `QrzApi`.
- New `QrzCallbookClient` actor (`Services/QrzCallbookClient.swift`): a thin facade over
  `QrzApi(secure: KeychainSecureStore())`, mirroring the `OAuthClient` template. The session
  key auth, XML parse, and alias/previous-call logic all moved to Rust.
- **Credential bridge (the data-sensitive part):** the user-facing
  `qrz.callbook.username`/`qrz.callbook.password` Keychain keys stay the single source of truth
  (Settings UI unchanged). The client reads them and syncs into the FFI's own `cw.qrz.*`
  secure-store namespace via `setCredentials`, but only when they change — so credential edits
  take effect on the next lookup without a relaunch, and the cred-missing gate
  (`.noQRZApiKey`) is preserved.
- `lookupInQRZWithResult` maps `FfiQrzLookup → CallsignInfo` and `CwError → CallsignLookupError`,
  and reconstructs the "Looked up as …" redirect note Swift-side (the FFI result doesn't carry
  it). Uses `QrzApi.lookup` (QRZ-only), **not** `lookupCallbook`, because the orchestrator
  (`CallsignLookupService+Lookup.swift`) already merges HamDB separately — routing through
  `lookupCallbook` would double-merge HamDB and mis-tag its data as `.qrz`.
- `CallsignLookupService+GridRepair` dropped its manual session-key threading; `QrzApi` keeps
  one in-memory session across the batch.
- Deleted all the legacy QRZ XML lookup code. QRZ **Logbook** ADIF upload/download (`QRZClient`,
  `+Upload`, `+ADIF`) — which has no FFI — stays Swift, untouched. Simulator build green; gates passed.
- Mapping behavior is unit-tested headlessly: `CallsignLookupQRZMappingTests` (6 cases) pins the
  `FfiQrzLookup → CallsignInfo` projection + redirect-note reconstruction.
- **Remaining QRZ-XML-in-Swift surface (follow-up, out of 0c scope):**
  `ExternalDataView.authenticateWithQRZ` still hand-rolls QRZ XML auth (+ its own `parseXMLValue`)
  to *validate credentials* at Settings login. `QrzApi` exposes no standalone "validate creds"
  method (only `lookup`), so a clean migration needs a new cw-net/cw-ffi validate method + bindings
  regen — a Rust change, not a Swift-only swap. Left as-is; dead `qrz.callbook.session.key`
  persistence removed.

## Phase 0d — Enrichment → EnrichmentApi  ⛔ RESCOPE (subset mismatch, not a clean swap)
On inspection this is **not** a duplicate-deleting port — `EnrichmentApi.lookup` is a
**per-callsign** enrichment (DXCC name/prefix/zone/continent, SKCC badge, clubs, server
memberships), but the Swift services it would replace are consumed in shapes the FFI can't
serve:
- **`CTYService` can't be removed.** Its two real consumers — `NeedsEngine` and
  `SpotNeedsMatcher` — call `CTYService.shared.database()` for the **whole `CTYDatabase`** and
  run bulk DXCC *matching* over it (`matchDXCC(spot:needs:db:)`). `EnrichmentApi` exposes no
  bulk-DB accessor, only `lookup(callsign)`. So CTY stays Swift for needs-matching; only the
  per-callsign DXCC-name *display* facet could move.
- **`CallsignInfo.memberships: [CallsignEnrichmentMembership]`** is woven through the whole
  display layer (`CallsignLookupService+Lookup` folds server memberships into it; ~30 call
  sites read `CallsignInfo`). The FFI returns `FfiMembership` (with a precomputed `chipLabel`).
  Swapping the membership type ripples into `CallsignInfo` and every consumer — a typed-model
  change, not a read-path swap.
- **`SKCCMembershipStore` lives in the shared `CarrierWaveCore` package** and is also consumed
  by macOS CW Sweep. Can't be deleted from iOS alone.
**Decision needed:** which facets actually move (likely only the per-callsign chip *display*:
SKCC badge + club chips + server-membership chips, fed by an app-lifetime `EnrichmentApi`
instance with `refresh()`/`refreshMemberships()` warmup at launch, mirroring Android's
`EnrichmentBadges`), what becomes of the bulk-DB `CTYService` consumers, and whether the result
is a duplicate *deletion* or just a parallel path. Visual chip parity across ~13 surfaces needs
a device. Treat as a design effort, like 0b/0e — not a mechanical port.

## Phase 0e — Spots → SpotsApi  ⛔ SCOPE MISMATCH
`SpotsApi` provides **global** POTA/RBN/SOTA/WWFF feeds (the Android Spots-tab style). iOS
`SpotsService` is a **per-callsign** spot lookup (`actor`) — a *different feature*, not a 1:1
target. The real `SpotsApi` targets are iOS's **global feed fetchers** (`POTAClient+Spots`,
`SOTASpotsCache`, the hunter spot list) feeding `POTASpotsView` / `ActivityLogSpotsList`.
Re-scope to those; leave the per-callsign `SpotsService` alone (or migrate separately).

---

## Phase 1 — Sync foundation + flip QSO authority  🔒 HIGH RISK (needs hands-on verify)
Reuses the existing shadow/mirror infra (`CwStoreQSOMode` `.off/.shadow/.on`,
`EntityWriteSink`, `OffMainStoreSeam`, the `*ReadSource` parity tests) behind the
`.rustStoreQSO` alpha flag.

**1a. FFI sync surface to ADD** — ✅ DONE (this part is codeable/testable headless; landed
ahead of the two-device 1b/1c). All four items implemented in `cw-store` + `cw-ffi`, bindings
regenerated (`build-xcframework.sh`), workspace `cargo test` + `clippy -D warnings` green:
- `dirty_only` on `QsoFilter`/`FfiQsoFilter` (SQL `AND dirty=1`) **and** on
  `SessionSpotFilter`/`ActivityLogFilter` (SQL `AND cloud_dirty_flag=1`) + their `Ffi*` records.
- Bulk `clear_dirty(entity_type, ids, not_if_modified_after: Option<i64>)` — the CAR-245
  newer-than-snapshot guard (applies to the `modified_at`/`updated_at`-bearing entities: qso,
  radioMacro); `activationMetadata` is a no-op (no single-id key, mirrors the Swift `break`);
  bounded by `MAX_FETCH_LIMIT`.
- `mark_all_dirty(entity_type)` — port of `+MarkAllDirty.swift` (QSO skips WEATHER/SOLAR/NOTE
  metadata modes); returns rows marked.
- bulk `delete_cloud_sync_metadatas(entity_type)` for `resetForLocalWipe`.
- New modules: `cw-store/src/sync_dirty.rs` (entity-type→table resolver + the two ops) and
  `cw-ffi/src/sync.rs` (FieldStore methods + entity_type→`FfiStoreTable` notify). `entity_type`
  is the **`JournalEntityType` raw value** (camelCase: `qso`/`servicePresence`/`loggingSession`/
  `activationMetadata`/`sessionSpot`/`activityLog`/`radioMacro`) — distinct from the PascalCase
  class names stored in `cloud_sync_metadata.entity_type`.
- **Not yet wired into Swift** — the `CloudSyncJournalEngine` seam still reads/writes
  `ModelContext`; consuming these from the journal is 1b/1c (two-device).

**1b. Re-point the journal seam** to `FieldStore` (no `CKSyncEngine`/journal-format change).
🟡 PARTIAL — the QSO store-access **building block is landed + unit-tested**; wiring it into the
live `CloudSyncJournalEngine` is the device-gated remainder.
- ✅ `QSOFields ↔ FfiQso` mapping (`CloudSync/QSOFields+FieldStore.swift`) — exact-parity with
  `SwiftDataStoreImporter.project` (lowercased-uuid id, MHz→kHz freq, epoch-second dates); the
  `FfiQso`-only columns (`callsignChangeNote`/`originalCallsign`/`aoaCode`/`contest*`) are
  **preserved** on inbound apply, matching SwiftData's `applyQSOFields`.
- ✅ `QSOJournalStore` seam (`CloudSync/QSOJournalStore.swift`) over `FieldStore`: dirty page
  (metadata-mode split), `clearDirty` (CAR-245 guard), `markAllDirty`, inbound upsert+merge
  (reuses `CloudSyncConflictResolver.mergeQSO`, preserves dirty), `softDelete`, `hasVisibleQSO`.
- ✅ Added `fetch_qso(id)` to `cw-store`/`cw-ffi` (the inbound merge needs by-id access incl.
  hidden rows; every other entity already had it). Regenerated bindings.
- ✅ Fixed the 6 Swift call sites the 1a `dirty_only` binding change broke (filter inits).
- ✅ 9 unit tests (`QSOJournalStoreTests`) green; CarrierWaveData package + **iOS app build**
  green. Mapping/merge/guard all verified headless.
- ✅ **Wired into the live engine** (at owner's explicit direction, accepting the unverified gate
  below). Every QSO touchpoint branches to `QSOJournalStore` when the seam is bound, else the
  SwiftData path runs verbatim: `+Outbound` `collectDirtyQSOs` (store-paged, metadata-clear
  deferred so offsets don't shift) + `clearQSODirtyFlag`; `+Inbound` `applyQSOUpsert` +
  `applyQSODeletion`; `+MarkAllDirty`; core `recordCounts` (dirty count from `dirty_qso_count`),
  `localDatabaseHasData`. Seam bound in `start()` via `resolveQSOJournalStore`.
- ✅ Added `dirty_qso_count()` to `cw-store`/`cw-ffi` (the journal clears the store's flag, not
  SwiftData's, so `recordCounts` would otherwise grow stale). Regenerated bindings.

**1c. Flip QSO write authority** to `FieldStore` — ✅ FLIPPED (iOS only), 🔒 UNVERIFIED.
- `CwStoreQSOMode.current` defaults to `.on` **on iOS** (`#if os(iOS)`); `.rustStoreQSO` removed
  from `isHiddenByDefault` so it's default-on + still user-toggleable (kill switch back to `.off`).
  The three iOS `@AppStorage(cwStoreQSOMode)` defaults flipped to `.on` so `applyQSOMirrorMode`
  actually spins up the mirror/import.
- **macOS (CW Sweep) deliberately stays `.off`:** it shares the journal engine but has no `.on`
  read/write seams (reads still SwiftData), so a flip would land inbound QSOs where its UI can't
  see them. Scoped out via `#if os(iOS)`.
- **Launch-race guard:** the seam only binds once `CwStoreImportCoordinator.hasEverCompletedImport()`
  is true, so a `.on` flag never points sync at a not-yet-imported (empty) store. First launch
  after the flip imports + uses SwiftData; later launches use the store.

**⚠️ Verification still owed (cannot be done headless — needs two devices):** at production data
scale, confirm main-thread O(1) + ≤1000-row batches during the first-launch import; **no
duplicate/orphan rows** after a full inbound+outbound round-trip **across two devices**; confirm
the picker kill-switch back to `.off` restores SwiftData authority (note: journal seam re-binds on
next launch, not instantly). The code compiles + unit-tests pass, but cross-device sync
correctness is unproven. **Watch the first TestFlight build closely; the `.off` toggle is the
rollback.**

## Phase 2 — Remaining synced entities  🔒 HIGH RISK
Repeat 1b/1c per entity, reusing FFI write logic: **Sessions** (`LoggingSessionManager` →
`SessionApi`), **Hunter Log** (`ActivityLogManager` → `ActivityLogApi`), **ServicePresence**,
**ActivationMetadata**, **SessionSpot**. One independently-verified flip per entity. Do NOT
batch flips.

## Phase 3 — Retire SwiftData
Remove the `@Model`s from `CarrierWaveSchema`/`AppSchema`; remove the dual-write mirror
(`RustStore/CwStoreMirror.swift`), importer (`SwiftDataStoreImporter`/`CwStoreImportCoordinator`),
`CwStoreReconciler`, snapshot service; remove `CwStoreQSOMode` + the `.rustStoreQSO` flag.

---

## What's next

The clean, self-contained swaps are done (0a Friends, 0c QRZ). Nothing else is a
pick-up-and-port: **every remaining item needs either a scope decision from a human or a
second physical device.** Concretely:

### A. Decisions needed before any more non-synced ports (0b / 0d / 0e)
Each is blocked on one product/architecture call. Answer these and the port becomes mechanical:
1. **0d Enrichment** — *Ship the per-callsign chip display (SKCC badge + club chips +
   server-membership chips) on `EnrichmentApi` as a **parallel path**, leaving `CTYService`
   for needs-matching and `SKCCMembershipStore` for macOS?* If yes, this is the most concrete
   next port (Android's `EnrichmentBadges` is the template) — but it **adds** a path, it does
   **not** delete a Swift duplicate, and it needs a device to eyeball chip parity across ~13
   surfaces. Decision: accept a parallel path, or hold out for a full deletion design?
2. **0e Spots** — *Re-point 0e at the **global** feed fetchers (`POTAClient+Spots`,
   `SOTASpotsCache` → `POTASpotsView`/`ActivityLogSpotsList`) and leave the per-callsign
   `SpotsService` alone?* If yes, it's bounded; if the goal is to also replace the per-callsign
   actor, that's a separate FFI feature.
3. **0b Activity feed** — *Keep `ActivityItem` for the user's own-activity record and route
   only the **remote friends-feed display** through `fetch_feed` (losing the offline feed
   cache), or do the bigger own-activity-vs-feed split?* Biggest design call of the three.

**Recommended order:** 0d (display sub-slice) → 0e (global feeds) → 0b (needs the most design),
**if** the parallel-path tradeoff in (1) is acceptable. Otherwise these stay parked and the
campaign jumps to Phases 1–3.

### B. The real goal — Phases 1–3 (synced entities, delete SwiftData)
This is where "Rust is the single source of truth" actually happens. It is a **separate,
two-device-verified campaign** and cannot start headless.
- **1a FFI sync surface** — ✅ DONE (see Phase 1 §1a). `dirty_only` / `clear_dirty` /
  `mark_all_dirty` / `delete_cloud_sync_metadatas` are in `cw-store`/`cw-ffi`, bindings
  regenerated, all Rust gates green. Everything downstream is now unblocked.
- **Next (1b/1c):** re-point the journal seam → flip QSO authority, **only** with two devices
  on hand for the round-trip / no-dup-orphan / rollback verification gate. The journal still
  reads `ModelContext`; the new FFI methods are not yet called from Swift.

### C. Loose follow-up (small)
0c left one QRZ-XML-in-Swift surface: `ExternalDataView.authenticateWithQRZ` login validation
(see 0c). Needs a new `QrzApi` "validate credentials" method (cw-net/cw-ffi + bindings regen) to
retire. Low priority; bundle it with the next Rust-side change.

## Key files
- Templates: `ios/CarrierWave/Services/{ClubsSyncService,OAuthClient,KeychainSecureStore}.swift`;
  `CwStoreProvider.shared.store()`.
- Friends (done): `Services/FriendsSyncService.swift`, `Models/{Friendship,FriendSuggestion}.swift`.
- Sync seam: `packages/CarrierWaveData/Sources/CarrierWaveData/CloudSync/`.
- FFI sync additions: `rust/cw-core/cw-store/src/{qso,session_spot,activity_log}.rs`,
  `cw-ffi/src/{lib.rs,entities/*.rs}`; regen via `rust/cw-core/scripts/build-xcframework.sh`.
- Mirror infra (reuse then retire): `RustStore/{CwStoreProvider,CwStoreMirror,QSOReadSource}.swift`,
  `ios/CarrierWave/CarrierWaveApp+QSOMirror.swift`.
