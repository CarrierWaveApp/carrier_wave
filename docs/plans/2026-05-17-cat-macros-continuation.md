# CAT Macros — Continuation Plan

**Branch:** `claude/cat-macros-placeholders-B469N`
**Status:** Data layer + catalog + executor + tests landed. No UI, no app wiring, no local Xcode build.
**Last commit:** `0b80e63` — `feat(macros): add user-authored CAT macros with data-driven vendor command catalog`

## What's already in

Read these to come up to speed (in this order):

1. `swift/packages/CarrierWaveData/FILE_INDEX.md` → the new `### Macros` section
2. `swift/packages/CarrierWaveData/Sources/CarrierWaveData/Macros/RadioMacroStep.swift` — the wire contract
3. `swift/packages/CarrierWaveData/Sources/CarrierWaveData/Macros/MacroExecutor.swift` — the `MacroExecutorSink` protocol (this is what the iOS app implements)
4. `swift/packages/CarrierWaveData/Sources/CarrierWaveData/Resources/RadioCommands/civ-icom.json` — the data-driven half of the system
5. `swift/packages/CarrierWaveData/Tests/CarrierWaveDataTests/Macros/*` — start with `MacroExecutorTests.swift`, the `RecordingSink` actor is the template for the real adapter

The full thread that produced this lives in the `claude/cat-macros-placeholders-B469N` session — design rationale is there if any decision below looks arbitrary.

## Step 0 — Validate before doing anything else

The package was format/lint-clean but never compiled (cloud env, no Xcode). Before any new work:

```bash
xc test-core    # CarrierWaveCore SPM tests — sanity check the toolchain
cd swift/packages/CarrierWaveData && swift build
cd swift/packages/CarrierWaveData && swift test --filter Macros
```

Expected failures and what they probably mean:

- **`Bundle.module` not found in `RadioCommandCatalog.loadBundled`** → `Package.swift` `resources: [.copy("Resources/RadioCommands")]` clause may need `.process(...)` instead of `.copy(...)` depending on Xcode version. Try `.process` first; SwiftPM's behavior differs across 5.9/5.10.
- **`actor RecordingSink: MacroExecutorSink` conformance error** about the async-getter requirements — if Swift complains that the actor's plain `var connectedProtocol: RadioCommandProtocol? { .civ }` doesn't satisfy `var connectedProtocol: RadioCommandProtocol? { get async }`, change the protocol to drop `async` (actor isolation makes calls async anyway) OR change the implementations back to `nonisolated var connectedProtocol: RadioCommandProtocol? { get async { .civ } }`. The first is cleaner.
- **`@Model RadioMacro` schema errors** about computed JSON-blob accessors → SwiftData sometimes wants `@Transient` on computed properties. Mark `tags`, `appliesTo`, `args`, `steps` with `@Transient` if it complains.
- **CI-V address default mismatch** — the bundled `civAddress` for IC-7300 is `0xA4` in tests but the real handler defaults to `0xA4` too (`CIVProtocolHandler.swift:9`). If the test expects `0x94` somewhere it's wrong; tests should match the handler default.

Fix what's broken, rerun, then proceed.

## Step 1 — Wire the executor to RadioSession (iOS Field)

The single missing link between "data layer compiles" and "user can press a button to run a macro."

**Create:** `swift/ios/CarrierWave/Services/Radio/RadioSessionMacroSink.swift`

```swift
import CarrierWaveData
import Foundation

/// Adapter that lets `MacroExecutor` dispatch into the live `RadioSession`.
/// One per session; throw it away when the session disconnects.
actor RadioSessionMacroSink: MacroExecutorSink {
    private let session: RadioSession
    private let civAddressOverride: UInt8?

    init(session: RadioSession, civAddress: UInt8? = nil) {
        self.session = session
        self.civAddressOverride = civAddress
    }

    var connectedProtocol: RadioCommandProtocol? {
        // Map from RadioService's connected-radio info; nil if not connected.
        // See RadioService.shared.connectedRadioProtocol or similar.
        ...
    }

    var civAddress: UInt8? { civAddressOverride ?? 0xA4 } // pull from handler when wired

    func setFrequencyHz(_ hz: UInt64) async -> Bool {
        await session.tuneToFrequency(Double(hz) / 1_000_000)
    }
    func setMode(_ mode: String) async -> Bool { await session.setMode(mode, universalModeRawValue: nil) }
    func setPowerWatts(_ watts: UInt8) async -> Bool { await session.setPowerLevel(watts) }
    func setPTT(_ on: Bool) async -> Bool { await session.setPTT(on) }
    func setRIT(_ on: Bool) async -> Bool { await session.setRIT(on) }
    func setXIT(_ on: Bool) async -> Bool { await session.setXIT(on) }
    func setRITXITOffsetHz(_ hz: Int) async -> Bool { await session.setRITXITOffset(hz) }
    func clearRITXIT() async -> Bool { await session.clearRITXIT() }
    func sendCW(_ text: String) async -> Bool { await session.sendCW(text) }
    func sendRawBytes(_ data: Data) async throws { try await session.sendRaw(data) }
}
```

Two unknowns to resolve as you write it:

1. **`connectedProtocol` source.** `RadioService` (`swift/ios/CarrierWave/Services/Radio/RadioService.swift`) tracks the active rig protocol — find the `@Published` or accessor that exposes it and map `.civ` / `.kenwood`. If only the handler instance is exposed, branch on `is CIVProtocolHandler` / `is KenwoodProtocolHandler`.
2. **CI-V slave address.** The handler stores it (`CIVProtocolHandler.civAddress`). Either expose it via `RadioSession` (preferred — small public read) or have the sink hold a reference to the handler directly.

When you wire it in:

- Add a debug "Run macro" command somewhere in `Settings → Experiments → Radio CAT Control` (gated by `ExperimentalFeature.radioControl`) so we can smoke-test without a full editor UI yet.
- Log every dispatched step via `RadioService.shared.addLog(.info, ...)` — see the iOS logging rule in `swift/ios/CLAUDE.md`. Never `print` or `os_log` from app code.

## Step 2 — Minimal SwiftUI editor

Once the sink works, build the editor. Suggested layout:

**New files** under `swift/ios/CarrierWave/Views/Settings/Macros/`:

- `MacrosListView.swift` — `@Query` is fine here (small table); list macros, edit/run buttons, "+ New", "Import .cwmacro"
- `MacroEditorView.swift` — name/icon/description/tags/appliesTo header, reorderable step list, "Add Step" sheet
- `MacroStepEditorView.swift` — switches on `RadioMacroStep.Kind`, renders the right input form per kind
- `VendorCommandPickerView.swift` — categorized list from `RadioCommandCatalog.shared.commands(forProtocol:)`, each row reveals param inputs introspected from `RadioCommandParam.type`
- `MacroRunSheetView.swift` — prompts for any `RadioMacroArg` values (with defaults pre-filled), shows step-by-step progress as it runs

**Run wiring:** dispatch via a `@MainActor` view-model that holds the `MacroExecutor` and the `RadioSessionMacroSink`. On run, push events to a `[String]` log so the sheet can show "→ setMode CW", "→ setFrequency 7032000", etc. in real time.

**Hard rules to honor:**

- `@Query` is BANNED for QSO/ServicePresence (PERFORMANCE rule). `RadioMacro` is a small table; `@Query` is fine.
- Each view file ≤ 500 lines, type body ≤ 300 lines. Split early.
- `RadioControl` is `.alpha` in `ExperimentalFeature` — wrap entry points in `ExperimentalBadge(feature: .radioControl)`.

## Step 3 — Macro execution from outside the editor

The interesting placements (in priority order):

1. **Long-press a CW keyer slot** → "Run macro instead." Reuses the existing `CWKeyerService` button strip in the Logger. Macros that only set rig state (no `sendCW`) become QSY shortcuts.
2. **Spot tap** → "QSY to spot via macro." When a user taps a spot, offer their saved "QSY to Hunter" macro (the example from the design doc) with the spot's freq/mode prefilled as runtime args.
3. **Session start** → "Run macro on activation start." A `LoggingSession` field pointing at a `RadioMacro.id` that runs once when the user taps "Start" on a POTA/SOTA session.

These can ship one per PR. Each is small once the editor exists.

## Step 4 — CW Sweep (macOS) parity

`MacroExecutor` and `RadioMacro` live in the shared `CarrierWaveData` package, so Sweep gets them for free. Build:

- `swift/macos/CWSweep/Services/Radio/MacRadioSessionMacroSink.swift` — equivalent adapter for Sweep's serial-radio transport
- Reuse the editor views via a thin macOS wrapper; the data is identical

Mac-specific addition: drop-target on the macro list that imports `.cwmacro` files dragged from Finder. Use `RadioMacroDocument.decode(from:)`.

## Step 5 — Catalog growth

Adding a new vendor command should be a one-file change. Process:

1. Append to `swift/packages/CarrierWaveData/Sources/CarrierWaveData/Resources/RadioCommands/civ-icom.json` (or kenwood-elecraft.json)
2. Add a `@Test` in `RadioCommandCatalogTests.swift` asserting the encoded byte sequence
3. Optionally update `supports` to indicate which radios are tested

**Catalog wish list** (already requested informally; not in scope of any PR yet):

- IC-705 GPS commands (`16 5A`-family)
- IC-9700 satellite-mode commands (`16 5A`, `1A 07`)
- IC-7610 dual-watch toggle
- Yaesu FT-891 / FT-991A — protocol is Kenwood-compatible but with quirks (9-digit `FA`/`FB`); needs a new `yaesu-` catalog file
- Elecraft K3 / KX3 — well-documented EX menu numbers; ripe for a community-maintained file

When third-party catalogs become a thing, add a remote-fetch path to `RadioCommandCatalog` (currently only `loadBundled`). Spec it like SubManager / equipment catalog updates.

## Step 6 — Firmware-side execution (deferred, NOT for next PR)

Only worth doing once timing tests show BLE round-trip jitter is hurting macros. Plan:

1. Add `RunMacro { repeated MacroStep steps; map<string,string> context }` to `proto/cwbp.proto`
2. Subset of `RadioMacroStep` that's safe firmware-side (no `vendorCommand` lookup — bundle resolved bytes; no template expansion — pre-resolve on the phone)
3. Bridge runs the sequence locally using its existing `verify.rs` / `usb.rs` paths
4. App falls back to local execution when bridge is on an older firmware version (negotiated via handshake `capabilities` bitmask)

Linear: file `CAR-XXX` when this becomes real.

## Known design corners not yet handled

Capture these in Linear if real users hit them; otherwise leave alone:

1. **Conditional steps** ("only PTT if frequency is in a ham band"). Punt until someone asks. Adding `.if(condition: String, then: [Step], else: [Step])` is a format-version bump.
2. **Loops / repeat-N.** Same — punt. If needed, `.repeat(count: String, steps: [Step])`.
3. **Math expressions** (`{khz * 1000}`). Earlier draft had them; cut in favor of "declare the arg in the target unit." Reintroduce as a format-2 feature only if real macros need it.
4. **Macro chaining** (one macro calls another by ID). Tempting but adds cycle-detection burden. Skip until requested twice.
5. **Per-step verification UI.** The executor currently swallows `setMode`/`setFrequency` Bool failures. For a "this macro failed at step N" report, capture each return value into `MacroExecutionReport` (add `failedSteps: [Int]`). Easy follow-up.

## Linear / CHANGELOG

The CHANGELOG entry under `[Unreleased]` covers the data layer. When the editor lands:

- Update the existing `[Unreleased]` "Added" entry rather than adding a parallel one — keep one entry per coherent feature spanning multiple PRs.
- File CAR issues for each follow-up step above; reference them in commit messages.

## One thing not to do

Don't add a SwiftUI editor that hand-writes hex into a text field as the "advanced" mode. The whole point of the catalog redesign was to keep users out of raw bytes. `.rawBytes` is in the schema as a deliberate escape hatch for community-shared macros that need it; the editor should require the user to type the protocol name explicitly and show a "⚠ Unverified" badge, not present hex as a normal authoring path.
