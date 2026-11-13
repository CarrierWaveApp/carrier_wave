# Force Re-download Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add per-service "Force Re-download All QSOs" buttons in debug mode that re-fetch and reprocess QSOs to repair data.

**Architecture:** Add a `reprocessQSOs()` method to SyncService+Process.swift that updates existing QSOs instead of skipping them. Add `forceRedownloadFrom*()` methods to SyncService+Download.swift. Add debug sections to each service settings view.

**Tech Stack:** SwiftUI, SwiftData, async/await

---

## Task 1: Add `updateExistingQSO()` Method to SyncService+Process.swift

**Files:**
- Modify: `CarrierWave/Services/SyncService+Process.swift`

**Step 1: Add the update method**

Add this method after `mergeIntoExisting()` (around line 95):

```swift
/// Update existing QSO with all fields from fetched data (for force re-download)
func updateExistingQSO(existing: QSO, from fetched: FetchedQSO) {
    existing.frequency = fetched.frequency
    existing.rstSent = fetched.rstSent
    existing.rstReceived = fetched.rstReceived
    existing.myGrid = fetched.myGrid
    existing.theirGrid = fetched.theirGrid
    existing.parkReference = fetched.parkReference
    existing.theirParkReference = fetched.theirParkReference
    existing.notes = fetched.notes
    existing.rawADIF = fetched.rawADIF
    existing.name = fetched.name
    existing.qth = fetched.qth
    existing.state = fetched.state
    existing.country = fetched.country
    existing.power = fetched.power
    existing.sotaRef = fetched.sotaRef

    // QRZ-specific
    if fetched.source == .qrz {
        existing.qrzLogId = fetched.qrzLogId
        existing.qrzConfirmed = fetched.qrzConfirmed
        existing.lotwConfirmedDate = fetched.lotwConfirmedDate
    }

    // LoTW-specific
    if fetched.source == .lotw {
        existing.lotwConfirmed = fetched.lotwConfirmed
        existing.lotwConfirmedDate = fetched.lotwConfirmedDate
        existing.dxcc = fetched.dxcc
    }

    existing.markPresent(in: fetched.source, context: modelContext)
}
```

**Step 2: Add the reprocess method**

Add this method after `updateExistingQSO()`:

```swift
/// Reprocess fetched QSOs, updating existing ones instead of skipping
func reprocessQSOs(_ fetched: [FetchedQSO]) throws -> (updated: Int, created: Int) {
    let debugLog = SyncDebugLog.shared
    debugLog.info("Reprocessing \(fetched.count) QSOs (force re-download)")

    let descriptor = FetchDescriptor<QSO>()
    let existingQSOs = try modelContext.fetch(descriptor)
    let existingByKey = Dictionary(grouping: existingQSOs) { $0.deduplicationKey }

    var updated = 0
    var created = 0

    for fetchedQSO in fetched {
        let key = fetchedQSO.deduplicationKey
        if let existing = existingByKey[key]?.first {
            updateExistingQSO(existing: existing, from: fetchedQSO)
            updated += 1
        } else {
            let newQSO = createQSO(from: fetchedQSO)
            modelContext.insert(newQSO)
            createPresenceForNewQSO(newQSO, source: fetchedQSO.source)
            created += 1
        }
    }

    try modelContext.save()
    debugLog.info("Reprocess complete: updated=\(updated), created=\(created)")
    return (updated, created)
}

/// Create presence records for a newly created QSO
private func createPresenceForNewQSO(_ qso: QSO, source: ServiceType) {
    for service in ServiceType.allCases {
        let presence: ServicePresence
        if service == source {
            presence = ServicePresence.downloaded(from: service, qso: qso)
        } else if service.supportsUpload {
            presence = ServicePresence.needsUpload(to: service, qso: qso)
        } else {
            presence = ServicePresence(serviceType: service, isPresent: false, qso: qso)
        }
        modelContext.insert(presence)
        qso.servicePresence.append(presence)
    }
}
```

**Step 3: Commit**

```bash
git add CarrierWave/Services/SyncService+Process.swift
git commit -m "feat: add reprocessQSOs method for force re-download"
```

---

## Task 2: Add Force Re-download Methods to SyncService+Download.swift

**Files:**
- Modify: `CarrierWave/Services/SyncService+Download.swift`

**Step 1: Add force re-download methods**

Add these public methods at the end of the file (before the closing `}`):

```swift
// MARK: - Force Re-download Methods

/// Force re-download all QSOs from QRZ and reprocess them
func forceRedownloadFromQRZ() async throws -> (updated: Int, created: Int) {
    let debugLog = SyncDebugLog.shared
    debugLog.info("Force re-downloading from QRZ", service: .qrz)

    let qsos = try await qrzClient.fetchQSOs(since: nil)
    let fetched = qsos.map { FetchedQSO.fromQRZ($0) }

    debugLog.info("Fetched \(fetched.count) QSOs from QRZ", service: .qrz)
    return try reprocessQSOs(fetched)
}

/// Force re-download all QSOs from POTA and reprocess them
func forceRedownloadFromPOTA() async throws -> (updated: Int, created: Int) {
    let debugLog = SyncDebugLog.shared
    debugLog.info("Force re-downloading from POTA", service: .pota)

    let qsos = try await potaClient.fetchAllQSOs()
    let fetched = qsos.map { FetchedQSO.fromPOTA($0) }

    debugLog.info("Fetched \(fetched.count) QSOs from POTA", service: .pota)
    return try reprocessQSOs(fetched)
}

/// Force re-download all QSOs from LoFi and reprocess them
func forceRedownloadFromLoFi() async throws -> (updated: Int, created: Int) {
    let debugLog = SyncDebugLog.shared
    debugLog.info("Force re-downloading from LoFi", service: .lofi)

    // Fetch ALL QSOs, not just since last sync
    let qsos = try await lofiClient.fetchAllQsos()
    let fetched = qsos.compactMap { FetchedQSO.fromLoFi($0.0, operation: $0.1) }

    debugLog.info("Fetched \(fetched.count) QSOs from LoFi", service: .lofi)
    return try reprocessQSOs(fetched)
}

/// Force re-download all QSOs from HAMRS and reprocess them
func forceRedownloadFromHAMRS() async throws -> (updated: Int, created: Int) {
    let debugLog = SyncDebugLog.shared
    debugLog.info("Force re-downloading from HAMRS", service: .hamrs)

    let qsos = try await hamrsClient.fetchAllQSOs()
    let fetched = qsos.compactMap { FetchedQSO.fromHAMRS($0.0, logbook: $0.1) }

    debugLog.info("Fetched \(fetched.count) QSOs from HAMRS", service: .hamrs)
    return try reprocessQSOs(fetched)
}

/// Force re-download all QSOs from LoTW and reprocess them
func forceRedownloadFromLoTW() async throws -> (updated: Int, created: Int) {
    let debugLog = SyncDebugLog.shared
    debugLog.info("Force re-downloading from LoTW", service: .lotw)

    // Fetch ALL QSOs (no qsoRxSince filter)
    let response = try await lotwClient.fetchQSOs(qsoRxSince: nil)
    let fetched = response.qsos.map { FetchedQSO.fromLoTW($0) }

    debugLog.info("Fetched \(fetched.count) QSOs from LoTW", service: .lotw)
    return try reprocessQSOs(fetched)
}
```

**Step 2: Check if LoFiClient has `fetchAllQsos()` method**

If `fetchAllQsos()` doesn't exist, we need to add it or use existing method with nil parameter. Check LoFiClient.swift first.

**Step 3: Commit**

```bash
git add CarrierWave/Services/SyncService+Download.swift
git commit -m "feat: add forceRedownloadFrom* methods for all services"
```

---

## Task 3: Add LoFiClient.fetchAllQsos() If Needed

**Files:**
- Modify: `CarrierWave/Services/LoFiClient.swift` (if needed)

**Step 1: Check existing methods**

Look for existing fetch method that can return all QSOs. If `fetchAllQsosSinceLastSync()` uses a stored timestamp, we need a variant that fetches everything.

**Step 2: Add method if needed**

```swift
/// Fetch ALL QSOs from LoFi (ignoring last sync timestamp)
func fetchAllQsos() async throws -> [(LoFiQso, LoFiOperation)] {
    // Implementation depends on existing code structure
    // May need to call API with sinceMillis: 0 or nil
}
```

**Step 3: Commit (if changes made)**

```bash
git add CarrierWave/Services/LoFiClient.swift
git commit -m "feat: add fetchAllQsos method to LoFiClient"
```

---

## Task 4: Add Debug Section to QRZ Settings View

**Files:**
- Modify: `CarrierWave/Views/Settings/ServiceSettingsViews.swift`

**Step 1: Add state and environment to QRZSettingsView**

Add these properties at the top of `QRZSettingsView` (after existing `@State` properties):

```swift
@AppStorage("debugMode") private var debugMode = false
@EnvironmentObject private var syncService: SyncService
@State private var isRedownloading = false
@State private var redownloadResult: String?
```

**Step 2: Add debug section to the List**

Add this section at the end of the `List` (before `.navigationTitle`):

```swift
if debugMode, isAuthenticated {
    Section {
        Button {
            Task { await forceRedownload() }
        } label: {
            if isRedownloading {
                HStack {
                    ProgressView()
                        .padding(.trailing, 4)
                    Text("Re-downloading...")
                }
            } else {
                Text("Force Re-download All QSOs")
            }
        }
        .disabled(isRedownloading)

        if let result = redownloadResult {
            Text(result)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    } header: {
        Text("Debug")
    } footer: {
        Text("Re-fetches all QSOs from QRZ and updates existing records with fresh parsed values.")
    }
}
```

**Step 3: Add the forceRedownload method**

Add this method to `QRZSettingsView`:

```swift
private func forceRedownload() async {
    isRedownloading = true
    redownloadResult = nil
    defer { isRedownloading = false }

    do {
        let result = try await syncService.forceRedownloadFromQRZ()
        redownloadResult = "Updated \(result.updated), Created \(result.created)"
    } catch {
        redownloadResult = "Error: \(error.localizedDescription)"
    }
}
```

**Step 4: Commit**

```bash
git add CarrierWave/Views/Settings/ServiceSettingsViews.swift
git commit -m "feat: add force re-download debug button to QRZ settings"
```

---

## Task 5: Add Debug Section to POTA Settings View

**Files:**
- Modify: `CarrierWave/Views/Settings/ServiceSettingsViews.swift`

**Step 1: Add state to POTASettingsView**

Add these properties to `POTASettingsView`:

```swift
@AppStorage("debugMode") private var debugMode = false
@EnvironmentObject private var syncService: SyncService
@State private var isRedownloading = false
@State private var redownloadResult: String?
```

**Step 2: Add debug section**

Add at the end of the `List` (similar pattern to QRZ):

```swift
if debugMode, potaAuth.isAuthenticated {
    Section {
        Button {
            Task { await forceRedownload() }
        } label: {
            if isRedownloading {
                HStack {
                    ProgressView()
                        .padding(.trailing, 4)
                    Text("Re-downloading...")
                }
            } else {
                Text("Force Re-download All QSOs")
            }
        }
        .disabled(isRedownloading)

        if let result = redownloadResult {
            Text(result)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    } header: {
        Text("Debug")
    } footer: {
        Text("Re-fetches all QSOs from POTA and updates existing records with fresh parsed values.")
    }
}
```

**Step 3: Add the forceRedownload method**

```swift
private func forceRedownload() async {
    isRedownloading = true
    redownloadResult = nil
    defer { isRedownloading = false }

    do {
        let result = try await syncService.forceRedownloadFromPOTA()
        redownloadResult = "Updated \(result.updated), Created \(result.created)"
    } catch {
        redownloadResult = "Error: \(error.localizedDescription)"
    }
}
```

**Step 4: Commit**

```bash
git add CarrierWave/Views/Settings/ServiceSettingsViews.swift
git commit -m "feat: add force re-download debug button to POTA settings"
```

---

## Task 6: Add Debug Section to LoFi Settings View

**Files:**
- Modify: `CarrierWave/Views/Settings/CloudSettingsViews.swift`

**Step 1: Add state to LoFiSettingsView**

Add these properties:

```swift
@AppStorage("debugMode") private var debugMode = false
@EnvironmentObject private var syncService: SyncService
@State private var isRedownloading = false
@State private var redownloadResult: String?
```

**Step 2: Add debug section**

Add at the end of the `List`:

```swift
if debugMode, isLinked {
    Section {
        Button {
            Task { await forceRedownload() }
        } label: {
            if isRedownloading {
                HStack {
                    ProgressView()
                        .padding(.trailing, 4)
                    Text("Re-downloading...")
                }
            } else {
                Text("Force Re-download All QSOs")
            }
        }
        .disabled(isRedownloading)

        if let result = redownloadResult {
            Text(result)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    } header: {
        Text("Debug")
    } footer: {
        Text("Re-fetches all QSOs from LoFi and updates existing records with fresh parsed values.")
    }
}
```

**Step 3: Add the forceRedownload method**

```swift
private func forceRedownload() async {
    isRedownloading = true
    redownloadResult = nil
    defer { isRedownloading = false }

    do {
        let result = try await syncService.forceRedownloadFromLoFi()
        redownloadResult = "Updated \(result.updated), Created \(result.created)"
    } catch {
        redownloadResult = "Error: \(error.localizedDescription)"
    }
}
```

**Step 4: Commit**

```bash
git add CarrierWave/Views/Settings/CloudSettingsViews.swift
git commit -m "feat: add force re-download debug button to LoFi settings"
```

---

## Task 7: Add Debug Section to HAMRS Settings View

**Files:**
- Modify: `CarrierWave/Views/Settings/HAMRSSettingsView.swift`

**Step 1: Add state**

Add these properties:

```swift
@AppStorage("debugMode") private var debugMode = false
@EnvironmentObject private var syncService: SyncService
@State private var isRedownloading = false
@State private var redownloadResult: String?
```

**Step 2: Add debug section**

Add at the end of the `List`:

```swift
if debugMode, isConfigured {
    Section {
        Button {
            Task { await forceRedownload() }
        } label: {
            if isRedownloading {
                HStack {
                    ProgressView()
                        .padding(.trailing, 4)
                    Text("Re-downloading...")
                }
            } else {
                Text("Force Re-download All QSOs")
            }
        }
        .disabled(isRedownloading)

        if let result = redownloadResult {
            Text(result)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    } header: {
        Text("Debug")
    } footer: {
        Text("Re-fetches all QSOs from HAMRS and updates existing records with fresh parsed values.")
    }
}
```

**Step 3: Add the forceRedownload method**

```swift
private func forceRedownload() async {
    isRedownloading = true
    redownloadResult = nil
    defer { isRedownloading = false }

    do {
        let result = try await syncService.forceRedownloadFromHAMRS()
        redownloadResult = "Updated \(result.updated), Created \(result.created)"
    } catch {
        redownloadResult = "Error: \(error.localizedDescription)"
    }
}
```

**Step 4: Commit**

```bash
git add CarrierWave/Views/Settings/HAMRSSettingsView.swift
git commit -m "feat: add force re-download debug button to HAMRS settings"
```

---

## Task 8: Add Debug Section to LoTW Settings View

**Files:**
- Modify: `CarrierWave/Views/Settings/LoTWSettingsView.swift`

**Step 1: Add state**

Add these properties:

```swift
@AppStorage("debugMode") private var debugMode = false
@EnvironmentObject private var syncService: SyncService
@State private var isRedownloading = false
@State private var redownloadResult: String?
```

**Step 2: Add debug section**

Add at the end of the `List`:

```swift
if debugMode, isAuthenticated {
    Section {
        Button {
            Task { await forceRedownload() }
        } label: {
            if isRedownloading {
                HStack {
                    ProgressView()
                        .padding(.trailing, 4)
                    Text("Re-downloading...")
                }
            } else {
                Text("Force Re-download All QSOs")
            }
        }
        .disabled(isRedownloading)

        if let result = redownloadResult {
            Text(result)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    } header: {
        Text("Debug")
    } footer: {
        Text("Re-fetches all QSOs from LoTW and updates existing records with fresh parsed values.")
    }
}
```

**Step 3: Add the forceRedownload method**

```swift
private func forceRedownload() async {
    isRedownloading = true
    redownloadResult = nil
    defer { isRedownloading = false }

    do {
        let result = try await syncService.forceRedownloadFromLoTW()
        redownloadResult = "Updated \(result.updated), Created \(result.created)"
    } catch {
        redownloadResult = "Error: \(error.localizedDescription)"
    }
}
```

**Step 4: Commit**

```bash
git add CarrierWave/Views/Settings/LoTWSettingsView.swift
git commit -m "feat: add force re-download debug button to LoTW settings"
```

---

## Task 9: Verify Build and Final Commit

**Step 1: Ask user to build**

Ask the user to run `make build` and report any errors.

**Step 2: Fix any issues**

Address any build errors reported.

**Step 3: Final commit and push**

```bash
git push
```
