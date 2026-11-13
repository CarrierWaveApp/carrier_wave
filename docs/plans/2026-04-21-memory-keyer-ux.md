# CW Memory Keyer UX Spec

**Status:** approved design
**Depends on:** `docs/plans/2026-04-21-memory-keyer-spec.md` (CWBP keyer protocol, already implemented)

---

## 1. Overview

Two UI pieces enable CW memory keying from the iOS session logger:

1. **Keyer row** — a horizontal strip of memory buttons above the existing command row, visible when a CW Bridge is connected in CW mode.
2. **Message editor** — a settings page for composing templates with macro pills and live preview, also accessible via long-press on any keyer button.

---

## 2. Keyer Row

### Placement
- Appears as a **separate row above the existing command row** in the keyboard accessory.
- Both rows visible simultaneously — keyer row (orange) on top, command row (purple) below.
- When no CW Bridge is connected, or the radio mode is not CW/CW-R, the keyer row is hidden entirely. The command row and number row are unaffected.

### Layout
- **Horizontally scrollable** `ScrollView(.horizontal)`.
- Only shows **programmed slots** (slots with non-empty text). Empty slots are omitted.
- Each button is an orange capsule: `background(Color.orange.opacity(0.15))`, `foregroundStyle(.orange)`, matching the existing command row capsule style but with a distinct color.
- Button label is the slot's **short label** (e.g., "CQ", "EXCH", "TU"), not the full template text. Max ~6 characters in the label.
- **STOP button** (red capsule, `■ STOP`) appended at the trailing edge. Always visible when the keyer row is shown, but only tappable when a send is active.

### Interaction
- **Tap** a slot button → sends `CW_SLOT_PLAY` to the bridge with the current QSO context (CALL, NR, RST, NAME, EXCH, MYCALL).
- **Long-press** a slot button → presents the message detail editor as a sheet.
- **Tap STOP** → sends `CW_STOP` to the bridge.

### Progress Feedback
- While a message is transmitting (`CW_PROGRESS` with `txActive` flag), the sending button's opacity reduces to 0.5 and it gets a subtle pulse animation.
- When `CW_PROGRESS` reports `complete`, the button returns to full opacity.
- If the app receives `CW_ACK` with a failure result, show a brief inline error (e.g., toast or the button flashing red).

### Status Line
- A small centered line above the keyer row shows: `14.060.00 MHz · CW · 28 WPM`
- Data sourced from `RadioService.radioFrequencyMHz`, `RadioService.radioMode`, and the CW engine's current WPM.
- Tapping the WPM opens a popover with a stepper (5-60) that sends `CW_SPEED` on change.

---

## 3. Message Editor

### Entry Points
1. **Settings > Radio > CW Messages** — full list of all 8 slots.
2. **Long-press** on any keyer button in the logger → sheet with the detail editor for that slot.

### List View (Settings)

Top section: **WPM stepper** (5-60, `@AppStorage("cwKeyer.wpm")`). Synced to bridge on change via `CW_SPEED`.

Messages section: one row per **programmed** slot, plus empty slots shown with placeholder text. Each row shows:
- Slot number in orange monospace bold (left-aligned, fixed width).
- Label text (e.g., "CQ", "Exchange").
- Expanded preview in secondary monospace below (e.g., "CQ CQ DE W6JY W6JY K").
- Disclosure indicator (chevron) to signal tappability.

"+ Add Message" button at the bottom if fewer than 8 slots are programmed.

### Detail Editor

Pushed via `NavigationLink` from the list, or presented as a `.sheet` from long-press.

Fields:
- **Label** — short display name for the button (max 8 chars). Plain text field. Auto-populated from the first word of the message template if left empty (e.g., "CQ CQ DE {MYCALL}" → label "CQ").
- **Message** — monospaced text field for the template. Full keyboard with the standard number row.
- **Macro pills** — horizontally wrapping row of tappable capsules. Tapping inserts the macro at the current cursor position in the message field. Two visual groups:
  - Variables (orange): `{MYCALL}`, `{CALL}`, `{NR}`, `{RST}`, `{NAME}`, `{EXCH}`
  - Prosigns (slightly different orange tint): `{BT}`, `{AR}`, `{SK}`, `{KN}`, `{AS}`
- **Preview** — read-only monospace field with green text on dark background. Shows the template expanded with sample values:
  - MYCALL → user's callsign from app settings
  - CALL → "W1AW" (placeholder)
  - NR → "001"
  - RST → "599"
  - NAME → "HIRAM"
  - EXCH → user's exchange from session settings, or "001" fallback

Preview updates live as the message field changes.

Save behavior: on dismiss (back navigation or sheet dismiss), the slot is saved to UserDefaults and synced to the bridge via `CW_SLOT_SET` if connected.

---

## 4. Template Variables

| Macro | Source | Example |
|-------|--------|---------|
| `{MYCALL}` | App settings (user's callsign) | W6JY |
| `{CALL}` | Current QSO callsign field | W1AW |
| `{NR}` | Session serial counter, zero-padded 3 digits | 042 |
| `{RST}` | RST sent field (defaults: 599 CW, 59 phone) | 599 |
| `{NAME}` | QRZ lookup name, or empty if unknown | HIRAM |
| `{EXCH}` | Session exchange setting | CT |

Prosigns are expanded by the bridge firmware to radio-specific encodings (Kenwood inline chars, CI-V `^` prefix).

---

## 5. Data Flow

### Storage
- **Bridge NVS**: canonical storage for the 8 slots (persists across power cycles).
- **UserDefaults**: local cache keyed as `cwKeyer.slot.{n}.label` and `cwKeyer.slot.{n}.text` (n = 1-8). Used for display when bridge is disconnected and for initial sync on connect.

### Sync on Connect
When `BridgeEvent.handshakeComplete` fires with `CWBP_CAP_CW_KEYER`:
1. For each locally-stored slot with non-empty text, send `CW_SLOT_SET` to the bridge.
2. Send `CW_SPEED` with the stored WPM value.

This is a one-way push (app → bridge). The bridge has no slot-read command — the app is the source of truth for slot content, the bridge is the source of truth for runtime state (buffer depth, TX status).

### Send Flow
1. User taps keyer button for slot N.
2. App builds context: `["MYCALL": "W6JY", "CALL": "W1AW", "NR": "042", "RST": "599", ...]`
3. App sends `CW_SLOT_PLAY(slot: N, context: ctx)` via `BridgeProtocol.playCWSlot()`.
4. Bridge expands template, chunks into CAT commands, starts sending.
5. Bridge pushes `CW_ACK(OK, bufDepth)` → app confirms send started.
6. Bridge pushes `CW_PROGRESS` at thresholds → app updates button state.
7. Bridge pushes `CW_PROGRESS(complete)` → app restores button to normal.

### Abort Flow
1. User taps STOP.
2. App sends `CW_STOP` via `BridgeProtocol.stopCW()`.
3. Bridge aborts radio buffer, pushes `CW_PROGRESS(complete)`.

---

## 6. Visibility Logic

The keyer row is shown when ALL of these are true:
- `RadioService.isConnected` is true
- Bridge handshake completed with `CWBP_CAP_CW_KEYER` capability
- `RadioService.radioMode` is "CW" or "CW-R"
- At least one slot has non-empty text in UserDefaults

When any condition becomes false, the keyer row animates out. The command row and number row are never affected.

---

## 7. New Files

| File | Purpose |
|------|---------|
| `Views/Logger/CWKeyerRow.swift` | SwiftUI keyer button row (scrollable, progress state) |
| `Views/Settings/CWMessageListView.swift` | Settings list of all 8 slots + WPM stepper |
| `Views/Settings/CWMessageEditorView.swift` | Detail editor: label, template, macro pills, preview |
| `Services/CWKeyerService.swift` | Actor: slot CRUD in UserDefaults, bridge sync, context building |

### Modified Files
| File | Change |
|------|--------|
| `LoggerKeyboardAccessory.swift` | Add keyer row above command row, conditional on radio state |
| `KeyboardAccessoryBuilder.swift` | Add keyer row to UIKit accessory (same conditions) |
| `RadioService+Bridge.swift` | Slot sync on handshake, CW event forwarding |
| Settings navigation | Add "CW Messages" row under Radio section |

---

## 8. Non-Goals

- **Freeform CW input** (type-and-send). That's a separate feature; this is memory keyer only.
- **WinKeyer support on iOS**. CW Sweep handles WinKeyer over serial; iOS uses the bridge.
- **Slot sync from bridge to app**. One-way push keeps the protocol simple.
- **More than 8 slots**. Bridge NVS limit. Sufficient for contest and casual use.
