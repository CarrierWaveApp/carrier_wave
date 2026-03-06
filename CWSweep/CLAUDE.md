# CW Sweep

macOS companion app for Carrier Wave (iOS amateur radio logging). Purpose-built for radio hunters and contesters operating with USB-connected radios and large monitors.

## Architecture

CW Sweep is a macOS app built with Xcode (`CWSweep.xcodeproj`, generated from `project.yml` via xcodegen). It depends on two shared SPM packages:

- **CarrierWaveCore** (`../CarrierWaveCore`) — Protocol logic (CI-V, Kenwood), parsers (ADIF, QuickEntry, Callsign), utilities (Maidenhead, Morse, Band), FT8 codec
- **CarrierWaveData** (`../CarrierWaveData`) — SwiftData models (QSO, LoggingSession, ServicePresence), shared services, iCloud sync

### Key Directories

```
CWSweep/
├── Models/
│   └── Spots/           # Spot types (RBN, POTA, SOTA, WWFF, Unified, Enriched, BandEdges, ClusterNode)
├── Services/
│   ├── Serial/          # POSIX termios, IOKit port monitor, frame assembler
│   ├── Radio/           # RadioSession, RadioManager, protocol handlers
│   ├── Spots/           # Spot clients (RBN, POTA, SOTA, WWFF, HamDB), GridCache, SpotAggregator
│   └── Cluster/         # TelnetClusterClient (NWConnection TCP), DXSpotParser, ClusterManager
├── Views/
│   ├── Workspace/       # NavigationSplitView: Sidebar | Content | Inspector
│   ├── Roles/           # Role-based layouts (Contester, Hunter, Activator, DXer, Casual)
│   ├── Logger/          # ParsedEntryView, QSOLogTableView, ParsedFieldSummary
│   ├── Spots/           # SpotListView (live), BandMapView (Canvas), ClusterView (telnet)
│   ├── Radio/           # RadioControlView
│   ├── CommandPalette/  # Cmd+K command palette
│   └── Settings/        # Tab-based settings with Keychain persistence
├── Commands/            # Menu bar commands (Radio, Logging, Spots, Sync) wired via FocusedValues
└── Utilities/           # PlaceholderView, FocusedValues
```

### Design Patterns

- **Role-based layouts**: `OperatingRole` enum drives which views are shown in `ContentAreaView`
- **Radio transport abstraction**: `RadioTransport` protocol (from CarrierWaveData) with serial implementation
- **Protocol handlers**: `RadioProtocolHandler` protocol with CIV, Kenwood, Elecraft implementations wrapping CarrierWaveCore
- **Observable state**: `RadioManager`, `SpotAggregator`, `ClusterManager`, `SerialPortMonitor` are `@MainActor @Observable`
- **Actor concurrency**: `RadioSession`, `SerialRadioTransport`, `FrameAssembler`, spot clients (RBN, POTA, SOTA, WWFF, HamDB), `TelnetClusterClient` are actors
- **Spot pipeline**: SpotAggregator polls 4 HTTP sources → UnifiedSpot → dedup by callsign+band → EnrichedSpot (distance/region). ClusterManager feeds DX cluster spots in.
- **Canvas rendering**: BandMapView uses SwiftUI Canvas for spot markers with hit testing
- **Menu wiring**: `FocusedValues` bridge WorkspaceView state to `CWSweepCommands`

## Issue Tracking

Issues are tracked in Linear under the **Carrier Wave** team (`CAR`) → **CW Sweep** project.

```bash
# List open CW Sweep issues (they live in Backlog state with high priority)
linear issue list --team CAR --project "CW Sweep" --state backlog --all-assignees --sort priority --no-pager
```

## Quick Reference

| Area | Details |
|------|---------|
| Performance | [docs/PERFORMANCE.md](docs/PERFORMANCE.md) |

## Code Standards

- `actor` for API clients, `@MainActor` for view-bound services
- Credentials in Keychain, never SwiftData
- Tests use in-memory SwiftData containers
- Follow linked docs: [Performance](docs/PERFORMANCE.md)

## Metadata Pseudo-Modes (IMPORTANT)

Modes `WEATHER`, `SOLAR`, `NOTE` are PoLo activation metadata — NOT actual QSOs.

**NEVER** count in stats, display in tables, or include in any user-facing aggregation. Each filtering site defines its own `metadataModes: Set<String>` — keep them in sync. See `QSOLogTableView`, `DashboardView`.

## Performance Rules (MANDATORY)

Full details: [docs/PERFORMANCE.md](docs/PERFORMANCE.md). CW Sweep shares Carrier Wave's iCloud SwiftData store — expect tens of thousands of QSOs. These cause multi-second freezes if violated:

- **`@Query` is BANNED** for QSO and ServicePresence — use `@State` + `FetchDescriptor` in `.task`
- **Always set `fetchLimit`** on QSO/ServicePresence descriptors
- **Dedup by UUID before display or counting** — CloudKit mirrors duplicate every QSO ~3x. `fetchCount` includes duplicates; always fetch records + dedup for accurate counts.
- **Use `.task` (not `.onAppear`)** for initial data loads — `.onAppear` fires synchronously before CloudKit data may be available; `.task` yields to the run loop first.
- **No full-table scans on main thread** — use predicates, not filter/map in view code
- **No network in text field `onChange`** without 300ms+ debounce
- **Bulk loading on background actors** — `ModelContext(container)` on the actor, convert to `Sendable` snapshots

## Quality Gates

```
xcodebuild build -> xcodebuild test -> commit
```

## Build & Test

```bash
# Generate Xcode project (after changing project.yml)
xcodegen generate

# Build .app bundle
xcodebuild -project CWSweep.xcodeproj -scheme CWSweep build -allowProvisioningUpdates

# Run tests (59 tests)
xcodebuild -project CWSweep.xcodeproj -scheme CWSweep test -allowProvisioningUpdates

# SPM build still works for quick iteration
swift build && swift test
```

## Project Generation

The `.xcodeproj` is generated from `project.yml` using [xcodegen](https://github.com/yonaskolb/XcodeGen). After editing `project.yml`, run `xcodegen generate` to regenerate.

## Distribution

Developer ID + Notarization (no App Sandbox). Hardened runtime for serial port access.

- Bundle ID: `com.jsvana.CWSweep`
- Team ID: `7UE4RDLUSX`
- Signing: Automatic (Apple Development)
- iCloud container: `iCloud.com.jsvana.FullDuplex` (shared with Carrier Wave iOS)
- App Group: `group.com.jsvana.FullDuplex`
- Shared Keychain: `$(AppIdentifierPrefix)com.fullduplex.shared`

## Entitlements

- iCloud (CloudKit + KVS)
- App Groups
- Push Notifications (CKSyncEngine)
- Audio Input (mic for CW/FT8)
- USB Device Access (serial ports)
- Shared Keychain
- No App Sandbox (hardened runtime only)
