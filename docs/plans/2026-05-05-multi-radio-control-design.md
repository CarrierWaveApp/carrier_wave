# Multi-Radio Control in CW Sweep — Design

**Status:** Draft
**Date:** 2026-05-05
**Branch:** `claude/multi-radio-control-plan-RNLbg`
**Owner:** Sweep
**Linear:** _to-file_ (CW Sweep project)

## Goal

Let CW Sweep operate two (or more) connected radios at the same time — the classic SO2R workflow plus the more general "remote rig + local rig", "HF + V/U", and "primary + spotting receiver" cases. Today, CW Sweep can hold multiple `RadioSession`s in a dictionary but everything user-visible (state, UI, tune commands, persistence, audio, waterfall) collapses to a single "active" radio. This design lifts that collapse without breaking single-radio users.

## Non-goals

- Networked SO2R (interlocks across machines / N1MM-style) — out of scope; we'll keep the single-host N1MM broadcast surface.
- Diversity reception / coherent IQ — different feature.
- Hardware band-decoder / interlock relays.
- Stereo split RX audio mixing — covered as a follow-up; v1 lets the user pick which radio's RX the Mac plays.

## Current state (what already supports multi-radio, what doesn't)

Confirmed by reading `swift/macos/CWSweep/Services/Radio/`:

| Already plural | Effectively singular |
|----------------|---------------------|
| `RadioManager.sessions: [UUID: RadioSession]` | `RadioManager.activeRadioId` is the only consumer |
| Per-session `RadioSession` actor (transport + handler + state) | `RadioManager.frequency / mode / xitEnabled / ritEnabled / ritXitOffset / isTransmitting / scopeSpanKHz / connectedPortPath / connectedRadioName / isConnected` reflect only the active session |
| `commandLog` exists | …but is one shared ring buffer, no per-radio tag |
| Auto-detect probes are per-port | `lastDeviceFingerprint` is a single `UserDefaults` key |
| `connect(profile:port:)` returns a session UUID | `RadioManager+Tune` extensions all hard-code `activeRadioId` |
| `WaterfallStore` is source-agnostic | One `WaterfallStore`, one `sculan10Waterfall` producer, one `flexPanadapter` producer, one `sculan10AudioPlayer`, one `radioAudioBroadcaster` |
| BLE/CoreBluetooth supports multiple peripherals | `activeBridge`, `activeBridgeTransport`, `activeBridgeSessionId`, `bridgeFirmwareVersion`, `bridgeCapabilities`, `bridgeDetectedRadio`, `bridgeCWSendingSlot`, `bridgeIsFramed`, … (one bridge total) |
| `RadioControlView` family picker | Picks one connection at a time; no concept of slots |

So the path forward isn't "build a multi-radio system from scratch" — it's "promote existing per-session truth into the UI and break the assumption that there's one active radio everywhere downstream."

## Concept: slots

Introduce **radio slots** as the user-visible identity. A slot is a stable label the operator interacts with (e.g. "Radio A", "Radio B"); a session is what's plugged in right now.

```swift
enum RadioSlot: String, CaseIterable, Codable, Identifiable {
    case a, b   // Start with two; design is open to N but UI/UX commits to 2.
    var id: String { rawValue }
    var label: String { "Radio \(rawValue.uppercased())" }
}
```

Why slots, not "just a list of UUIDs":

- Persistence is stable — disconnect/reconnect doesn't shuffle which radio is "A".
- Spot-tune affordances (right-click → "Tune Radio B"), keyboard shortcuts (`⌘1` / `⌘2` focus), and contest features (Radio A is Run, Radio B is Mult) need stable labels.
- Single-radio users see slot A only; the abstraction is invisible.
- Saved profiles + auto-connect become per-slot.

`RadioManager` holds `slots: [RadioSlot: UUID]` mapping slot → current session, alongside the existing `sessions: [UUID: RadioSession]`. `activeRadioId` becomes `focusedSlot: RadioSlot` and is purely a UI focus pointer (which radio receives "tune" / mode / PTT when the user doesn't disambiguate).

## Architecture changes

### 1. Per-session state on `RadioManager`

Move singular state off `RadioManager` and into a per-session view-model.

```swift
@MainActor @Observable
final class RadioSlotState {
    let slot: RadioSlot
    let sessionId: UUID
    var profile: RadioProfile
    var connectedPortPath: String?
    var connectedRadioName: String?
    var frequency: Double = 0
    var mode: String = ""
    var scopeSpanKHz: Double = 0
    var xitEnabled = false
    var ritEnabled = false
    var ritXitOffset = 0
    var isTransmitting = false
    var bridge: BridgeSlotState?   // see §3
    var lastError: String?
}
```

`RadioManager` then exposes:

```swift
var slotStates: [RadioSlot: RadioSlotState] = [:]
var focusedSlot: RadioSlot = .a

// Backward compat — preserve every existing call site by routing through focused slot.
var frequency: Double { slotStates[focusedSlot]?.frequency ?? 0 }
var mode: String { slotStates[focusedSlot]?.mode ?? "" }
var isConnected: Bool { !slotStates.isEmpty }
// …etc
```

These computed properties keep `RadioControlView`, `StatusBarView`, the band map's frequency cursor, etc. compiling unchanged on day one.

`pollActiveState()` becomes `pollAllSessions()` and writes into the matching `RadioSlotState` — one polling loop iterates the slot map. This is also the right place to decide how often to poll secondary radios (e.g. 100 ms for focused, 500 ms for unfocused, configurable).

### 2. Tune API takes an explicit slot

`RadioManager+Tune.swift`:

```swift
func tuneToFrequency(_ freqMHz: Double, slot: RadioSlot? = nil) async -> Bool
func setMode(_ mode: String, slot: RadioSlot? = nil) async -> Bool
func setPTT(_ on: Bool, slot: RadioSlot? = nil) async -> Bool
// etc.
```

`slot == nil` ⇒ use `focusedSlot`. Existing callers (`tuneToSpot`, command palette, vim-mode key bindings) keep working with no edit. New callers — context menus, contest layouts that target Radio A vs B — pass an explicit slot.

`tuneToSpot` gets an overload that takes an explicit slot for "right-click spot → Tune on Radio B".

### 3. CW Bridge state per slot

Replace the eleven `bridge*` properties on `RadioManager` and `activeBridge*` triple with a per-slot `BridgeSlotState`:

```swift
@MainActor @Observable
final class BridgeSlotState {
    var bridge: BridgeProtocol
    var transport: BLERadioTransport
    var firmwareVersion: String?
    var capabilities: UInt8 = 0
    var usbConnected = false
    var detectedRadio: String?
    var detecting = false
    var isFramed = false
    var hasCWKeyer = false
    var cwSendingSlot: Int?
    var cwSpeed: UInt8 = 25
    var cwFlags: BridgeFrame.CWProgressFlags = []
    var cwBufferDepth: UInt8 = 0
    var eventTask: Task<Void, Never>?
    var stateTask: Task<Void, Never>?
}
```

Stored in `RadioSlotState.bridge`. `RadioManager+Bridge` is rewritten so each handler closure captures the `slot` it belongs to. CoreBluetooth supports multiple connected peripherals, so two bridges is mostly bookkeeping — the work is making sure `BLEDelegate` callbacks find the right slot's transport. (Likely a `[CBPeripheral: BLERadioTransport]` registry on the discovery service.)

### 4. Producers per session

`sculan10Waterfall`, `flexPanadapter`, `activeSCULAN10`, `sculan10AudioListenerID` move into the slot. `WaterfallStore` becomes per-slot too:

```swift
final class RadioSlotState {
    let waterfallStore = WaterfallStore()
    var sculan10Waterfall: SCULAN10WaterfallData
    var flexPanadapter: FlexPanadapterService
    var activeSCULAN10: SCULAN10Transport?
    // …
}
```

The "which waterfall does the panel show?" question is then a UI choice. v1: the waterfall panel mirrors `focusedSlot`. v2: optional split / stacked waterfalls.

`RadioAudioBroadcaster` stays per slot too. The Mac speaker can only realistically render one slot at a time without confusing the operator; we add a small "Audio: A | B" toggle in the status bar. Remote LAN broadcast can publish per-slot streams (downstream consumers already key by topic — see `RemoteOpService`).

### 5. Persistence

`RadioManager+Persistence.swift` today writes:

- `radio.lastDeviceFingerprint` — string
- a single `RadioProfile` keyed by fingerprint

Becomes:

- `radio.slot.<slot>.lastDeviceFingerprint`
- profile dict keyed by `(slot, fingerprint)` so the same physical radio used in slot A on Tuesday and slot B on Wednesday isn't stomped.

`autoConnect(ports:)` iterates all slots, attempting each saved fingerprint. Connection failures don't cascade — slot A failing doesn't block slot B.

### 6. Command log

Tag every entry with its originating slot. `RadioCommandLog.append(direction:, text:, slot:)`. `CommandLogSection` adds a slot-filter chip row when more than one radio is connected. The remote LAN broadcaster needs no schema change — adds a `slot` field to existing event JSON (best to bump `commandLog` topic version when the API surface lands).

## UI changes

### Radio Control view

`RadioControlView.swift` today is a single connection-family picker that mutates one `RadioManager` connection. Refactor into:

```
+-----------------------------------------------------+
| Radio Control                                       |
| [ Radio A | Radio B | + ]   ⚙ Preferences           |
| ─────────────────────────────────────────────────── |
|   < family picker for selected slot >               |
|   < USB / TCPIP / Bridge sub-section >              |
|                                                     |
|  Command log (filter: All | A | B)                  |
+-----------------------------------------------------+
```

The slot tab strip is the new top-level. Each slot has its own connection-family `@AppStorage` key (`radio.slot.<slot>.connectionFamily`). The `+` button reveals a third slot only when both A and B are configured (keeps the default UX simple). Disconnecting a slot drops it back to "Not connected" but keeps the saved profile.

USB autodetect-on-Connect already prevents the user from accidentally connecting the same physical port twice — we add an explicit guard: `connect(profile:port:)` rejects a port that's already owned by another slot, surfaced as the existing error banner.

### Status bar

`StatusBarView.swift` today shows one radio status pill. Replaces with per-slot pills — `A: 14.025 CW · K3` / `B: 7.040 CW · IC-7300` — and a small audio indicator on the slot whose RX audio is currently routed to the Mac speaker.

### Spot tune affordances

- Click a spot → tune the focused slot (today's behavior, unchanged).
- Right-click a spot → "Tune Radio A" / "Tune Radio B".
- Drag a spot onto a slot's status pill → tune that slot. (Stretch.)

`SpotEntryBridge` already mediates spot-to-popup; it grows a slot parameter, default `nil` (= focused).

### Command palette

`CommandPaletteView` and `RadioPaletteView` currently parse "tune 14.025" into a tune action against the active radio. Add slot prefixes:

- `a tune 14.025` / `b tune 14.025`
- `a mode CW` / `b mode CW`
- `swap` — swap A and B frequencies (SO2R staple)
- `focus a` / `focus b` — change focused slot

Default (no prefix) = focused slot.

### Keyboard shortcuts

- `⌘1` / `⌘2` — focus Radio A / Radio B.
- `⌃⌘S` — swap frequencies between A and B.
- `⌃⌘A` — toggle which slot the Mac speaker plays.

These wire through `CWSweepCommands.swift` and `FocusedValues.swift`.

### Radio role hint (contest-only)

In Contester layout (`ContesterLayout.swift`), surface a "Run / Mult" tag per slot. This is annotation-only at first — no contest-engine logic change. Future: wire to the contest scoring engine for run-vs-mult attribution.

## Edge cases

1. **Same physical radio across slots.** Forbidden — `connect` checks the port path and BLE peripheral UUID against existing slots and surfaces "Already connected to slot A" instead of dropping a session.
2. **Two FlexRadios on the LAN.** Discovery already keys on serial; the manual-IP path needs a slot context. UDP discovery service is shared, but each slot picks its own target.
3. **Two BLE bridges.** Pair both in Settings. `BridgeDiscoveryService` returns a list; slot UI picks one. `BLEDelegate` registry maps `CBPeripheral` → `BLERadioTransport` so callbacks route correctly.
4. **Disconnecting the focused slot.** `focusedSlot` falls back to the other connected slot if any; otherwise stays put with empty state.
5. **PTT collisions.** v1 doesn't enforce mutual exclusion — the operator's job. v2 adds an opt-in interlock setting that refuses a PTT on slot B if slot A is transmitting (and surfaces a beep / visual flash).
6. **Polling pressure.** Two radios on USB at 100 ms each is fine, but two SCU-LAN10 + one Flex on the same machine starts to bite. The split poll cadence (focused 100 ms, others 500 ms) caps it; we expose the unfocused interval in `RadioPreferencesPopover`.
7. **Auto-XIT / `tuneToSpot` semantics on the unfocused slot.** Tune a spot to slot B → still applies the same auto-XIT pref that's user-global today. Don't fork that pref unless users ask.
8. **Vim mode binding.** Vim mode acts on focused slot. `:slot a` / `:slot b` switches focus.
9. **Watch / iOS handoff.** `HandoffService` ships one frequency. Sends focused slot's frequency. No protocol change.

## Migration

The single-radio path has to keep working unchanged through the entire refactor.

- Step 1 lands the `RadioSlotState` model with only slot A populated. Computed shims on `RadioManager` (`var frequency: Double { slotStates[.a]?.frequency ?? 0 }`) keep all existing reads working.
- Step 2 retires the old singular fields once the build is green. SwiftLint will pick up unused stored properties.
- Persistence migration: on first launch after the upgrade, the existing `radio.lastDeviceFingerprint` and saved profile are copied into slot A's keyspace, then the old keys deleted.

## Phasing

| Phase | Scope | Outcome |
|-------|-------|---------|
| 1 | `RadioSlotState` model, slot map, computed shims, polling loop iterates slots | All existing UI works; no user-visible change. |
| 2 | Tune API takes optional slot; per-slot persistence + auto-connect | Two radios can be connected via xcode-only test path. |
| 3 | `RadioControlView` slot tab strip; status bar pills; right-click "Tune Radio B" | First user-visible multi-radio. |
| 4 | Command-palette slot prefixes; `⌘1`/`⌘2`/`⌃⌘S` shortcuts; vim `:slot` | Power-user ergonomics. |
| 5 | Per-slot bridge state; multi-bridge BLE | Two bridges. |
| 6 | Per-slot waterfall + audio routing toggle | Visual + audio multi-radio. |
| 7 | Contest Run/Mult tagging; PTT interlock setting | Contest SO2R. |

Phases 1–3 are the minimum shippable feature ("CW Sweep can control two radios"). 4–7 are independently valuable follow-ups, each landable on its own.

## Files touched (rough)

Primary surgery:

- `swift/macos/CWSweep/Services/Radio/RadioManager.swift`
- `swift/macos/CWSweep/Services/Radio/RadioManager+Tune.swift`
- `swift/macos/CWSweep/Services/Radio/RadioManager+Bridge.swift`
- `swift/macos/CWSweep/Services/Radio/RadioManager+Persistence.swift`
- `swift/macos/CWSweep/Services/Radio/RadioManager+Audio.swift`
- `swift/macos/CWSweep/Services/Radio/RadioManager+Transport.swift`
- `swift/macos/CWSweep/Services/Radio/RadioCommandLog.swift`

New file:

- `swift/macos/CWSweep/Services/Radio/RadioSlotState.swift`

UI:

- `swift/macos/CWSweep/Views/Radio/RadioControlView.swift`
- `swift/macos/CWSweep/Views/Radio/USBRadioSection.swift`, `TCPIPRadioSection.swift`, `CWBridgeSection.swift`, `CommandLogSection.swift`
- `swift/macos/CWSweep/Views/Workspace/StatusBarView.swift`
- `swift/macos/CWSweep/Views/CommandPalette/CommandPaletteView.swift`, `RadioPaletteView.swift`
- `swift/macos/CWSweep/Commands/CWSweepCommands.swift`
- `swift/macos/CWSweep/Utilities/SpotEntryBridge.swift`

File-length watch: `RadioManager.swift` is already near the 500-line limit; the slot-state extraction probably needs to land alongside a `RadioManager+Slots.swift` to stay under budget.

## Open questions

1. **N for slots.** Is two enough, or do we want three from day one (triplexer / SO3R)? Recommend committing to two in the UI, leaving `RadioSlot` itself open-ended.
2. **Default focused slot on launch.** Last-focused, or always A? Recommend last-focused (one `UserDefaults` key).
3. **N1MM broadcast: per-slot or focused-only?** N1MM clients expect a single radio. v1 broadcasts focused only; v2 lets the user pick which slot.
4. **Remote LAN protocol versioning.** Adding `slot` to `radio.frequency`/`radio.command-log`/`radio.waterfall` topics is additive; iOS clients ignoring the field still work. Worth bumping a feature-flag string in the hello payload so the iOS app can show "your Mac has multiple radios" affordances.
5. **Contest engine awareness.** Should `ContestEngine` count QSOs against the slot they were logged from? Probably yes for run-vs-mult stats, but that's its own design.

## Risks

- **Refactor scope creep.** The shims in §Migration are load-bearing; if we skip them, the diff explodes. Keep the singular field shims in `RadioManager` until phase 2 is complete, then delete in a single follow-up.
- **CoreBluetooth multi-peripheral edge cases.** Two simultaneous BLE bridges hasn't been exercised. Phase 5 owns the bring-up; expect a separate investigation in `docs/investigations/`.
- **`RadioManager.swift` 500-line cap.** Plan the split before you start, not while compiling.
- **Audio routing surprises.** Operators expect the speaker to follow focus changes by default but not steal audio mid-QSO. v1 ships an explicit toggle and a "follow focus" preference (default off).
