# File Index (root)

Per-subproject indexes. Load only the one(s) relevant to your task.

| area | index |
|------|-------|
| iOS app (entry points, models, utilities, tests) | `swift/ios/FILE_INDEX.md` |
| iOS services (sync, radio, spots, CW, FT8, telemetry, …) | `swift/ios/CarrierWave/Services/FILE_INDEX.md` |
| iOS views (SwiftUI screens by feature) | `swift/ios/CarrierWave/Views/FILE_INDEX.md` |
| CW Sweep (macOS) | `swift/macos/FILE_INDEX.md` |
| Watch app | `swift/watch/FILE_INDEX.md` |
| Widgets | `swift/widgets/FILE_INDEX.md` |
| CarrierWaveCore (SPM, logic + FT8 codec + LoFi CLI) | `swift/packages/CarrierWaveCore/FILE_INDEX.md` |
| CarrierWaveData (SPM, SwiftData + CloudKit sync) | `swift/packages/CarrierWaveData/FILE_INDEX.md` |
| Rust server (activities API, aggregators, RBN proxy) | `server/FILE_INDEX.md` |
| CW Bridge firmware (ESP32-S3, `firmware/`) | `firmware/CLAUDE.md` (no index; small crate) |
| CW Sat Bridge firmware (ESP32-P4, `firmware-sat/`) | `firmware-sat/CLAUDE.md` (no index; small crate) |
| CW SWL (SDR recording workspace) | `swl/FILE_INDEX.md` |
| Website (Hugo manual, devlog) | `website/FILE_INDEX.md` |

## Rules

- Load exactly **one** FILE_INDEX.md per task — pick by subproject above.
- Never load the root + a child index together; the root is just pointers.
- When adding, removing, or renaming files, update the nearest FILE_INDEX.md.
- Keep each index ≤ 600 lines. If one grows past that, split further (add a deeper `FILE_INDEX.md` and a pointer row here).
