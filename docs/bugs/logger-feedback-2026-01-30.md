# Logger Feedback - January 30, 2026

**Source:** Reddit feedback from field tester
**Status:** FIXED

## Summary

Field testing feedback from an actual POTA activation revealed several usability issues, particularly around screen timeout, timestamp display, QRZ callsign info, pileup workflow, and command-line enhancements for SPOT functionality.

---

## Issues

### 1. Screen Timeout Prevention (HIGH PRIORITY)

**Problem:** The device screen times out during logging, interrupting the workflow. User expects the app to keep the screen on while actively logging.

**Current behavior:** No screen timeout prevention implemented.

**Expected behavior:** While a logging session is active, prevent the device from sleeping.

**Implementation:**
- File: `CarrierWave/Services/LoggingSessionManager.swift`
- Use `UIApplication.shared.isIdleTimerDisabled = true` when session starts
- Set back to `false` when session ends
- Consider making this a setting (on by default)

**Files to modify:**
- `CarrierWave/Services/LoggingSessionManager.swift` - add idle timer control
- `CarrierWave/Views/Logger/LoggerSettingsView.swift` - add toggle if making it optional

---

### 2. QSO Time Display - Use UTC Consistently (MEDIUM PRIORITY)

**Problem:** During entry, UTC time is shown. But in the QSO list, time displays in local timezone. This is confusing for amateur radio operators who work in UTC.

**Current behavior:** `LoggerQSORow` uses `TimeZone(identifier: "UTC")` in the formatter, but the user reports seeing local time. Need to verify this is actually happening.

**Location:** `CarrierWave/Views/Logger/LoggerView.swift` - `LoggerQSORow`

**Investigation needed:** The code shows UTC should be used. Check if there's another display location showing local time, or if the formatter isn't being applied correctly.

**Files to check:**
- `CarrierWave/Views/Logger/LoggerView.swift` - `LoggerQSORow` (line ~568)
- `CarrierWave/Views/Logs/LogsListView.swift` - main logs view

---

### 3. QRZ Callsign Info Not Displaying (HIGH PRIORITY)

**Problem:** User never saw QRZ info for callsigns during logging.

**Current behavior:** `CallsignLookupService` should perform lookups, and `LoggerCallsignCard` should display results.

**Investigation needed:**
- Is QRZ authentication working?
- Is the lookup timing out?
- Is the card displaying but with no data?

**Files to check:**
- `CarrierWave/Services/CallsignLookupService.swift` - lookup logic
- `CarrierWave/Views/Logger/LoggerCallsignCard.swift` - display logic
- `CarrierWave/Services/QRZClient.swift` - API client

**Debugging suggestions:**
- Add logging to `CallsignLookupService.lookup()` to see if requests are being made
- Check if QRZ session is valid
- Verify network connectivity during the activation

---

### 4. Animation Delay During Pileups (HIGH PRIORITY)

**Problem:** Animations cause delays when rapidly entering QSOs during pileups, slowing down the logging workflow.

**Current behavior:** Multiple animations on `LoggerView`:
- `LoggerCallsignCard` has enter/exit transitions
- Form sections animate visibility changes
- Toast notifications animate

**Proposed solution:**
1. Add a "Quick Log Mode" or "Contest Mode" setting that disables animations
2. Reduce or remove animation duration on critical paths
3. Consider pre-loading the next input field to reduce perceived delay

**Files to modify:**
- `CarrierWave/Views/Logger/LoggerView.swift` - reduce animation durations
- `CarrierWave/Views/Logger/LoggerSettingsView.swift` - add Quick Log Mode toggle

---

### 5. Layout vs Keyboard Visibility (MEDIUM PRIORITY)

**Problem:** When the keyboard is visible, it's hard to see callsign info while entering data.

**Current behavior:** The callsign info card appears above the input field, but may be pushed off-screen by the keyboard.

**Proposed solutions:**
1. Add keyboard-aware scrolling to ensure callsign info stays visible
2. Consider a compact callsign info bar that stays pinned above the keyboard
3. Allow users to configure which fields appear in the main logging view

**Files to modify:**
- `CarrierWave/Views/Logger/LoggerView.swift` - improve keyboard handling
- `CarrierWave/Views/Logger/LoggerCallsignCard.swift` - create compact variant

---

### 6. SPOT Command Enhancements (MEDIUM PRIORITY)

**Problem:** `SPOT` command only self-spots. User wants `SPOT <message>` to include a comment on pota.app (e.g., `SPOT QRT` or `SPOT QSY`).

**Current behavior:** `SPOT` posts a basic self-spot with no comment.

**Requested behavior:**
- `SPOT` - self-spot with no comment (current)
- `SPOT QRT` - self-spot with "QRT" as comment
- `SPOT QSY` - self-spot with "QSY" as comment (optionally prompt for new frequency)
- `SPOT <any text>` - self-spot with custom comment

**Implementation:**
1. Modify `LoggerCommand.swift` to parse `SPOT <args>`:
```swift
case spot(comment: String?)  // Change from just `case spot`
```

2. Update `POTAClient+Spot.swift` to accept and send comment parameter

3. Special handling for `SPOT QSY`:
   - Post spot with "QSY" comment
   - Optionally show a frequency input prompt after

**Files to modify:**
- `CarrierWave/Models/LoggerCommand.swift` - parse SPOT with arguments
- `CarrierWave/Services/POTAClient+Spot.swift` - add comment parameter
- `CarrierWave/Views/Logger/LoggerView.swift` - handle SPOT QSY flow

---

### 7. Map Not Showing Current Activation QSOs (MEDIUM PRIORITY)

**Problem:** Map showed old QSOs from October but nothing from the current activation.

**Investigation needed:**
- Map filters by `theirGrid` - if logged QSOs don't have grid info, they won't appear
- Check if QSOs from logger have `theirGrid` populated
- The lookup result includes grid when available, but it needs to be saved to the QSO

**Current behavior:** `QSOMapView` filters QSOs that have `theirGrid?.isEmpty == false`

**Likely issue:** When logging QSOs, the `theirGrid` field may not be populated from the callsign lookup.

**Files to check:**
- `CarrierWave/Services/LoggingSessionManager.swift` - `logQSO` method
- `CarrierWave/Views/Logger/LoggerView.swift` - verify grid is passed to logQSO

**Fix:** Ensure the grid from callsign lookup is saved to the QSO when logging.

---

## Feature Requests

### A. Enhanced Command-Line Interface

**Request:** Make as many functions controllable from the command line as possible.

**Current commands:**
- `FREQ <MHz>` - set frequency
- `MODE <mode>` - set mode  
- `SPOT` - self-spot to POTA
- `RBN` - show RBN panel
- `SOLAR` - show solar conditions
- `WEATHER` - show weather
- `HELP` - show help

**Suggested new commands:**
- `SPOT <comment>` - self-spot with comment (see issue #6)
- `QRT` - end session (shortcut for menu action)
- `NOTES <text>` - set notes for next QSO
- `PARK <ref>` - change park reference
- `CALL <callsign>` - change my callsign
- `GRID <grid>` - change my grid

---

## Priority Summary

| Priority | Issue | Effort | Status |
|----------|-------|--------|--------|
| HIGH | Screen timeout prevention | Low | FIXED |
| HIGH | QRZ callsign info not showing | Debug | FIXED |
| HIGH | Animation delay during pileups | Medium | FIXED |
| MEDIUM | UTC time display consistency | Low | FIXED |
| MEDIUM | Layout vs keyboard visibility | Medium | FIXED |
| MEDIUM | SPOT command enhancements | Medium | FIXED |
| MEDIUM | Map not showing activation QSOs | Debug | FIXED |

---

## Notes

- The tester was doing an actual POTA activation, so this is real-world field usage
- Pileup performance is critical for CW contesting and POTA activators
- UTC consistency is a standard expectation for ham radio logging software
