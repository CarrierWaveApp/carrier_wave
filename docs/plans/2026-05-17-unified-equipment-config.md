# Unified Equipment Configuration

**Date:** 2026-05-17
**Status:** Phase 1–4 landed (data layer + service + migration + UI)
**Branch:** `claude/unified-equipment-config-OLTXj`

## Implementation Notes (2026-05-17 follow-up)

**Open question 2** resolved: explicit per-session opt-in for CW Bridge.
The bridge is not pinned to a radio profile by default — `bleViaBridge`
is a profile flag the user toggles in the per-item connection sheet.

Shipped in this iteration:

- **CarrierWaveData** — `RadioConnectionProfile` (Codable, JSON-backed
  on `EquipmentItem`), `RadioTransportKind` / `RadioProtocolKind`,
  `RadioCatalogMetadata` helper (derives protocol/transports/bridge
  compat from existing catalog data so the server doesn't need new
  fields yet), `connectionProfileJSON` on `EquipmentItem` +
  `connectionProfile` computed accessor, `connectionProfile` on
  `EquipmentInventorySnapshot`, `radioItemID` on `LoggingSession`.
- **iOS Radio** — `RadioService+Profile.swift` (`connect(toItem:)`,
  `currentProfileSnapshot()`, `apply(profile:owningItemID:displayName:)`).
- **iOS Migration** — `RadioConfigMigration` runs once after equipment
  migration: lifts current `RadioService` UserDefaults into the matching
  (or synthesized custom) radio's profile, back-fills
  `LoggingSession.radioItemID` by name match.
- **iOS LoggingSessionManager+Radio** — `connectRadio()` prefers
  `session.radioItem.connectionProfile` when present; falls back to
  legacy `connectToSavedDevice()` for users mid-migration.
- **iOS UI** — `EquipmentItemDetailView+Connection` section for radios,
  `RadioConnectionSheet` editor (transport/protocol picker, per-transport
  detail fields, CW Bridge toggle, deep-link to global Radio settings
  for scanning/SmartLink/RS-BA1 auth).
- **iOS Session Start Sheet** — captures `selectedRadioItemID` from
  `InventoryPickerSheet` (new `onItemSelected` callback), passes it
  through `LoggingSessionManager.startSession(...)` so auto-connect
  picks up the right radio's profile.

Deliberately deferred:

- Catalog metadata as server-side fields (still derived locally via
  `RadioCatalogMetadata`). Adding them to `EquipmentAPIEntry` is a
  trivial follow-up once the activities server populates them.
- Removing the legacy `RadioService.connectToSavedDevice()` global
  path. Both paths coexist for one release so a downgrade doesn't wipe
  state. Remove in the next version.
- Custom-from-string quick-create in the session start sheet (the
  existing `InventoryPickerSheet` "Add custom" footer covers this; the
  explicit confirm flow can move into the radio picker later).
- Status chip / "Connect" affordance in the logger HUD — the existing
  `RadioPanel` still drives manual control. Replace with the FK-driven
  chip in a follow-up.
- Per-item RS-BA1 / SmartLink credentials in Keychain keyed by
  `keychainCredentialRef`. Plumbed in the profile but the
  read/write sites still use the legacy global keys.

## Goal

Collapse the three places we ask "which radio?" into one. If a user owns
an IC-705, picks it as session equipment, and has previously configured
how it connects, the app should connect on session start without a
separate "Connect Radio" step. CW Bridge becomes a piece of equipment;
adding it to a session for a bridge-compatible radio routes the
connection through the bridge automatically.

## Current Seams

| Concern | Where it lives today | Storage |
|---|---|---|
| Owned gear | `EquipmentItem` (SwiftData) | CarrierWaveData/Models/EquipmentInventory.swift |
| Radio connection settings | `RadioService` singleton | `UserDefaults` + Keychain |
| Protocol (CI-V / Kenwood / Flex) | Re-detected per connect from rig name string | (none — reactive) |
| CW Bridge | `BridgeProtocol` actor wrapping BLE transport | Firmware on companion; no iOS-side config |
| Session equipment | `LoggingSession.myRig` / `myAntenna` / `myKey` / `myMic` | Free-form `String` fields |
| Connection lifecycle | `LoggingSessionManager+Radio.connectRadio()` | Manual trigger |

The structural mismatch — structured `EquipmentItem` vs. free-form
session strings vs. global `UserDefaults` radio settings — is why we
have three onboarding flows for the same concept.

## Target Model

### 1. Connection profile lives on the equipment item

Add an optional connection profile to `EquipmentItem` for radio-class
items (1:1 child or inline value type):

```swift
struct RadioConnectionProfile: Codable {
    enum Transport: String, Codable { case ble, wifi, flexSmartSDR, usbSerial }

    var transport: Transport
    var bleDeviceUUID: UUID?        // BLE only
    var bleViaBridge: Bool          // via CW Bridge?
    var hostAddress: String?        // WiFi / Flex
    var port: Int?
    var keychainCredentialRef: String?  // Flex SmartLink / RS-BA1 creds
}
```

`RadioService` becomes stateless w.r.t. *which* radio. Its public API
shifts from `connectToSavedDevice()` (global) to
`connect(to item: EquipmentItem)` (parameterized).

### 2. Catalog declares protocol + supported transports

Today the rig protocol is sniffed at connect time. Move it to the
canonical catalog entry:

```swift
struct EquipmentCatalogEntry {
    let slug: String
    let displayName: String
    // …
    let radioProtocol: RadioProtocol?         // .civ / .kenwood / .flexSmartSDR / .yaesu
    let supportedTransports: [Transport]      // [.ble, .wifi] for IC-705; [.usbSerial] for FTDX10
    let bridgeCompatible: Bool                // works with CW Bridge?
}
```

Custom items (slug prefix `custom-`) leave these `nil` until the user
configures them — they are *unconfigured*, not invalid.

### 3. CW Bridge as an equipment item

Add a catalog entry for the bridge itself with its own slug and
`category = .accessory`. Users add it to inventory once; for sessions
that include both a bridge-compatible radio and the bridge,
`RadioConnectionProfile.bleViaBridge = true` is implied (or
auto-toggled) so `BridgeProtocol` wraps the BLE transport.

### 4. Session references items by ID, with denormalized name

Replace string fields with FK + cached display name:

```swift
@Model class LoggingSession {
    var radioItemID: UUID?
    var antennaItemID: UUID?
    var keyItemID: UUID?
    var micItemID: UUID?

    // Denormalized for export / search / display when item is missing
    var myRig: String
    var myAntenna: String
    var myKey: String
    var myMic: String
    // …
}
```

The string fields stay (export portability, free-form entry of a
buddy's rig, importing legacy logs). They are written from the item's
display name when an item is chosen.

### 5. Custom-from-string

Free-form entry in the session start sheet does not disappear — it
becomes a **quick-create custom item**:

1. User types "Yaesu FT-991" in the rig picker.
2. We search `EquipmentInventory` and `EquipmentCatalog` for matches.
3. No exact match → "Add 'Yaesu FT-991' as custom equipment" affordance.
4. Accepting creates an `EquipmentItem` with `catalogId = "custom-<uuid>"`,
   name from the string, everything else unconfigured.
5. The session FK is set to the new item.

So **every session radio is a real item**. "Configured" vs.
"unconfigured" replaces "structured vs. free-form" as the distinction —
and the user can upgrade an unconfigured custom item later by filling
in protocol + transport + connection details.

## UX Changes

### Equipment Browser (`EquipmentBrowserView`)

- Radio rows gain a **Connection** section: "Not configured" / "BLE —
  IC-705-A1B2" / "WiFi — 192.168.1.50" / "via CW Bridge".
- Tapping it opens a sheet that absorbs the screens currently under
  Settings → Radio (transport picker, device scan, IP entry,
  SmartLink login).
- A new accessory category surfaces the **CW Bridge** as an item to
  add. Once added, bridge-compatible radios show a "Use CW Bridge"
  toggle in their connection sheet.

### Session Start Sheet (`SessionStartSheet+Equipment`)

- Radio picker becomes a list of `EquipmentItem`s with connection
  state badges (configured / unconfigured / disconnected /
  connecting / connected).
- Picking an unconfigured radio shows an inline "Configure now"
  affordance; user can skip and proceed without auto-connect.
- Free-form typing → quick-create custom item (above).

### Session Detail / Logger HUD

- Replace the manual "Connect Radio" button with a status chip driven
  by the session's radio item:
  - **Configured + idle** → auto-attempt on session start.
  - **Connecting** → spinner.
  - **Connected** → green dot, tap to disconnect.
  - **Failed** → red dot with reason, tap to retry.
  - **Unconfigured** → "Configure" link to the connection sheet.

### Settings

- Settings → Radio collapses to a thin "Default radio" preference plus
  a deep-link to Equipment. Everything else moves into the per-item
  connection sheet.

## Migration

Single-shot migration on first launch of the new build, run from the
SwiftData migration plan:

1. **Materialize an `EquipmentItem` from existing `RadioService`
   settings.**
   - Read `transportType`, `bleDeviceUUID`, `hostAddress`, etc. from
     `UserDefaults`/Keychain.
   - Look for a matching radio in `EquipmentInventory` (by catalog
     slug if previously set, else by stored rig name string).
   - If found → attach a `RadioConnectionProfile` to that item.
   - If not found → create a `custom-` `EquipmentItem` named from the
     last-used rig string, attach the profile to it.
2. **Back-fill `LoggingSession.radioItemID`** by name-matching `myRig`
   against `EquipmentInventory.name`. Unmatched sessions keep their
   string and `radioItemID = nil` — they show as legacy and don't
   auto-connect.
3. **Leave `UserDefaults` keys in place for one release** (read-only
   fallback) so a downgrade doesn't wipe state. Remove next version.
4. **CW Bridge:** if `bleViaBridge` was true in the old config (or the
   handshake was ever observed), seed a CW Bridge `EquipmentItem` and
   set `bleViaBridge = true` on the migrated radio's profile.

Tests: extend `Tests/CarrierWaveDataTests/` with a migration test that
seeds the old `UserDefaults` shape + a session row, runs the migration,
asserts the resulting `EquipmentItem` + `radioItemID`.

## Auto-Connect Behavior

In `LoggingSessionManager`:

- On `startSession()`, if `session.radioItem?.connectionProfile` is
  non-nil, call `RadioService.connect(to:)` automatically.
- Connection attempts are observable on the session, not the global
  service, so the chip in the logger HUD reflects *this session's*
  radio.
- Disconnect on `endSession()` unless another active session shares
  the same item (multi-radio sessions stay out of scope here — see
  `2026-05-05-multi-radio-control-design.md`).

Failure modes:

- **No saved profile** → no-op, chip shows "Configure".
- **Hardware unreachable** → chip shows failure with reason; user can
  tap to retry. Session continues; manual logging still works.
- **Different radio currently connected** → prompt "Disconnect X to
  connect Y?" rather than silently swapping.

## Phasing

Roughly four PRs, in order:

1. **Catalog metadata.** Add `radioProtocol`, `supportedTransports`,
   `bridgeCompatible` to `EquipmentCatalog`. Populate for all current
   entries. No behavior change yet — just data.
2. **`RadioConnectionProfile` on `EquipmentItem` + migration.** Wire
   `RadioService.connect(to:)` alongside the existing API. Keep both
   call sites working. Land the migration. Existing UI unchanged.
3. **Equipment Browser connection sheet.** Move radio configuration UI
   under the item. Settings → Radio becomes a stub. CW Bridge item +
   "Use CW Bridge" toggle.
4. **Session FK + auto-connect.** Add `radioItemID` to
   `LoggingSession`, update `SessionStartSheet+Equipment` pickers,
   replace the manual Connect button with the status chip,
   quick-create custom flow. Remove the deprecated
   `RadioService.connectToSavedDevice()` path.

## Open Questions

1. **One profile per item, or multiple?** An IC-705 can be reached
   over BLE (in the field) *and* WiFi (at home). Single profile means
   the user re-configures when they change location. Multiple profiles
   per item is cleaner long-term but more UI; I'd start with one and
   revisit if users complain.
2. **What lights up the "Use CW Bridge" toggle?** Owning a bridge item
   alone, or bridge item + bridge-compatible radio in the same
   session? Leaning toward the latter: ownership ≠ intent.
3. **What about non-radio gear that has "config"?** Memory keyer
   curves, antenna tuner presets, etc. Out of scope here — this is
   strictly about radio connection. If we generalize, a separate
   `EquipmentConfiguration` polymorphic blob would be the move.
4. **Where do FT8 / FlexRadio / RS-BA1 credentials live?** Keychain
   today, keyed by a global identifier. Re-key by `EquipmentItem.id`
   during migration so multiple Flex radios are addressable
   independently.
5. **Should custom-from-string be implicit or explicit?** Implicit
   (auto-create on session start) is fewer taps but creates ghost
   inventory if the user mis-types. Explicit ("Add as custom
   equipment?" confirm) is slightly more friction but predictable.
   Lean explicit.

## Touched Files (anticipated)

- `swift/packages/CarrierWaveData/Sources/CarrierWaveData/Models/EquipmentInventory.swift`
- `swift/packages/CarrierWaveData/Sources/CarrierWaveData/Models/EquipmentCatalog.swift`
- `swift/packages/CarrierWaveData/Sources/CarrierWaveData/Models/LoggingSession.swift`
- `swift/packages/CarrierWaveData/Sources/CarrierWaveData/Migration/*` (new migration step)
- `swift/ios/CarrierWave/Services/Radio/RadioService.swift`
- `swift/ios/CarrierWave/Services/LoggingSessionManager+Radio.swift`
- `swift/ios/CarrierWave/Views/Settings/EquipmentBrowserView.swift`
- `swift/ios/CarrierWave/Views/Settings/RadioSettingsView.swift` (mostly deleted)
- `swift/ios/CarrierWave/Views/Logger/SessionStartSheet+Equipment.swift`
- `swift/packages/CarrierWaveData/Tests/CarrierWaveDataTests/` (migration test)
