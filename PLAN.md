# Implementation Plan: POTA Rove Interface

Design: [docs/plans/pota-rove-interface.md](docs/plans/pota-rove-interface.md)

---

## Step 1: `RoveStop` Model + Schema Registration

**New file:** `CarrierWave/Models/RoveStop.swift` (~60 lines)

Create a `@Model` class for rove stops. JSON-codable so it can be stored as
`Data` on `LoggingSession` (avoids a SwiftData relationship, which would require
schema migration and adds complexity for an ordered list).

```swift
struct RoveStop: Codable, Identifiable {
    var id: UUID = UUID()
    var parkReference: String        // "US-1234" or "US-1234, US-5678" for n-fer
    var startedAt: Date
    var endedAt: Date?
    var myGrid: String?
    var qsoCount: Int = 0
    var notes: String?
}
```

**Why a `Codable` struct stored as `Data`** rather than a separate `@Model`:
- Rove stops are always loaded/saved with their parent session — never queried independently
- Ordered lists in SwiftData require manual sort-order management; JSON preserves insertion order
- No schema migration needed; the field is just a new optional `Data?` column
- Follows the same pattern as `spotCommentsData` on `LoggingSession`

**Edit:** `CarrierWave/Models/LoggingSession.swift`

Add three stored properties:
```swift
var isRove: Bool = false
var roveStopsData: Data?           // JSON-encoded [RoveStop]
```

Add computed accessor (same pattern as `spotComments`):
```swift
var roveStops: [RoveStop] {
    get { /* decode from roveStopsData */ }
    set { /* encode to roveStopsData */ }
}

var currentRoveStop: RoveStop? {
    roveStops.last(where: { $0.endedAt == nil }) ?? roveStops.last
}

var roveStopCount: Int { roveStops.count }
```

**Edit:** `CarrierWave/Models/LoggingSession+Frequencies.swift`

Update `defaultTitle` for rove sessions:
```swift
case .pota:
    if isRove {
        let count = roveStopCount
        if let park = parkReference {
            return "\(myCallsign) Rove (\(count) parks)"
        }
        return "\(myCallsign) POTA Rove"
    }
    // existing park title logic...
```

**No changes to `CarrierWaveApp.swift`** — no new `@Model` classes.

**Update:** `docs/FILE_INDEX.md` — add `RoveStop.swift` entry.

---

## Step 2: `LoggingSessionManager` Rove Lifecycle Methods

**Edit:** `CarrierWave/Services/LoggingSessionManager.swift`

### 2a: Extend `startSession()` signature

Add `isRove: Bool = false` parameter. When `true` and `activationType == .pota`:
- Set `session.isRove = true`
- Create the first `RoveStop` with the provided `parkReference` and `startedAt: Date()`
- Encode into `roveStopsData`

### 2b: Add `nextRoveStop()` method (~50 lines)

```swift
func nextRoveStop(
    parkReference: String,
    myGrid: String?,
    postQRTSpot: Bool,
    autoSpotNewPark: Bool
) {
```

Logic:
1. Guard `activeSession?.isRove == true`
2. Close current stop: set `endedAt = Date()`, snapshot `qsoCount` from session QSOs
   with matching park ref
3. Optionally fire QRT spot for old park (reuse `postQRTSpotIfNeeded`)
4. Create new `RoveStop(parkReference:, startedAt: Date(), myGrid:)`
5. Append to `roveStops` array and re-encode
6. Update `session.parkReference` to the new park reference
7. Update `session.myGrid` if grid changed
8. Restart spot comments polling with new park reference (existing
   `startSpotCommentsPolling()` already reads `session.parkReference`)
9. Optionally fire initial spot for new park (existing `postSpot()`)
10. Save context

### 2c: Adjust `endSession()` for roves

Before ending, close the current rove stop (set `endedAt`, snapshot `qsoCount`).
The rest of `endSession()` works as-is.

### 2d: Adjust `logQSO()` for roves

After `session.incrementQSOCount()`, also increment the current rove stop's
`qsoCount` in the JSON array and re-encode. This keeps per-stop counts accurate
for the rove bar without needing to query QSOs per park.

---

## Step 3: Session Start Sheet — Rove Toggle

**Edit:** `CarrierWave/Views/Logger/SessionStartHelperViews.swift`

In `ActivationSectionView`, add a `@Binding var isRove: Bool` parameter. Below
the `ParkEntryField` (only when `activationType == .pota`), add:

```swift
Toggle(isOn: $isRove) {
    VStack(alignment: .leading, spacing: 2) {
        Text("This is a rove")
            .font(.subheadline.weight(.medium))
        Text("Visit multiple parks in one session")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
```

**Edit:** `CarrierWave/Views/Logger/SessionStartSheet.swift`

- Add `@State var isRove = false` state
- Pass `isRove: $isRove` to `ActivationSectionView`
- In `startSession()`, pass `isRove: isRove` to `sessionManager?.startSession()`

**Edit:** `CarrierWave/Views/Logger/SessionStartSheet+Sections.swift`

Update `activationSection` to pass the new binding.

---

## Step 4: "Next Stop" Sheet

**New file:** `CarrierWave/Views/Logger/NextRoveStopSheet.swift` (~120 lines)

A half-sheet (`.presentationDetents([.medium])`) with:
- `ParkEntryField` for the new park
- Text field for grid (pre-filled from GPS via `GridLocationService`)
- Toggle: "Post QRT spot for [current park]" (default: on, reads `potaQRTSpotEnabled`)
- Toggle: "Auto-spot at new park" (default: on, reads `potaAutoSpotEnabled`)
- Warning banner if entered park was already visited (check `roveStops`)
- "Start Stop" button (`.borderedProminent`, `.tint(.green)`)
- Divider + "Finish Rove" button (`.bordered`, calls `sessionManager?.endSession()`)

Validation: park reference must be non-empty and valid per `ParkReference.isValid`.

On "Start Stop": calls `sessionManager?.nextRoveStop(...)`, dismisses sheet.

**Update:** `docs/FILE_INDEX.md` — add entry.

---

## Step 5: Rove Bar in Session Header

**New file:** `CarrierWave/Views/Logger/RoveProgressBar.swift` (~100 lines)

A horizontally scrolling bar showing all stops as capsules:

```swift
struct RoveProgressBar: View {
    let stops: [RoveStop]
    let currentStopId: UUID?
    let onNextStop: () -> Void
    let onTapStop: (RoveStop) -> Void
```

Components:
- Header: "Rove: Stop N of M · X QSOs total" (`.caption`, `.secondary`)
- `ScrollView(.horizontal)` with `HStack(spacing: 8)`:
  - Each stop is a capsule showing park ref (`.caption.monospaced()`) + QSO count
  - Current stop: green background, bold, filled circle indicator
  - Past stops: `Color(.systemGray5)` background, muted text
  - Tapping a past stop calls `onTapStop` (shows popover with park name, time range)
- "Next Stop" button: trailing, `.bordered`, `.tint(.green)`, arrow.right icon

**Edit:** `CarrierWave/Views/Logger/LoggerView.swift`

In `activeSessionHeader(_:)` (~line 1336 area), replace/augment the
`parkHeaderView` call:

```swift
if session.isRove {
    RoveProgressBar(
        stops: session.roveStops,
        currentStopId: session.currentRoveStop?.id,
        onNextStop: { showNextStopSheet = true },
        onTapStop: { stop in selectedRoveStop = stop }
    )
} else if session.activationType == .pota {
    parkHeaderView(session)
}
```

Add state variables:
```swift
@State private var showNextStopSheet = false
@State private var selectedRoveStop: RoveStop?
```

Add sheet presentation:
```swift
.sheet(isPresented: $showNextStopSheet) {
    NextRoveStopSheet(sessionManager: sessionManager, onDismiss: { ... })
        .presentationDetents([.medium])
}
.popover(item: $selectedRoveStop) { stop in
    RoveStopPopover(stop: stop)  // inline, ~30 lines
}
```

**Update:** `docs/FILE_INDEX.md` — add entry.

---

## Step 6: POTA Command Integration

**Edit:** `CarrierWave/Views/Logger/LoggerView.swift`

In `executeSheetCommand(_:)` (~line 1816), change the `.pota` case:

```swift
case .pota:
    if sessionManager?.activeSession?.isRove == true {
        showNextStopSheet = true
    } else {
        showPOTAPanel = true
    }
```

This means during a rove, typing `POTA` opens the "Next Stop" sheet instead of
the spots panel. The spots panel is still accessible via the spot summary or the
RBN panel.

---

## Step 7: Spotting Integration on Stop Change

**Edit:** `CarrierWave/Services/LoggingSessionManager+Spotting.swift`

No new methods needed — `nextRoveStop()` (Step 2b) calls the existing:
- `postQRTSpotIfNeeded(for:)` — works because it reads `session.parkReference`
  (which still holds the *old* park at call time)
- `postSpot()` — works because it reads `session.parkReference` (which is updated
  to the *new* park before this call)
- `startSpotCommentsPolling()` — restarts polling for the new park

Ensure `nextRoveStop()` calls these in the right order:
1. Fire QRT for old park (capture old parkRef first)
2. Update `session.parkReference` to new park
3. Fire initial spot for new park
4. Restart spot comments polling

---

## Step 8: Sessions List — Rove Row

**Edit:** `CarrierWave/Views/Sessions/SessionRow.swift`

In `headerRow`, when `session.isRove`:
- Replace the single park reference with a compact rove summary
- Show "N parks" count + arrow-separated park list (truncated to ~3 with "+ N more")

```swift
if session.isRove {
    let stops = session.roveStops
    let parkRefs = stops.map { ParkReference.split($0.parkReference).first ?? $0.parkReference }
    let display = parkRefs.prefix(3).joined(separator: " → ")
    let suffix = parkRefs.count > 3 ? " + \(parkRefs.count - 3) more" : ""
    Text(display + suffix)
        .font(.caption.monospaced())
        .foregroundStyle(.green)
}
```

---

## Step 9: Session Detail — Rove Timeline

**Edit:** `CarrierWave/Views/Sessions/SessionDetailView.swift`

In `infoSection`, when `session.isRove`, replace the single "Reference" row with
a rove timeline section:

```swift
if session.isRove {
    Section("Rove Stops") {
        ForEach(session.roveStops) { stop in
            RoveStopRow(stop: stop)
        }
    }
}
```

**Add** `RoveStopRow` as a private subview (~30 lines) within `SessionDetailView`
or as a small standalone view:
- Circle indicator (filled green for current, outlined for completed)
- Park reference (monospaced, green) + resolved park name
- Time range (HH:mm–HH:mm UTC) + QSO count
- Grid square if available
- Vertical connecting line between rows (using overlay or GeometryReader)

---

## Step 10: Tests

**New file:** `CarrierWaveTests/RoveStopTests.swift` (~80 lines)

Test `RoveStop` codable round-trip and `LoggingSession` rove accessors:
- `testRoveStopEncodeDecode` — encode/decode preserves all fields
- `testCurrentRoveStop` — returns the open stop (no endedAt)
- `testRoveStopCount` — correct count after appending stops
- `testRoveStopsEmptyByDefault` — nil data returns empty array

**New file:** `CarrierWaveTests/LoggingSessionRoveTests.swift` (~100 lines)

Test `LoggingSessionManager` rove lifecycle using in-memory SwiftData:
- `testStartRoveSession` — creates session with `isRove=true` and first stop
- `testNextRoveStop` — closes current stop, creates new one, updates parkReference
- `testRoveQSOCountTracking` — per-stop QSO counts increment correctly
- `testEndRoveSession` — closes current stop before ending session
- `testDefaultTitleForRove` — title shows "Rove (N parks)"

---

## Step 11: Changelog + File Index

**Edit:** `CHANGELOG.md` — add under `### Added`:
```
- POTA rove mode: activate multiple parks in a single session with "Next Stop" transitions
```

**Edit:** `docs/FILE_INDEX.md` — add entries for:
- `CarrierWave/Models/RoveStop.swift`
- `CarrierWave/Views/Logger/NextRoveStopSheet.swift`
- `CarrierWave/Views/Logger/RoveProgressBar.swift`

---

## Step 12: Format, Lint, Build

Run `xc quality` (format → lint → build) to verify everything compiles and passes
lint. Run `xc test-unit` to verify new and existing tests pass.

---

## Files Changed Summary

| Action | File | Lines |
|--------|------|-------|
| **New** | `Models/RoveStop.swift` | ~60 |
| **New** | `Views/Logger/NextRoveStopSheet.swift` | ~120 |
| **New** | `Views/Logger/RoveProgressBar.swift` | ~100 |
| **New** | `Tests/RoveStopTests.swift` | ~80 |
| **New** | `Tests/LoggingSessionRoveTests.swift` | ~100 |
| Edit | `Models/LoggingSession.swift` | +15 |
| Edit | `Models/LoggingSession+Frequencies.swift` | +10 |
| Edit | `Services/LoggingSessionManager.swift` | +60 |
| Edit | `Views/Logger/SessionStartSheet.swift` | +5 |
| Edit | `Views/Logger/SessionStartSheet+Sections.swift` | +2 |
| Edit | `Views/Logger/SessionStartHelperViews.swift` | +15 |
| Edit | `Views/Logger/LoggerView.swift` | +20 |
| Edit | `Views/Sessions/SessionRow.swift` | +15 |
| Edit | `Views/Sessions/SessionDetailView.swift` | +30 |
| Edit | `CHANGELOG.md` | +1 |
| Edit | `docs/FILE_INDEX.md` | +3 |

**Total:** 5 new files (~460 lines), 11 edited files (~175 lines added)

---

## Deferred (Phase 4 polish, not in this plan)

- MAP command showing route between stops with geodesic arcs
- GPS auto-grid update via `GridLocationService` on stop change
- Rove-specific share card with route map
- Rove statistics (parks/hour, total distance, longest gap)
- "Part of rove" badge in POTA Activations view
