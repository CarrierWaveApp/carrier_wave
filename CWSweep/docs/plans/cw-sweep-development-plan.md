# CW Sweep — macOS Companion App for Carrier Wave

## Context

Carrier Wave is a full-featured amateur radio logging app for iOS/iPadOS. CW Sweep is its macOS companion, purpose-built for **radio hunters and contesters** who operate with USB-connected radios and large monitors. The macOS experience prioritizes:

- **Dense information display**: Spots, logger, band map, and cluster visible simultaneously
- **Keyboard-first interaction**: Rapid-fire contest logging without touching the mouse
- **USB radio CAT control**: Direct serial connection (replacing iOS's BLE approach)
- **Role-based layouts**: Switchable views for Contester, Hunter, Activator, DXer, and Casual operating modes

**Distribution**: Developer ID + Notarization (no App Sandbox, full serial port access)
**Repository**: `~/projects/cw_sweep` (separate from `carrier_wave`)
**MVP Priority**: Logging + Radio Control first

---

## Phase 0: Shared Package Extraction ✅

Before building CW Sweep, extract shared code from Carrier Wave into independent SPM packages that both apps consume.

### 0.1 — Extract CarrierWaveCore into its own repo ✅

`CarrierWaveCore` already targets `macOS(.v13), iOS(.v17)` and has zero external dependencies. Move it to its own repository.

**New repo**: `~/projects/carrier_wave_core` (or a GitHub repo both projects reference)

**Contents** (already cross-platform):
- `ADIFParser`, `BandUtilities`, `CallsignDetector`, `CallsignEditDistance`
- `CIVProtocol`, `KenwoodProtocol` — radio protocol byte-level logic
- `FrequencyFormatter`, `MaidenheadConverter`, `ModeEquivalence`, `MorseCode`
- `ParkReference`, `SCPDatabase`, `DeduplicationMatcher`, `TwoferMatcher`
- `ServiceType`, `StreakCalculator`, `QSOSnapshot`, `QuickEntryParser`
- `QueryLanguage/` — lexer, parser, AST, analyzer
- `FT8Decoder`, `FT8Encoder`, `FT8MessageTypes`, `FT8QSOStateMachine` (wraps vendored C `ft8_lib`)
- `LoFi/` — full LoFi client
- `CFT8` C target (vendored ft8_lib)

**Update carrier_wave** to reference CarrierWaveCore as a remote/local SPM dependency instead of an embedded package.

### 0.2 — Create CarrierWaveData shared package ✅

A new SPM package containing models and platform-agnostic services.

**New repo**: `~/projects/carrier_wave_data`
**Platforms**: `macOS(.v14), iOS(.v17)` (macOS 14 required for CKSyncEngine)
**Depends on**: CarrierWaveCore

**Models to extract from `carrier_wave/CarrierWave/Models/`:**

| Model | File | Syncs via iCloud? |
|-------|------|-------------------|
| `QSO` | `QSO.swift` | Yes |
| `ServicePresence` | `ServicePresence.swift` | Yes |
| `LoggingSession` | `LoggingSession.swift` | Yes |
| `ActivationMetadata` | `ActivationMetadata.swift` | Yes |
| `SessionSpot` | `SessionSpot.swift` | Yes |
| `ActivityLog` | `ActivityLog.swift` | Yes |
| `CloudSyncMetadata` | `CloudSyncMetadata.swift` | No (sync infra) |
| `UploadDestination` | `UploadDestination.swift` | No (sync config) |
| `Types.swift` | Various enums | N/A |

**Services to extract from `carrier_wave/CarrierWave/Services/`:**

| Service | Current Path | Notes |
|---------|-------------|-------|
| `QRZClient` (actor) | `Services/QRZClient.swift` + extensions | Pure HTTP |
| `POTAClient` (actor) | `Services/POTAClient.swift` + extensions | Extract auth as protocol |
| `LoFiClient` (actor) | `Services/LoFi/` | Pure HTTP |
| `HAMRSClient` (actor) | `Services/HAMRSClient.swift` | Pure HTTP |
| `LoTWClient` (actor) | `Services/LoTWClient.swift` + extensions | Pure HTTP |
| `ClubLogClient` (actor) | `Services/ClubLogClient.swift` + extensions | Pure HTTP |
| `SOTAClient` | `Services/SOTAClient.swift` | Pure HTTP |
| `WWFFClient` | `Services/WWFFClient.swift` | Pure HTTP |
| `RBNClient` | `Services/RBNClient.swift` | Pure HTTP/WebSocket |
| `NOAAClient` | `Services/NOAAClient.swift` | Pure HTTP |
| `CloudSyncEngine` | `Services/CloudSync/` (14 files) | CKSyncEngine, no UI |
| `SyncService` | `Services/SyncService.swift` + extensions | Orchestration |
| `DeduplicationService` | `Services/DeduplicationService.swift` | Pure logic |
| `ImportService` | `Services/ImportService.swift` | ADIF parsing |
| `ADIFExportService` | `Services/ADIFExportService.swift` | Pure logic |
| `KeychainHelper` | `Utilities/KeychainHelper.swift` | Security framework |
| `SettingsSyncService` | `Services/SettingsSyncService.swift` | iCloud KVS |
| `BackupService` | `Services/BackupService.swift` | FileManager |
| `QSOProcessingActor` | `Services/QSOProcessingActor.swift` + extensions | Background processing |

**Protocol abstractions** (new, in CarrierWaveData):
```swift
protocol RadioServiceProtocol: Sendable { ... }  // BLE (iOS) vs Serial (macOS)
protocol AudioCaptureProtocol: Sendable { ... }   // Different AVAudioEngine routing
protocol POTAAuthProvider: Sendable { ... }        // WebView (iOS) vs ASWebAuth (macOS)
```

**Services that stay iOS-only** (NOT extracted):
- `BLERadioService`, `LiveActivityService`, `WidgetDataWriter`
- `PhoneSessionDelegate` (WatchConnectivity)
- `CWAudioCapture` (iOS-specific AVAudioSession)

### 0.3 — Phased extraction plan ✅

1. Create `carrier_wave_core` repo, move CarrierWaveCore contents, update carrier_wave to use remote SPM dep
2. Create `carrier_wave_data` repo with Package.swift
3. Move models one at a time (start with no-dependency models: `CloudSyncMetadata`, `UploadDestination`, `ActivityLog`)
4. Move core trio: `QSO`, `ServicePresence`, `LoggingSession`
5. Move remaining models
6. Move API clients (actors)
7. Move sync infrastructure
8. Move KeychainHelper, SettingsSyncService, BackupService
9. Update carrier_wave imports, build, test at each step

---

## Phase 1: CW Sweep MVP — Logger + Radio Control + Sync ✅

### 1.1 — Project Setup ✅

**Create `~/projects/cw_sweep/`:**
- Xcode project targeting macOS 14+ (Sonoma)
- Hardened runtime, no sandbox
- SPM dependencies: CarrierWaveCore, CarrierWaveData
- Bundle ID: `com.jsvana.CWSweep`
- Team ID: same as Carrier Wave (`7UE4RDLUSX`)

**Entitlements** (hardened runtime, NOT sandboxed):
```xml
com.apple.security.device.audio-input = true   <!-- mic for CW/FT8 -->
com.apple.security.device.usb = true           <!-- serial ports -->
```

**Shared entitlements** (match Carrier Wave for sync):
- App Group: `group.com.jsvana.FullDuplex`
- iCloud KVS: `$(TeamIdentifierPrefix)com.jsvana.FullDuplex` (use iOS bundle ID!)
- iCloud container: `iCloud.com.jsvana.FullDuplex`
- CloudKit enabled
- Keychain sharing: `$(AppIdentifierPrefix)com.fullduplex.shared`
- Push notifications (CKSyncEngine triggers)

### 1.2 — Window Architecture ✅

Single primary workspace window + detachable auxiliary panels.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Toolbar: [Role Picker] [Session] [Radio: IC-7300 14.074] [Solar] [Sync]   │
├────────┬──────────────────────────────────────┬─────────────────────────────┤
│  Side  │          Primary Content              │     Inspector / Context     │
│  bar   │  (Adapts based on sidebar selection   │  (Callsign detail, QSO     │
│        │   AND active role preset)             │   edit, spot detail)        │
│ ────── │                                      │                             │
│ Logger │                                      │                             │
│ Spots  │                                      │                             │
│ Map    │                                      │                             │
│ Band   │                                      │                             │
│ ────── │                                      │                             │
│ POTA   │                                      │                             │
│ FT8    │                                      │                             │
│ CW     │                                      │                             │
│ ────── │                                      │                             │
│ QSO Log│                                      │                             │
│ Dash   │                                      │                             │
│ ────── │                                      │                             │
│ Radio  │                                      │                             │
│ Sync   │                                      │                             │
├────────┴──────────────────────────────────────┴─────────────────────────────┤
│ Status Bar: [QSO #1247] [Session: 2h 14m] [UTC 1847]                      │
└─────────────────────────────────────────────────────────────────────────────┘
```

**SwiftUI Scenes:**
```swift
@main struct CWSweepApp: App {
    var body: some Scene {
        Window("CW Sweep", id: "workspace") { WorkspaceView() }
            .defaultSize(width: 1400, height: 900)
            .commands { CWSweepCommands() }

        Window("Band Map", id: "bandmap") { BandMapPanel() }
        Window("Spot Cluster", id: "cluster") { ClusterPanel() }

        Settings { SettingsView() }

        MenuBarExtra("CW Sweep", systemImage: "antenna.radiowaves.left.and.right") {
            MenuBarExtraView()
        }
        .menuBarExtraStyle(.window)
    }
}
```

### 1.3 — Role-Based Layouts ✅

Five operating roles, switchable via toolbar segmented control or `Cmd+1` through `Cmd+5`:

| Role | Primary Panels | Target User |
|------|---------------|-------------|
| **Contester** | Entry bar + band map + recent QSOs + multiplier tracker + rate | Contest operators |
| **Hunter** | Spot list + quick log + band map (compact) | POTA/SOTA/WWFF hunters |
| **Activator** | Activation header + logger + session log + self-spot controls | Park/summit activators |
| **DXer** | DX cluster + band map + DXCC tracker + logger | DX chasers |
| **Casual** | QSO log table + logger + stats | General logging |

Each role is a `LayoutConfiguration` — a serializable description of which panes are visible, their sizes, and positions. Users can customize and save their own layouts.

### 1.4 — USB Serial Radio CAT Control ✅

**Transport abstraction** — same protocol logic for BLE (iOS) and Serial (macOS):

```swift
protocol RadioTransport: Sendable {
    var isConnected: Bool { get async }
    func send(_ data: Data) async throws
    var receivedData: AsyncStream<Data> { get }
    func connect() async throws
    func disconnect() async
}
```

**Serial port layer** — POSIX termios wrapped in Swift actor:
- `SerialPort` — raw POSIX termios wrapper (open, configure, read, write, DTR/RTS control)
- `SerialRadioTransport` — actor conforming to `RadioTransport`, owns a `SerialPort`
- `SerialPortMonitor` — IOKit notifications for USB hot-plug detection
- `FrameAssembler` — byte stream to protocol frames (CI-V `FE..FD` or Kenwood `;`)
- `ProtocolAutoDetector` — probes baud rates and protocol types

**Protocol handlers** — thin wrappers around existing CarrierWaveCore logic:
- `CIVProtocolHandler` → delegates to existing `CIVProtocol`
- `KenwoodProtocolHandler` → delegates to existing `KenwoodProtocol`
- `YaesuProtocolHandler` — NEW (Yaesu CAT is NOT Kenwood-compatible despite similar syntax)
- `ElecraftProtocolHandler` — extends Kenwood with Elecraft-specific commands

**RadioSession** — transport-agnostic actor that polls frequency/mode and publishes state
**RadioManager** — `@MainActor @Observable`, manages multiple radio connections (SO2R ready)

**Supported radios** (Phase 1 — CI-V and Kenwood families):

| Radio | Protocol | Default Baud | CI-V Address |
|-------|----------|-------------|--------------|
| Icom IC-7300 | CI-V | 19200 | 0x94 |
| Icom IC-7610 | CI-V | 19200 | 0x98 |
| Icom IC-705 | CI-V | 19200 | 0xA4 |
| Kenwood TS-890S | Kenwood | 115200 | N/A |
| Kenwood TS-590SG | Kenwood | 9600 | N/A |
| Elecraft K3/K3S | Kenwood ext | 38400 | N/A |
| Elecraft K4 | Kenwood ext | 115200 | N/A |
| Xiegu G90/X6100 | CI-V | 19200 | 0x70 |

Yaesu and FlexRadio support deferred to Phase 2+.

### 1.5 — QSO Logger ✅

**Single-line parsed entry** — one text field, not separate tabbable fields:
```
┌─────────────────────────────────────────────────────────────────────┐
│ > W6JSV CA 59 57 14045                                    [Log ↵] │
└─────────────────────────────────────────────────────────────────────┘
  Parsed: Call=W6JSV  State=CA  RST Sent=59  RST Rcvd=57  Freq=14.045
```

The user types everything into a single text field and hits Enter. The app parses the string using `QuickEntryParser` (already in CarrierWaveCore) augmented with context-aware parsing:

- **Callsign**: Detected by regex (first token matching callsign pattern)
- **Frequency**: Numeric value matching frequency range (e.g., `14045` → 14.045 MHz)
- **RST**: Two adjacent 2-3 digit numbers (e.g., `59 57` or `599 599`)
- **Mode**: Recognized keywords (`CW`, `SSB`, `FT8`, `USB`, `LSB`, etc.)
- **Park/Summit**: Recognized reference patterns (`K-1234`, `W4C/CM-001`)
- **Grid**: 4-6 character Maidenhead grid (e.g., `FN42`)
- **Exchange**: Contest-specific fields parsed based on active contest definition
- **Commands**: Prefixed tokens (same as iOS: `FREQ`, `MODE`, `SPOT`, `QRT`, `RBN`, `POTA`, `P2P`, `SOLAR`, `WEATHER`, `MAP`, `WEBSDR`)

**Parsing context**: The parser adapts based on active role and contest:
- Casual mode: liberal parsing, all fields optional
- Contest mode: exchange fields expected based on `ContestDefinition`
- Hunter mode: park reference expected
- If radio is connected, frequency/mode default from radio (only overridden if typed)

**Visual feedback**: Below the text field, a parsed-field summary shows what the parser understood in real-time as the user types. Unrecognized tokens are highlighted. Ambiguous parses show alternatives.

**Keyboard flow**:
- Type everything, hit Enter to log
- Escape to clear
- Up arrow to recall/edit last entry
- Command palette (`Cmd+K`) for non-logging commands

**QSO log table** — SwiftUI `Table` with sortable, resizable, reorderable columns:
- Date/Time, Callsign, Frequency, Band, Mode, RST Sent, RST Rcvd, Park, Grid, Notes
- `alternatingRowBackgrounds()`, compact row height (24pt)
- Context menu for edit, delete, lookup, export

**Session management** — same model as iOS:
- Start/pause/end sessions
- Equipment tracking
- Programs (POTA, SOTA, WWFF, casual)

### 1.6 — iCloud Sync (Day 1) ✅

Same CloudKit container (`iCloud.com.jsvana.FullDuplex`), same CKSyncEngine code from CarrierWaveData.

**First-launch flow:**
1. CKSyncEngine fetches all records from shared zone
2. iCloud Keychain delivers credentials (shared keychain group)
3. iCloud KVS delivers shared settings (callsign, grid, equipment)
4. Progress UI shows "Syncing your logbook from iCloud..."

**Credential sharing** — KeychainHelper with `7UE4RDLUSX.com.fullduplex.shared` + `kSecAttrSynchronizable: true`. User authenticates once on iOS, macOS gets credentials automatically.

### 1.7 — Keyboard-First Design ✅

**Global shortcuts:**

| Shortcut | Action |
|----------|--------|
| `Cmd+1`..`Cmd+5` | Switch role preset |
| `Cmd+L` | Focus QSO entry field |
| `Cmd+K` | Command palette |
| `Cmd+0` | Toggle sidebar |
| `Cmd+Opt+I` | Toggle inspector |
| `Cmd+F` | Find in current view |
| `Cmd+Shift+F` | QSO query search |
| `Enter` | Log QSO |
| `Escape` | Wipe/clear entry |
| `Cmd+Shift+D` | Detach current pane to window |

**Command palette** (`Cmd+K`) — VS Code / Raycast-style:
- Type commands: "Log QSO", "Start POTA Activation", "Tune to 14.274"
- Quick callsign lookup: type a callsign
- Frequency entry: type "14.074" to tune radio
- Park search: type "K-1234"

### 1.8 — Menu Bar ✅

Standard macOS menu bar with Radio and Logging menus:

- **File**: New Session, Import/Export (ADIF, Cabrillo), Print
- **Edit**: Standard + Edit Last QSO, Find, QSO Query
- **View**: Sidebar, Inspector, Roles, Panels, Detach
- **Radio**: Connect/Disconnect, Tune to Frequency, Band Up/Down, Mode, PTT
- **Logging**: Log QSO, Wipe, Start/Pause/End Session, Self-Spot
- **Sync**: Sync Now, Upload to services
- **Window**: Standard + Command Palette, auxiliary windows

**Menu Bar Extra**: Solar conditions + active session summary in menu bar.

**Dock Badge**: QSO count for active session.

---

## Phase 2: Spots, Band Map, and Operating Views ✅

### 2.1 — Spot Integration

Unified spot pipeline from all sources:
- POTA spots (existing `POTAClient`)
- RBN spots (existing `RBNClient`)
- SOTA spots (existing `SOTAClient`)
- WWFF spots (existing `WWFFClient`)

**Spot list** — SwiftUI `Table`:
- Columns: Age indicator, Callsign, Frequency, Park/Summit, Name, Spotter, Age
- Color coding: green (new park), yellow (hunted before, not today), gray (hunted today)
- Click spot → populate logger + tune radio

### 2.2 — Band Map

Visual frequency display showing stations as labeled markers:
- Color: red (new DXCC), green (new mult), cyan (new station), gray (worked)
- Current frequency cursor from radio
- Click to QSY
- Spot aging (fade after 10min, remove after 20min)
- Single-band or stacked all-bands view
- Canvas-based rendering for performance

### 2.3 — Telnet DX Cluster

macOS-only feature — direct TCP connection to cluster nodes:
- Preset list of well-known nodes (W3LPL, etc.)
- Custom node support
- Filter commands sent to cluster
- Spot parsing and integration into unified spot pipeline

### 2.4 — Hunter Layout

Spot list (primary) + quick log + band map (compact) + inspector.
- One-click "Hunt" from spot
- Hunted today counter / daily goal

### 2.5 — Activator Layout

Activation header + logger + session log + self-spot controls.
- Progress bar (8/10 QSOs)
- Self-spot with auto-respot timer
- Rove mode (multi-park)

### 2.6 — DXer Layout

DX cluster + band map (multi-band) + DXCC tracker + logger.
- DXCC matrix (entity × band, worked/confirmed)
- Needed-on-band alerts
- Bearing/distance display

---

## Phase 3: Contest Features

### 3.1 — Contest Engine

**ContestDefinition** — declarative contest rules (JSON catalog):
- Exchange fields, multiplier types, scoring rules, dupe rules, Cabrillo template
- Ship ~50 templates (ARRL DX, CQ WW, Sweepstakes, Field Day, state QSO parties, etc.)
- User-created custom definitions

**New models** (in CarrierWaveData, synced to iOS for review):
- `ContestSession` — extends LoggingSession concept with operator/power/band categories, running score
- `MultiplierEntry` — per (band × multiplier-value) tracking
- `ContestDefinition` — persisted user-created definitions

### 3.2 — Contest Logger

Same single-line parsed entry as casual logging, but with contest-aware parsing:
```
> W6JSV 59 3          → Call=W6JSV  RST=59  CQ Zone=3
> K3LR 599 05         → Call=K3LR  RST=599  Zone=05  (auto: different continent = 3 pts)
```

- Parser knows expected exchange fields from active `ContestDefinition`
- Real-time dupe checking (in-memory dictionary, sub-millisecond)
- Visual dupe indicators: green=new mult, cyan=new station, red=DUPE (shown in parsed summary)
- Exchange auto-fill: if station worked on another band, pre-populate exchange in parsed summary
- CQ vs S&P mode toggle (`Ctrl+S`)
- Band stacking (remember last freq per band)
- Rate display (QSOs/hr, points/hr)
- Function keys (F1-F12) still send CW/voice messages in parallel with the text entry

### 3.3 — Multiplier Tracker

- Band × multiplier matrix view
- Zone map, state/section map, county map (SVG resources)
- "Needed on current band" filter
- New-mult audio alert (configurable)

### 3.4 — Score Summary

- Real-time scoring by band/mode
- Rate sheet (QSOs per hour)
- Rate graph (Swift Charts)
- Previous-year comparison
- Off-time tracking

### 3.5 — CW Memory Keyer + Voice Keyer

**CW**: Function keys send stored CW messages via:
1. CAT `KY` command (Kenwood/Elecraft — radio handles timing)
2. CAT CW memory commands (Icom)
3. Serial DTR/RTS toggling (fallback, jitter-prone above 30 WPM)

**Voice**: Record/playback WAV files through radio USB audio:
- F1-F6 mapped to message slots
- Auto-PTT before playback
- Messages support macros ({MYCALL}, {HISCALL}, {NR}, {EXCH})

### 3.6 — Cabrillo Export

Generate Cabrillo 3.0 files for contest log submission:
- Template-driven formatting per contest
- Preview before save
- Header fields from contest session setup

### 3.7 — N1MM+ / WSJT-X Interop

- Emit N1MM+-compatible UDP broadcasts (contactinfo, RadioInfo, ScoreInfo)
- Listen for WSJT-X UDP broadcasts (decoded messages, frequency changes)
- Enables integration with external tools (CW Skimmer, etc.)

---

## Phase 4: Audio, FT8, CW Decode

### 4.1 — Audio Routing

macOS-specific audio configuration:
- Radio USB audio input → FT8 decoder, CW decoder, monitor mix
- Radio USB audio output ← FT8 encoder, voice keyer
- CoreAudio device discovery and selection
- Auto-match audio devices to serial ports by USB location ID

### 4.2 — FT8

Reuse FT8 engine from CarrierWaveCore (`FT8Decoder`, `FT8Encoder`, `FT8QSOStateMachine`):
- Audio capture from radio USB input
- Waterfall display
- Decode list with enrichment (DXCC, distance, worked-before)
- Auto-sequencing
- PTT via CAT for transmit

### 4.3 — CW Decoder

Reuse CW decoder from iOS:
- Audio from radio USB input
- Scrolling text display
- Adjustable center frequency and bandwidth
- Clickable decoded callsigns

---

## Phase 5: Polish + Advanced

### 5.1 — Multi-Monitor Support

- Any pane detachable to its own window (`Cmd+Shift+D`)
- Shared `@Observable` state across all windows
- Window position persistence per monitor
- Suggested layouts: dual monitor (workspace + band map), triple (cluster + workspace + band map)

### 5.2 — SO2R (Two Radios)

- `RadioManager` supports multiple `RadioSession` instances
- `Alt+`` toggles focus between Radio 1 and Radio 2
- Per-radio entry fields, band map, function keys
- Stereo audio routing (Radio 1 left, Radio 2 right)

### 5.3 — Dark/Field Mode

- Night-vision mode with red-shifted palette
- True black backgrounds
- Configurable via `Cmd+Shift+N`

### 5.4 — Award Tracking

- DXCC (Mixed/CW/Phone/Digital/Challenge) — band/mode/entity matrix
- WAS (50-state checklist per band/mode)
- WAZ (40-zone checklist)
- VUCC (grid count per VHF band)
- WPX (prefix tracking)

### 5.5 — Yaesu Protocol Support

Separate handler for Yaesu CAT (different from Kenwood despite similar syntax):
- FT-991A, FTDX10, FTDX101, FT-710, FT-891
- Different frequency digit count, mode codes, PTT commands

### 5.6 — FlexRadio Support

TCP/IP transport (SmartSDR API) — entirely different from serial:
- Discovery via UDP broadcast
- Text command protocol
- Multiple virtual receivers (slices)
- Opus-encoded audio streaming

---

## Key Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Distribution | Developer ID + Notarization | Full serial port access, standard for ham radio software |
| Sandbox | Hardened runtime, no sandbox | Serial ports not accessible from sandbox |
| Repo structure | Separate repo (`cw_sweep`) + shared packages | Clean separation, shared code via CarrierWaveCore + CarrierWaveData |
| Sync | Same CloudKit container | Automatic cross-device sync, existing CKSyncEngine |
| Credentials | Shared keychain group | One-time auth on iOS, macOS gets credentials automatically |
| Serial API | POSIX termios | No dependencies, full control, standard |
| Port naming | `/dev/cu.*` only | Avoids DCD blocking on `/dev/tty.*` |
| Transport abstraction | `RadioTransport` protocol | Same protocol logic for BLE (iOS) and Serial (macOS) |
| Concurrency | Swift actors throughout | No dispatch queues, no manual locking |
| Window model | Single workspace + detachable panels | Balances simplicity with multi-monitor flexibility |
| Navigation | Source list sidebar | macOS convention, scalable, keyboard-navigable |
| Content layout | Role-based compound layouts | Each operating mode has fundamentally different workflows |
| QSO table | SwiftUI `Table` | Native sorting, column reordering, selection |
| Band map | Canvas-based rendering | Performance with hundreds of markers |
| CW keying | Prefer radio-side keyer (CAT `KY`) | Avoids OS timing jitter |
| Yaesu protocol | Separate handler (not Kenwood) | Different frequency format, mode codes, PTT commands |

---

## Verification Plan

### Phase 0 (Shared Package Extraction) ✅
- `swift build` on CarrierWaveCore for both macOS and iOS
- `swift test` on CarrierWaveCore (25 existing test files)
- Build and test Carrier Wave iOS after extraction — must pass all existing tests
- Verify iCloud sync still works between iOS devices

### Phase 1 (MVP) ✅
- Build CW Sweep, verify it launches and shows empty workspace
- Install on Mac, verify iCloud sync pulls QSOs from iOS
- Connect radio via USB, verify frequency/mode read
- Log a QSO, verify it syncs to iOS Carrier Wave
- Verify credentials auto-share via iCloud Keychain
- Test all keyboard shortcuts

### Phase 2 (Spots + Operating Views)
- Verify spot list populates from POTA/RBN/SOTA/WWFF
- Click spot → verify radio tunes + logger populates
- Test each role layout switches correctly
- Verify telnet cluster connection and spot parsing

### Phase 3 (Contest)
- Set up a contest, log QSOs, verify dupe checking
- Verify multiplier tracking updates in real-time
- Export Cabrillo, validate format against contest rules
- Verify contest data syncs to iOS (read-only review)

### Phase 4 (Audio)
- Verify FT8 decode from radio USB audio
- Verify CW decode from radio USB audio
- Verify voice keyer playback routes to radio

---

## File Structure (CW Sweep repo)

```
~/projects/cw_sweep/
├── CWSweep/
│   ├── CWSweepApp.swift                 # @main, Scene definitions
│   ├── ContentView.swift                # WorkspaceView root
│   │
│   ├── Models/                          # macOS-only models
│   │   ├── ContestDefinition.swift      # (local catalog, not SwiftData)
│   │   ├── RadioProfile.swift           # Serial port config, rig model
│   │   └── LayoutConfiguration.swift    # Role-based layout state
│   │
│   ├── Services/                        # macOS-only services
│   │   ├── Serial/                      # USB serial communication
│   │   │   ├── SerialPort.swift         # POSIX termios wrapper
│   │   │   ├── SerialRadioTransport.swift
│   │   │   ├── SerialPortMonitor.swift  # IOKit hot-plug
│   │   │   ├── FrameAssembler.swift
│   │   │   └── ProtocolAutoDetector.swift
│   │   ├── Radio/
│   │   │   ├── RadioSession.swift       # Transport-agnostic session
│   │   │   ├── RadioManager.swift       # Multi-radio management
│   │   │   ├── CIVProtocolHandler.swift # Wraps CarrierWaveCore CIVProtocol
│   │   │   ├── KenwoodProtocolHandler.swift
│   │   │   ├── YaesuProtocolHandler.swift
│   │   │   └── ElecraftProtocolHandler.swift
│   │   ├── PTT/
│   │   │   ├── SerialPTTController.swift
│   │   │   └── CWKeyer.swift
│   │   ├── Audio/
│   │   │   ├── AudioDeviceDiscovery.swift
│   │   │   └── RadioAudioRouter.swift
│   │   ├── Contest/
│   │   │   ├── ContestEngine.swift      # Scoring, dupe check, mults
│   │   │   ├── CabrilloExportService.swift
│   │   │   └── ContestTemplateLoader.swift
│   │   ├── Cluster/
│   │   │   └── TelnetClusterClient.swift
│   │   └── Interop/
│   │       └── NetworkInteropManager.swift  # N1MM+, WSJT-X UDP
│   │
│   ├── Views/
│   │   ├── Workspace/
│   │   │   ├── WorkspaceView.swift      # NavigationSplitView root
│   │   │   ├── SidebarView.swift
│   │   │   ├── ContentAreaView.swift    # Role-dispatching view
│   │   │   ├── InspectorView.swift
│   │   │   └── StatusBarView.swift
│   │   ├── Roles/
│   │   │   ├── ContesterLayout.swift
│   │   │   ├── HunterLayout.swift
│   │   │   ├── ActivatorLayout.swift
│   │   │   ├── DXerLayout.swift
│   │   │   └── CasualLayout.swift
│   │   ├── Logger/
│   │   │   ├── ParsedEntryView.swift    # Single-line parsed text entry
│   │   │   ├── ParsedFieldSummary.swift # Real-time parse feedback
│   │   │   ├── QSOLogTableView.swift    # SwiftUI Table
│   │   │   └── QuickLogView.swift       # Hunter quick-log (also parsed)
│   │   ├── Spots/
│   │   │   ├── SpotListView.swift
│   │   │   ├── BandMapView.swift
│   │   │   └── ClusterView.swift
│   │   ├── Contest/
│   │   │   ├── ContestSetupView.swift
│   │   │   ├── MultiplierTrackerView.swift
│   │   │   ├── ScoreSummaryView.swift
│   │   │   └── RateGraphView.swift
│   │   ├── DX/
│   │   │   ├── DXCCTrackerView.swift
│   │   │   └── AwardTrackingView.swift
│   │   ├── Radio/
│   │   │   ├── RadioControlView.swift
│   │   │   ├── RadioSettingsView.swift
│   │   │   └── CWKeyerView.swift
│   │   ├── Sessions/
│   │   │   ├── SessionsListView.swift
│   │   │   └── SessionDetailView.swift
│   │   ├── Map/
│   │   │   └── QSOMapView.swift
│   │   ├── Dashboard/
│   │   │   └── DashboardView.swift
│   │   ├── Settings/
│   │   │   └── SettingsView.swift       # Tab-based Settings scene
│   │   ├── CommandPalette/
│   │   │   └── CommandPaletteView.swift
│   │   └── MenuBarExtra/
│   │       └── MenuBarExtraView.swift
│   │
│   ├── Commands/
│   │   └── CWSweepCommands.swift        # Menu bar commands
│   │
│   ├── Utilities/
│   │   └── PlatformDefaults.swift       # macOS-specific defaults
│   │
│   └── Resources/
│       ├── ContestTemplates/            # JSON contest definitions
│       ├── CountyMaps/                  # SVG county maps for state QSO parties
│       └── cty.dat                      # DXCC entity database (AD1C)
│
├── CWSweepTests/
├── CWSweep.xcodeproj
└── CLAUDE.md
```

---

## Dependency Graph

```
┌─────────────────┐      ┌─────────────────┐
│   CW Sweep      │      │  Carrier Wave   │
│   (macOS)       │      │  (iOS/iPadOS)   │
└────────┬────────┘      └────────┬────────┘
         │                        │
         │    ┌───────────────┐   │
         └───►│CarrierWaveData│◄──┘
              │  (SPM pkg)    │
              └───────┬───────┘
                      │
              ┌───────▼───────┐
              │CarrierWaveCore│
              │  (SPM pkg)    │
              └───────────────┘
```
