# Two-fer POTA Support and Duplicate QSO Repair

**Date:** 2026-02-04
**Status:** Done

## Problem Summary

### Issue 1: Two-fer activations fail to upload

When activating multiple parks simultaneously (a "two-fer" or "three-fer"), Ham2K PoLo stores the park reference as comma-separated values like `US-1044, US-3791`. 

Carrier Wave's POTA upload logic validates park references with regex `^[A-Za-z]{1,4}-\d{1,6}$`, which only matches single parks. This causes uploads to fail with "Invalid park reference format".

POTA expects **separate uploads for each park** - the same QSOs should be uploaded once per park in the two-fer.

### Issue 2: Duplicate QSOs from multi-source imports

When QSOs are imported from both PoLo (with full two-fer park ref `US-1044, US-3791`) and POTA.app (with single park ref `US-1044`), duplicates are created because the park references don't match exactly.

Example from user's database:
- 22 QSOs with `US-1044, US-3791` (from PoLo import)
- 22 QSOs with `US-1044, U` (truncated, from POTA download)

The deduplication service doesn't merge these because park references must match exactly.

## Solution Design

### Part 1: Two-fer Upload Support

**Approach:** Split comma-separated park references and upload to each park separately.

#### Changes to `POTAClient.swift`

1. Add helper to split park references:
```swift
/// Split comma-separated park references (e.g., "US-1044, US-3791" -> ["US-1044", "US-3791"])
static func splitParkReferences(_ parkRef: String) -> [String] {
    parkRef.split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
        .filter { !$0.isEmpty }
}
```

2. Add helper to check if park ref is multi-park:
```swift
/// Check if park reference contains multiple parks (two-fer, three-fer, etc.)
static func isMultiPark(_ parkRef: String) -> Bool {
    parkRef.contains(",")
}
```

#### Changes to `SyncService+Upload.swift`

Modify `uploadToPOTA` to handle multi-park references:

```swift
func uploadToPOTA(qsos: [QSO]) async throws -> Int {
    // Filter out metadata pseudo-modes before grouping
    let realQsos = qsos.filter { !Self.metadataModes.contains($0.mode.uppercased()) }
    
    // Expand multi-park QSOs: each QSO with "US-1044, US-3791" becomes entries for both parks
    var expandedByPark: [String: [QSO]] = [:]
    for qso in realQsos {
        guard let parkRef = qso.parkReference, !parkRef.isEmpty else { continue }
        
        let parks = POTAClient.splitParkReferences(parkRef)
        for park in parks {
            expandedByPark[park, default: []].append(qso)
        }
    }
    
    var totalUploaded = 0
    var totalFailed = 0

    // ... rest of upload logic using expandedByPark instead of byPark
}
```

#### Changes to `POTAActivation.swift`

Keep grouping logic as-is (group by full park reference string). A two-fer like `US-1044, US-3791` stays as one activation row.

Add computed properties for multi-park support:

```swift
/// Individual parks in this activation (splits comma-separated refs)
var parks: [String] {
    POTAClient.splitParkReferences(parkReference)
}

/// Whether this is a multi-park activation (two-fer, three-fer, etc.)
var isMultiPark: Bool {
    parks.count > 1
}

/// Upload status per park (for tracking partial upload failures)
/// Key: park reference, Value: true if uploaded successfully
var uploadStatusByPark: [String: Bool] {
    // Check if QSOs are present for each individual park
    // This requires tracking per-park upload status (see ServicePresence changes)
}
```

**UI behavior:** One combined row showing "US-1044, US-3791". Single "Upload" button uploads to both parks. If one fails, show tappable error icon with details.

#### Changes to `ServicePresence` or new tracking model

For two-fers, we need to track upload status **per park**, not just per service. Options:

**Option A: Extend ServicePresence**
Add optional `parkReference` field to `ServicePresence` so a QSO can have multiple POTA presence records (one per park in a two-fer).

**Option B: New `POTAParkUploadStatus` model**
```swift
@Model
final class POTAParkUploadStatus {
    var qso: QSO?
    var parkReference: String
    var isUploaded: Bool
    var uploadError: String?
    var uploadedAt: Date?
}
```

**Recommended: Option A** - simpler, reuses existing infrastructure. A two-fer QSO would have two `ServicePresence` records for POTA, distinguished by a new `parkReference` field.

#### Changes to `POTAActivationsView` and helper views

Update `ActivationRow` to show:
- Combined park reference display: "US-1044, US-3791"
- Single upload button that uploads to all parks
- Error icon (tappable) if any park upload failed, showing which park(s) failed
- Partial status: "1/2 parks uploaded" or checkmark when all complete

```swift
// In ActivationRow
if activation.isMultiPark {
    if let failedParks = activation.failedParks, !failedParks.isEmpty {
        Button {
            showErrorSheet = true
        } label: {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
        .sheet(isPresented: $showErrorSheet) {
            UploadErrorSheet(failedParks: failedParks)
        }
    }
}
```

### Part 2: Duplicate QSO Repair Service

**Approach:** Create a repair service (following the `POTAPresenceRepairService` pattern) that:
1. Detects QSOs that are duplicates due to partial park reference matching
2. Merges them by absorbing the truncated version into the full version

#### New file: `TwoferDuplicateRepairService.swift`

```swift
/// Service to detect and repair duplicate QSOs created by two-fer park reference mismatches.
/// When QSOs are imported from multiple sources (PoLo with full ref, POTA with single ref),
/// duplicates can be created. This service finds and merges them.
actor TwoferDuplicateRepairService {
    let container: ModelContainer
    
    struct RepairResult: Sendable {
        let duplicateGroupsFound: Int
        let qsosMerged: Int
        let qsosRemoved: Int
    }
    
    init(container: ModelContainer) {
        self.container = container
    }
    
    /// Count potential duplicate groups (QSOs with same call/time but different park refs where one is subset of other)
    func countDuplicates() throws -> Int {
        // Implementation: find QSOs where parkRef contains "," and there's another QSO
        // with same callsign/timestamp but single park that's a subset
    }
    
    /// Repair duplicates by merging truncated/single-park versions into full multi-park versions
    func repairDuplicates() throws -> RepairResult {
        // Implementation:
        // 1. Find all QSOs with multi-park references
        // 2. For each, find potential duplicates (same call, similar timestamp, park is subset)
        // 3. Merge: keep the multi-park version, absorb service presence from single-park version
        // 4. Delete the single-park duplicate
    }
}
```

#### Detection logic:

Two QSOs are considered duplicates if:
1. Same callsign (case-insensitive)
2. Timestamps within 60 seconds (POTA rounds to minutes)
3. Same band (or one is empty)
4. Same mode family
5. One park reference contains the other as a prefix/subset
   - `US-1044, US-3791` contains `US-1044`
   - `US-1044, U` is a truncated version of `US-1044, US-3791`

#### Merge strategy:

- **Winner:** QSO with the most complete park reference (most commas or longest)
- **Absorb from loser:**
  - Service presence records (if loser has `isPresent=true` for a service, winner inherits it)
  - Any fields that are nil in winner but populated in loser
- **Delete loser** after merge

### Part 3: Integration

#### Trigger repair on sync

Add to `SyncService` or `DashboardView+Actions`:

```swift
/// Check for and optionally repair two-fer duplicate QSOs
func checkForTwoferDuplicates() async {
    let repairService = TwoferDuplicateRepairService(container: modelContext.container)
    do {
        let count = try await repairService.countDuplicates()
        if count > 0 {
            // Show alert to user offering repair
            twoferDuplicateCount = count
            showingTwoferRepairAlert = true
        }
    } catch {
        print("Failed to check for two-fer duplicates: \(error)")
    }
}
```

#### UI for repair

Add alert similar to POTA presence repair in `DashboardView`:

```swift
.alert("Duplicate QSOs Found", isPresented: $showingTwoferRepairAlert) {
    Button("Merge Duplicates") {
        Task { await repairTwoferDuplicates() }
    }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("\(twoferDuplicateCount) duplicate QSOs found from two-fer activations. Merge them?")
}
```

## Implementation Order

1. **Phase 1: Two-fer upload support**
   - Add `splitParkReferences` and `isMultiPark` helpers to `POTAClient`
   - Update `SyncService+Upload.uploadToPOTA` to expand multi-park QSOs
   - Update `POTAActivation.groupQSOs` to show separate activations per park
   - Test: Verify two-fer QSOs now upload successfully to both parks

2. **Phase 2: Duplicate repair service**
   - Create `TwoferDuplicateRepairService` actor
   - Implement `countDuplicates()` method
   - Implement `repairDuplicates()` method with merge logic
   - Add unit tests for detection and merge logic

3. **Phase 3: UI integration**
   - Add state variables to `DashboardView` for two-fer repair
   - Add check on dashboard appear (or sync complete)
   - Add repair alert and action
   - Update FILE_INDEX.md with new service

## Testing Considerations

- Test two-fer upload with `US-1044, US-3791` format
- Test three-fer upload with `US-1044, US-3791, US-5678` format
- Test duplicate detection with exact timestamp match
- Test duplicate detection with 30-second offset (POTA rounding)
- Test merge preserves service presence correctly
- Test merge handles truncated park refs like `US-1044, U`

## Files to Modify

| File | Changes |
|------|---------|
| `CarrierWave/Services/POTAClient.swift` | Add `splitParkReferences`, `isMultiPark` helpers |
| `CarrierWave/Services/SyncService+Upload.swift` | Expand multi-park QSOs, upload to each park, track per-park results |
| `CarrierWave/Models/POTAActivation.swift` | Add `parks`, `isMultiPark`, `uploadStatusByPark`, `failedParks` computed properties |
| `CarrierWave/Models/ServicePresence.swift` | Add optional `parkReference` field for per-park POTA tracking |
| `CarrierWave/Views/POTAActivations/POTAActivationsView.swift` | Handle multi-park upload, show error icon for failures |
| `CarrierWave/Views/POTAActivations/POTAActivationsHelperViews.swift` | Add `UploadErrorSheet` for showing failed park details |
| `CarrierWave/Services/TwoferDuplicateRepairService.swift` | **NEW** - Repair service for duplicate QSOs |
| `CarrierWave/Views/Dashboard/DashboardView.swift` | Add repair alert state |
| `CarrierWave/Views/Dashboard/DashboardView+Actions.swift` | Add repair check/action methods |
| `docs/FILE_INDEX.md` | Add new service to index |
| `CHANGELOG.md` | Document new features |

## Design Decisions

1. **UI for two-fer activations:** One combined row showing both parks (e.g., "US-1044, US-3791"). Single "Upload" button uploads to all parks. If any park upload fails, show tappable error icon with details about which park(s) failed.

2. **Duplicate repair:** Always prompt the user before merging. Check on dashboard appear, show alert with count, let user confirm before repair runs.

3. **Truncated park refs (e.g., `US-1044, U`):** Merge into the complete version if one exists. Don't try to infer the missing part.
