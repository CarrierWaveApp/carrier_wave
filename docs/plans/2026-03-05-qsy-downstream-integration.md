# QSY URI Downstream Integration Plans

**Date:** 2026-03-05
**Status:** Draft
**Depends on:** QSY URI parser + notification routing (already implemented)

## Current State

The QSY URI parser (`QSYURIParser`) and notification routing are implemented:

1. `CarrierWaveApp.handleQSYURL()` parses `qsy://` URIs and posts notifications
2. `ContentView` receives notifications and switches to the correct tab
3. **No downstream view consumes the notification data yet** — the tab switches happen, but form pre-fill / radio tuning / search population do not

This document covers wiring up all four remaining actions.

---

## Plan 1: QSY Spot → Logger Form Pre-Fill

**Notification:** `.didReceiveQSYSpot`
**Tab:** `.logger` (already switched by ContentView)

### Behavior

When a `qsy://spot` URI is opened, the logger form should pre-fill identically to how POTA/RBN sidebar spots work today:

| Field | Source | Fallback |
|-------|--------|----------|
| Callsign | `callsign` | Required |
| Frequency | `frequencyMHz` | No change |
| Mode | `mode` | No change |
| Notes | `ref` + `comment` | Empty |
| Grid | `grid` | Ignored (populated via lookup) |

Toast: "QSY: {callsign}" or "QSY: {callsign} on {freq}" if frequency present.

### Implementation

**File: `LoggerView+Modifiers.swift`** — add `.onReceive(.didReceiveQSYSpot)`:

```swift
.onReceive(NotificationCenter.default.publisher(for: .didReceiveQSYSpot)) { notification in
    handleQSYSpotNotification(notification)
}
```

**File: `LoggerView+Commands.swift`** — add handler method:

```swift
func handleQSYSpotNotification(_ notification: Notification) {
    guard let userInfo = notification.userInfo,
          let callsign = userInfo["callsign"] as? String,
          sessionManager?.activeSession != nil
    else {
        if sessionManager?.activeSession == nil {
            ToastManager.shared.warning("Start a session first")
        }
        return
    }

    // Save pre-spot frequency for cancel
    preSpotFrequency = sessionManager?.activeSession?.frequency

    callsignInput = callsign

    if let freqMHz = userInfo["frequencyMHz"] as? Double {
        _ = sessionManager?.updateFrequency(freqMHz, isTuningToSpot: true)
    }

    if let mode = userInfo["mode"] as? String {
        sessionManager?.updateMode(mode)
    }

    // Build notes from ref + comment
    var noteParts: [String] = []
    if let ref = userInfo["ref"] as? String {
        noteParts.append(ref)
    }
    if let comment = userInfo["comment"] as? String {
        noteParts.append(comment)
    }
    if !noteParts.isEmpty {
        notes = noteParts.joined(separator: " - ")
    }

    let freqStr = (userInfo["frequencyMHz"] as? Double)
        .map { " on \(FrequencyFormatter.formatWithUnit($0))" } ?? ""
    ToastManager.shared.info("QSY: \(callsign)\(freqStr)")
}
```

### Edge Cases

- **No active session:** Show warning toast, discard notification
- **Mode present:** Update session mode (like `handleSpotSelection` doesn't do today — this is new for QSY)
- **Grid present:** Store for later use in QSO creation but don't overwrite lookup grid

### Files Changed

| File | Change |
|------|--------|
| `LoggerView+Modifiers.swift` | Add `.onReceive(.didReceiveQSYSpot)` |
| `LoggerView+Commands.swift` | Add `handleQSYSpotNotification()` |

---

## Plan 2: QSY Tune → Radio Frequency Change

**Notification:** `.didReceiveQSYTune`
**Tab:** `.logger` (already switched by ContentView)

### Behavior

When a `qsy://tune` URI is opened, the connected BLE radio tunes to the specified frequency. The session frequency also updates to match.

| Action | Source | Required |
|--------|--------|----------|
| Set radio frequency | `frequencyMHz` | Yes |
| Update session frequency | `frequencyMHz` | Yes |
| Switch mode | `mode` | No (optional) |

Toast: "Tuned to {freq}" or "Tuned to {freq} {mode}" if mode present.

### Implementation

**File: `LoggerView+Modifiers.swift`** — add `.onReceive(.didReceiveQSYTune)`:

```swift
.onReceive(NotificationCenter.default.publisher(for: .didReceiveQSYTune)) { notification in
    handleQSYTuneNotification(notification)
}
```

**File: `LoggerView+Commands.swift`** — add handler:

```swift
func handleQSYTuneNotification(_ notification: Notification) {
    guard let userInfo = notification.userInfo,
          let freqMHz = userInfo["frequencyMHz"] as? Double
    else {
        return
    }

    // Update session frequency (also sends to BLE radio if connected)
    _ = sessionManager?.updateFrequency(freqMHz, isTuningToSpot: true)

    if let mode = userInfo["mode"] as? String {
        sessionManager?.updateMode(mode)
    }

    let modeStr = (userInfo["mode"] as? String).map { " \($0)" } ?? ""
    ToastManager.shared.info(
        "Tuned to \(FrequencyFormatter.formatWithUnit(freqMHz))\(modeStr)"
    )
}
```

### Notes

- `updateFrequency(_:isTuningToSpot:)` already calls `sendFrequencyToRadio()` which calls `BLERadioService.shared.setFrequency()` if connected — no additional BLE wiring needed
- Pass `isTuningToSpot: true` to suppress QSY spot posting (we're receiving, not generating)
- Works with or without an active session — if no session, the frequency update is a no-op but the BLE radio still tunes

### Edge Cases

- **No active session:** Only tune BLE radio directly via `BLERadioService.shared.setFrequency(freqMHz)`, skip session update
- **No BLE radio connected:** Update session frequency only, no error
- **Mode not supported:** Ignore unsupported mode strings

### Files Changed

| File | Change |
|------|--------|
| `LoggerView+Modifiers.swift` | Add `.onReceive(.didReceiveQSYTune)` |
| `LoggerView+Commands.swift` | Add `handleQSYTuneNotification()` |

---

## Plan 3: QSY Lookup → Logs Search Pre-Fill

**Notification:** `.didReceiveQSYLookup`
**Tab:** `.logs` (already switched by ContentView)

### Behavior

When a `qsy://lookup/{callsign}` URI is opened, navigate to the Logs tab and populate the search field with the callsign. The existing query engine handles the rest.

### Challenge

`LogsListContentView.queryText` is `@State` — it can't be set from outside. Two approaches:

**Option A: Notification listener in LogsListContentView** (recommended)
- Add `.onReceive(.didReceiveQSYLookup)` directly in `LogsListContentView`
- Extract callsign from notification, set `queryText`
- Simplest, self-contained

**Option B: Binding passed from parent**
- Thread a `Binding<String?>` through `LogsContainerView` → `LogsListContentView`
- More SwiftUI-idiomatic but requires changing 3 init signatures

### Implementation (Option A)

**File: `LogsListView.swift`** (contains `LogsListContentView`) — add notification handler:

```swift
.onReceive(NotificationCenter.default.publisher(for: .didReceiveQSYLookup)) { notification in
    guard let callsign = notification.userInfo?["callsign"] as? String else {
        return
    }
    queryText = callsign
    // Debounce is already wired — setting queryText triggers search
}
```

Add this modifier to the main body of `LogsListContentView`.

Toast: none (the search results are the feedback).

### Edge Cases

- **Empty callsign:** Ignore (guard handles this)
- **Already searching:** Overwrites current query, which is correct behavior
- **View not yet loaded:** Notification fires before `.task` — queryText will be set and the initial load picks it up

### Files Changed

| File | Change |
|------|--------|
| `Views/Logs/LogsListView.swift` | Add `.onReceive(.didReceiveQSYLookup)` in `LogsListContentView` body |

---

## Plan 4: QSY Log → QSO Confirmation Sheet

**Notification:** `.didReceiveQSYLog`
**Tab:** `.logger` (already switched by ContentView)

### Behavior

When a `qsy://log` URI is opened, show a confirmation sheet with pre-filled QSO data. The user reviews and taps "Log" to create the QSO, or "Cancel" to discard.

This is different from `qsy://spot` which just pre-fills the form — `qsy://log` includes RST, time, and other fields that make it a complete QSO ready to record.

### New State

Add to `LoggerView`:

```swift
@State var pendingQSYLog: QSYLogConfirmation?
```

Where `QSYLogConfirmation` is a new `Sendable` struct:

```swift
struct QSYLogConfirmation: Equatable, Sendable {
    let callsign: String
    let frequencyMHz: Double
    let mode: String
    var rstSent: String?
    var rstReceived: String?
    var grid: String?
    var ref: String?
    var refType: String?
    var time: Date?
    var contest: String?
    var srx: String?
    var stx: String?
    var source: String?
    var comment: String?
}
```

### UI: Confirmation Sheet

Present as a `.sheet` with:

```
┌─────────────────────────────┐
│  Log QSO?                   │
│                             │
│  W1ABC                      │
│  14.062 MHz  CW             │
│  RST: 599 / 599             │
│  Grid: FN42                 │
│  Ref: US-1234 (POTA)        │
│  Source: N3FJP               │
│                             │
│  [Cancel]        [Log QSO]  │
└─────────────────────────────┘
```

Display all non-nil fields. "Log QSO" creates the QSO in the active session. "Cancel" discards.

### Implementation

**File: `LoggerView+Modifiers.swift`** — add notification handler + sheet:

```swift
.onReceive(NotificationCenter.default.publisher(for: .didReceiveQSYLog)) { notification in
    handleQSYLogNotification(notification)
}
.sheet(item: $pendingQSYLog) { confirmation in
    QSYLogConfirmationSheet(
        confirmation: confirmation,
        onConfirm: { confirmQSYLog(confirmation) },
        onCancel: { pendingQSYLog = nil }
    )
}
```

**File: `LoggerView+Commands.swift`** — add handler:

```swift
func handleQSYLogNotification(_ notification: Notification) {
    guard let userInfo = notification.userInfo,
          let callsign = userInfo["callsign"] as? String,
          let freqMHz = userInfo["frequencyMHz"] as? Double,
          let mode = userInfo["mode"] as? String,
          sessionManager?.activeSession != nil
    else {
        if sessionManager?.activeSession == nil {
            ToastManager.shared.warning("Start a session first")
        }
        return
    }

    pendingQSYLog = QSYLogConfirmation(
        callsign: callsign,
        frequencyMHz: freqMHz,
        mode: mode,
        rstSent: userInfo["rstSent"] as? String,
        rstReceived: userInfo["rstReceived"] as? String,
        grid: userInfo["grid"] as? String,
        ref: userInfo["ref"] as? String,
        refType: userInfo["refType"] as? String,
        time: userInfo["time"] as? Date,
        contest: userInfo["contest"] as? String,
        srx: userInfo["srx"] as? String,
        stx: userInfo["stx"] as? String,
        source: userInfo["source"] as? String,
        comment: userInfo["comment"] as? String
    )
}

func confirmQSYLog(_ confirmation: QSYLogConfirmation) {
    // Update session freq/mode to match
    _ = sessionManager?.updateFrequency(
        confirmation.frequencyMHz, isTuningToSpot: true
    )
    sessionManager?.updateMode(confirmation.mode)

    // Pre-fill form fields so logQSO() picks them up
    callsignInput = confirmation.callsign
    rstSent = confirmation.rstSent ?? defaultRST(for: confirmation.mode)
    rstReceived = confirmation.rstReceived ?? defaultRST(for: confirmation.mode)
    if let grid = confirmation.grid { theirGrid = grid }
    if let ref = confirmation.ref { theirPark = ref }
    if let comment = confirmation.comment { notes = comment }

    // Log the QSO
    logQSO()

    pendingQSYLog = nil
    ToastManager.shared.success("Logged \(confirmation.callsign)")
}
```

**New file: `Views/Logger/QSYLogConfirmationSheet.swift`** — confirmation UI:

A simple sheet (~80 lines) showing the QSO details in a `Form` with confirm/cancel buttons. Pattern matches `DeleteSessionConfirmationSheet`.

### Edge Cases

- **No active session:** Warning toast, discard
- **Time field:** If `time` is provided, pass it through to QSO creation (may need `logQSO(at:)` variant). If not provided, use current time (default behavior)
- **Duplicate detection:** The existing duplicate detection in `logQSO()` handles this — if the callsign+band+park is a dupe, the user sees the normal dupe warning
- **Contest exchange fields:** `srx`/`stx` map to existing session exchange fields if the session has a contest type

### Files Changed

| File | Change |
|------|--------|
| `Models/QSYLogConfirmation.swift` | New — confirmation data struct |
| `Views/Logger/QSYLogConfirmationSheet.swift` | New — confirmation sheet UI |
| `LoggerView.swift` | Add `@State var pendingQSYLog` |
| `LoggerView+Modifiers.swift` | Add `.onReceive(.didReceiveQSYLog)` + `.sheet(item:)` |
| `LoggerView+Commands.swift` | Add `handleQSYLogNotification()` + `confirmQSYLog()` |

---

## Implementation Order

1. **Plan 2 (Tune)** — Smallest change, no UI, self-contained
2. **Plan 1 (Spot)** — Mirrors existing `handleSpotSelection` pattern
3. **Plan 3 (Lookup)** — Single-line addition to LogsListContentView
4. **Plan 4 (Log)** — Most complex, new sheet + model

Plans 1-3 can be done in a single commit. Plan 4 is a separate commit.

## Testing

Manual testing via Safari or terminal:

```bash
# Spot: pre-fill logger with W1ABC on 14.062 CW
xcrun simctl openurl booted "qsy://spot?c=W1ABC&f=14062000&m=CW"

# Tune: change radio to 7.030 MHz
xcrun simctl openurl booted "qsy://tune?f=7030000"

# Lookup: search logs for W1ABC
xcrun simctl openurl booted "qsy://lookup/W1ABC"

# Log: confirm and log a QSO
xcrun simctl openurl booted "qsy://log?c=W1ABC&f=14062000&m=CW&rs=599&rr=599"
```

Also test from other apps that generate QSY URIs (N3FJP, DXKeeper, etc.) once the scheme is registered.
