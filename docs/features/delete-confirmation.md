# Delete Confirmation Guidelines

## Rule

**All delete operations MUST present a confirmation dialog before executing.** No data should be removed (or hidden) without explicit user confirmation.

This applies to:
- Swipe-to-delete on QSO rows
- Swipe-to-delete on any list item (sessions, recordings, profiles, etc.)
- Toolbar/button delete actions
- Bulk delete operations
- Any action that sets `isHidden = true` or removes a SwiftData model

## Pattern

Use a SwiftUI `.alert` with a destructive button:

```swift
@State private var itemToDelete: MyModel?

// In swipe action — set state, do NOT delete directly
.swipeActions(edge: .trailing, allowsFullSwipe: false) {
    Button(role: .destructive) {
        itemToDelete = item
    } label: {
        Label("Delete", systemImage: "trash")
    }
}

// Confirmation alert
.alert(
    "Delete Item",
    isPresented: Binding(
        get: { itemToDelete != nil },
        set: { if !$0 { itemToDelete = nil } }
    )
) {
    Button("Delete", role: .destructive) {
        if let item = itemToDelete {
            performDelete(item)
        }
        itemToDelete = nil
    }
    Button("Cancel", role: .cancel) {
        itemToDelete = nil
    }
} message: {
    if let item = itemToDelete {
        Text("Delete \(item.displayName)?")
    }
}
```

### Key details

- **`allowsFullSwipe: false`** — prevents accidental deletion from a fast full swipe
- **Destructive button role** — renders the delete button in red
- **Cancel button role** — ensures the alert is dismissable without action
- **Clear state on dismiss** — always nil out the pending delete item

## Review Checklist

When reviewing changes that involve deletion:

- [ ] Is there a confirmation dialog before the delete executes?
- [ ] Is `allowsFullSwipe` set to `false` on swipe actions?
- [ ] Does the confirmation message identify what will be deleted?
- [ ] Does canceling leave the data untouched?

## Where confirmations are currently implemented

| View | Item Deleted | File |
|------|-------------|------|
| RecentQSOsSection | Activity Log QSO (hide) | `CarrierWave/Views/ActivityLog/RecentQSOsSection.swift` |
| DailySummaryView | Activity Log QSO (hide) | `CarrierWave/Views/ActivityLog/DailySummaryView.swift` |
| POTAActivationDetailView | Activation QSO (hide) | `CarrierWave/Views/POTAActivations/POTAActivationDetailView.swift` |
| SessionsView | Session / orphan activation (delete + hide QSOs) | `CarrierWave/Views/Sessions/SessionsView.swift` |
| LoggerView (qsoListSection) | Logger QSO (swipe-to-hide) | `CarrierWave/Views/Logger/LoggerView.swift` |
| SessionDetailView | Session QSO (swipe-to-hide) | `CarrierWave/Views/Sessions/SessionDetailView.swift` |
