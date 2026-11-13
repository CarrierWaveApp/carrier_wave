# POTA Parks Cache Design

## Overview

Add a local cache of POTA park data from `https://pota.app/all_parks_ext.csv` to display human-readable park names wherever park references appear in the app.

## Decisions

- **Storage**: File-based cache in app's caches directory
- **Access**: Singleton service `POTAParksCache.shared`
- **Initial state**: Silent fallback to park codes until downloaded

## CSV Format

The POTA parks CSV contains ~15,000 parks with columns including:
- `reference` - Park code (e.g., "K-1234", "VE-0001")
- `name` - Park name (e.g., "Yellowstone National Park")
- `active` - Whether the park is active
- `entityId` - DXCC entity
- `locationDesc` - Location description (e.g., "US-WY")
- `latitude`, `longitude` - Coordinates

We only need `reference` and `name` for the initial implementation.

## Architecture

### POTAParksCache Service

Location: `CarrierWave/Services/POTAParksCache.swift`

```swift
actor POTAParksCache {
    static let shared = POTAParksCache()
    
    // In-memory lookup after parsing
    private var parks: [String: String] = [:]  // reference -> name
    private var isLoaded = false
    
    // Public API
    func name(for reference: String) async -> String?
    func ensureLoaded() async
    func refreshIfNeeded() async  // Checks 2-week staleness
    func forceRefresh() async throws
}
```

### File Storage

- **Cache file**: `<CachesDirectory>/pota_parks.csv`
- **Metadata**: `<CachesDirectory>/pota_parks_metadata.json` containing:
  ```json
  {
    "downloadedAt": "2026-01-26T12:00:00Z",
    "recordCount": 15234
  }
  ```

### Refresh Logic

1. On `ensureLoaded()`:
   - If cache file exists and metadata shows < 2 weeks old: parse and use
   - If cache file missing or stale: trigger background download
   - If download fails: use existing cache if available, else empty

2. On `refreshIfNeeded()`:
   - Check metadata timestamp
   - If >= 2 weeks old: download in background
   - Non-blocking, failures logged but not surfaced

3. On `forceRefresh()`:
   - Download regardless of age
   - Throws on failure (for manual refresh from settings)

### CSV Parsing

Simple line-by-line parsing:
1. Skip header row
2. Split each line by comma (handling quoted fields)
3. Extract `reference` (column 0) and `name` (column 1)
4. Build dictionary

### Integration Points

Update these locations to show park names:

1. **POTAActivationsView.swift** (~line 159)
   - Currently uses `parkName(for:)` from jobs
   - Add fallback to `POTAParksCache.shared.name(for:)`

2. **DashboardHelperViews.swift** - `groupedByPark()` (~line 123)
   - `StatCategoryItem` identifier shows park reference
   - Add name to description field

3. **LogsListView.swift** (if park references displayed)
   - Check if park reference shown, add name

4. **Any QSO detail views**
   - Add park name next to `parkReference` and `theirParkReference`

### Initialization

In `CarrierWaveApp.swift`, during app startup:
```swift
Task {
    await POTAParksCache.shared.ensureLoaded()
}
```

This loads/downloads parks data in background without blocking launch.

## File Updates to CLAUDE.md

Add to File Index under Services:
```
| `POTAParksCache.swift` | POTA park reference to name lookup cache |
```

## Error Handling

- Network failures: Log warning, continue with empty/stale cache
- Parse failures: Log error, treat as empty cache
- File system errors: Log error, use in-memory only for session

## Testing Notes

- Cache can be tested with in-memory storage by making storage injectable
- Mock the network layer for download tests
- Test stale detection with manipulated metadata timestamps
