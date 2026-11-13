## CarrierWaveData Package (`swift/packages/CarrierWaveData/`)

Shared SwiftData models and cloud sync engine used by both the iOS app and CW Sweep.

### Models (`Sources/CarrierWaveData/Models/`)

| File | Purpose |
|------|---------|
| `Achievement.swift` | Profile achievement catalog + user award types (mirrors server) |
| `QSO.swift` | Core contact record model |
| `QSO+Dedup.swift` | QSO deduplication logic |
| `LoggingSession.swift` | Logging session model |
| `LoggingSession+ActivationThreshold.swift` | Per-program activation QSO thresholds (POTA=10, SOTA=4, WWFF=44) |
| `TOTATypes.swift` | TOTACategory + T3Candidate value types for TOTA enrichment fields on LoggingSession |
| `ServicePresence.swift` | POTA/SOTA/WWFF service presence |
| `SessionSpot.swift` | Spot within a logging session |
| `ActivationMetadata.swift` | Park activation metadata |
| `ActivityLog.swift` | Activity tracking model |
| `CloudSyncMetadata.swift` | iCloud sync metadata per record |
| `ContestDefinition.swift` | Contest definition model |
| `SDRParameterEvent.swift` | SDR parameter change events |
| `SDRTranscriptModels.swift` | SDR transcript types (Word, Line, Transcript, DetectedQSORange) for cw-swl integration |
| `Types.swift` | Shared type definitions |
| `UploadDestination.swift` | Upload destination configuration |
| `WebSDRFavorite.swift` | WebSDR favorite stations |
| `WebSDRRecording.swift` | WebSDR recording metadata |
| `EquipmentCatalog.swift` | Equipment catalog types: CatalogEntry, EquipmentCategory, OperatingMode, PortabilityClass, CatalogSearchResult |
| `EquipmentInventory.swift` | SwiftData EquipmentItem model with catalog link, nickname, specs, connection profile; EquipmentInventorySnapshot for cross-actor use |
| `EquipmentInventory+Ffi.swift` | `EquipmentInventorySnapshot(ffi:)` adapter — builds the snapshot from a Rust `FfiEquipmentItem` (the read-flip surface) |
| `RadioConnectionProfile.swift` | RadioConnectionProfile (Codable, stored as JSON on EquipmentItem), RadioTransportKind/RadioProtocolKind enums, RadioCatalogMetadata helper (derives protocol/transports/bridge compat from catalog entries) |
| `CallsignEnrichment.swift` | Codable wire/runtime types for server callsign enrichment dataset (CWops + future SKCC) shared by iOS and Sweep |

### Import (`Sources/CarrierWaveData/Import/`)

| File | Purpose |
|------|---------|
| `SwiftDataStoreImporter.swift` | One-time SwiftData→cw-store (SQLCipher) seed importer: `importAll(from:into:)` batched fetch per `@Model` (fresh context, `fetchLimit` set), idempotent upsert, per-table `ImportReport`. See `docs/plans/2026-06-14-swiftdata-import-design.md` |
| `SwiftDataStoreImporter+Projections.swift` | Faithful `@Model`→`Ffi*` `project(_:)` overloads for all 12 entities (Date→unix, UUID→lowercased string, Int→Int64, JSON arrays→text, blobs verbatim) |
| `SwiftDataStoreImporter+Verify.swift` | `verify(_:)`/`compareCounts(_:to:)` → `VerifyReport`: compares per-table row counts (SwiftData source vs cw-store) — the "no rows lost" gate |
| `CwStoreImportCoordinator.swift` | Orchestrates the on-device seed: App Group store URL + device-local (non-synced) keychain key, `runIfNeeded(from:)` imports→verifies→records a `UserDefaults` completion marker. Manual (Settings) trigger |

### Query (`Sources/CarrierWaveData/Query/`)

| File | Purpose |
|------|---------|
| `QueryStore.swift` | Actor wrapping the writer SQLite connection (GRDB DatabaseQueue) |
| `QueryReader.swift` | Actor wrapping a read-only DatabaseQueue with run/explain/profile API |
| `QueryFacade.swift` | Process-wide shared QueryStore registration; fire-and-forget mirror helpers |
| `QuerySQLFunctions.swift` | Custom `cw_*` SQL functions (distance, bearing, user-relative grid helpers) registered on every reader connection |
| `Schema/SchemaVersion.swift` | Current schema version constant |
| `Schema/Migrations.swift` | GRDB DatabaseMigrator: qsos, dxcc, polo_notes, dxcc_status view, meta |
| `Schema/ScopeSchema.swift` | Transient scope schema: spots, spot_observations, spotters |
| `Models/QSORow.swift` | GRDB record for slim QSO mirror |
| `Models/OperatorProfileRow.swift` | GRDB record for cached per-callsign operator profiles (name/QTH/grid/license, sourced from prior QSOs + QRZ) |
| `Models/SpotRow.swift` | GRDB record for projected scope.spots |
| `Models/SpotObservationRow.swift` | GRDB record for raw observations (per-skimmer fan-out) |
| `Models/SpotterRow.swift` | GRDB record for skimmer/spotter location |
| `Models/DXCCRow.swift` | GRDB record for the dxcc reference table |
| `Models/PoloNoteRow.swift` | GRDB record for polo_notes |
| `Mapping/QSOMapper.swift` | QSO → QSORow with metadata-mode filter |
| `Results/QueryResultSet.swift` | Sendable result envelope: columns, rows, truncated flag |
| `Results/QueryError.swift` | Wrapped GRDB error with sql + offset |
| `Profiling/QueryProfile.swift` | EXPLAIN-plan + wall-clock profile envelope |
| `SavedQuery/SavedQuery.swift` | Codable .cwquery doc |
| `SavedQuery/SavedQueryURL.swift` | cwquery:// URL scheme codec |
| `SavedQuery/SavedQueryStore.swift` | Actor managing .cwquery files on disk; schema-version import gate |

### RustStore (`Sources/CarrierWaveData/RustStore/`)

Read-side seams for the SwiftData→cw-store migration. Each `*ReadSource` has a SwiftData impl + a Rust (`FieldStore`) impl, routed by `CwStoreQSOMode`; SwiftData stays authoritative until a per-entity cutover.

| File | Purpose |
|------|---------|
| `CwStoreProvider.swift` | Process-wide shared `FieldStore` (SQLCipher) provider |
| `CwStoreLocation.swift` | Where `cw-store.db` lives: iOS app-private Application Support (one-time move out of the App Group, avoids `0xdead10cc`); macOS App Group — team-prefixed `7UE4RDLUSX.com.jsvana.FullDuplex` (`legacyMacAppGroupID` = the old `group.` ID) |
| `QSOReadSource.swift` | `CwStoreQSOMode` enum + QSO read sources (count + `.cwquery`→SQL page) |
| `CwStoreSyncMode.swift` | Sync-engine selection seam (`off` = CKSyncEngine, `serverSync` = E2E server); default `.off`, mirrors the `CwStoreQSOMode` pattern |
| `AnalyticsReadSource.swift` | `AnalyticsReadSource` protocol + `RustAnalyticsReadSource` impl (cw-store SQL `GROUP BY`): distinct counts, count-by, activation/park/equipment/combo rollups, grid tiles, WAS, DXCC-worked, state counts, service-presence counts, brag metrics. Headline DTOs live here; the rest in `AnalyticsTypes.swift` |
| `AnalyticsTypes.swift` | Analytics-surface DTOs for the park/state/equipment/combo/brag surfaces + `SessionInput`/`SessionItemInput` (flattened LoggingSession oracle inputs) + `ItemTallyRow`/`SessionItemDetailResult` (per-equipment-item breakdown) |
| `AnalyticsAggregator.swift` | Pure-Swift aggregation oracle (cross-impl parity reference) — distinct counts, count-by, activation, grid, WAS, DXCC, presence + shared helpers; `PresenceInput` |
| `AnalyticsAggregator+Sessions.swift` | Oracle extension for the park/state/equipment/combo/brag surfaces (split for file length) |
| `AnalyticsAggregator+SessionItemDetail.swift` | Oracle extension for the per-equipment-item QSO breakdown (`session_item_detail`) |
| `AnalyticsReadSource+SessionItemDetail.swift` | `RustAnalyticsReadSource.sessionItemDetail` (cw-store `session_item_detail` → `SessionItemDetailResult`) |
| `AnalyticsBragDistanceTypes.swift` | Distance-shaped brag DTOs (`BragContactRow`/`BragBandRecordRow`/`BragPowerContactRow`/`BragEfficiencyRow`/`BragDistanceStatsResult`) |
| `AnalyticsAggregator+BragDistance.swift` | Oracle extension for the distance-shaped brag stats (`brag_distance_stats`) |
| `AnalyticsReadSource+BragDistance.swift` | `RustAnalyticsReadSource.bragDistanceStats` (cw-store `brag_distance_stats` → `BragDistanceStatsResult`) |
| `AnalyticsBragStreakTypes.swift` | Streak-shaped brag DTOs (`StreakValueRow`/`ModeStreakRow`/`BragStreaksResult`) |
| `AnalyticsAggregator+BragStreaks.swift` | Oracle extension for the streak-shaped brag stats (`brag_streaks`, UTC day fold) |
| `AnalyticsReadSource+BragStreaks.swift` | `RustAnalyticsReadSource.bragStreaks` (cw-store `brag_streaks` → `BragStreaksResult`) |
| `AnalyticsBragGeographicTypes.swift` | Geographic brag DTO (`BragGeographicResult`) |
| `AnalyticsAggregator+BragGeographic.swift` | Oracle extension for the geographic brag stats (`brag_geographic`; continent sets duplicated from `ContinentMapper`) |
| `AnalyticsReadSource+BragGeographic.swift` | `RustAnalyticsReadSource.bragGeographic` (cw-store `brag_geographic` → `BragGeographicResult`) |
| `AnalyticsBragRecordsTypes.swift` | Volume/records/fun brag DTO (`BragRecordsResult`) |
| `AnalyticsAggregator+BragRecords.swift` | Oracle extension for the records/volume/fun brag stats (`brag_records`) |
| `AnalyticsReadSource+BragRecords.swift` | `RustAnalyticsReadSource.bragRecords` (cw-store `brag_records` → `BragRecordsResult`) |
| `AnalyticsBragSessionTypes.swift` | Session/sequence brag DTO (`BragSessionStatsResult`) |
| `AnalyticsAggregator+BragSession.swift` | Oracle extension for the session/sequence brag stats (`brag_session_stats`, fetch-and-fold) |
| `AnalyticsReadSource+BragSession.swift` | `RustAnalyticsReadSource.bragSessionStats` (cw-store `brag_session_stats` → `BragSessionStatsResult`) |
| `AnalyticsBragPotaTypes.swift` | POTA-brag DTOs (`BragPotaResult` + `BragBestActivationRow`) |
| `AnalyticsAggregator+BragPota.swift` | Oracle extension for the POTA-brag stats (`brag_pota`) |
| `AnalyticsReadSource+BragPota.swift` | `RustAnalyticsReadSource.bragPota` (cw-store `brag_pota` → `BragPotaResult`) |
| `AnalyticsAggregator+BragSignal.swift` | Oracle extension for averageRST + worked-member-callsigns (club stats) |
| `AnalyticsReadSource+BragSignal.swift` | `RustAnalyticsReadSource.bragAverageRST` + `workedMemberCallsigns` (cw-store `brag_average_rst` / `worked_member_callsigns`) |
| `QSORowSnapshot.swift` | Sendable QSO row + `PresenceSummary` for off-main Logbook rendering |
| `QSOParityProbe.swift` | SwiftData-vs-Rust count + query (ID-order) parity comparison for QSO |
| `LoggingSessionReadSource.swift` | LoggingSession read sources + `LoggingSessionSnapshot` (count **and** id-ordered list; all ~75 columns, full field+order parity) |
| `ServicePresenceReadSource.swift` | ServicePresence read sources (count parity; backs the write-seam parity) |
| `CountReadSource.swift` | Generic count read-source backbone (`SwiftDataCountReadSource<Model>` + `RustCountReadSource` factories) for the 9 peripheral entities |
| `EquipmentItemReadSource.swift` | EquipmentItem read sources + `EquipmentItemSnapshot` (count **and** id-ordered list; both backends, full field+order parity) |
| `LoadoutReadSource.swift` | `Loadout` value type ⇄ `FfiLoadout` + `LoadoutStore` seam (all/upsert/delete) over the Rust `loadout` table |
| `ActivationMetadataReadSource.swift` | ActivationMetadata read sources + snapshot (count + list ordered by `(parkReference, date)`; full field parity) |
| `ActivityLogReadSource.swift` | ActivityLog read sources + snapshot (count + id-ordered list; full field parity) |
| `CloudSyncMetadataReadSource.swift` | CloudSyncMetadata read sources + snapshot (count + `recordName`-ordered list; full field parity) |
| `RadioMacroReadSource.swift` | RadioMacro read sources + snapshot (count + id-ordered list; full field parity, incl. JSON blobs) |
| `SessionSpotReadSource.swift` | SessionSpot read sources + snapshot (count + id-ordered list; full field parity) |
| `UploadDestinationReadSource.swift` | UploadDestination read sources + snapshot (count + id-ordered list; full field parity) |
| `WebSDRFavoriteReadSource.swift` | WebSDRFavorite read sources + snapshot (count + `hostPort`-ordered list; full field parity) |
| `WebSDRRecordingReadSource.swift` | WebSDRRecording read sources + snapshot (count + id-ordered list; full field parity) |
| `StoreCountParity.swift` | Generic per-entity SwiftData-vs-Rust row-count parity comparison |
| `QSOWriteSink.swift` | Main-actor QSO write authority (upsert/hide/delete, single + batch) routed by `CwStoreQSOMode`: `on` writes cw-store first then a mirror-suppressed SwiftData save; `QSOWriteSinkRegistry` + `commitUpsert`/`commitDeleteBatch` routing helpers. Moved from the iOS app 2026-10-05 |
| `EntityWriteSink.swift` | Generic per-entity write seam (LoggingSession, SessionSpot, EquipmentItem, …) with the same `on`-first contract, `EntityWriteSinkRegistry` (type-keyed), `commitUpsert`/`commitDelete` routing |
| `EntityWriteSinkFactory.swift` | `registerAll(store:mirror:)` wires each entity's `upsert_*`/`delete_*` FFI into an `EntityWriteSink`, projecting via `SwiftDataStoreImporter` |
| `SeamWriteBatch.swift` | Coordinated multi-entity seam write for shared saves (one `save()` flushing several entities) under one mirror-suppression window; `SeamWriteBatchRegistry` |
| `OffMainStoreSeam.swift` | Off-main analogue for background `ModelContext` savers: `commit(in:storeOps:)`, `commitPresence`, `commitActivationMetadata`, `commitQSOsWithPresence` (batch FFI, one txn per table) |

### ServerSync (`Sources/CarrierWaveData/ServerSync/`)

Carrier Wave Sync (E2E sync server) client shared by iOS and CW Sweep. Hosts install `ServerSyncLog`, `SuspensionGuardFactory`, and `SyncKeyService.passphraseProvisioner`.

| File | Purpose |
|------|---------|
| `ActivitiesServer.swift` | `defaultURL`, `resolvedBaseURL` (honors the `activitiesServerURLOverride` default), `normalizeBase` — one resolver for every client |
| `ServerSyncHooks.swift` | `ServerSyncLogging` + `ServerSyncLog` (lock-guarded process-wide sink), `SuspensionGuard` + `SuspensionGuardFactory` (iOS background-task assertion; nothing on macOS) |
| `KeychainSecureStore.swift` | Rust `SecureStore` foreign trait over `KeychainHelper` for the OAuth refresh token + PKCE verifier |
| `OAuthClient.swift` | Actor facade over Rust `AuthApi`: magic-link start/poll/complete, `validAccessToken`, logout; `platform` defaults to ios/macos |
| `SyncAccountClient.swift` | Account bearer for `/v1/sync/*` (`syncAuthToken`) + escrow PUT/GET (`SyncKeyBlob`); `SyncAccountError` |
| `SyncProfile.swift` | `SyncRunSummary` + `SyncProfile` (per-phase timings, shareable report) |
| `SyncKeyService.swift` | `@MainActor @Observable` passphrase lifecycle: status/phase, create (refuses if an escrow exists), unlock, run-once, upload-full-log, forget-on-device; per-server Keychain slot `sync.data.key.<base>` |
| `SyncKeyService+Pass.swift` | Pass driver + persistence: per-server cursor / seeded flag / escrow fingerprint, headless `runBackgroundPass(trigger:)` (enrolled + seeded gate, fingerprint check), `performSync` (auto-seed first pass, suspension guard), `resetForLocalWipe` |
| `SyncReplica.swift` | `SyncAppliedChange` (Sendable mirror of cw-ffi `SyncAppliedKey`), `ServerSyncReplica` protocol + `ServerSyncReplicaRegistry`, and `SwiftDataSyncReplica`: copies server-pulled QSO/session rows from cw-store into a SwiftData follower off-main with the mirror suppressed (never dirty); posts `didApplyNotification`. Fed by `SyncKeyService.pullOffMain` via `sync_run_pull_detailed` |
| `ServerSnapshotCoordinator.swift` | Per-server pushed-entry counter + `snapshotIfDue` cadence check (`ServerSyncSnapshotHeuristic`); upload itself awaits a cw-ffi snapshot export |

### CloudSync (`Sources/CarrierWaveData/CloudSync/`)

Journal-based iCloud sync — the only sync path since the per-record CKSyncEngine
implementation was removed. Both Carrier Wave (iOS) and CW Sweep (macOS) write
batched JSON `ChangeJournal` CKRecords into a single shared CloudKit zone and
upload SQLite snapshots periodically for fast device bootstrap.

| File | Purpose |
|------|---------|
| `CloudSyncJournalEngine.swift` | Main `CKSyncEngine` actor — start/stop, fetch, journal-mode bootstrap, record counts, accountChange |
| `CloudSyncJournalEngine+Outbound.swift` | Dirty record collection → `JournalOperation` batches → `ChangeJournal` CKRecords |
| `CloudSyncJournalEngine+Inbound.swift` | Decode journal CKRecords + snapshot bootstrap, conflict-resolve via `CloudSyncConflictResolver` |
| `CloudSyncJournalEngine+Fields.swift` | Extract `Sendable` field structs from models / apply structs back to models |
| `CloudSyncJournalEngine+MarkAllDirty.swift` | Batched `cloudDirtyFlag = true` for "Force Full Sync" / iCloud sign-in |
| `CloudSyncJournalEngine+ServerSync.swift` | Phase 7.2 `CwStoreSyncMode` seam: routes start/schedule/fetch to an injected server-sync (`sync_run_once`) runner instead of CKSyncEngine |
| `SyncEscrowValidation.swift` | Escrow-fingerprint verdict gating E2E server pushes (poisoned-tenant guard, Phase 7.1) |
| `ServerSyncSnapshotHeuristic.swift` | Server snapshot cadence: `entries_since_snapshot >= max(30, total_log * 0.2)` (Phase 7.4, single source of the constant) |
| `CloudSyncJournalEntry.swift` | `JournalPayload` + `JournalOperation` types and CKRecord coding |
| `CloudSyncModelFactories.swift` | Build new model instances from inbound field structs |
| `QSOFields+FieldStore.swift` | `QSOFields ↔ FfiQso` mapping (Phase 1b) — exact-parity with `SwiftDataStoreImporter.project`; preserves `FfiQso`-only columns on inbound apply |
| `LoggingSessionFields+FieldStore.swift` | `FfiLoggingSession.toLoggingSessionFields()` — reverse of the importer projection so the replica can reuse `LoggingSession.fromFields` / `LoggingSessionFields.apply(to:)` |
| `QSOJournalStore.swift` | `FieldStore`-backed QSO journal store-access seam (Phase 1b): dirty page / clearDirty (CAR-245) / markAllDirty / inbound upsert+merge / softDelete / hasVisibleQSO. Not yet wired into the engine (device-gated 1c) |
| `CloudSyncConflictResolver.swift` | Pure-logic field-level merge for QSO / ServicePresence / LoggingSession / etc. |
| `CloudSyncSnapshotService.swift` | Upload/download whole-DB SQLite snapshot via `CKAsset` |
| `SnapshotValidator.swift` | Validate a downloaded snapshot before swapping it in |
| `LoggingSessionFields.swift` | `Sendable` field struct for the LoggingSession model |
| `CloudSyncZone.swift` | Shared `CKRecordZone.ID` constant for the journal zone |
| `CloudSyncEvent.swift` / `CloudSyncEventLog.swift` | Activity-log events surfaced in Settings |
| `CloudSyncSummary.swift` | Aggregated event-log summary for the Settings activity row |
| `CloudSyncRecordCounts.swift` | Snapshot of per-table dirty counts for the Settings panel |
| `SessionContinuityNotifications.swift` | `Notification.Name`s and userInfo keys for cross-device active-session continuity (CloudKit `cwLoggingSessionRemotelyChanged`, LAN `cwLANActiveSessionReceived`, local `cwLocalActiveSessionChanged`) |

### Repair (`Sources/CarrierWaveData/Repair/`)

Reusable seams for one-time data repairs. See `CONTEXT.md` for vocabulary.

| File | Purpose |
|------|---------|
| `BatchedRewrite.swift` | Predicate + per-row mutation, single pass. Owns the batched-fetch / save-per-batch invariants so repairs become 4-arg call sites. |
| `CrossBatchMerge.swift` | Collect snapshots across all batches → group/match → merge winner + delete loser. Split into `plan()` / `apply(_:)` so dry-run is free. |

### Protocols (`Sources/CarrierWaveData/Protocols/`)

| File | Purpose |
|------|---------|
| `AudioCaptureProtocol.swift` | Audio capture abstraction |
| `POTAAuthProvider.swift` | POTA authentication provider protocol |
| `RadioTransport.swift` | Radio transport abstraction |
| `SessionLifecycleAPI.swift` | Cross-platform session lifecycle vocabulary (active session, pause/resume/finish). iOS `LoggingSessionManager` and macOS `MacSessionManager` both conform (CAR-276) |

### Radio (`Sources/CarrierWaveData/Radio/`)

| File | Purpose |
|------|---------|
| `RadioProtocolHandler.swift` | Radio CAT command protocol abstraction |
| `RadioCommandDirection.swift` | TX/RX/status direction enum for transport log callbacks |
| `RadioSession.swift` | Transport-agnostic radio session with polling and state |
| `RadioSession+Duplex.swift` | IC-9700 Main/Sub helpers: `readSatelliteMode` / `setSatelliteMode` (`16 5A`), `readSelectedBand` (`07 D2`), `tuneSubBand` (`07 D1` → `05` → `06` → `07 D0` with polling paused, each step awaiting `FB`), `sendAwaitingAck` |
| `FrameAssembler.swift` | Protocol frame extraction from byte streams (CI-V, Kenwood, SmartSDR) |
| `CIVProtocolHandler.swift` | Icom CI-V protocol handler |
| `KenwoodProtocolHandler.swift` | Kenwood/Elecraft protocol handler |
| `YaesuProtocolHandler.swift` | Yaesu CAT protocol handler (IF-command polling); used by serial, CW Bridge, and SCU-LAN10 |
| `FlexProtocolHandler.swift` | FlexRadio SmartSDR ASCII command handler: slice tune, mode, PTT, CWX, subscriptions |
| `FlexRadioTransport.swift` | TCP transport for FlexRadio SmartSDR API (NWConnection, port 4992) |
| `SmartLinkAuth.swift` | Auth0 OAuth authentication for FlexRadio SmartLink (login, token refresh) |
| `SmartLinkClient.swift` | TLS client for SmartLink WAN server (radio discovery, connection brokering) |
| `IcomWiFiTransport.swift` | Icom WiFi/LAN (RS-BA1 UDP) transport: config, auth flow, keepalive, CI-V demux (scope frames → `scopeFrames`) |
| `IcomWiFiTransport+Packets.swift` | RS-BA1 packet builders and binary helpers |
| `UDPChannel.swift` | POSIX UDP socket wrapper |
| `SCULAN10Crypto.swift` | SCU-LAN10 packet framing + XOR crypto, channel/message-type enums, error type |
| `SCULAN10Transport.swift` | SCU-LAN10 `RadioTransport` actor: 4 UDP channels, auth, CAT/scope/audio streams, keepalives |
| `SCULAN10PortChannel.swift` | Raw POSIX UDP socket wrapper for one SCU-LAN10 port (internal) |
| `SCULAN10TransportDiagnostic.swift` | Audio-frame inspection/capture helpers for the SCU-LAN10 transport (internal) |
| `SCULAN10DebugStats.swift` | Per-channel packet-counter snapshot for the SCU-LAN10 debug view |
| `RSBA1Protocol.swift` | RS-BA1 protocol constants and passcode cipher |
| `RemoteSessionStateBridge.swift` | Converts between `CarrierWaveCore.RemoteSessionState` (LAN wire format) and `LoggingSession`: `init(session:)`, `LoggingSession.apply(remote:)`, `LoggingSession.makeFromRemote(_:)` |

### Satellite (`Sources/CarrierWaveData/Satellite/`)

Shared rotator / tracker layer for the iOS satellite tab and CW Sweep's Satellites workspace. Tests: `Tests/CarrierWaveDataTests/Satellite/`.

| File | Purpose |
|------|---------|
| `SatelliteDoppler.swift` | Doppler math from the engine's slant-range rate: `f_rx = f·(1 − ṙ/c)`, `f_tx = f·(1 + ṙ/c)`, shifts, `−ṙ/c` factor, 10 Hz rounding |
| `TrackerDevice.swift` | `TrackerKind` (CSN S.A.T. / PSR-100 / generic rotctld), `RotatorProtocolKind` (Hamlib TCP 4533, PSR-100 HTTP 8080, EasyComm II + GS-232B UDP 2390→2391, S.A.T. XML UDP 12000→12001), `RotatorPosition` (wrap/clamp/axis error), `TrackerEndpoint` (persisted choice + web UI URL), `DiscoveredTracker` |
| `RotatorProtocolCodec.swift` | Pure encoders/parsers for all five rotator protocols (move, position query, stop; single-axis S.A.T. replies merge onto the last reading) + `detectProtocol(fromReply:)` for discovery |
| `RotatorTransport.swift` | `RotctlTCPTransport` (NWConnection, newline replies), `PSR100HTTPTransport` (the Mk2's web server: `GET /command?cmd=…`, `/data` on connect — crosses VLANs, default for PSR-100) and `UDPRotatorTransport` (local port bound to the rotor's TX port so fixed-port and source-port replies both land) behind the `RotatorTransport` actor protocol; `TrackerEndpoint.makeTransport()` |
| `TrackerDiscoveryService.swift` | `@MainActor @Observable` LAN sweep: enumerates IPv4 interfaces (clamped to /24), probes TCP 4533 + `p` (S.A.T. vs PC rotctld told apart by the port-80 page), HTTP :8080 "PSR-100" fingerprint, and EasyComm/S.A.T.-XML UDP broadcast probes that reveal the PSR-100's configured protocol; `identify(host:)` probes one address (incl. unicast UDP) so the type is never chosen by hand; persisted `knownHosts` (probed directly every sweep) + `extraNetworks` (CIDRs, learned from any identified/saved host's /24 or added by hand) so rotors on other VLANs are found hands-free; `addManual` fallback |
| `TrackerAutoDetector.swift` | `@MainActor @Observable` hands-free detection: sweeps on start / `NWPathMonitor` change / every 3 min, silently re-links the remembered unit, raises `pending` for new units (pure `promptCandidate`/`autoConnectTarget` ranking S.A.T. > PSR-100 > PC rotctld), session dismiss vs persisted ignore; `DiscoveredTracker.detectedTitle/Message` prompt copy |
| `RotatorController.swift` | `@MainActor @Observable` rotator driver: connect/remember endpoint (UserDefaults), explicit follow mode, deadband + elevation floor, 1 s position polling with failure escalation (real transport error surfaced), stop/park/moveTo, manual `nudge` (pure `jogged` wrap/clamp), PSR-100 connects prefer HTTP control, pointing error |

### Utilities (`Sources/CarrierWaveData/Utilities/`)

| File | Purpose |
|------|---------|
| `MacGroupContainerMigration.swift` | macOS only: one-time move of CW Sweep's data (root `cw-store.*` + children of each `Library/<folder>/`, i.e. the SwiftData `CWSweep.store` and CloudKit assets) from the iOS-style `group.` container to the team-prefixed one macOS 15+ verifies from the signature — ends the per-launch "access data from other apps" prompt; conflict-checks before moving, marker set only after a full pass, outcome under `macGroupContainerMigration.lastOutcome` |
| `EquipmentStorage.swift` | Shared EquipmentType enum and UserDefaults-backed equipment list storage (antenna, key, mic) |
| `GearReminderStorage.swift` | Gear reminder model and iCloud KVS-backed storage for pre-session packing checklist |
| `KeychainHelper.swift` | Keychain credential storage |
| `HandoffConstants.swift` | Handoff activity types, userInfo keys, and HandoffSessionState for iOS↔macOS session continuity |
| `BoundedFetch.swift` | `BoundedDescriptor<T>` — compile-time enforced fetch limit (max 1,000) for QSO/ServicePresence queries |
| `BatchedFetch.swift` | `BatchedFetch<T>` — memory-safe batched iteration with fresh ModelContext per batch |
| `QSOMode.swift` | Shared metadata mode constants (WEATHER, SOLAR, NOTE) and filtering helpers |
| `PendingUploadReason.swift` | Enum classifying why a QSO is pending upload (missing fields, callsign mismatch, etc.) |
| `ServiceConfiguration.swift` | Utility to check which upload services have credentials configured (Keychain-based) |
| `ExperimentalFeature.swift` | Central registry of experimental features with maturity levels, descriptions, and UserDefaults opt-in gating |
| `WhatsNew.swift` | WhatsNewEntry/WhatsNewItem types (version, platforms, kind-tagged change rows) |
| `WhatsNewCatalog+ArchiveOldest.swift` | Oldest archived WhatsNewEntry release notes (cascade target when `+ArchiveOlder` exceeds the 500-line cap); concatenated after `archivedOlderEntries` |
| `WhatsNewCatalog.swift` | Static ordered catalog of WhatsNewEntry release notes — single source of truth for both platforms |
| `WhatsNewService.swift` | Tracks last-seen version in UserDefaults and computes unseen entries to present in WhatsNewSheet |
| `CatalogMatcher.swift` | Fuzzy string matching for equipment names against canonical catalog (Levenshtein + alias support) |
| `EquipmentMigration.swift` | Migrates legacy string-based equipment lists to structured EquipmentItem models with catalog matching |
| `ReferenceStatsLoader.swift` | Generic background actor for per-reference activation/QSO stats (parks, summits, WWFF) |
| `FullADIFExportActor.swift` | Background actor: batch-fetch all QSOs and stream full ADIF log to temp file (shared via ADIFExportConfig) |
| `FullQSONExportActor.swift` | Background actor: batch-fetch all QSOs and stream full QSON (QSO Object Notation) log to temp file |

### Contest (`Sources/CarrierWaveData/Services/Contest/`)

| File | Purpose |
|------|---------|
| `ContestTypes.swift` | Shared contest types: DupeStatus, QSOContestSnapshot, ContestScoreSnapshot, ContestOperatingMode |
| `ContestEngine.swift` | Pure-logic scoring and dupe-checking actor for contests |
| `ContestExchangeParser.swift` | Token classifier for contest exchange fields (RST, zone, section, serial, etc.) |
| `CabrilloExportService.swift` | Template-driven Cabrillo 3.0 log generator |
| `ContestTemplateLoader.swift` | Loads contest definitions from bundled JSON templates |
| `ContestEnrichmentMatcher.swift` | Maps contest IDs to enrichment source slugs (e.g. cwops-cwt → cwops); prefills name/identifier exchange fields from membership data |

### FT8 (`Sources/CarrierWaveData/`)

| File | Purpose |
|------|---------|
| `FT8QSOLogger.swift` | FT8CompletedQSOData struct and FT8QSOLogger protocol for QSO persistence |

### Views (`Sources/CarrierWaveData/Views/`)

| File | Purpose |
|------|---------|
| `ActivityGridCell.swift` | `ActivityGridColors` (green activation, blue hunter, purple AMT practice, platform `empty`) and `ActivityGridCell` — one activity-grid day shared by Field's `ActivityGrid` and CW Sweep's `ActivityGridMac`: diagonal split for activation + hunter, purple fill for practice-only days, purple corner dot when both |

### Another Morse Trainer (`Sources/CarrierWaveData/Services/AMT/`)

Shared AMT account + practice stats for Field and CW Sweep over the Rust `AmtApi` (email-link PKCE sign-in, token rotation, `/v1/me/stats`, offline snapshot). Tests: `Tests/CarrierWaveDataTests/AMT/AMTActivityTests.swift`.

| File | Purpose |
|------|---------|
| `AMTService.swift` | `@MainActor @Observable` singleton: `isSignedIn`/`account`/`stats`/`activityByUTCDay`/`pendingEmail`, `startSignIn(email:)`, `pollForCompletion`, throttled `refreshStatsIfNeeded` (15 min) / `refreshStats`, `signOut`; a dead session (user removed Carrier Wave in AMT) flips `isSignedIn` off |
| `AMTActivity.swift` | `AMTDayActivity` (seconds + level 1–4 → grid intensity) and `AMTActivityFormatting` (local `today` for the stats call, `yyyy-MM-dd` ↔ UTC/local day keys, `activityByUTCDay`, duration text) |

### WSJT-X (`Sources/CarrierWaveData/Services/Wsjtx/`)

Shared owner of the WSJT-X UDP listener (`WsjtxApi`, CAR-281) for CW Sweep and Field (CAR-282). Tests: `Tests/CarrierWaveDataTests/Wsjtx/WsjtxIngestServiceTests.swift` (dedup/insert decisions, ADIF twin, session attach, feed routing, settings persistence — no socket).

| File | Purpose |
|------|---------|
| `WsjtxIngestService.swift` | `@MainActor @Observable` service: UserDefaults-persisted `isEnabled`/`host`/`port` (default 127.0.0.1:2237), `start`/`stop`/`applyEndpoint` lifecycle with a generation token so stale callbacks are dropped, live state (`isRunning`, `lastError`, bounded `recentEvents`, counts, `lastLoggedSummary`), app hooks (`sessionProvider`, `stationCallsignProvider`, `commit`, `onQSOLogged`) |
| `WsjtxIngestService+Ingest.swift` | Message routing (`handleMessage`) and the insert path: `wsjtxMapQsoLogged`/`wsjtxMapLoggedAdif` → dedup by id (UUIDv5 of the WSJT-X key) and by `QSO.deduplicationKey` within a ±3 min same-callsign window → `FfiReflector.hydrate` → insert on the main context → `commit` (default `save()`; the `CwStoreMirror` follows). Attaches to the active `LoggingSession` when one exists |
| `WsjtxIngestTypes.swift` | `WsjtxIngestEvent` (feed line), `WsjtxIngestOutcome` (inserted/duplicate/failed), `WsjtxStatusSummary`, and `WsjtxDelegateBridge` (Rust-thread `WsjtxListenerDelegate` → `Sendable` event) |

### Macros (`Sources/CarrierWaveData/Macros/`)

User-authored CAT macros with placeholder substitution. Data-driven vendor command catalog so adding a new CI-V/Kenwood command ships as a JSON change, not a Swift release. `RadioMacroDocument` is the import/export format; `MacroExecutor` dispatches resolved steps through `MacroExecutorSink` (iOS wires it to `RadioSession`).

| File | Purpose |
|------|---------|
| `RadioMacro.swift` | `@Model RadioMacro` — SwiftData entity; steps/args stored as JSON blobs to avoid schema migrations on enum growth |
| `RadioMacroStep.swift` | Codable step enum: setFrequency / setMode / setPower / ptt / setRIT / setXIT / setRITXITOffset / clearRITXIT / sendCW / delay / vendorCommand / rawBytes. Every value field is `String` so placeholders work anywhere |
| `RadioMacroDocument.swift` | `.cwmacro` file format — `format` versioned wrapper around `RadioMacroSpec` + `RadioMacroArg` for sharable JSON |
| `RadioCommandSpec.swift` | Catalog command/param/value Codable types; param `type` discriminator (bool, enum, uint8/16/32/64, freqHz, string) |
| `RadioCommandCatalog.swift` | Process-wide registry; loads bundled `Resources/RadioCommands/*.json`; per-spec `encodePayload(args:engine:)` resolves placeholders, validates ranges/enums, emits raw bytes (CI-V) or ASCII (Kenwood) |
| `MacroContext.swift` | Live session context (myCall, FREQ, PARK, etc.); `value(forToken:)` resolves uppercase context tokens. `.preview` for editor/tests |
| `MacroTemplateEngine.swift` | `{TOKEN}` / `{name:format}` expansion. Format hints: `bcd2..bcd6` (CI-V LSB-first BCD), `hex2..hex8` (space-separated hex bytes), `dec3..dec4` (zero-padded decimal for Kenwood ASCII), `ascii` |
| `MacroExecutor.swift` | Stateless runner; protocol gate, arg validation, step dispatch via `MacroExecutorSink`. CI-V framing pulls slave address from the sink |
| `Resources/RadioCommands/civ-icom.json` | 15 commands for IC-7300/7610/705/9700: preamp, attenuator, NB, NR, compressor, monitor, VOX, AGC speed, split, VFO select/swap/equalize, memory select, RX filter, ATU tune |
| `Resources/RadioCommands/kenwood-elecraft.json` | TS-480/590/890/K3/KX2/KX3: menu (EX), VOX, power, NB |

#### State Profiles — "radio-as-code" (`Macros/StateProfile/`)

Declarative desired-state layer that compiles down to the imperative macro engine. Terraform-style `refresh → plan → apply → verify` loop. The planner is IO-agnostic via `RadioStateGateway`; runs against a mock, a raw-CAT transport, or a live `RadioSession`. Read-back for frequency/mode/power already exists via the protocol handler's decode + the session poll loop — there is no synchronous CAT query.

| File | Purpose |
|------|---------|
| `RadioStateField.swift` | `RadioStateCodec` (bidirectional decode/encode) + `RadioStateField` (CAT prefix + codec, readable flag); `kx2Spike` field set (FA/MD/PC + write-only RG) |
| `RadioStateProfile.swift` | `RadioStateProfile` (desired key→value map) + `builtIns`; `RadioStatePlanAction` (noChange/update/blindApply), `RadioStatePlan` (drift/changes/unverifiable/isConverged) |
| `RadioStateGateway.swift` | `RadioStateGateway` IO seam (currentValue/apply) + `RadioStateTransport` + `CatalogStateGateway` (codec over a raw transport) |
| `RadioStatePlanner.swift` | `RadioStatePlanner`: refresh, plan (diff), compile (→ `RadioMacroSpec`), apply (→ failed keys), verify |
| `RadioSessionStateGateway.swift` | `RadioControlSurface` (slice of `RadioSession`, conformed) + `RadioSessionStateGateway`: reads live `RadioState`, writes via typed setters with raw-ASCII fallback. Shared by iOS + Sweep |

