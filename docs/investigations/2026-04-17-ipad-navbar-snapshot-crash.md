# iPad UINavigationBar Assertion Crash on Background

**Date:** 2026-04-17
**Crash IDs:** 2788 (primary), 2789, 2790 (duplicates)
**Device:** iPad14,4, iOS 26.2.1
**Builds:** 335, 320
**Severity:** High (100% repro for affected tester)

## Symptom

App crashes every time user switches away from Carrier Wave on iPad. Crash occurs during system snapshot with `EXC_CRASH (SIGABRT)` — an `NSAssertionHandler` failure in `-[UINavigationBar layoutSubviews]` (UINavigationBar.m:4030).

## Root Cause

Nested `UINavigationController` instances inside `NavigationSplitView`'s detail column.

`ContentView` uses `NavigationSplitView` on iPad. The detail pane displayed the same tab content as iPhone, where each tab embeds its own `NavigationStack`. This created nested navigation controllers:

```
NavigationSplitView (outer UINavigationController)
  └─ detail:
       └─ DashboardView / SessionsIdleView / etc.
            └─ NavigationStack (inner UINavigationController) ← conflict
```

When the system takes a snapshot (`_performSystemSnapshotWithActions:`), the split view's adaptive layout transitions (`_prepareTransitionToLayout:`). During this transition, `UINavigationBar.layoutSubviews` fires an assertion because the inner navigation bar is in an inconsistent state — it belongs to the inner controller but is being laid out during the outer controller's transition.

## Call Stack (abbreviated)

```
_performSystemSnapshotWithActions
  → _sceneBoundsDidChange
    → _adjustSizeClassesAndResizeWindowToFrame
      → _UISplitViewControllerAdaptiveImpl _prepareTransitionToLayout
        → _UISplitViewControllerAdaptiveColumnView.contentView.setter
          → _addSubview → _postMovedFromSuperview
            → UINavigationController _positionNavigationBarHidden
              → UINavigationBar layoutSubviews → ASSERTION FAILURE
```

## Fix

Added `isInNavigationContext: Bool = false` to views that embed their own `NavigationStack`:
- `DashboardView`
- `SessionsIdleView`
- `SessionsIntentView`
- `CWTranscriptionView`
- `SessionsTabView` (passes through to children)

When `true`, these views skip their inner `NavigationStack` and rely on the parent navigation context. `LogsContainerView` and `ActivityView` already had this parameter.

Created `ContentView+iPadDetail.swift` with iPad-specific tab content builders that pass `isInNavigationContext: true`, and updated the `NavigationSplitView` detail to use `iPadSelectedTabContent` instead of the shared `selectedTabContent`.

iPhone path is unchanged — `TabView` doesn't provide a navigation context, so inner `NavigationStack` wrappers remain.

## Files Changed

- `ContentView.swift` — iPad detail uses `iPadSelectedTabContent`; widened access on properties for cross-file extension
- `ContentView+iPadDetail.swift` — New file with iPad-specific tab content builders
- `DashboardView.swift` — Added `isInNavigationContext`, extracted `dashboardContent`
- `SessionsTabView.swift` — Added `isInNavigationContext`, passes to children
- `SessionsIdleView.swift` — Added `isInNavigationContext`, extracted `sessionsIdleContent`
- `SessionsIntentView.swift` — Added `isInNavigationContext`, extracted `sessionsIntentContent`
- `CWTranscriptionView.swift` — Added `isInNavigationContext`, extracted `transcriptionContent`

## Verification

- Build passes (22s)
- iPhone path unchanged (default `isInNavigationContext = false`)
- iPad detail views now use NavigationSplitView's navigation context directly
