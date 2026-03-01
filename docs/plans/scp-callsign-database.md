# Super Check Partial (SCP) Callsign Database

## Overview

Integrate the MASTER.SCP callsign database from supercheckpartial.com into Carrier Wave. Provides real-time callsign suggestions as the user types, confidence indicators for entered callsigns, and "did you mean?" typo correction — all offline, from a lightweight cached file.

## Data Characteristics

- **Source:** `http://www.supercheckpartial.com/MASTER.SCP`
- **Format:** Plain text, one uppercase callsign per line, no header
- **Size:** ~50-87K callsigns, ~350-700KB on disk
- **Updates:** ~twice/year (January, October). We'll check weekly.
- **In memory:** `Set<String>` for exact match, sorted `[String]` for partial search. ~2MB RAM.

---

## Step 1: SCPDatabase (CarrierWaveCore)

**New file:** `CarrierWaveCore/Sources/CarrierWaveCore/SCPDatabase.swift`

Pure-logic type, fully testable without iOS. Holds the in-memory callsign set and provides all query methods.

```swift
public struct SCPDatabase: Sendable {
    private let callsigns: Set<String>      // exact lookup O(1)
    private let sorted: [String]            // prefix/substring search

    public init(callsigns: [String])        // dedupes, uppercases, sorts

    /// Classic SCP: all callsigns containing the fragment (case-insensitive).
    /// Returns up to `limit` matches, sorted alphabetically.
    public func partialMatch(_ fragment: String, limit: Int = 20) -> [String]

    /// Is this exact callsign in the database?
    public func contains(_ callsign: String) -> Bool

    /// Near-misses within edit distance. Delegates to CallsignEditDistance.
    /// Only called for complete callsigns (4+ chars), not during typing.
    public func nearMatches(for callsign: String, maxDistance: Int = 1) -> [(callsign: String, distance: Int)]

    public var count: Int
    public var isEmpty: Bool
}
```

**Matching strategy for `partialMatch`:**
- Fragment ≤2 chars → return empty (too broad)
- Fragment 3+ chars → `sorted.filter { $0.contains(fragment) }`, capped at `limit`
- ~80K short strings, substring check is <10ms on-device — no exotic indexing needed

**Tests:** `CarrierWaveCore/Tests/CarrierWaveCoreTests/SCPDatabaseTests.swift`
- `partialMatch` returns correct subsets
- `contains` exact match (case-insensitive)
- `nearMatches` finds edit-distance-1 candidates
- Empty database returns empty results
- Fragment too short returns empty

---

## Step 2: SCPService (CarrierWave/Services)

**New file:** `CarrierWave/Services/SCPService.swift`

`@MainActor` observable service that manages download, cache, and exposes the database for SwiftUI binding. Singleton pattern like other app services.

```swift
@MainActor
@Observable
final class SCPService {
    static let shared = SCPService()

    private(set) var database: SCPDatabase = SCPDatabase(callsigns: [])
    private(set) var lastUpdated: Date?
    private(set) var isLoading = false

    /// Load from disk cache, then check for remote update if stale.
    func loadAndRefresh() async

    /// Force re-download from remote.
    func forceRefresh() async
}
```

**Cache strategy:**
- File stored at: `Library/Caches/MASTER.SCP`
- ETag stored in `UserDefaults` key `scpETag`
- `lastUpdated` stored in `UserDefaults` key `scpLastUpdated`
- On `loadAndRefresh()`:
  1. Load from disk if file exists → populate `database` immediately (fast startup)
  2. If last check was >7 days ago, fetch remote with `If-None-Match` header
  3. If 304 Not Modified → update timestamp only
  4. If 200 → write to disk, update ETag + timestamp, rebuild `database`
- Network errors are silent — stale cache is fine, the data changes rarely

**Parsing:**
- Split response by newlines, filter empty lines, uppercase, pass to `SCPDatabase(callsigns:)`

**Lifecycle:**
- Called from app startup (`.task` on root view or `AppDelegate`)
- Non-blocking — UI works fine without SCP data, it just won't show suggestions until loaded

---

## Step 3: Logger Integration

### State additions in `LoggerView.swift`

```swift
@State var scpSuggestions: [String] = []
```

### Triggering SCP lookup in `LoggerView+Data.swift`

Inside `onCallsignChanged(_:)`, after the existing early returns:

```swift
// SCP partial check — lightweight, no debounce needed
let fragment = callsign.trimmingCharacters(in: .whitespaces).uppercased()
if fragment.count >= 3, LoggerCommand.parse(callsign) == nil {
    scpSuggestions = SCPService.shared.database.partialMatch(fragment)
} else {
    scpSuggestions = []
}
```

This runs synchronously on main thread (<10ms) so no Task/debounce needed — unlike the QRZ lookup which is network-bound.

### Confidence indicator in `LoggerView+FormFields.swift`

When callsign is 4+ characters and SCP is loaded:
- Callsign IS in SCP → subtle checkmark or green tint on the input field border
- Callsign is NOT in SCP → subtle amber indicator (not blocking — could be a new ham)
- SCP not loaded → no indicator

This is a small visual addition, not a separate view. Add to the existing `.overlay()` on the callsign input `HStack`.

### "Did you mean?" on submit

In `logQSO()` (LoggerView+QSOLogging.swift), before actually creating the QSO:
- If callsign is NOT in SCP and `nearMatches(maxDistance: 1)` returns results → show a brief confirmation: "Not found in SCP. Did you mean W6JSV?" with Continue / Fix options
- If callsign IS in SCP → log immediately, no interruption
- This is opt-in behavior (gated behind a setting, default ON)

---

## Step 4: SCP Suggestions View

**New file:** `CarrierWave/Views/Logger/SCPSuggestionsView.swift`

Minimal horizontal scrolling chip bar, shown between the callsign input field and the form fields when `!scpSuggestions.isEmpty && callsignFieldFocused`.

```
┌─────────────────────────────────────────┐
│ [Callsign input field]           [LOG]  │
├─────────────────────────────────────────┤
│ W6JSV  W6JTI  W6JZH  W6JBR  W6JKV  →  │  ← horizontal scroll chips
├─────────────────────────────────────────┤
│ RST: 599    Grid: ____    State: __     │
```

**Behavior:**
- Tap a chip → fills callsign input field, dismisses suggestions
- Chips use monospaced font, `Color(.systemGray5)` background, rounded corners (design language)
- Scrollable horizontally, max ~20 items
- Animate in/out with `.transition(.move(edge: .top).combined(with: .opacity))`
- Hidden when `scpSuggestions` is empty or field not focused

**Size budget:** <80 lines for this view.

---

## Step 5: Settings Toggle

Add a toggle in Settings under a "Logger" or "Assistance" section:

```swift
@AppStorage("scpEnabled") var scpEnabled = true
```

- "Super Check Partial" toggle — enables/disables SCP suggestions + confidence indicator
- Below the toggle: last updated date, callsign count, "Update Now" button
- When disabled, `onCallsignChanged` skips SCP lookup entirely

---

## File Summary

| File | Type | Lines (est.) |
|------|------|-------------|
| `CarrierWaveCore/.../SCPDatabase.swift` | New | ~80 |
| `CarrierWaveCore/.../SCPDatabaseTests.swift` | New | ~80 |
| `CarrierWave/Services/SCPService.swift` | New | ~120 |
| `CarrierWave/Views/Logger/SCPSuggestionsView.swift` | New | ~70 |
| `CarrierWave/Views/Logger/LoggerView.swift` | Edit | +3 lines (state) |
| `CarrierWave/Views/Logger/LoggerView+Data.swift` | Edit | +8 lines (SCP lookup in onCallsignChanged) |
| `CarrierWave/Views/Logger/LoggerView+FormFields.swift` | Edit | +15 lines (confidence overlay, suggestions slot) |
| `CarrierWave/Views/Logger/LoggerView+QSOLogging.swift` | Edit | +20 lines (did-you-mean on submit) |
| `CarrierWave/Views/Settings/*` | Edit | +15 lines (toggle + info) |
| `docs/FILE_INDEX.md` | Edit | +4 lines |
| `CHANGELOG.md` | Edit | +1 line |

**Total:** 3 new files (~270 lines), 6 edited files (~65 lines added)

---

## Implementation Order

1. **SCPDatabase** + tests (CarrierWaveCore) — can be built and tested independently
2. **SCPService** — download, cache, parse
3. **Logger state + onCallsignChanged** — wire up SCP lookup
4. **SCPSuggestionsView** — chip bar UI
5. **Confidence indicator** — border tint on callsign input
6. **Did-you-mean** — submit-time check
7. **Settings toggle** — enable/disable + info display
8. **FILE_INDEX + CHANGELOG** — housekeeping

## Non-Goals (for now)

- CW decoder disambiguation (future — depends on decoder confidence API)
- Enriching SCP with QRZ data (callsign → name/location)
- Custom SCP files or user-contributed callsigns
- Watch app integration
