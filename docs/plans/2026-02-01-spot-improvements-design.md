# Logger RBN/POTA Spot Improvements Design

**Date:** 2026-02-01  
**Status:** Approved

## Overview

Four improvements to the spot display and handling in the logger:

1. Color-code spot age by freshness
2. Auto-attach spot comments to matching QSOs
3. Label self-spots with a badge
4. Post QRT spot when ending POTA session

## Feature 1: Spot Age Color Coding

### Behavior

Apply color to the spot age text based on freshness:

| Age | Color | Meaning |
|-----|-------|---------|
| < 2 minutes | Green | Very fresh, activator likely still on frequency |
| 2-10 minutes | Blue | Recent, good chance they're still active |
| 10-30 minutes | Orange | Getting stale, may have QSY'd |
| > 30 minutes | Gray | Old spot, likely no longer valid |

### Implementation

- Add `ageColor: Color` computed property to `UnifiedSpot`
- Add `ageColor: Color` computed property to `POTASpot`
- Update `RBNPanelView.spotRow()` to apply color to time text
- Update `POTASpotRow` to apply color to time text

## Feature 2: Spot Comments → QSO Notes

### Matching Logic

When new spot comments arrive:

1. Get the spotter's callsign from the comment
2. Find QSOs in current session where `qso.callsign` matches the spotter's callsign
3. Filter to QSOs where `|comment.timestamp - qso.timestamp| <= 5 minutes`
4. If match found, append comment to QSO notes

### Note Format

```
[Spot: W1ABC] Great signal into FL!
```

If QSO already has notes:
```
Existing notes | [Spot: W1ABC] Great signal into FL!
```

### Implementation

- Add `onNewComments: (([POTASpotComment]) -> Void)?` callback to `SpotCommentsService`
- Add `processedSpotIds: Set<Int64>` to `LoggingSessionManager` to track attached comments
- Add `attachSpotComments(_:)` method to `LoggingSessionManager`
- Wire callback in `startSpotCommentsPolling()`

## Feature 3: Self-Spot Labeling

### Detection Logic

Compare spot callsign against user's configured callsign:
- Case insensitive comparison
- Strip portable suffixes (/P, /M, /QRP, etc.) before comparing

### Visual Treatment

Add "SELF" badge next to self-spots:
- Small capsule with purple/indigo background
- Positioned after the callsign or source indicator

### Implementation

- Add `isSelfSpot(userCallsign:) -> Bool` to `UnifiedSpot`
- Add `isSelfSpot(userCallsign:) -> Bool` to `POTASpot`
- Add helper function `normalizeCallsign(_:) -> String` to strip suffixes
- Update `RBNPanelView.spotRow()` to show "SELF" badge
- Update `POTASpotRow` to show "SELF" badge
- Pass user callsign from session to spot views

## Feature 4: QRT Spot on Session End

### Flow

When ending a POTA session:

1. Check if `potaQRTSpotEnabled` setting is true (default: true)
2. Query POTA API to check if any spots exist for this activator/park
3. If spots exist, post QRT spot with comment "QRT"
4. Proceed with normal session cleanup

### Setting

- Key: `potaQRTSpotEnabled`
- Default: `true`
- UI: Toggle in POTA settings alongside auto-spot toggle

### Implementation

- Add `potaQRTSpotEnabled` UserDefaults key
- Add `postQRTSpotIfNeeded() async` to `LoggingSessionManager`
- Modify `endSession()` to call `postQRTSpotIfNeeded()` before cleanup
- Add toggle to `ServiceSettingsViews.swift` POTA section

## Files to Modify

| File | Changes |
|------|---------|
| `SpotsService.swift` | Add `ageColor`, `isSelfSpot()` to `UnifiedSpot` |
| `POTAClient+Spots.swift` | Add `ageColor`, `isSelfSpot()` to `POTASpot` |
| `RBNPanelView.swift` | Apply age color, add self-spot badge |
| `POTASpotRow.swift` | Apply age color, add self-spot badge |
| `LoggingSessionManager.swift` | Comment→QSO matching, QRT spot logic |
| `SpotCommentsService.swift` | Add callback for new comments |
| `ServiceSettingsViews.swift` | Add QRT spot toggle |

## Testing

Manual testing scenarios:

1. **Age coloring**: Verify spots show correct colors at different ages
2. **Comment attachment**: Log a QSO, have that callsign post a spot comment, verify note appears
3. **Self-spot badge**: Self-spot during session, verify "SELF" badge appears
4. **QRT spot**: End POTA session that had spots, verify QRT posted to POTA
