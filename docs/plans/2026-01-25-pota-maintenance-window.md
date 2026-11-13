# POTA Maintenance Window Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Block all POTA API operations during 0000-0400 UTC maintenance window and clearly communicate this to users.

**Architecture:** Add a static maintenance window check to POTAClient, skip POTA operations in SyncService when in window, and show status via existing sync result strings plus a persistent card indicator.

**Tech Stack:** Swift, SwiftUI, SwiftData

---

## Task 1: Add Maintenance Window Detection to POTAClient

**Files:**
- Modify: `CarrierWave/Services/POTAClient.swift`

**Step 1: Add maintenanceWindow error case**

In `POTAClient.swift`, add the new case to the `POTAError` enum (after `case networkError(Error)`):

```swift
case maintenanceWindow
```

**Step 2: Add error description for maintenanceWindow**

In the `errorDescription` computed property, add the case (before the closing brace):

```swift
case .maintenanceWindow:
    "POTA is in maintenance (0000-0400 UTC)"
```

**Step 3: Add isInMaintenanceWindow function**

Add this static function to the `POTAClient` actor (after the `authService` property, before `groupQSOsByPark`):

```swift
/// Check if current time is within POTA maintenance window (0000-0400 UTC daily)
static func isInMaintenanceWindow(at date: Date = Date()) -> Bool {
    let calendar = Calendar(identifier: .gregorian)
    guard let utc = TimeZone(identifier: "UTC") else { return false }
    let hour = calendar.dateComponents(in: utc, from: date).hour ?? 0
    return hour >= 0 && hour < 4
}
```

**Step 4: Commit**

```bash
git add CarrierWave/Services/POTAClient.swift
git commit -m "feat: add POTA maintenance window detection (0000-0400 UTC)"
```

---

## Task 2: Add Maintenance Skip Tracking to SyncResult

**Files:**
- Modify: `CarrierWave/Services/SyncService.swift`

**Step 1: Add potaMaintenanceSkipped to SyncResult**

In the `SyncResult` struct, add a new property after `mergedQSOs`:

```swift
var potaMaintenanceSkipped: Bool
```

**Step 2: Update SyncResult initialization in syncAll**

In the `syncAll()` method, update the `SyncResult` initialization to include the new field:

```swift
var result = SyncResult(
    downloaded: [:], uploaded: [:], errors: [], newQSOs: 0, mergedQSOs: 0,
    potaMaintenanceSkipped: false
)
```

**Step 3: Update SyncResult initialization in downloadOnly**

In the `downloadOnly()` method, update the `SyncResult` initialization:

```swift
var result = SyncResult(
    downloaded: [:], uploaded: [:], errors: [], newQSOs: 0, mergedQSOs: 0,
    potaMaintenanceSkipped: false
)
```

**Step 4: Commit**

```bash
git add CarrierWave/Services/SyncService.swift
git commit -m "feat: add potaMaintenanceSkipped to SyncResult"
```

---

## Task 3: Skip POTA Downloads During Maintenance Window

**Files:**
- Modify: `CarrierWave/Services/SyncService+Download.swift`

**Step 1: Add maintenance window check in downloadFromAllSources**

In the `downloadFromAllSources()` method, modify the POTA download block. Change:

```swift
// POTA download
if potaAuthService.isAuthenticated {
    group.addTask {
        await self.downloadFromPOTA(timeout: timeout)
    }
}
```

To:

```swift
// POTA download (skip during maintenance window)
if potaAuthService.isAuthenticated, !POTAClient.isInMaintenanceWindow() {
    group.addTask {
        await self.downloadFromPOTA(timeout: timeout)
    }
}
```

**Step 2: Commit**

```bash
git add CarrierWave/Services/SyncService+Download.swift
git commit -m "feat: skip POTA downloads during maintenance window"
```

---

## Task 4: Skip POTA Uploads During Maintenance Window and Track Skip

**Files:**
- Modify: `CarrierWave/Services/SyncService+Upload.swift`

**Step 1: Change uploadToAllDestinations to return maintenance skip status**

Change the method signature from:

```swift
func uploadToAllDestinations() async -> [ServiceType: Result<Int, Error>]
```

To:

```swift
func uploadToAllDestinations() async -> (results: [ServiceType: Result<Int, Error>], potaMaintenanceSkipped: Bool)
```

**Step 2: Add maintenance window check and tracking**

At the start of the method, add tracking variable:

```swift
func uploadToAllDestinations() async -> (results: [ServiceType: Result<Int, Error>], potaMaintenanceSkipped: Bool) {
    let qsosNeedingUpload = try? fetchQSOsNeedingUpload()
    let timeout = syncTimeoutSeconds
    var potaMaintenanceSkipped = false

    let results = await withTaskGroup(of: (ServiceType, Result<Int, Error>).self) { group in
```

**Step 3: Modify POTA upload block to check maintenance window**

Change the POTA upload block from:

```swift
// POTA upload
if potaAuthService.isAuthenticated {
    let potaQSOs = qsosNeedingUpload?.filter {
        $0.needsUpload(to: .pota) && $0.parkReference?.isEmpty == false
    } ?? []
    if !potaQSOs.isEmpty {
        group.addTask {
            await self.uploadPOTABatch(qsos: potaQSOs, timeout: timeout)
        }
    }
}
```

To:

```swift
// POTA upload (skip during maintenance window)
if potaAuthService.isAuthenticated {
    if POTAClient.isInMaintenanceWindow() {
        potaMaintenanceSkipped = true
    } else {
        let potaQSOs = qsosNeedingUpload?.filter {
            $0.needsUpload(to: .pota) && $0.parkReference?.isEmpty == false
        } ?? []
        if !potaQSOs.isEmpty {
            group.addTask {
                await self.uploadPOTABatch(qsos: potaQSOs, timeout: timeout)
            }
        }
    }
}
```

**Step 4: Update return statement**

Change the end of the method from:

```swift
        var results: [ServiceType: Result<Int, Error>] = [:]
        for await (service, result) in group {
            results[service] = result
        }
        return results
    }
}
```

To:

```swift
        var results: [ServiceType: Result<Int, Error>] = [:]
        for await (service, result) in group {
            results[service] = result
        }
        return results
    }

    return (results: results, potaMaintenanceSkipped: potaMaintenanceSkipped)
}
```

**Step 5: Commit**

```bash
git add CarrierWave/Services/SyncService+Upload.swift
git commit -m "feat: skip POTA uploads during maintenance window and track skip"
```

---

## Task 5: Update SyncService to Use New Upload Return Type

**Files:**
- Modify: `CarrierWave/Services/SyncService.swift`

**Step 1: Update performUploadsIfEnabled to handle new return type**

Change the `performUploadsIfEnabled` method signature and implementation. Replace:

```swift
private func performUploadsIfEnabled(
    into result: inout SyncResult,
    debugLog: SyncDebugLog
) async {
    if isReadOnlyMode {
        debugLog.info("Read-only mode enabled, skipping uploads")
        return
    }

    let uploadResults = await uploadToAllDestinations()
    for (service, uploadResult) in uploadResults {
        switch uploadResult {
        case let .success(count):
            result.uploaded[service] = count
        case let .failure(error):
            result.errors.append(
                "\(service.displayName) upload: \(error.localizedDescription)")
        }
    }
}
```

With:

```swift
private func performUploadsIfEnabled(
    into result: inout SyncResult,
    debugLog: SyncDebugLog
) async {
    if isReadOnlyMode {
        debugLog.info("Read-only mode enabled, skipping uploads")
        return
    }

    let (uploadResults, potaSkipped) = await uploadToAllDestinations()
    result.potaMaintenanceSkipped = potaSkipped

    if potaSkipped {
        debugLog.info("POTA skipped due to maintenance window (0000-0400 UTC)", service: .pota)
    }

    for (service, uploadResult) in uploadResults {
        switch uploadResult {
        case let .success(count):
            result.uploaded[service] = count
        case let .failure(error):
            result.errors.append(
                "\(service.displayName) upload: \(error.localizedDescription)")
        }
    }
}
```

**Step 2: Commit**

```bash
git add CarrierWave/Services/SyncService.swift
git commit -m "feat: handle POTA maintenance skip in sync results"
```

---

## Task 6: Skip POTA in Single-Service Sync Methods

**Files:**
- Modify: `CarrierWave/Services/SyncService.swift`

**Step 1: Update syncPOTA to check maintenance window**

In the `syncPOTA()` method, add a maintenance window check at the start (after `isSyncing = true`):

```swift
func syncPOTA() async throws -> (downloaded: Int, uploaded: Int) {
    isSyncing = true
    defer {
        isSyncing = false
        syncPhase = nil
    }

    // Check maintenance window
    if POTAClient.isInMaintenanceWindow() {
        throw POTAError.maintenanceWindow
    }

    var downloaded = 0
    var uploaded = 0
    // ... rest of method unchanged
```

**Step 2: Commit**

```bash
git add CarrierWave/Services/SyncService.swift
git commit -m "feat: block single-service POTA sync during maintenance window"
```

---

## Task 7: Show Maintenance Status on POTA Dashboard Card

**Files:**
- Modify: `CarrierWave/Views/Dashboard/DashboardView+ServiceCards.swift`

**Step 1: Add maintenance window indicator to potaCard**

In the `potaCard` computed property, after the sync status overlay block and before the "Synced QSOs" HStack, add a maintenance window indicator. Find this section:

```swift
if potaAuth.isAuthenticated {
    // Show sync status overlay during global sync
    if syncService.isSyncing {
        SyncStatusOverlay(phase: syncService.syncPhase, service: .pota)
    } else {
        // Synced QSOs
        HStack(spacing: 4) {
```

Change it to:

```swift
if potaAuth.isAuthenticated {
    // Show sync status overlay during global sync
    if syncService.isSyncing {
        SyncStatusOverlay(phase: syncService.syncPhase, service: .pota)
    } else {
        // Maintenance window indicator
        if POTAClient.isInMaintenanceWindow() {
            HStack(spacing: 4) {
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundStyle(.orange)
                Text("Maintenance until 0400 UTC")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        }

        // Synced QSOs
        HStack(spacing: 4) {
```

**Step 2: Commit**

```bash
git add CarrierWave/Views/Dashboard/DashboardView+ServiceCards.swift
git commit -m "feat: show POTA maintenance window indicator on dashboard card"
```

---

## Task 8: Show Toast After Sync When POTA Was Skipped

**Files:**
- Modify: `CarrierWave/Views/Dashboard/DashboardView+Actions.swift`

**Step 1: Update performFullSync to show maintenance message**

In the `performFullSync()` method, after the sync completes successfully, check if POTA was skipped. Change:

```swift
do {
    let result = try await syncService.syncAll()
    print("Sync: down=\(result.downloaded), up=\(result.uploaded), new=\(result.newQSOs)")
    if !result.errors.isEmpty {
        print("Sync errors: \(result.errors)")
    }
} catch {
```

To:

```swift
do {
    let result = try await syncService.syncAll()
    print("Sync: down=\(result.downloaded), up=\(result.uploaded), new=\(result.newQSOs)")
    if !result.errors.isEmpty {
        print("Sync errors: \(result.errors)")
    }
    if result.potaMaintenanceSkipped {
        potaSyncResult = "Maintenance until 0400 UTC"
    }
} catch {
```

**Step 2: Update performPOTASync to handle maintenance error**

In the `performPOTASync()` method, add specific handling for the maintenance error. Change:

```swift
} catch {
    potaSyncResult = "Error: \(error.localizedDescription)"
}
```

To:

```swift
} catch POTAError.maintenanceWindow {
    potaSyncResult = "Maintenance until 0400 UTC"
} catch {
    potaSyncResult = "Error: \(error.localizedDescription)"
}
```

**Step 3: Commit**

```bash
git add CarrierWave/Views/Dashboard/DashboardView+Actions.swift
git commit -m "feat: show POTA maintenance message after sync"
```

---

## Task 9: Final Verification

**Step 1: Ask user to build the project**

Ask the user to run `make build` and report any errors.

**Step 2: Ask user to run tests**

Ask the user to run `make test` and report any failures.

**Step 3: Final commit if needed**

If any fixes were needed, commit them:

```bash
git add -A
git commit -m "fix: address build/test issues for POTA maintenance window"
```
