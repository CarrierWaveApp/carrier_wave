# Carrier Wave

A monorepo for amateur radio QSO (contact) logging — an iOS app, a macOS companion, and shared Swift packages. Cloud synchronization to QRZ.com, Parks on the Air (POTA), and Ham2K LoFi.

## Apps

### Carrier Wave (iOS)

Full-featured QSO logger for iPhone and iPad.

- **QSO Logging** — Callsign, band, mode, frequency, RST reports, grid squares, park references, and notes
- **Multi-Service Sync** — Upload QSOs to QRZ.com, POTA, and Ham2K LoFi with per-contact sync status tracking
- **ADIF Import/Export** — Import logs from other software with intelligent deduplication
- **Dashboard** — Activity statistics by band, mode, and country with drill-down views
- **POTA Integration** — Dedicated uploads view with park grouping and upload history

### CW Sweep (macOS)

Purpose-built companion for radio hunters and contesters operating with USB-connected radios and large monitors.

- **Serial Radio Control** — CI-V (Icom), Kenwood, and Elecraft protocol support via USB serial
- **Live Spot Aggregation** — RBN, POTA, SOTA, and WWFF spots with dedup and distance enrichment
- **DX Cluster** — Telnet cluster client with spot parsing
- **Band Map** — Canvas-rendered spot visualization
- **Role-Based Layouts** — Contester, Hunter, Activator, DXer, and Casual operating modes
- **Command Palette** — Cmd+K quick access
- **Shared iCloud Store** — QSOs sync between Carrier Wave and CW Sweep via iCloud

## Requirements

- iOS 17.0+ / macOS 14.0+
- Xcode 16.0+

## Architecture

Built with SwiftUI and SwiftData. No external dependencies.

### Monorepo Structure

```
carrier_wave/
├── CarrierWave/           # iOS app (SwiftUI/SwiftData)
├── CWSweep/               # macOS companion app (xcodeproj via xcodegen)
├── CarrierWaveCore/       # SPM: protocol logic, parsers, utilities, FT8 codec
├── CarrierWaveData/       # SPM: SwiftData models, cloud sync, shared services
├── CarrierWaveTests/      # iOS app tests
├── CarrierWaveWatch/      # watchOS companion
└── CarrierWaveWidgets/    # Widget extension
```

### Shared Packages

- **CarrierWaveCore** — Protocol logic (CI-V, Kenwood), parsers (ADIF, QuickEntry, Callsign), utilities (Maidenhead, Morse, Band), FT8 codec
- **CarrierWaveData** — SwiftData models (QSO, LoggingSession, ServicePresence), cloud sync, shared services

### Key Patterns

- **Actor-based clients** for thread-safe network operations
- **Keychain storage** for credentials (never stored in SwiftData)
- **Deduplication** via 2-minute time buckets + band + mode + callsign
- **Batch uploads** (50 QSOs per batch for QRZ, park-grouped for POTA)

## Building

```bash
# Carrier Wave (iOS)
xcodebuild -project CarrierWave.xcodeproj -scheme CarrierWave \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# CW Sweep (macOS) — requires xcodegen for project generation
xcodegen generate --spec CWSweep/project.yml
xcodebuild -project CWSweep/CWSweep.xcodeproj -scheme CWSweep build
```

## Sync Services

| Service | Auth Method | Features |
|---------|-------------|----------|
| QRZ.com | Session-based | Batch ADIF upload |
| POTA | Bearer token | Park-grouped multipart upload |
| Ham2K LoFi | Email device linking | Bidirectional sync |

## License

MIT License. See [LICENSE](LICENSE) for details.
