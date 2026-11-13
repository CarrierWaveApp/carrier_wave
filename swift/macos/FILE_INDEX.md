# CW Sweep File Index

## Root

| File | Description |
|------|-------------|
| `Package.swift` | SPM package manifest (executable target + test target) |
| `CLAUDE.md` | Project conventions and architecture overview |
| `docs/ElecraftK3ProgrammersReference.md` | Elecraft K3S/K3/KX3/KX2 Programmer's Reference (Rev G5) — CAT command reference |

## CWSweep/ — App Source

### Entry Point

| File | Description |
|------|-------------|
| `CWSweepApp.swift` | @main app with Window scenes, MenuBarExtra, ModelContainer setup; runs `MacGroupContainerMigration.runIfNeeded()` first thing in `init` |
| `CWSweepApp+Snapshot.swift` | Dev hook: `--snapshot-satellites <png> [secs] [--grid XX00]` opens the Satellites workspace, waits for live data + the saved rotator link, captures the main window's real content to a PNG (+ `.log`), and exits — headless UI screenshots without Screen Recording permission |
| `CWSweepApp+Wsjtx.swift` | Launch hook for the shared `WsjtxIngestService` (CAR-282): attaches the container, wires inserted QSOs to `QueryFacade.mirrorQSO` + `SelectionState.logInsertedQSORow`, starts the UDP listener if enabled |
| `ContentView.swift` | Root view delegating to WorkspaceView |

### Models/

| File | Description |
|------|-------------|
| `LayoutConfiguration.swift` | OperatingRole, SidebarItem, SidebarSection enums; layout state struct |
| `RadioProfile.swift` | RadioProtocolType, RadioModel (known radios), serial port config |
| `SelectionState.swift` | @Observable shared QSO selection state for inspector wiring |
| `SDRTranscriptModels.swift` | CW transcript structs: words, lines, QSO ranges, noise detection |

### Models/Spots/

| File | Description |
|------|-------------|
| `SpotSource.swift` | SpotSource enum (rbn, pota, sota, wwff, dxSummit, dxHeat, dxWatch, cluster) with display names and colors |
| `UnifiedSpot.swift` | Unified spot format with factory methods from each source type (incl. DX web APIs) |
| `DXWebSpot.swift` | Response models for DX Summit, DXHeat, DXWatch APIs + SplitInfoParser for comment parsing |
| `SpotRegion.swift` | SpotRegion (14 regions), SpotRegionGroup, EnrichedSpot, SpotSummary |
| `BandEdges.swift` | Band edge frequency definitions for band map canvas rendering |
| `ClusterNode.swift` | DX cluster node presets (W3LPL, VE7CC, etc.) and custom node support |
| `DXClusterSpot.swift` | Parsed DX cluster spot struct with mode guessing |
| `BandScopeFilterConfig.swift` | SpotStatusFilter enum, BandScopeFilterConfig defaults per operating role |

### Services/Serial/

| File | Description |
|------|-------------|
| `SerialPort.swift` | POSIX termios wrapper for USB serial (open, read, write, DTR/RTS) |
| `SerialRadioTransport.swift` | Actor conforming to RadioTransport; manages read loop + AsyncStream |
| `SerialPortMonitor.swift` | IOKit-based /dev/cu.* port discovery with USB hot-plug detection |
| `FrameAssembler.swift` | Actor assembling byte streams into CI-V, Kenwood, or SmartSDR protocol frames |

### Services/Radio/

| File | Description |
|------|-------------|
| `RadioProtocolHandler.swift` | Protocol for encode/decode of frequency, mode, PTT commands |
| `CIVProtocolHandler.swift` | Icom CI-V protocol handler wrapping CarrierWaveCore CIVProtocol |
| `KenwoodProtocolHandler.swift` | Kenwood CAT protocol handler wrapping CarrierWaveCore KenwoodProtocol |
| `ElecraftProtocolHandler.swift` | Elecraft K3/K4 handler extending KenwoodProtocolHandler with CW keying |
| `YaesuProtocolHandler.swift` | _(moved to shared CarrierWaveData/Radio/)_ Yaesu CAT protocol handler using IF command for efficient polling |
| `RadioSession.swift` | Actor managing transport + protocol; polls frequency/mode state |
| `RadioCommandLog.swift` | @MainActor @Observable ring-buffer log of TX/RX commands for in-app visibility |
| `FlexRadioTransport.swift` | TCP transport for FlexRadio SmartSDR API (NWConnection, port 4992) |
| `FlexProtocolHandler.swift` | SmartSDR ASCII command handler: slice tune, mode, PTT, CWX, subscriptions |
| `FlexDiscoveryService.swift` | @MainActor @Observable UDP discovery of FlexRadio devices on the LAN |
| `RadioManager.swift` | @MainActor @Observable managing multiple radio sessions (SO2R ready, Flex TCP + serial) |
| `RadioSlotState.swift` | RadioSlot enum (.a/.b), RadioSlotState (per-slot @Observable freq/mode/XIT/RIT), BridgeSlotState (per-slot CW Bridge state), RadioConnectError |
| `RadioManager+Slots.swift` | Slot bookkeeping (next-available, lookup), scope-span hook, multi-session polling loop |
| `RadioManager+CW.swift` | Unified CW keyer entry points (Bridge → WinKeyer → active radio's CAT handler), with cwKeyerAvailable() probe |
| `RadioManager+Bridge.swift` | RadioManager extension: CW Bridge connect flow, CWBP event handling, bridge-specific CW keyer commands |
| `RadioManager+BridgeSlots.swift` | Per-slot BridgeSlotState population + mirror helper called from bridge event observers |
| `RadioManager+Tune.swift` | Shared tuneToSpot() extension consolidating XIT-aware tune logic |
| `RadioManager+Duplex.swift` | IC-9700 satellite-mode duplex: `supportsSubBandDuplex`, `enterSatelliteMode` (reads `16 5A`, remembers it in `satelliteModeRestore`), `restoreSatelliteMode` (also on disconnect), `tuneSubBand` via `RadioSession.tuneSubBand` |
| `RadioManager+Persistence.swift` | Save/load detected RadioProfile per device fingerprint for auto-reconnect |
| `RadioAutoDetect.swift` | Host-side port of firmware autodetect: VID/PID baud hints + DetectError + Result |
| `RadioAutoDetect+Probes.swift` | CI-V identify + Kenwood `ID;` probes, byte-level response parsers |
| `BLERadioTransport.swift` | Actor: CoreBluetooth NUS transport for CW Bridge (RadioTransport + scanning) |
| `BLEDelegate.swift` | CBCentralManager/CBPeripheral delegate forwarding events to BLERadioTransport |
| `BridgeFrame.swift` | CWBP protobuf frame builders/parsers, BridgeEvent (incl. cwSpeedChanged), capability flags |
| `BridgeProtocol.swift` | Actor: CWBP framing layer over BLE (handshake, CAT passthrough, CW keyer, set-verify) |
| `BridgeRigDetector.swift` | Maps bridge-reported radio IDs to CW Sweep RadioProtocolType + radio name |
| `BridgeDiscoveryService.swift` | @MainActor @Observable BLE scanner for CW Bridge discovery and pairing |
| `WaterfallStore.swift` | @MainActor @Observable source-agnostic waterfall buffer (magnitudes, geometry, source label, line sequence, exclusive-source gating) |
| `IcomWaterfallData.swift` | @MainActor producer: reassembles Icom `27 00` scope frames (IC-9700 LAN / IC-705 WiFi) into `WaterfallStore` lines tagged Main/Sub |
| `RadioManager+Transport.swift` | Network transport factories (Icom WiFi, SCU-LAN10, FlexRadio) split out for file-length budget |
| `MacRadioSessionMacroSink.swift` | Bridges `MacroExecutorSink` to the active `RadioManager`/`RadioSession` for macro execution |
| `RadioProfileRunner.swift` | @MainActor entry point running a declarative `RadioStateProfile` against the active session (refresh→plan→apply→verify) via the shared `RadioSessionStateGateway`; triggered by the `profile <name>` palette command |

### Services/DXCC/

| File | Description |
|------|-------------|
| `DXCCLookupService.swift` | @MainActor @Observable: loads CTY.dat (bundled or downloaded), callsign-to-DXCC entity resolution |
| `DXCCNeededChecker.swift` | @MainActor @Observable: loads worked/confirmed entities from SwiftData, checks spots for needed status |

### Services/Export/

| File | Description |
|------|-------------|

### Services/Achievements/

| File | Description |
|------|-------------|
| `AchievementsFetcher.swift` | URLSession-based reader for the public `/v1/achievements` + `/v1/users/:callsign/achievements` endpoints (read-only, no auth) |

### Services/

| File | Description |
|------|-------------|
| `AccountService.swift` | `@MainActor @Observable` Carrier Wave account session for the Mac over the shared `OAuthClient` (platform macos): `requestLink(callsign:email:)` → poll until the emailed link is clicked (30 s send timeout), `cancel`, `signOut`, `accessToken()`; resumes a pending verification on `refresh()` |
| `ServerSync/ServerSyncService.swift` | Carrier Wave Sync front for the Mac (`@MainActor @Observable`, replaces the CloudKit `CloudSyncService`): owns the shared `SyncKeyService`, publishes `syncStatus`/`lastSyncDate`/`counts`/upload progress/`errorMessage`, `isEnabled` = signed in + local key; passes at launch (enrolled + seeded), every 5 min, 30 s after local `ModelContext.didSave`, on wake; `syncPending`, `forceFullSync`, `refreshCounts` (dirty QSOs from cw-store), `resetForLocalWipe` (cursor + seeded reset) |
| `ServerSync/SweepSyncLogSink.swift` | `ServerSyncLogging` sink → unified log (`ServerSync` category) + `CwStoreWriteLog` |
| `CwStoreSeams.swift` | `CwStoreSeams.save(_:qsos:sessions:spots:deletedSpots:)` — one-liner main-context save through `SeamWriteBatch` (cw-store first under `.on`), plain save when no seam is active |

| File | Description |
|------|-------------|
| `MacrosRegistryHolder.swift` | @MainActor @Observable wrapper around the shared `MacrosRegistryService` actor; configured at app launch |

### Services/Import/

| File | Description |
|------|-------------|
| `ADIFImportActor.swift` | Background actor importing ADIF files into SwiftData with dedup by `deduplicationKey` and ServicePresence creation |
| `ADIFRecordQSOFactory.swift` | Shared `ADIFRecord` → `QSO` construction (incl. `SAT_NAME`/`PROP_MODE`) + ServicePresence attach, used by the file importer and the S.A.T. listener |

### Services/SatLog/

| File | Description |
|------|-------------|
| `SatLogListenerService.swift` | @MainActor @Observable facade for the CSN S.A.T. satellite-tracker ADIF listener (CAR-343): enabled/transport/port settings (UserDefaults), status, recent records, parse → ingest hand-off |
| `SatLogListener.swift` | Actor owning the `NWListener` (UDP or TCP) that receives pushed ADIF; per-connection `SatLogRecordBuffer`, flushes partial TCP records on close |
| `SatLogRecordBuffer.swift` | Tolerant ADIF record splitter: bare records, `<eoh>` header, multi-record payloads, case-insensitive `<eor>`, TCP partial buffering |
| `SatLogIngestor.swift` | @MainActor SwiftData writer: `ADIFRecordQSOFactory` → dedup (bounded ±3 min fetch by `deduplicationKey`) → attach active session → save |
| `LANAddress.swift` | `getifaddrs` IPv4 enumeration (en0 first) shown in Settings so the S.A.T.'s QSO LOG IP is easy to fill in |

### Services/Jtty/

JTTY modem (CAR-351): WSJT-X 3.2's keyboard/contest mode, decoded and encoded by the GPL `jtty-sidecar` helper running as a separate process (shared-memory protocol v1). CW Sweep owns audio, PTT, macros and the terminal.

| File | Description |
|------|-------------|
| `JttyModels.swift` | `JttyDecodeResult`, `JttyTxRendering`, `JttyExchangeProfile` (serial / Field Day / RTTY Roundup), `JttySidecarStatus`, `JttyTerminalEntry` |
| `JttyShmLayout.swift` | Byte offsets, sizes and enums of the helper's `JttyShm` segment (protocol v1, `src/protocol.h`); pinned by `JttyShmLayoutTests` |
| `JttySidecarClient.swift` | Client side of the shared-memory protocol: `open(name:)` (shm_open via dlsym + mmap, header/version check), `writeReceiveAudio` (audio-thread ring writer), `drainResults`, async `transmit` (request/seq_done handshake, copies rendered PCM), search/command control |
| `JttySidecarProcess.swift` | Spawns `jtty-sidecar serve <name> --parent <pid>`, relays stderr lines, terminate backstop |
| `JttySidecarInstaller.swift` | Pinned release (`JttySidecarRelease`: version, URL, SHA-256), download + checksum + chmod + quarantine strip into Application Support, custom-path resolution, `version` probe |
| `MacAudioDevices.swift` | CoreAudio HAL enumeration (`MacAudioDevice`: id, UID, name, in/out channel counts, defaults) |
| `JttyAudioEngine.swift` | AVAudioEngine capture → mono Float32 → 12 kHz Int16 (AVAudioConverter) into the helper's ring; 48 kHz playback of rendered TX audio with played-back completion; per-UID input/output device selection via `kAudioOutputUnitProperty_CurrentDevice`; peak level callback |
| `JttyMacroExpander.swift` | WSJT-X F1–F8 templates (`%M %H %Q %E %N %G`), shipped defaults, profile exchange text, normalisation, missing-field check |
| `JttyService.swift` | ` ` modem: persisted settings (enable, devices, tone, profile, macros, auto-PTT, helper path, serial, exchange), helper lifecycle (install → spawn → wait for segment → audio → 50 ms result polling → health), terminal entries merged by message id, callsign token extraction |
| `JttyService+Transmit.swift` | Macro send, free-text send, serialised transmit chain (render → PTT lead → play → PTT release), abort |

### Services/Satellite/

Satellites workspace backend. Orbits, passes and transponders come from the shared Rust engine (`SatelliteApi`, same as iOS/Android); rotator + Doppler math from `CarrierWaveData/Satellite/`.

| File | Description |
|------|-------------|
| `SweepSatelliteEngine.swift` | Lazily-built shared `SatelliteApi` over `CwStoreProvider` (macOS twin of iOS `SatelliteEngine`) |
| `SatelliteModels.swift` | `SweepSatellite`/`SweepTransmitter` (bridged from FFI, `primary(in:)` tuning rule), `SweepPass` (AOS/peak/LOS, `countdown`), `SkyTrackPoint`, `SatelliteLiveLook` (dead-reckoning), `SatelliteDopplerReadout`, `SatelliteModeKind`, and `SatellitePassFrame` — the per-tick snapshot the views render |
| `SatellitePassModel.swift` | `@MainActor @Observable`: catalog load, observer from `myGrid`, 6 h upcoming list (active first, min-peak filter), selection + auto-advance after LOS, 1 Hz `look()` tick building the frame (predicted track from `groundTrack` clipped to the pass, flown track accumulated live), then pushes to `SatelliteCATController` and steers `RotatorController` (pre-positions to AOS azimuth 5 min early). Keeps running across sidebar tabs. Cache-first `load` (engine `loadCached`, background `refresh`; newer TLEs re-run the pass list) |
| `SatellitePassModel+Labels.swift` | `tleAgeLabel` and the FM uplink CTCSS table (`tonesHz`), split out for the type-body budget |
| `SatelliteCATController.swift` | Doppler CAT: tunes the downlink slot and the `SatelliteUplinkTarget` (second radio, or the IC-9700 Sub band in satellite mode) via `RadioManager` with 10 Hz rounding + 20 Hz deadband; modes once per satellite (USB down / LSB up on linear birds); reads the dial back through `SatelliteDialFollower`; keeps tuning the uplink during TX; restores satellite mode on disarm |
| `SatelliteDialFollower.swift` | Pure linear-transponder dial following: readbacks that are not a recent command (after a settle window, inside the passband) become an offset from the downlink low edge; `SatelliteDopplerReadout` applies it to the uplink, reversed on inverting transponders |
| `SatelliteWaterfallSynth.swift` | Deterministic synthetic waterfall lines (downlink ±25 kHz, flat-top signal width by mode, strength by range, seeded noise) for the corrected/uncorrected passband views |

### Services/VimMode/

| File | Description |
|------|-------------|
| `VimCommandParser.swift` | `VimCommand` enum + `:` command-line parser (radio, CW, cluster, activation, alerts, palette-parity navigation/info commands) |
| `VimActionExecutor+Palette.swift` | Vim `:` handlers mirroring command-palette actions — `freq`, `mode`, pane navigation, `sync [now]`, `inspector`, `role`, `find`/`last`/`count` (CAR-211) |

### Views/Achievements/

| File | Description |
|------|-------------|
| `AchievementBadgeView.swift` | macOS achievement tile (mirrors iOS look) |
| `AchievementShowcaseWindow.swift` | "Badges" Window scene: catalog grid grouped by category, lights up earned ones |
| `AchievementDetailPopover.swift` | Click-to-show popover (icon, tier, description, earned status) anchored to a tile |

### Services/Query/

| File | Description |
|------|-------------|
| `QuerySeedCoordinator.swift` | @Observable seed/delta-sync coordinator for the SQLite QSO mirror (5K-row batches) |

### Views/Query/

| File | Description |
|------|-------------|
| `QueryWorkbenchView.swift` | Split-pane workbench: saved-query sidebar, editor, results, profile panel |
| `QueryWorkbenchModel.swift` | @Observable model: SQL editor state, run/profile/save/import actions |
| `QueryEditorView.swift` | Multi-line SQL editor with error band |
| `QueryResultsView.swift` | Grid-based results table with sticky headers |
| `QueryColumnFormatters.swift` | Convention-based + columnHints overrides for known column types |
| `SavedQuerySidebar.swift` | Saved-query list with save/import sheet and share-as-URL context menu |
| `StarterQueries.swift` | Bundled starter library seeded into SavedQueryStore on first launch |

### Services/Spots/

| File | Description |
|------|-------------|
| `RBNClient.swift` | Actor wrapping Vail ReRBN API for reverse beacon spots |
| `SpotObservationMapper.swift` | UnifiedSpot → SpotObservationRow / SpotterRow for the SQLite mirror |
| `POTASpotsClient.swift` | Lightweight actor for unauthenticated POTA spot fetching |
| `DXSummitClient.swift` | Actor polling DX Summit REST API (dxsummit.fi) for DX spots |
| `DXHeatClient.swift` | Actor polling DXHeat REST API (dxheat.com) for DX spots with mode/grid/LoTW |
| `DXWatchClient.swift` | Actor polling DXWatch compact JSON API (dxwatch.com) with incremental polling |
| `HamDBClient.swift` | Actor wrapping HamDB.org API for grid/license lookups |
| `GridCache.swift` | GridCache + CallsignStateCache actors with 1-hour TTL |
| `SpotAggregator.swift` | @MainActor @Observable central service: polls, deduplicates, enriches spots |
| `SpotAggregator+Enrichment.swift` | SpotAggregator extension: enrichment, HamDB lookups, geo helpers |
| `PoloNotesStore.swift` | Actor managing Polo callsign notes: iCloud KVS config, disk cache, 24h refresh |
| `CallsignEnrichmentStore.swift` | Actor wrapping server enrichment dataset (CWops, future SKCC); disk cache, ETag, 12h refresh, sync lookup |
| `POTASpotService.swift` | POTA self-spot posting with re-spot timer and comment token expansion |

### Services/Cluster/

| File | Description |
|------|-------------|
| `DXSpotParser.swift` | Regex parser for DX cluster spot lines |
| `TelnetClusterClient.swift` | Actor using NWConnection TCP for DX cluster telnet connections |
| `ClusterManager.swift` | @MainActor @Observable managing cluster connection, scrollback, spot feed |
| `ClusterWorkedBeforeChecker.swift` | Caches today's QSOs for O(1) worked-before lookup by callsign+band+mode |

### Views/Workspace/

| File | Description |
|------|-------------|
| `WorkspaceView.swift` | Root NavigationSplitView; injects RadioManager, SpotAggregator, ClusterManager  |
| `VimWorkspaceBridge.swift` | ViewModifier consuming vim `SelectionState` requests (navigate, role, inspector, delete QSO) with the same handlers the command palette uses |
| `SidebarView.swift` | Section-organized navigation sidebar  Honors the `-initialSidebarItem <rawValue>` launch argument (`SidebarItem.fromLaunchArguments`) to open on a panel for checking |
| `ContentAreaView.swift` | Dispatches to role layouts or feature views based on sidebar selection |
| `InspectorView.swift` | Context-sensitive inspector panel (QSO detail view) |
| `StatusBarView.swift` | Bottom bar with QSO count, session duration, WSJT-X badge, radio status, satellite badge, UTC clock |
| `TrackerDetectedAlert.swift` | `.trackerDetectedAlert()` on the workspace: "CSN S.A.T. detected — Connect?" from `TrackerAutoDetector.pending` (Connect → link + jump to Satellites, Not Now, Ignore This Device) |
| `SatelliteStatusBadge.swift` | Status-bar pill (only while a rotator is linked or Doppler CAT is armed): rotator state + position, CAT summary, TLE age; click posts `.showSatellites` → Satellites sidebar item |
| `WsjtxStatusBadge.swift` | Status-bar chip shown while the WSJT-X listener runs: last logged QSO (or "listening"), counts in the tooltip |
| `SessionsSidebarRoot.swift` | Sessions sidebar dispatcher: idle → `SessionsLandingView`, pending intent → `SessionsComposerView`, active session → `CustomLayoutView` (non-contest) or `ContestSessionContainer` (contest). Both render through the unified `LayoutStore` + `LayoutRenderer` panel system. |
| `ContestSessionContainer.swift` | Contest session host: loads `ContestDefinition` for the active session's `contestId`, starts `ContestManager`, then renders the active `LayoutStore` layout through `LayoutRenderer` with `contestManager`/`contestDefinition` in `PanelContext`. Falls back to the built-in `contesterPreset` if the active layout has no contest panels. Owns the Sessions toolbar Cabrillo export and `CabrilloFile` document. |
| `SessionsLandingView.swift` | Intent-first landing for the Sessions sidebar item: 2×2 grid (Activate / Hunt / Casual / Contest) + Continue strip of paused sessions, mirroring iOS `SessionsIntentView` |
| `SessionsComposerView.swift` | Inline session composer (no modal). Intent-driven: Activate/POTA park typeahead + SOTA/WWFF, Contest typeahead, Hunt/Casual short-circuit. Auto-populates callsign (Keychain), grid (UserDefaults), freq/mode (RadioManager), power/antenna/rig (last session) |
| `SessionsComposerFields.swift` | Field components for `SessionsComposerView`: `SectionLabel`, `MonoTextField`, `ManualRefField`, `FrequencyReadout`, `ModeReadout`, `PowerField`, `FromRadioBadge`, `RadioStatusChip`, `NoRadioChip`, `RecentChipStrip` |
| `ContestSearchField.swift` | Inline contest typeahead used by `SessionsComposerView`. Live-now contests bubble to the top; filterable by name/id/sponsor. Driven by `ContestDefinitionsRefresher` |
| `SessionToolbarControl.swift` | Toolbar menu button next to `LayoutPicker` exposing End / Pause for the active session — observes `.didChangeLoggingSession` and acts via a local `MacSessionManager` |

### Views/Roles/

| File | Description |
|------|-------------|
| `CasualLayout.swift` | VSplitView: QSO log table + parsed entry |
| `HunterLayout.swift` | HSplitView: spot list | (entry + log + band map) |
| `ActivatorLayout.swift` | Two-state container: cold-start view or operating layout |
| `ContesterLayout.swift` | Entry + HSplitView: (log + rate) | band map |
| `DXerLayout.swift` | HSplitView: spots | (band map + entry + log) |

### Views/Activation/

| File | Description |
|------|-------------|
| `ColdStartView.swift` | Top-level cold-start layout: setup row + three-column HSplitView |
| `ColdStartView+SetupRow.swift` | Setup essentials row: park search, frequency, mode, callsign, start button |
| `ColdStartView+SessionSetup.swift` | Scrollable session setup: equipment, power, operators, rove, notes |
| `PropagationPanelView.swift` | Solar indices bar, band conditions grid, space weather alerts |
| `BandConditionTile.swift` | Single clickable band tile with day/night conditions |
| `SpaceWeatherView.swift` | DONKI geomagnetic/flare/CME status cards |
| `VerticalBandMapView.swift` | Vertical-axis Canvas band map with spot markers and frequency suggestion |
| `FrequencySuggestionView.swift` | Recommended frequency card with explanation |
| `PastActivationsListView.swift` | Scrollable past session list with qualified indicators |
| `ParkChangeDropdown.swift` | Popover for mid-session park changes with search + visited parks |
| `SessionHistoryPopover.swift` | Toolbar popover showing past activations |
| `ActivationHeader.swift` | Activation session header with park chip dropdown and history popover |
| `ActivationHeader+Spotting.swift` | POTA self-spot button + auto re-spot toggle for the activation header |
| `EquipmentPickerField.swift` | Equipment dropdown picker backed by EquipmentStorage |
| `RegulatedBandMapView.swift` | Band map with operator class privilege boundaries and click-to-tune |
| `RegulatedBandMapView+Canvas.swift` | Canvas drawing for regulated band map |
| `RovePlannerView.swift` | Map-based rove stop planner with distance calculation and drag-to-reorder |
| `ParkSearchField.swift` | Park reference/name text field with 300ms-debounced POTA autocomplete, recent parks, and selection callback |
| `OperatorChipsView.swift` | Operator chip list with auto-commit input field |

### Views/Logger/

| File | Description |
|------|-------------|
| `ParsedEntryView.swift` | Single-line parsed QSO entry using QuickEntryParser; logs to SwiftData. Accepts optional `contestManager`/`contestDefinition` — when set, the `.contestEntry` panel and the `qsoLog` panel reuse it in contest mode |
| `ParsedEntryView+CallsignLookup.swift` | Extension with DXCC/callsign/Polo lookup methods for ParsedEntryView |
| `ParsedEntryView+Contest.swift` | Contest add-ons for ParsedEntryView: ContestExchangeParser parsing of named exchange fields, live dupe / new-mult banner, exchange-field chip strip, ContestMacroBar, and `logContestQSO` routing into `ContestManager.logQSO` |
| `ParsedFieldSummary.swift` | Real-time FieldChip display of parsed fields (Call, Freq, Mode, etc.) |
| `QSOEntryPopupView.swift` | Persistent popup window with quick entry + dedicated fields for every QSO part |
| `QSOEntryPopupView+CallsignLookup.swift` | Extension with DXCC/callsign/Polo lookup methods for QSOEntryPopupView |
| `QSOLogTableView.swift` | SwiftUI Table with sortable columns; fetches QSOs from SwiftData |
| `SweepMembershipChip.swift` | Single-row chip for one organisation membership shown in the QSO entry popup info bar |

### Views/DXpeditions/

| File | Description |
|------|-------------|
| `DXpeditionsListView.swift` | macOS DXpeditions table with month navigation, filtering, and on-air badges |

### Views/Spots/

| File | Description |
|------|-------------|
| `SpotListView.swift` | Live spot table from SpotAggregator with source/band/region/text filters |
| `BandMapView.swift` | Canvas-based horizontal band map with color schemes, filter bar, aging, summary bar |
| `BandMapView+Drawing.swift` | Canvas drawing: sub-band shading, spot markers, VFO cursor with filter width |
| `BandMapView+Helpers.swift` | Spot priority, lane assignment, chip drawing, source-aware aging |
| `BandScopeFilterBar.swift` | Collapsible filter bar: source toggles, status filter, region toggles |
| `BandSummaryBar.swift` | Spot/new/mult counts per band with cross-band mult indicators |
| `SpotHitRects.swift` | Non-observed store for Canvas spot hit-test rects (avoids a @State redraw loop) |
| `ContestBandScopeView.swift` | Vertical-axis band scope with vim navigation, context menu, and click-to-tune |
| `ContestBandScopeView+HelpOverlay.swift` | Floating keyboard shortcut help overlay (? key) |
| `ClusterView.swift` | DX cluster main view: connection bar, command buttons, view mode switching, worked-before |
| `ClusterView+SmartTable.swift` | Smart spot table using enriched spots from SpotAggregator (RBN + cluster + DX web) |
| `ClusterView+RawViews.swift` | All Spots table (raw cluster) and Raw scrollback views |
| `ClusterSpotDetailView.swift` | Inspector panel showing spot details (frequency, distance, bearing, DXCC, worked status) |
| `SpotDetailInspector.swift` | Inspector panel: spot details, HamDB operator info, Polo notes, previous QSOs |
| `SpotDetailPane.swift` | Standalone layout pane wrapper for SpotDetailInspector via SelectionState |
| `CallsignModifiersView.swift` | Shared view displaying parsed callsign prefix/suffix modifiers with meanings |
| `WaterfallView.swift` | Canvas-rendered waterfall driven by `WaterfallStore` (works for SCU-LAN10, FlexRadio, future producers) |
| `WaterfallPanel.swift` | Layout panel wrapper around `WaterfallView` with placeholder when no producer is feeding the store |
| `WaterfallSpotOverlay.swift` | Spot-overlay strip for the waterfall panel |
| `ContestBandScopeView+Waterfall.swift` | Rotated 90° waterfall layer on the contest band scope, reads from `WaterfallStore` |
| `ContestBandScopeView+Rendering.swift` | Canvas drawing for the contest band scope (axis, ladder, spot rows) |
| `ContestBandScopeView+MiniMap.swift` | Mini-map overlay for the contest band scope |

### Views/Jtty/

| File | Description |
|------|-------------|
| `JttyTerminalPanel.swift` | `.jttyTerminal` panel: status chip / level meter / TX indicator header, scrolling terminal (received lines grow in place, sent in blue), his-call / queued / serial or exchange row with Log → `SelectionState.pendingSpotEntry`, F1–F8 macro bar with function-key shortcuts + Esc abort, free-text entry |

### Views/Satellites/

Satellites workspace (sidebar item in Operating): a desktop pass console on the Carrier Wave navy/indigo/amber/green/coral instrument theme. Everything renders from `SatellitePassModel.frame`.

| File | Description |
|------|-------------|
| `SatelliteTheme.swift` | Design tokens matching the rest of Carrier Wave: black canvas, systemGray6/5 cards, system blue (`accent`, track/selection) / yellow (`satellite`) / green (`rx`) / red (`tx`), monospaced numeric font, waterfall colormap (black → blue → green → yellow → red → white) with a 256-entry LUT |
| `SatellitesView.swift` | Root `SatellitesView(model:)`: header · (pass sidebar \| sky column + details) · waterfall · status row; `.task { model.start() }` and never stops tracking; `@AppStorage("satellite.waterfallCorrected")`; `.navigationTitle("CW Sweep — Satellites")` |
| `SatellitesView+Chrome.swift` | `SatellitesHeaderView` (title + selected satellite, CAT toggle, rotator-follow toggle, Corrected/Uncorrected picker, refresh, 1 Hz UTC clock) and `SatelliteStatusRowView` (rig + CAT, rotator state + kind, callsign, TLE age, grid) |
| `SatellitePassSidebarView.swift` | Upcoming-pass list: name, max el, AOS HH:mm UTC · duration, "LOS in m:ss" for the active pass / "AOS in m:ss" under an hour, indigo selection + amber active bar; loading / failed+Retry / no-grid / no-passes (min-peak stepper) states |
| `SatelliteSkyPlotView.swift` | Polar sky plot Canvas in a 30 fps `TimelineView` (horizon/30°/60° rings, N/E/S/W, dashed predicted + solid flown tracks as cached unit paths, AOS/LOS labels, amber bearing line + pulsing dead-reckoned marker, green rotator reticle), `SatelliteLookReadoutView` (AZ/EL, range, range rate) and `SatelliteElevationProfileView` (elevation vs time with amber now-cursor) |
| `SatellitePassDetailView.swift` | Right-column cards: identity (display name, NORAD, mode line + CTCSS, RX/TX PTT pill, rig frequency), Doppler RX (green) / TX (coral, tinted while keyed, "—" for beacons) rows, six stat tiles (range, range rate, LOS/AOS countdown, max el, altitude, S-meter), rotator card (state, Az/El, pointing error, Park/Stop) |
| `SatelliteWaterfallView.swift` | `SatelliteWaterfallBuffer` (120-line ring buffer fed by `SatelliteWaterfallSynth` every 150 ms) + Canvas blitting one LUT-colored image per repaint; dashed rig-tuned marker, MHz scale, ±25 kHz hint, corrected/uncorrected legend |
| `SatellitePointTrackButton.swift` | "Point & Track" under the sky plot (rotator linked + pass selected): slews to the satellite's az/el or rise azimuth and turns Follow on; shows the commanded pointing while tracking, second click stops |
| `SatellitesView+Keys.swift` | `.rotatorArrowKeys(_:)` on the workspace root: arrow keys jog the linked rotator by the manual step (⇧ 15°, ⌥ 1°, key repeat while held), Esc stops; text fields keep their own arrows |
| `SatelliteRotatorManualControls.swift` | Hand controls inside the rotator card: jog pad with 1°/5°/15° step (`RotatorController.nudge`), go-to AZ/EL, Park, coral Stop; manual moves leave follow mode. Also `HoldRepeatJogButton` (hold-to-repeat jog, tint params default to `SatelliteTheme`) reused by `RotatorManualSection` |
| `SatellitePassFormatting.swift` | `SatellitePassFormat` pure helpers: UTC clock/HH:mm, countdowns, MHz/kHz/degree/km formatting, polar projection + unit track paths, pass fraction |

### Views/Rotator/

| File | Description |
|------|-------------|
| `RotatorControlView.swift` | Sidebar → System → Rotator console in the Radio/WinKeyer idiom (headline row + link-state pill, full-width `GroupBox`es, no fixed widths): `RotatorStatusRows`, `RotatorManualControls` (hold-to-repeat jog pad via `HoldRepeatJogButton`, shared `rotator.manualStepDeg` step, go-to AZ/EL, Park, red Stop, commanded target), `TrackerDiscoveryRows` + Scan button, `TrackerManualAddRows`; Doppler CAT stays in Settings |
| `RotatorLinkSections.swift` | Context-neutral row groups shared by the Rotator panel (GroupBox) and Settings → Trackers (Form): `RotatorStatusRows` (endpoint, link dot, reported AZ/EL, connect/disconnect/park/stop/forget, minimum-elevation slider), `RotatorStateStyle.color`, `TrackerDiscoveryRows` + `TrackerDiscoveryScanButton` + `TrackerDiscoveryFooter`, `TrackerManualAddRows` (owns the identify flow, fallback type pickers, extra-network chips); plus the Form wrappers `RotatorStatusSection` / `TrackerDiscoverySections` |

### Views/FT8/

| File | Description |
|------|-------------|
| `FT8OperatingView.swift` | Main FT8 view composing controls, waterfall, decode list, TX log, QSO state bar |
| `FT8WaterfallView.swift` | Canvas-rendered spectrogram with decode markers, TX cursor, click-to-set-frequency |
| `FT8DecodeListView.swift` | SwiftUI Table: UTC, dB, Hz, Message, DXCC, Distance columns with context menu |
| `FT8ControlsView.swift` | Band picker, mode buttons, TX state display, cycle countdown, audio input picker |

### Views/Panadapter/

| File | Description |
|------|-------------|
| `PanadapterView.swift` | Canvas-rendered wideband waterfall with spot overlay, spectrum line, click-to-tune |

### Views/Contest/

| File | Description |
|------|-------------|
| `ContestBrowserView.swift` | Full catalog with list/calendar toggle, NavigationSplitView master-detail, mode chips in rows |
| `ContestDetailMacView.swift` | Rich detail: header with live indicator, chip bar, two-column exchange+scoring, rules, categories, source |
| `ContestPickerView.swift` | Sheet for selecting a contest from the server-published catalog |
| `ContestCalendarView.swift` | Month/week/day calendar with mode picker, month grid, day-click detail pane, UTC scheduling |
| `ContestCalendarTimeline.swift` | CalendarContest struct, CalendarFormatters, WeekTimelineView with 7-column event blocks |
| `ContestCalendarDayView.swift` | DayTimelineView with 24-hour timeline, positioned event blocks, scroll-aware hints, now indicator |
| `ContestScoringPipelineView.swift` | Visual scoring pipeline: per-QSO rules, multiplier phases, aggregate formula with connecting arrows |
| `ContestChips.swift` | Reusable ContestChip, ContestModeChips (color-coded CW/SSB/RTTY), ContestBandChips |
| `ContestMacroBar.swift` | CW message buttons (CQ / Exch / TU / His Call / Stop) sent via RadioManager keyer, with call+serial token expansion |
| `ContestBandBreakdown.swift` | Compact per-band QSO/multiplier strip derived from the running score snapshot |
| `ContestPanels.swift` | Contest panel views surfaced through `PanelRegistry`: `ContestScorePanel` (header + category/power/overlay pickers + off-time/band-change readouts), `ContestBandBreakdownPanel`, `ContestRecentQSOsPanel`, `ContestPanelPlaceholder` (shown outside contest sessions) |

### Views/WhatsNew/

| File | Description |
|------|-------------|
| `WhatsNewSheet.swift` | Post-update release-notes sheet (cards per version, kind-tagged item rows, fixed window size) |

### Views/Other

| File | Description |
|------|-------------|
| `Radio/RadioControlView.swift` | Top-level USB / TCP-IP / CW Bridge segmented picker shell, gear popover, error banner |
| `Radio/USBRadioSection.swift` | USB port list with autodetect-on-Connect (CI-V then Kenwood `ID;`) |
| `Radio/ManualOverrideRow.swift` | Per-port protocol+baud override shown when autodetect fails |
| `Radio/TCPIPRadioSection.swift` | Network sub-picker (Flex / SCU-LAN10 / Icom WiFi) and section dispatcher |
| `Radio/FlexRadioSection.swift` | FlexRadio network discovery UI with manual IP entry and connect controls |
| `Radio/SCULAN10Section.swift` | SCU-LAN10 host/port/credentials inline + connect with retry |
| `Radio/IcomWiFiSection.swift` | Icom RS-BA1 host/credentials inline + radio model picker |
| `Radio/CWBridgeSection.swift` | CW Bridge BLE discovery, pairing, connect, and status/diagnostics panel |
| `Radio/CommandLogSection.swift` | Live TX/RX command log with copy/clear |
| `Radio/RadioPreferencesPopover.swift` | Auto-connect / poll interval / Auto-XIT settings (gear-icon popover) |
| `Settings/SettingsView.swift` | Tab-based settings (General, Sync, Keyer, Accounts, Notes, Data, POTA, Remote, S.A.T., SDR, Vim Mode, Macros) — radio + WinKeyer hardware live in their feature panels |
| `Settings/SettingsView.swift` | Tab-based settings (General, Sync, Keyer, Accounts, Notes, Data, POTA, Remote, WSJT-X, SDR, Vim Mode, Macros) — radio + WinKeyer hardware live in their feature panels |
| `Settings/CallsignNotesSettingsTab.swift` | Manage Polo callsign notes sources (add/delete/toggle, iCloud KVS sync) |
| `Settings/DataSettingsTab.swift` | Data management: QSO count overview, clear log with backup and confirmation |
| `Settings/SDRSettingsTab.swift` | External SDR waterfall input: device (SoapySDR detect / rtl_tcp / test tones), IF-tap vs direct-RF mapping, K3 preset, per-mode IF calibration, span/fps |
| `Settings/AMTAccountSection.swift` | Another Morse Trainer section of the Accounts tab: email-link sign-in via the shared `AMTService`, connected account + practice streak, refresh, sign out |
| `Settings/POTASettingsTab.swift` | POTA settings (license class, auto-spot, re-spot timer, comment template) |
| `Settings/RemoteSettingsTab.swift` | Start/stop the Remote LAN server, show 6-digit pairing code, manage paired iOS devices |
| `Settings/CarrierWaveSyncSettingsTab.swift` | Settings → Sync (replaces the iCloud tab): server row, account-required notice, passphrase create / unlock / forget, status, last sync, pending count, Sync Now, Upload Full Log, last summary + Share Sync Report; mirrors iOS `SyncPassphraseView` over `ServerSyncService` |
| `Settings/CarrierWaveAccountSection.swift` | Settings → Accounts → "Carrier Wave Account": callsign (prefilled from `myCallsign`) + optional email, Send Sign-in Link / waiting / failed states, signed-in status with account id and Sign Out; drives `AccountService` |
| `Settings/TrackersSettingsTab.swift` | Settings → Trackers: `RotatorStatusSection` + `TrackerDiscoverySections` (shared with the Rotator sidebar panel) plus the Doppler CAT toggle + downlink/uplink slot pickers (`SatelliteCATController`) |
| `Settings/SatLogSettingsTab.swift` | S.A.T. tracker listener: enable toggle, UDP/TCP picker, port, LAN IP list with copy, status/last error, recent records, S.A.T. setup footnote |
| `Settings/WsjtxSettingsTab.swift` | WSJT-X UDP listener (CAR-282): enable toggle, host/port (default 127.0.0.1:2237) committed on submit/blur, running/stopped + last error, session counts, WSJT-X status line, live feed of decodes/logged/duplicate events; footer explains WSJT-X → Settings → Reporting → UDP Server |
| `Settings/JttySettingsTab.swift` | JTTY modem (CAR-351): enable toggle + status, helper install/reinstall/custom path, receive/transmit device pickers (`MacAudioDevices`), tone frequency, exchange profile, auto-PTT, F1–F8 template editor with WSJT-X defaults, helper log |
| `Settings/Macros/MacrosLibrarySettingsTab.swift` | Settings tab that hosts `MacrosLibraryView` inside a NavigationStack |
| `Settings/Macros/MacrosLibraryView.swift` | Top-level radio macros library (segmented Mine / Browse / Updates) |
| `Settings/Macros/MacrosLibraryView+Mine.swift` | User-authored macros tab with @Query, context menu duplicate/delete |
| `Settings/Macros/MacrosLibraryView+Browse.swift` | Registry browse tab with search-debounced server pagination |
| `Settings/Macros/MacrosLibraryView+Updates.swift` | Update list driven by `MacrosRegistryHolder.snapshot.pendingUpdates` |
| `Settings/Macros/MacroDetailView.swift` | Read-only detail with capability chips, steps, Run/Edit/Export toolbar |
| `Settings/Macros/MacroEditorView.swift` | Full editor (header / capabilities / args / steps in extensions) |
| `Settings/Macros/MacroEditorView+HeaderSection.swift` | Identity + icon picker + tags + applies-to editors |
| `Settings/Macros/MacroEditorView+CapabilitiesSection.swift` | Capability toggles with inferred-vs-declared conflict resolution |
| `Settings/Macros/MacroEditorView+ArgsSection.swift` | Args list with add/edit sheets and `MacroDraftArg` form |
| `Settings/Macros/MacroEditorView+StepsSection.swift` | Steps list with reorder/delete context menu + step kind picker |
| `Settings/Macros/MacroRunSheetView.swift` | Run UI: arg prompts, safety banner, live log, outcome banner |
| `Settings/Macros/MacroRunWindowController.swift` | NSHostingView-backed NSWindow wrapper for `MacroRunSheetView` |
| `Settings/Macros/MacroBrowseDetailView.swift` | Registry-side detail view for an uninstalled macro with Install button |
| `Settings/Macros/MacroUpdateReviewView.swift` | Diff-and-apply sheet for a pending registry update |
| `Settings/Macros/MacroImportSheet.swift` | Cwmacro import flow with provenance routing and raw-bytes confirmation |
| `Settings/Macros/MacroCapabilityChips.swift` | Compact + full capability chip strips reused across the library |
| `Settings/Macros/MacroAppSafetyEnvironment.swift` | `MacroSafetyEnvironment` over `SharedEnvironment.shared.radioManager` |
| `Settings/Macros/StepEditors/MacroStepEditorSheet.swift` | Dispatch sheet routing to per-kind step editors |
| `Settings/Macros/StepEditors/MacroStepKindPicker.swift` | Grouped picker for adding new steps (radio/ptt/cw/flow/advanced) |
| `Settings/Macros/StepEditors/*StepEditor.swift` | Per-kind step editors (Delay/Frequency/Mode/Power/PTT/CW/RawBytes/ReadField/WaitUntil/Assert/VendorCommand) |
| `CommandPalette/CommandPaletteView.swift` | Cmd+K command palette with frequency/callsign/park detection; hosts `CommandPaletteFrequencyParser` (kHz/MHz rules shared with vim `:freq`) |
| `CommandPalette/RadioPaletteView.swift` | Cmd+Shift+P radio command palette with parse-and-confirm pattern |
| `CommandPalette/PaletteQSOQueries.swift` | Bounded, UUID-deduped QSO/session lookups (`FIND`/`LAST`/`COUNT`) shared by the radio palette and vim `:find`/`:last`/`:count`; owns `QSOSearchResult` |
| `MenuBarExtra/MenuBarExtraView.swift` | Menu bar extra showing solar conditions + session summary |
| `Dashboard/DashboardView.swift` | Dashboard with QSO counts, band breakdown, rate chart, the activity grid (per-UTC-day activation/hunter counts from the QSO scan), and the Another Morse Trainer streak card when connected |
| `Dashboard/ActivityGridMac.swift` | GitHub-style activity grid mirroring Field's: 7×weeks UTC grid, month labels, legend, hover tooltips; cells are the shared `ActivityGridCell` with AMT practice days in purple |
| `GridTracker/GridTrackerView.swift` | Grid tracker view with heatmap, stats, and worked grid list |
| `GridTracker/GridHeatmapMac.swift` | Canvas-based Maidenhead field heatmap with click-to-filter |
| `GridTracker/GridDataActor.swift` | Background actor for computing grid statuses from QSO data |
| `Map/QSOMapView.swift` | MapKit map plotting QSO locations from grid squares with band colors and date filter |
| `Map/ActivationMapPane.swift` | Activator map pane: QSO dots, geodesic arc during callsign entry, mode-driven spot rendering, local SQL query runner |
| `Map/ActivationMapPane+Overlays.swift` | RBN skimmer, all-spots, SQL-query, and geodesic-arc map content overlays |
| `Map/ActivationMapPane+Toolbar.swift` | Toolbar + spot-mode Menu picker (Off / RBN / All Spots / Saved SQL Query) |
| `Map/ActivationMapPane+Camera.swift` | Camera/region helpers and great-circle geodesic path computation |
| `FinderDropTarget.swift` | View modifier that accepts `.cwmacro` Finder drops, presents `MacroImportSheet` |
| `AppDelegate/MacroURLHandler.swift` | Parses `cwmacro://` + `https://carrierwave.app/m/<slug>` and bridges to `FinderDropTarget` |

### Services/Contest/

| File | Description |
|------|-------------|
| `ContestClient.swift` | Lightweight client for fetching contest definitions from activities server (no auth) |
| `ContestDefinitionsRefresher.swift` | @MainActor @Observable: coordinates fetching + caching contest definitions via ContestDefinitionsStore |
| `ContestManager.swift` | @MainActor @Observable bridge to ContestEngine: serial assignment, DXCC enrichment, SwiftData persistence, category/power, dupes/mults, live score, Cabrillo export |

### Services/Awards/

| File | Description |
|------|-------------|
| `WASTracker.swift` | Worked All States tracker: WASProgress struct, 50-state computation from QSO snapshots |
| `WAZTracker.swift` | Worked All Zones tracker: WAZProgress struct, 40 CQ zone computation from QSO snapshots |
| `AwardsDashboardService.swift` | AwardsComputationActor: loads CTY.dat, fetches QSOs, computes WAS+WAZ progress |

### Services/FT8/

| File | Description |
|------|-------------|
| `FT8Models.swift` | FT8OperatingMode, FT8TXEvent, FT8TXState, ChannelRecommendation, FT8CompletedQSOData, FT8QSOLogger protocol, MacAudioInputInfo |
| `MacFT8AudioEngine.swift` | Actor-based audio engine using AVAudioEngine + CoreAudio device enumeration, anti-alias FIR decimation |
| `MacFT8WaterfallData.swift` | @MainActor @Observable FFT spectrogram (2048-point, Hann window, vDSP, 100-3000Hz range) |
| `MacFT8DecodeEnricher.swift` | Enriches FT8 decodes with DXCC entity, needed status, distance/bearing, worked-before |
| `MacFT8SessionManager.swift` | @MainActor @Observable FT8 session orchestrator: slot timing, decode handling, QSO logging |

### Services/Panadapter/

| File | Description |
|------|-------------|
| `FlexPanadapterService.swift` | @MainActor @Observable: UDP listener + `display pan create` driver that pushes SmartSDR spectrum lines into `WaterfallStore` |
| `IQPanadapterService.swift` | @MainActor @Observable bridge from the Rust `PanadapterHandle` (cw-sdr) to `WaterfallStore` (`.sdr`, exclusive while enabled); CAT tuning push, IF calibration, `PanadapterEventListener` |
| `SDRInputSettings.swift` | Codable UserDefaults settings for the SDR input + K3 preset + FFI record conversion |
| `Vita49Frame.swift` | Minimal VITA-49 packet parser (stream ID, class ID, payload) used by `FlexPanadapterService` |

### Services/Propagation/

| File | Description |
|------|-------------|
| `Services/Propagation/PropagationService.swift` | @MainActor @Observable service wiring HamQSL + DONKI + PropagationEstimator |
| `Services/Propagation/FrequencySuggestionEngine.swift` | Pure logic: General+ frequency gap finding from spot activity |

### Services/AI/

| File | Description |
|------|-------------|
| `SmartCallsignCompleter.swift` | Actor: learns from QSO history, ranks callsign suggestions by frequency/recency/needed |
| `PropagationPredictor.swift` | Actor: analyzes QSO history patterns to predict band openings by entity/band/hour/month |
| `NaturalLanguageLogSearch.swift` | Pattern-matching log search parser: entity, band, mode, date ranges, grid, park refs |

### Services/MultiOp/

| File | Description |
|------|-------------|
| `MultiOpProtocol.swift` | Codable message types for multi-operator networking: QSO, dupe check, multiplier, band lock |
| `MultiOpServer.swift` | Actor TCP server with Bonjour advertisement for multi-operator contest logging |
| `MultiOpClient.swift` | @MainActor @Observable: Bonjour discovery, connect/disconnect, dupe checks, band locks |

### Services/SDRReceiver/

| File | Description |
|------|-------------|
| `RTLSDRClient.swift` | Actor: rtl_tcp client with 5-byte command protocol, I/Q processing, FFT spectrum |
| `SDRReceiverManager.swift` | @MainActor @Observable: manages SDR receiver connections and CW skimmer pipeline |

### Services/Handoff/

| File | Description |
|------|-------------|
| `HandoffService.swift` | @MainActor @Observable: NSUserActivity-based iOS↔macOS session handoff |

### Services/PTT/

| File | Description |
|------|-------------|
| `MacroEngine.swift` | Per-mode F1-F12 macro system with ESM sequencing and variable expansion |
| `VoiceKeyerService.swift` | SSB voice keyer: record/playback, TTS callsign insertion, DVK CQ loop |

### Services/Remote/

| File | Description |
|------|-------------|
| `RemoteOpService.swift` | @MainActor @Observable: NWListener + Bonjour, paired-device registry, 6-digit pairing code, broadcast surface |
| `RemoteOpService+CW.swift` | CW keyer command handlers and `currentCWStatusSnapshot()` (split off main type to keep body under 300 lines) |
| `RemoteOpService+Multipeer.swift` | MPC advertiser hookup + `acceptConnection`/`acceptTransport` plumbing for both LAN and MPC transports |
| `MultipeerTransportListener.swift` | `MCNearbyServiceAdvertiser` wrapper that accepts MPC invitations and feeds the session into `RemoteOpService.acceptTransport(_:)` |
| `RemoteOpConnection.swift` | Actor: per-client transport-driven receive loop, frame dispatch, hello/pair handshake, subscription registry |
| `RemoteOpConnection+CW.swift` | CW keyer dispatch handlers + `requireAuth` helper + `sendCurrentCWStatus` snapshot |
| `RemoteOpConnection+Waterfall.swift` | Initial `WaterfallClearedEvent` snapshot helper for the `radio.waterfall` topic |
| `RemoteOpPublishers.swift` | @MainActor: bridges RadioManager + SpotAggregator to RemoteOpService via withObservationTracking; emits `cw.keyer` and `radio.waterfall` snapshots (10 fps throttle) |
| `SpotAggregator+Remote.swift` | EnrichedSpot → wire RemoteSpot conversion with band/mode/source/needed/snr filters |

### Commands/

| File | Description |
|------|-------------|
| `CWSweepCommands.swift` | Menu bar commands: Radio, Logging, Spots, Sync menus |

### Utilities/

| File | Description |
|------|-------------|
| `PlaceholderView.swift` | Generic placeholder view for unimplemented features |
| `FocusedValues.swift` | FocusedValueKey definitions for menu command wiring |
| `SpotColorScheme.swift` | BandScopeColorMode enum (contest/dxcc/freshness/source) + color resolver |
| `SpotListOrdering.swift` | Pure spots-list ordering rules: default sort constant, self-spot detection, pin-own-spots-to-top under the default sort |
| `SpotTuneDestination.swift` | Where a spot tune lands (radio / SDR waterfall / log entry only): context-menu footnote and no-radio status line |
| `SpotFilterComponents.swift` | Shared filter bar components: BandFilterPicker, ModeFilterPicker, SpotSearchField, SpotFilterConstants |
| `SpotEntryBridge.swift` | Singleton bridge to pass spot selection from workspace to Add QSO popup window |
| `CallsignComponents.swift` | Callsign parser: base call extraction, prefix/suffix modifier decoding with DXCC entity resolution |
| `DismissOnOutsideInteraction.swift` | View modifier + frame-capture helper that closes a typeahead overlay on Escape or left-click outside the field/overlay frames (used by ParkSearchField, ContestSearchField) |

## CWSweepTests/

| File | Description |
|------|-------------|
| `CWSweepTests.swift` | Tests for OperatingRole, SidebarSection, RadioModel, FrameAssembler, protocols |
| `RadioAutoDetectTests.swift` | Tests for host-side autodetect: cable hints, baud candidates, CI-V/Kenwood parsers, profile mapping |
| `SpotTypeTests.swift` | Tests for UnifiedSpot, SpotRegion, EnrichedSpot, POTASpot, SpotSource |
| `SpotListOrderingTests.swift` | Tests for `SpotListOrdering`: self-spot detection, default-sort detection, stable self-spot pinning |
| `SpotTuneDestinationTests.swift` | Tests for `SpotTuneDestination` resolution, footnotes and status lines |
| `DXSpotParserTests.swift` | Tests for DX cluster spot line parsing and mode guessing |
| `BandEdgesTests.swift` | Tests for band lookup, x-position calculation, roundtrip, boundaries |
| `ContestDefinitionTests.swift` | Tests for contest definition loading and rule parsing |
| `ContestEngineTests.swift` | Tests for contest scoring engine |
| `ContestExchangeParserTests.swift` | Tests for contest exchange field parsing |
| `CWKeyerTests.swift` | Tests for CW keyer timing and character encoding |
| `CabrilloExportTests.swift` | Tests for Cabrillo contest log export format |
| `N1MMBroadcastTests.swift` | Tests for N1MM+ UDP broadcast interop |
| `ContestTemplateLoaderTests.swift` | Tests for contest template YAML loading |
| `ContestManagerTests.swift` | Tests for contest state management |
| `WaterfallTests.swift` | Tests for `WaterfallStore` (append/clear/setReceiving), VITA-49 parser, and Flex stream-handle decoding |
| `SatellitePassTests.swift` | `SweepPass` countdown/state, `SatelliteDopplerReadout` sign convention (ISS ±10 kHz / ±3.4 kHz), primary-transmitter rule, frame countdown/S-meter, dead-reckoning wrap, waterfall synth (signal placement corrected vs uncorrected, noise-only below horizon, determinism), Satellites sidebar section |
| `SatelliteDuplexTests.swift` | `SatelliteDopplerReadout` with a passband offset (inverting / non-inverting), `SatelliteDialFollower` rules (FM ignored, settle window, echo tolerance, fast-Doppler memory, passband rejection + clamp, reset), `SatelliteUplinkTarget` raw round-trip and legacy uplink-slot migration |
| `SatLogListenerTests.swift` | `SatLogRecordBuffer` tolerance (bare/header/multi/case/TCP partial), satellite field preservation through `ADIFRecordQSOFactory`, `SatLogIngestor` dedup on retransmit + session attach |
| `SDRPanadapterTests.swift` | `WaterfallStore` exclusive-source gating, IF calibration peak search, K3 preset, end-to-end tone source through the Rust `cw-sdr` pipeline |
