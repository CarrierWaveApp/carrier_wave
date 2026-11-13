# Carrier Wave: Field (iOS)

SwiftUI/SwiftData iOS app for amateur radio QSO logging with cloud sync to QRZ, POTA, and Ham2K LoFi.

## Experimental Features (IMPORTANT)

`ExperimentalFeature` in `../packages/CarrierWaveData/Sources/CarrierWaveData/Utilities/ExperimentalFeature.swift` is the **single source of truth** for all experimental features. Every experimental feature must be registered here.

**Current experiments and maturity:**

| Feature | Enum Case | Maturity | Hidden | Notes |
|---------|-----------|----------|--------|-------|
| iCloud QSO Sync | `.icloudSync` | Beta | No | Data-loss risk, auto-backup on enable |
| Radio CAT Control | `.radioControl` | Alpha | No | Hardware-dependent (BLE/WiFi/Flex) |
| Video Export | `.videoExport` | Beta | No | GPU-intensive, edge cases |
| FT8 | `.ft8` | Alpha | No | Audio decode/transmit |
| Tune In | `.tuneIn` | Beta | No | KiwiSDR WebSDR streaming |
| eQSL | `.eqsl` | Beta | No | Upload/download confirmations |
| Smart Spots / Needs | `.needs` | Beta | No | DXCC/WAS/hunter recommendations |
| Park Boundaries | `.parkGIS` | Beta | No | GIS boundary polygons on map |
| SQL Query Runner | `.queryRunner` | Alpha | Yes | Spot SQL editor (`SpotQueryEditorView`): write/run/save `.cwquery` SQL against the spot engine's scope DB + QSO mirror |
| Remote Control of CW Sweep | `.remoteSweep` | Alpha | Yes | Tab gated; pairs phone with CW Sweep on Mac |
| Propagation Check | `.propagationCheck` | Alpha | Yes | RBN/PSK Reporter antenna comparison |
| Weather Radar | `.weatherRadar` | Alpha | Yes | NEXRAD CONUS radar overlay + NWS active alerts; reached from the Weather panel button (US only) |
| Activity Map Layers | `.activityLayers` | Alpha | No | Toggleable overlays on the Parks & Summits map (grid squares, TOTA tiles, US states + counties, SOTA activation zones, WWFF) plus the `rosette` multiplier finder (POTA+SOTA / POTA+WWFF / county-line) |
| Band Scope | `.bandScope` | Alpha | Yes | Standalone vertical band scope of live spots from the Rust spot engine; driven by saved `.cwquery` SQL; reached from the Experiments hub |
| Carrier Wave Sync | `.syncServer` | Alpha | No | E2E-encrypted server sync (replaces iCloud). Always-visible badged **top-level** row in Settings → Carrier Wave Sync. Passphrase key-escrow + manual push/pull sync with content-addressed dedup + durable cursor; no authority flip yet. Graduation review: after two-device sync verification |
| Satellites | `.satellites` | Alpha | Yes | Hidden tab: live satellite positions on an MKMapView, SatNOGS DB TLEs propagated on-device with SGP4 (SatelliteKit SPM dep). Graduation review: 2026-12 |
| WSJT-X Logging | `.wsjtx` | Beta | No | Settings → Services → WSJT-X: UDP listener (`WsjtxFieldService` over the shared `WsjtxIngestService`) that logs QSOs WSJT-X broadcasts from another computer; foreground only. Graduation review: 2027-01 |

**CW Sweep (macOS)** is entirely experimental — it is a separate app target, not gated by this enum.

**Recently graduated:** Awards & Certificates (`.awards`), Brag Sheet (`.bragSheet`), CW Transcription (`.transcription`), and Log Scanning (`.logScanning`) graduated to stable — enum cases, badges, and guards removed. The CW tab (transcription) is now always available; add it from More → Customize.

**Recently removed:** Events, Activation Recommendations, Speech to Text, and Horizon Survey were deleted — enum cases, feature views, and the Events tab removed.

**Rules:**
- When adding a new experimental feature: add a case to `ExperimentalFeature`, add `ExperimentalBadge` at its entry point(s), update this table, **and set a target graduation review date** (see graduation policy in [docs/ux-north-star.md](../../docs/ux-north-star.md)). Marquee features also get an Explore card (`Views/Explore/ExploreFeature.swift`).
- When graduating a feature to stable: remove its enum case, remove all `ExperimentalBadge` and `ExperimentalFeature.isEnabled()` guards, remove from this table, keep/promote its Explore card, and announce it via a What's New entry on the next version bump.
- **Graduation policy:** experiments are reviewed every release. Beta features stable for 2+ releases with no open data-loss/crash issues graduate by default — shipping good work permanently behind a flag is a discoverability bug, not caution.
- Hidden features (`isHiddenByDefault = true`) are gated — they don't appear in the UI until enabled from Settings > Experiments. Tab-based features (e.g. Remote Control of CW Sweep) are excluded from `TabConfiguration.disabledTabs` when enabled.
- Non-hidden features are always visible but display an `ExperimentalBadge` (orange for beta, red for alpha).
- Use `ExperimentalBadge(feature:)` — never hand-roll orange capsule badges.
- The Experiments hub is at `CarrierWave/Views/Settings/ExperimentsView.swift`.

## iOS-Specific Import Rule

**Use `import UIKit` instead of `import Foundation`** in the `CarrierWave/` app target — with `MemberImportVisibility` + whole-module compilation, `import Foundation` can fail to resolve Foundation types in archive builds. `UIKit` re-exports Foundation via `@_exported import` and resolves reliably. Files that already import `SwiftUI` don't need this (SwiftUI also re-exports Foundation).

## Logging Rule (IMPORTANT)

**Never use `print(...)`, `os_log`, `Logger`, `NSLog`, or `debugPrint` from app code.** All diagnostic output in the iOS target must go through the app's internal logging surfaces so the user can see it in-app, share it via the in-app log export, and so logs survive into bug reports. There is no Mac attached during real use — `os_log` output is invisible.

- **Radio / BLE / bridge / CAT / handshake diagnostics** → `RadioService.shared.addLog(.info | .error, "...")` (or `.sent` / `.received` with `data:` for transport bytes). This is the log shown in the Logger panel.
- **Any other domain** → use that domain's existing in-app log surface. If none exists, add one — do not reach for `os_log`/`Logger`.

When writing from a non-`@MainActor` context (e.g. an `actor` like `BridgeProtocol`, or a Core Bluetooth delegate callback), capture the values you need first and dispatch to the main actor before logging:

```swift
let bytes = data.count
Task { @MainActor in
    RadioService.shared.addLog(.info, "Bridge: handshake RX \(bytes) bytes")
}
```

Existing `print(...)` calls in `BLEDelegate.swift` and similar files predate this rule and are being migrated incrementally; do not add new ones.

## What's New Sheet

The app version is `CARRIER_WAVE_IOS_MARKETING_VERSION` / `CARRIER_WAVE_IOS_BUILD_NUMBER` in `../Versions.xcconfig` (never edit `MARKETING_VERSION` in the pbxproj — `scripts/check-versions.sh` rejects literals there). When bumping it, prepend a matching `WhatsNewEntry` (with `platforms: [.iOS, ...]`) to `WhatsNewCatalog.entries` in `../packages/CarrierWaveData/Sources/CarrierWaveData/Utilities/WhatsNewCatalog.swift`. See root `CLAUDE.md` → "What's New Sheet" for the full workflow.

## Quick Reference

| Area | Details |
|------|---------|
| Sync System | [../../docs/features/sync.md](../../docs/features/sync.md) |
| iCloud Sync & Backup | [../../docs/features/icloud-sync.md](../../docs/features/icloud-sync.md) |
| Statistics | [../../docs/features/statistics.md](../../docs/features/statistics.md) |
| Tours | [../../docs/features/tour-requirements.md](../../docs/features/tour-requirements.md) |
| Delete Confirmation | [../../docs/features/delete-confirmation.md](../../docs/features/delete-confirmation.md) |
