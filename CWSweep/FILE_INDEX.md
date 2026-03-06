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
| `CWSweepApp.swift` | @main app with Window scenes, MenuBarExtra, ModelContainer setup |
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
| `SpotSource.swift` | SpotSource enum (rbn, pota, sota, wwff, cluster) with display names and colors |
| `RBNSpot.swift` | Decodable struct for Reverse Beacon Network spots |
| `POTASpot.swift` | Decodable struct for POTA spots with timestamp parsing and state extraction |
| `SOTASpot.swift` | Decodable struct for SOTA spots with summit details |
| `WWFFSpot.swift` | Decodable struct for WWFF spots |
| `UnifiedSpot.swift` | Unified spot format with factory methods from each source type |
| `SpotRegion.swift` | SpotRegion (14 regions), SpotRegionGroup, EnrichedSpot, SpotSummary |
| `BandEdges.swift` | Band edge frequency definitions for band map canvas rendering |
| `ClusterNode.swift` | DX cluster node presets (W3LPL, VE7CC, etc.) and custom node support |
| `DXClusterSpot.swift` | Parsed DX cluster spot struct with mode guessing |

### Services/Serial/

| File | Description |
|------|-------------|
| `SerialPort.swift` | POSIX termios wrapper for USB serial (open, read, write, DTR/RTS) |
| `SerialRadioTransport.swift` | Actor conforming to RadioTransport; manages read loop + AsyncStream |
| `SerialPortMonitor.swift` | IOKit-based /dev/cu.* port discovery with USB hot-plug detection |
| `FrameAssembler.swift` | Actor assembling byte streams into CI-V or Kenwood protocol frames |

### Services/Radio/

| File | Description |
|------|-------------|
| `RadioProtocolHandler.swift` | Protocol for encode/decode of frequency, mode, PTT commands |
| `CIVProtocolHandler.swift` | Icom CI-V protocol handler wrapping CarrierWaveCore CIVProtocol |
| `KenwoodProtocolHandler.swift` | Kenwood CAT protocol handler wrapping CarrierWaveCore KenwoodProtocol |
| `ElecraftProtocolHandler.swift` | Elecraft K3/K4 handler extending KenwoodProtocolHandler with CW keying |
| `RadioSession.swift` | Actor managing transport + protocol; polls frequency/mode state |
| `RadioCommandLog.swift` | @MainActor @Observable ring-buffer log of TX/RX commands for in-app visibility |
| `RadioManager.swift` | @MainActor @Observable managing multiple radio sessions (SO2R ready) |

### Services/Spots/

| File | Description |
|------|-------------|
| `RBNClient.swift` | Actor wrapping Vail ReRBN API for reverse beacon spots |
| `POTASpotsClient.swift` | Lightweight actor for unauthenticated POTA spot fetching |
| `SOTAClient.swift` | Actor wrapping SOTAwatch API (api2.sota.org.uk) |
| `WWFFClient.swift` | Actor wrapping WWFF Spotline API (spots.wwff.co) |
| `HamDBClient.swift` | Actor wrapping HamDB.org API for grid/license lookups |
| `GridCache.swift` | GridCache + CallsignStateCache actors with 1-hour TTL |
| `SpotAggregator.swift` | @MainActor @Observable central service: polls, deduplicates, enriches spots |
| `PoloNotesStore.swift` | Actor managing Polo callsign notes: iCloud KVS config, disk cache, 24h refresh |

### Services/WebSDR/

| File | Description |
|------|-------------|
| `KiwiSDRTypes.swift` | KiwiSDRMode enum, KiwiSDRError, mode mapping from amateur radio modes |
| `KiwiSDRADPCM.swift` | IMA ADPCM decoder for KiwiSDR compressed audio streams |
| `AudioRingBuffer.swift` | Thread-safe circular buffer for audio samples (OSAllocatedUnfairLock) |
| `KiwiSDRClient.swift` | Actor: WebSocket client for KiwiSDR protocol (auth, tune, audio frames) |
| `KiwiSDRAudioEngine.swift` | AVAudioEngine + AVAudioSourceNode for live KiwiSDR audio playback |
| `WebSDRRecorder.swift` | Actor: records PCM audio to CAF files with parameter event tracking |
| `WebSDRDirectory.swift` | Actor: fetches/caches KiwiSDR public receiver directory |
| `KiwiSDRStatusFetcher.swift` | Fetches /status endpoint from individual KiwiSDR receivers |
| `WebSDRSession.swift` | Actor: coordinates KiwiSDRClient + AudioEngine + Recorder lifecycle |
| `TuneInManager.swift` | @MainActor @Observable: SDR Tune In coordinator with receiver selection strategies |
| `CWSWLClient.swift` | Actor: CW-SWL transcription server API client |
| `RecordingPlaybackEngine.swift` | @MainActor @Observable: AVAudioPlayer wrapper with transcript sync |
| `RecordingClipExporter.swift` | M4A clip export from CAF recordings via AVAssetExportSession |

### Services/Cluster/

| File | Description |
|------|-------------|
| `DXSpotParser.swift` | Regex parser for DX cluster spot lines |
| `TelnetClusterClient.swift` | Actor using NWConnection TCP for DX cluster telnet connections |
| `ClusterManager.swift` | @MainActor @Observable managing cluster connection, scrollback, spot feed |

### Views/Workspace/

| File | Description |
|------|-------------|
| `WorkspaceView.swift` | Root NavigationSplitView; injects RadioManager, SpotAggregator, ClusterManager |
| `SidebarView.swift` | Section-organized navigation sidebar |
| `ContentAreaView.swift` | Dispatches to role layouts or feature views based on sidebar selection |
| `InspectorView.swift` | Context-sensitive inspector panel (QSO detail view) |
| `StatusBarView.swift` | Bottom bar with QSO count, session duration, radio status, UTC clock |

### Views/Roles/

| File | Description |
|------|-------------|
| `CasualLayout.swift` | VSplitView: QSO log table + parsed entry |
| `HunterLayout.swift` | HSplitView: spot list | (entry + log + band map) |
| `ActivatorLayout.swift` | Activation header + HSplitView: (entry + log) | spots |
| `ContesterLayout.swift` | Entry + HSplitView: (log + rate) | band map |
| `DXerLayout.swift` | HSplitView: spots | (band map + entry + log) |

### Views/Logger/

| File | Description |
|------|-------------|
| `ParsedEntryView.swift` | Single-line parsed QSO entry using QuickEntryParser; logs to SwiftData |
| `ParsedFieldSummary.swift` | Real-time FieldChip display of parsed fields (Call, Freq, Mode, etc.) |
| `QSOLogTableView.swift` | SwiftUI Table with sortable columns; fetches QSOs from SwiftData |

### Views/Spots/

| File | Description |
|------|-------------|
| `SpotListView.swift` | Live spot table from SpotAggregator with source/band/region/text filters |
| `BandMapView.swift` | Canvas-based band map with spot markers, frequency cursor, sub-band shading |
| `ClusterView.swift` | DX cluster connection bar, scrollback, parsed spot table |
| `SpotDetailInspector.swift` | Inspector panel: spot details, HamDB operator info, Polo notes, previous QSOs |

### Views/SDR/

| File | Description |
|------|-------------|
| `SDRPlayerView.swift` | Main SDR player: connection status, tuning controls, meters, record button |
| `SDRMeterView.swift` | Reusable horizontal audio level / S-meter bar |
| `RecordingLibraryView.swift` | Table-based recording browser with HSplitView player panel |
| `RecordingPlayerView.swift` | Inline playback: scrubber, transport, speed picker, transcript |

### Views/Other

| File | Description |
|------|-------------|
| `Radio/RadioControlView.swift` | Serial port list, connect/disconnect, frequency/mode display |
| `Sessions/SessionsListView.swift` | Session management with start/pause/end controls |
| `Settings/SettingsView.swift` | Tab-based settings (General, Radio, SDR, Sync, Accounts, Notes) |
| `Settings/CallsignNotesSettingsTab.swift` | Manage Polo callsign notes sources (add/delete/toggle, iCloud KVS sync) |
| `Settings/SDRSettingsTab.swift` | SDR settings: default mode, auto-record, CW-SWL transcription config |
| `CommandPalette/CommandPaletteView.swift` | Cmd+K command palette with frequency/callsign/park detection |
| `MenuBarExtra/MenuBarExtraView.swift` | Menu bar extra showing solar conditions + session summary |
| `Dashboard/DashboardView.swift` | Dashboard with QSO counts, band breakdown, rate chart |
| `Map/QSOMapView.swift` | MapKit map plotting QSO locations from grid squares with band colors and date filter |

### Commands/

| File | Description |
|------|-------------|
| `CWSweepCommands.swift` | Menu bar commands: Radio, Logging, Spots, Sync menus |

### Utilities/

| File | Description |
|------|-------------|
| `PlaceholderView.swift` | Generic placeholder view for unimplemented features |
| `FocusedValues.swift` | FocusedValueKey definitions for menu command wiring |

## CWSweepTests/

| File | Description |
|------|-------------|
| `CWSweepTests.swift` | Tests for OperatingRole, SidebarSection, RadioModel, FrameAssembler, protocols |
| `SpotTypeTests.swift` | Tests for UnifiedSpot, SpotRegion, EnrichedSpot, POTASpot, SpotSource |
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
| `KiwiSDRTypesTests.swift` | Tests for KiwiSDRMode mapping, bandwidth, carrier offset, error descriptions |
| `KiwiSDRADPCMTests.swift` | Tests for IMA ADPCM decoding: silence, clamping, consistency |
| `AudioRingBufferTests.swift` | Tests for ring buffer write/read/wrap/overflow/reset/resample |
| `TuneInManagerTests.swift` | Tests for TuneInStrategy, TuneInSpot, TuneInManager state |
| `SDRTranscriptTests.swift` | Tests for transcript word/line/QSO range Codable round-trips |
