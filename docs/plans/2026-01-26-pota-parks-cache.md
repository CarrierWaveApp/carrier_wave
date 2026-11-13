# POTA Parks Cache Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Download and cache POTA parks CSV to display park names wherever park references appear.

**Architecture:** File-based cache in Caches directory with metadata JSON tracking download timestamp. Actor-based singleton service for thread-safe access. Auto-refresh every 2 weeks.

**Tech Stack:** Swift actors, URLSession, FileManager, Codable for metadata

---

## Task 1: Create POTAParksCache Service

**Files:**
- Create: `CarrierWave/Services/POTAParksCache.swift`

**Step 1: Create the cache service with metadata struct and basic structure**

```swift
// POTA Parks Cache
//
// Downloads and caches park reference data from pota.app for
// displaying human-readable park names throughout the app.

import Foundation

// MARK: - POTAParksCacheMetadata

struct POTAParksCacheMetadata: Codable {
    let downloadedAt: Date
    let recordCount: Int
}

// MARK: - POTAParksCache

actor POTAParksCache {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = POTAParksCache()

    /// Get park name for a reference (e.g., "K-1234" -> "Yellowstone National Park")
    /// Returns nil if park not found or cache not loaded
    func name(for reference: String) -> String? {
        parks[reference.uppercased()]
    }

    /// Ensure cache is loaded, downloading if necessary
    func ensureLoaded() async {
        guard !isLoaded else { return }

        // Try to load from disk first
        if loadFromDisk() {
            isLoaded = true
            // Check if refresh needed in background
            Task {
                await refreshIfNeeded()
            }
            return
        }

        // No cache on disk, download
        do {
            try await downloadAndCache()
            isLoaded = true
        } catch {
            print("POTAParksCache: Failed to download parks: \(error)")
            isLoaded = true // Mark loaded to avoid repeated attempts
        }
    }

    /// Check if cache is stale and refresh if needed (non-blocking)
    func refreshIfNeeded() async {
        guard let metadata = loadMetadata() else {
            // No metadata, need to download
            try? await downloadAndCache()
            return
        }

        let twoWeeksAgo = Date().addingTimeInterval(-14 * 24 * 60 * 60)
        if metadata.downloadedAt < twoWeeksAgo {
            try? await downloadAndCache()
        }
    }

    /// Force refresh the cache, throwing on failure
    func forceRefresh() async throws {
        try await downloadAndCache()
    }

    /// Number of parks in cache (for display/debugging)
    var parkCount: Int {
        parks.count
    }

    /// Last download date (for display/debugging)
    func lastDownloadDate() -> Date? {
        loadMetadata()?.downloadedAt
    }

    // MARK: Private

    private static let csvURL = URL(string: "https://pota.app/all_parks_ext.csv")!
    private static let cacheFileName = "pota_parks.csv"
    private static let metadataFileName = "pota_parks_metadata.json"

    private var parks: [String: String] = [:] // reference -> name
    private var isLoaded = false

    private var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    private var cacheFileURL: URL {
        cacheDirectory.appendingPathComponent(Self.cacheFileName)
    }

    private var metadataFileURL: URL {
        cacheDirectory.appendingPathComponent(Self.metadataFileName)
    }

    private func loadFromDisk() -> Bool {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
            return false
        }

        do {
            let csvData = try String(contentsOf: cacheFileURL, encoding: .utf8)
            parks = parseCSV(csvData)
            return !parks.isEmpty
        } catch {
            print("POTAParksCache: Failed to load from disk: \(error)")
            return false
        }
    }

    private func loadMetadata() -> POTAParksCacheMetadata? {
        guard let data = try? Data(contentsOf: metadataFileURL) else {
            return nil
        }
        return try? JSONDecoder().decode(POTAParksCacheMetadata.self, from: data)
    }

    private func saveMetadata(recordCount: Int) {
        let metadata = POTAParksCacheMetadata(
            downloadedAt: Date(),
            recordCount: recordCount
        )
        if let data = try? JSONEncoder().encode(metadata) {
            try? data.write(to: metadataFileURL)
        }
    }

    private func downloadAndCache() async throws {
        let (data, response) = try await URLSession.shared.data(from: Self.csvURL)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw URLError(.badServerResponse)
        }

        guard let csvString = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        // Parse and store in memory
        let parsed = parseCSV(csvString)
        parks = parsed

        // Save to disk
        try csvString.write(to: cacheFileURL, atomically: true, encoding: .utf8)
        saveMetadata(recordCount: parsed.count)

        print("POTAParksCache: Downloaded \(parsed.count) parks")
    }

    private func parseCSV(_ csv: String) -> [String: String] {
        var result: [String: String] = [:]
        let lines = csv.components(separatedBy: .newlines)

        // Skip header row
        for line in lines.dropFirst() {
            guard !line.isEmpty else { continue }

            let fields = parseCSVLine(line)
            guard fields.count >= 2 else { continue }

            let reference = fields[0].uppercased()
            let name = fields[1]

            guard !reference.isEmpty, !name.isEmpty else { continue }
            result[reference] = name
        }

        return result
    }

    /// Parse a CSV line handling quoted fields
    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))

        return fields
    }
}
```

**Step 2: Verify file compiles**

Ask user to run: `make build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add CarrierWave/Services/POTAParksCache.swift
git commit -m "feat: add POTAParksCache service for park name lookups"
```

---

## Task 2: Initialize Cache on App Launch

**Files:**
- Modify: `CarrierWave/CarrierWaveApp.swift`

**Step 1: Add cache initialization in app body**

Find the `body` property and add a `.task` modifier to ContentView:

```swift
var body: some Scene {
    WindowGroup {
        ContentView()
            .task {
                await POTAParksCache.shared.ensureLoaded()
            }
            .onOpenURL { url in
                handleURL(url)
            }
    }
    .modelContainer(sharedModelContainer)
}
```

**Step 2: Verify file compiles**

Ask user to run: `make build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add CarrierWave/CarrierWaveApp.swift
git commit -m "feat: initialize POTA parks cache on app launch"
```

---

## Task 3: Add Park Names to POTA Activations View

**Files:**
- Modify: `CarrierWave/Views/POTAActivations/POTAActivationsView.swift`

**Step 1: Add state for cached park names**

Add a state variable after the existing `@State` declarations in `POTAActivationsContentView`:

```swift
@State private var cachedParkNames: [String: String] = [:]
```

**Step 2: Update parkName(for:) to use cache as fallback**

Replace the existing `parkName(for:)` function:

```swift
private func parkName(for reference: String) -> String? {
    // First try from fetched jobs (most accurate for user's parks)
    if let name = jobs.first(where: { $0.reference.uppercased() == reference.uppercased() })?.parkName {
        return name
    }
    // Fall back to cached park names
    return cachedParkNames[reference.uppercased()]
}
```

**Step 3: Load cached names on appear**

In the `.onAppear` modifier, add cache loading:

```swift
.onAppear {
    if isAuthenticated, potaClient != nil, jobs.isEmpty {
        Task { await refreshJobs() }
    }
    startMaintenanceTimer()
    // Load cached park names
    Task {
        await loadCachedParkNames()
    }
}
```

**Step 4: Add the loadCachedParkNames function**

Add this function in the private section:

```swift
private func loadCachedParkNames() async {
    await POTAParksCache.shared.ensureLoaded()
    // Pre-load names for all parks in our activations
    var names: [String: String] = [:]
    for activation in activations {
        let ref = activation.parkReference.uppercased()
        if let name = await POTAParksCache.shared.name(for: ref) {
            names[ref] = name
        }
    }
    await MainActor.run {
        cachedParkNames = names
    }
}
```

**Step 5: Verify file compiles**

Ask user to run: `make build`
Expected: Build succeeds

**Step 6: Commit**

```bash
git add CarrierWave/Views/POTAActivations/POTAActivationsView.swift
git commit -m "feat: show park names in POTA activations view from cache"
```

---

## Task 4: Add Park Names to Dashboard Stats

**Files:**
- Modify: `CarrierWave/Views/Dashboard/DashboardHelperViews.swift`

**Step 1: Update groupedByPark() to include park names in description**

The `groupedByPark()` function in `QSOStatistics` needs to look up park names. Since this is a synchronous context, we need a different approach. Add a static helper and update the function.

First, add this extension at the bottom of the file:

```swift
// MARK: - Park Name Lookup Helper

extension QSOStatistics {
    /// Synchronous park name lookup (returns nil if cache not ready)
    /// Use this only when async lookup is not possible
    static func parkNameSync(for reference: String) -> String? {
        // This is a workaround for synchronous contexts
        // The cache should already be loaded by app launch
        var result: String?
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            result = await POTAParksCache.shared.name(for: reference)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 0.1)
        return result
    }
}
```

**Step 2: Update the groupedByPark function**

Replace the return statement in `groupedByPark()` to include park names:

```swift
private func groupedByPark() -> [StatCategoryItem] {
    // Filter to QSOs with park references, excluding metadata modes
    let parksOnly = qsos.filter {
        $0.parkReference != nil && !$0.parkReference!.isEmpty
            && !Self.metadataModes.contains($0.mode.uppercased())
    }
    // Group by park + UTC date (each UTC day at a park is a separate activation)
    let grouped = Dictionary(grouping: parksOnly) { qso in
        "\(qso.parkReference!)|\(qso.utcDateOnly.timeIntervalSince1970)"
    }
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .medium
    dateFormatter.timeStyle = .none
    dateFormatter.timeZone = TimeZone(identifier: "UTC")
    return grouped.map { _, qsos in
        let park = qsos.first?.parkReference ?? "Unknown"
        let date = qsos.first?.utcDateOnly ?? Date()
        let status = qsos.count >= 10 ? "Valid" : "\(qsos.count)/10 QSOs"
        let parkName = Self.parkNameSync(for: park)
        let description = parkName.map { "\($0) - \(status)" } ?? status
        return StatCategoryItem(
            identifier: "\(park) - \(dateFormatter.string(from: date))",
            description: description,
            qsos: qsos,
            date: date
        )
    }
}
```

**Step 3: Verify file compiles**

Ask user to run: `make build`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add CarrierWave/Views/Dashboard/DashboardHelperViews.swift
git commit -m "feat: show park names in dashboard stats drilldown"
```

---

## Task 5: Add Park Names to QSO Log List

**Files:**
- Modify: `CarrierWave/Views/Logs/LogsListView.swift`

**Step 1: Add state for park name in QSORow**

Update `QSORow` to look up and display park names. Add a state variable:

```swift
struct QSORow: View {
    // MARK: Internal

    let qso: QSO
    let serviceConfig: ServiceConfiguration

    @State private var parkName: String?
```

**Step 2: Update the park reference display**

In the `body` of `QSORow`, update the park label to show the name:

```swift
if let park = qso.parkReference {
    if let name = parkName {
        Label("\(park) - \(name)", systemImage: "tree")
            .foregroundStyle(.green)
    } else {
        Label(park, systemImage: "tree")
            .foregroundStyle(.green)
    }
}
```

**Step 3: Add task to load park name**

Add a `.task` modifier after the `.padding(.vertical, 4)`:

```swift
.padding(.vertical, 4)
.task {
    if let park = qso.parkReference {
        parkName = await POTAParksCache.shared.name(for: park)
    }
}
```

**Step 4: Verify file compiles**

Ask user to run: `make build`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add CarrierWave/Views/Logs/LogsListView.swift
git commit -m "feat: show park names in QSO log list"
```

---

## Task 6: Update CLAUDE.md File Index

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Add POTAParksCache to the Services table**

Find the Services table in CLAUDE.md and add a new row after `POTAClient+GridLookup.swift`:

```markdown
| `POTAParksCache.swift` | POTA park reference to name lookup cache |
```

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add POTAParksCache to file index"
```

---

## Task 7: Final Verification

**Step 1: Run linting**

Ask user to run: `make lint`
Expected: No errors

**Step 2: Run build**

Ask user to run: `make build`
Expected: Build succeeds

**Step 3: Final commit if any fixes needed**

If lint/format changes were made:
```bash
git add -A
git commit -m "chore: fix lint issues"
```

---

## Summary

This plan creates:

1. **POTAParksCache** - Actor-based singleton that downloads/caches the POTA parks CSV
2. **App initialization** - Loads cache on app launch
3. **UI integration** - Shows park names in:
   - POTA Activations view (section headers, upload confirmations)
   - Dashboard stats drilldown
   - QSO log list

The cache auto-refreshes every 2 weeks and fails silently, falling back to just showing park codes.
