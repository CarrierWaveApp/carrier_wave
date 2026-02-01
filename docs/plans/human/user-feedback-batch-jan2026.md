# User Feedback Batch - January 2026

## Overview

This document tracks fixes for user-reported issues from January 2026 feedback.

**Status: COMPLETED** - All 6 issues have been implemented.

## Issues

### 1. Onboarding "Skip" Button Wording

**Status:** DONE

**Report:** When any service is connected on the initial services setup screen, the "Skip" button should change to "Next" to indicate connections will be saved.

**Location:** `CarrierWave/Views/Tour/OnboardingView.swift`

**Fix:**
- In `connectServicesStep`, change the navigation button logic
- When `connectedServices.isEmpty`, show "Skip"
- When `!connectedServices.isEmpty`, show "Next"
- Both buttons advance to the next step (same behavior, different label)

**Implementation:**
```swift
// In navigationButtons, update the connectServices case:
case .connectServices:
    Button(connectedServices.isEmpty ? "Skip" : "Next") {
        withAnimation {
            currentStep = .complete
        }
    }
    .buttonStyle(.borderedProminent)
```

---

### 2. Technician CW Band Privileges Incorrect

**Status:** DONE

**Report:** Technicians are incorrectly warned they cannot operate CW at 7.030 MHz and 21.060 MHz. According to FCC Part 97, Technicians have CW privileges on portions of 80m, 40m, 15m, and 10m bands.

**Location:** `CarrierWave/Models/BandPlan.swift`

**Root Cause:** The `BandPlan.segments` array is missing Technician CW privileges for 80m, 40m, and 15m. Currently only 10m has Technician segments.

**Fix:** Add the following Technician CW segments per FCC Part 97.301(e):
- **80m:** 3.525-3.600 MHz (CW only)
- **40m:** 7.025-7.125 MHz (CW only)
- **15m:** 21.025-21.200 MHz (CW only)
- **10m:** 28.000-28.500 MHz (already present)

**Implementation:**
```swift
// Add to 80m section:
BandSegment(
    band: "80m", startMHz: 3.525, endMHz: 3.600, modes: ["CW"],
    minimumLicense: .technician, notes: "Tech CW only"
),

// Add to 40m section:
BandSegment(
    band: "40m", startMHz: 7.025, endMHz: 7.125, modes: ["CW"],
    minimumLicense: .technician, notes: "Tech CW only"
),

// Add to 15m section:
BandSegment(
    band: "15m", startMHz: 21.025, endMHz: 21.200, modes: ["CW"],
    minimumLicense: .technician, notes: "Tech CW only"
),
```

---

### 3. Improved Warning Message for Bands with No Tech Privileges

**Status:** DONE

**Report:** For bands where Technicians have no privileges at all (160m, 60m, 30m, 20m, 17m, 12m), the warning should say "Technicians cannot operate in any mode within the XX band" rather than implying they might have some privileges.

**Location:** `CarrierWave/Services/BandPlanService.swift`

**Fix:** In the `validate` function, detect when a Technician has zero privileges on a band and return a more specific message.

**Implementation:**
```swift
// After determining the user doesn't have privileges, check if they have ANY privileges on this band
if license == .technician {
    let band = matchingSegments.first?.band
    let techPrivilegesOnBand = BandPlan.segments.filter { segment in
        segment.band == band && segment.minimumLicense == .technician
    }
    
    if techPrivilegesOnBand.isEmpty, let band {
        return BandPlanViolation(
            type: .noPrivileges,
            message: "Technicians cannot operate in any mode within the \(band) band",
            suggestion: "Requires General or higher"
        )
    }
}
```

---

### 4. iPad Tab Bar Changes Require Restart

**Status:** DONE

**Report:** On iPhone, tab bar setting changes are instant. On iPad, they don't take effect until app restart.

**Location:** `CarrierWave/ContentView.swift`

**Root Cause:** The iPad navigation uses `NavigationSplitView` with a `List` bound to `visibleTabs`, but unlike the iPhone `TabView`, it doesn't subscribe to the `.tabConfigurationChanged` notification.

**Fix:** Add the same `onReceive` handler to the iPad navigation that the iPhone navigation has.

**Implementation:**
```swift
private var iPadNavigation: some View {
    NavigationSplitView {
        List(visibleTabs, id: \.self, selection: $selectedTab) { tab in
            Label(tab.title, systemImage: tab.icon)
        }
        .navigationTitle("Carrier Wave")
    } detail: {
        selectedTabContent
    }
    .onReceive(NotificationCenter.default.publisher(for: .tabConfigurationChanged)) { _ in
        visibleTabs = TabConfiguration.visibleTabs()
        if let selected = selectedTab, !visibleTabs.contains(selected) {
            selectedTab = visibleTabs.first
        }
    }
}
```

---

### 5. iPad Tab Bar - Remove 4-Tab Limit / Show All Tabs by Default

**Status:** DONE

**Report:** With the iPad's side nav menu, there's plenty of room for all tabs. The 4-tab limit should be removed for iPad, and all tabs should be visible by default.

**Location:** 
- `CarrierWave/ContentView.swift` - iPad navigation
- Settings view where tab configuration is managed

**Fix Options:**
1. **Option A (Minimal):** For iPad, ignore the hidden tabs setting and show all configurable tabs
2. **Option B (Better UX):** Create separate default settings for iPad vs iPhone

**Recommended Implementation (Option A):**
```swift
// In ContentView, modify visibleTabs initialization for iPad:
private var iPadVisibleTabs: [AppTab] {
    // On iPad, show all configurable tabs plus More
    TabConfiguration.tabOrder()
}

// Use iPadVisibleTabs instead of visibleTabs in iPadNavigation
```

**Note:** The user also suggested allowing order customization while showing all tabs. This is already supported - users can reorder via Settings even if nothing is hidden.

---

### 6. Frequency Precision - Support Sub-kHz Entry (e.g., 14.030.50)

**Status:** DONE

**Report:** Users cannot enter frequencies with precision beyond kHz (e.g., 14.030.50 or 14.03050). If entered, the value is rounded or the frequency field shows blank.

**Locations:**
- `CarrierWave/Views/Logger/SessionStartSheet.swift` - Initial frequency entry
- `CarrierWave/Models/LoggingSession.swift` - Frequency storage (already `Double`, supports precision)
- `CarrierWave/Views/Logger/LoggerView.swift` - Frequency display/edit during session

**Root Cause:** The frequency TextField uses `.decimalPad` keyboard which is correct, but the parsing and display use `%.3f` format (3 decimal places = kHz precision). Also, the frequency command parsing may be truncating.

**Fix:**
1. Update display format from `%.3f` to support more precision (e.g., `%.4f` or `%.5f`)
2. Update frequency parsing to handle both dot and decimal notation
3. Ensure `FREQ` command handles sub-kHz precision

**Implementation:**

In `SessionStartSheet.swift`:
```swift
// Change frequency display format in suggestions and elsewhere
// Current: String(format: "%.3f", freq)
// New: Use a helper that shows precision as needed

private func formatFrequency(_ freq: Double) -> String {
    // Show up to 5 decimal places, trimming trailing zeros
    let formatted = String(format: "%.5f", freq)
    // Remove unnecessary trailing zeros but keep at least 3 decimals
    var result = formatted
    while result.hasSuffix("0") && result.contains(".") {
        let beforeDot = result.prefix(while: { $0 != "." }).count
        let afterDot = result.count - beforeDot - 1
        if afterDot > 3 {
            result.removeLast()
        } else {
            break
        }
    }
    return result
}
```

In `LoggerCommand.swift` (frequency parsing):
```swift
// Ensure the regex/parsing handles formats like:
// - 14.060 (standard)
// - 14.06050 (sub-kHz as decimal)
// - 14060.5 (kHz with decimal - should convert to MHz)
```

In `LoggerView.swift` session header:
```swift
// Current: String(format: "%.3f MHz", freq)
// New: formatFrequency(freq) + " MHz"
```

---

## Testing Checklist

- [ ] Onboarding: Connect a service, verify button says "Next" not "Skip"
- [ ] Band Plan: Set license to Technician, verify 7.030 CW allowed, 7.200 SSB blocked
- [ ] Band Plan: Technician on 20m shows "cannot operate in any mode" message
- [ ] iPad: Change tab visibility in Settings, verify immediate effect without restart
- [ ] iPad: Verify all tabs visible in sidebar by default
- [ ] Frequency: Enter 14.03050 in session start, verify it's preserved and displayed correctly
- [ ] Frequency: Use FREQ 14.03050 command, verify precision maintained

## Implementation Order

Suggested order based on complexity and user impact:

1. **Onboarding button wording** - Simple, good UX improvement
2. **Technician CW privileges** - Critical bug fix, affects operations
3. **Tech band warning messages** - Enhancement to #2
4. **iPad tab bar notification** - Bug fix
5. **iPad show all tabs** - UX improvement
6. **Frequency precision** - More complex, affects multiple files
