# Findings & Decisions

## Requirements
- Post-session modal prompting POTA upload
- Map icon in POTA activation row
- Activation map view showing contacts
- RST-based contact coloring on map
- Share functionality for activation map

## Research Findings

### Session End Flow
- `LoggingSessionManager.endSession()` handles session end
- Posts QRT spot if enabled (fires and forgets)
- No modal is shown currently - session just ends
- Called from LoggerView (likely via stop button or sheet dismiss)

### POTA Activation Row
- Located in `POTAActivationsHelperViews.swift` → `ActivationRow`
- Currently has: Date, callsign, status icon, upload status
- Buttons: Export ADIF (doc icon), Share (square.and.arrow.up)
- Share currently generates `ActivationShareCardView` with map - exists in `ActivationShareRenderer.renderWithMap`
- No standalone map view icon yet

### QSO Model
- `rstSent: String?` and `rstReceived: String?` available
- Format is typically "599", "579", "449", etc.
- Both fields are optional but usually populated

### Map Implementation
- `QSOMapView.swift` is the main map
- Uses `QSOAnnotation` and `QSOMarkerView` for markers
- Supports filtering by band, mode, park, date range
- `MapFilterState` controls display options
- `QSOArc` draws geodesic paths to contacts
- Currently NO RST-based coloring

## Technical Decisions
| Decision | Rationale |
|----------|-----------|
| Modal only for POTA sessions with unuploaded QSOs | Don't pester user when nothing to upload |
| Modal options: Upload Now / Later / Don't Ask Again | User control over workflow |
| Show success in modal, then dismiss | Confirm action completed |
| Average rstSent + rstReceived for color | Both values contribute to signal quality |
| Green: 599/59, Yellow: 579/559/57/55, Red: <55 | Standard RST quality scale |
| Activation map is simple full-screen view | No complex filtering needed for single activation |
| Share button in activation map uses existing share renderer | Reuse proven code, same output |

## Issues Encountered
| Issue | Resolution |
|-------|------------|
|       |            |

## Resources
-

## Visual/Browser Findings
-

---
*Update this file after every 2 view/browser/search operations*
*This prevents visual information from being lost*
