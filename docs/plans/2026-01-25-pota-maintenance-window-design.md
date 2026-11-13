# POTA Maintenance Window Design

## Problem

POTA performs maintenance operations daily between 0000-0400 UTC. Uploads during this window are guaranteed to fail. The app should detect this window and communicate clearly to users rather than attempting operations that will fail.

## Solution

Block all POTA API operations during the maintenance window and communicate this to users via:
1. A toast/banner after sync completes explaining POTA was skipped
2. A persistent indicator on the Dashboard POTA card during the window

## Implementation

### 1. Maintenance Window Detection

Add to `POTAClient.swift`:

```swift
static func isInMaintenanceWindow(at date: Date = Date()) -> Bool {
    let calendar = Calendar(identifier: .gregorian)
    let utc = TimeZone(identifier: "UTC")!
    let hour = calendar.dateComponents(in: utc, from: date).hour ?? 0
    return hour >= 0 && hour < 4
}
```

### 2. New Error Case

Add to `POTAError` enum in `POTAClient.swift`:

```swift
case maintenanceWindow

var errorDescription: String? {
    switch self {
    case .maintenanceWindow:
        "POTA is in maintenance (0000-0400 UTC)"
    // ... existing cases
    }
}
```

### 3. Block Operations in SyncService

In `SyncService+Upload.swift`, check before POTA upload:
- If in maintenance window, skip POTA operations and track that it was skipped

In `SyncService+Download.swift`, check before POTA download operations:
- Same behavior as uploads

### 4. Track Maintenance Skip in Sync Results

`SyncService` needs to communicate that POTA was skipped due to maintenance so the UI can show a toast. This can be done via the existing sync result mechanism or a new property.

### 5. Dashboard POTA Card Indicator

In `DashboardView+ServiceCards.swift`, when rendering the POTA card:
- Check `POTAClient.isInMaintenanceWindow()`
- If true, display "Maintenance until 0400 UTC" on the card

### 6. Toast After Sync

In `DashboardView.swift` or `DashboardView+Actions.swift`:
- After sync completes, check if POTA was skipped due to maintenance
- Show toast: "POTA sync paused until 0400 UTC (maintenance window)"

## Files to Modify

| File | Changes |
|------|---------|
| `POTAClient.swift` | Add `maintenanceWindow` error case, add `isInMaintenanceWindow()` function |
| `SyncService+Upload.swift` | Check maintenance window before POTA upload |
| `SyncService+Download.swift` | Check maintenance window before POTA download |
| `SyncService.swift` | Track maintenance skip status |
| `DashboardView+ServiceCards.swift` | Show maintenance indicator on POTA card |
| `DashboardView.swift` or `DashboardView+Actions.swift` | Show toast after sync |

## User Experience

1. User triggers sync during maintenance window
2. Sync runs for other services (QRZ, LoFi, etc.) normally
3. POTA operations are skipped silently during sync
4. After sync completes, toast appears: "POTA sync paused until 0400 UTC (maintenance window)"
5. Dashboard POTA card shows "Maintenance until 0400 UTC" whenever viewed during the window
6. After 0400 UTC, normal POTA operations resume automatically
