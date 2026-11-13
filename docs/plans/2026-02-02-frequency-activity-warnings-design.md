# Frequency Activity Warnings Design

**Date:** 2026-02-02
**Status:** Pending approval

## Overview

Extend the existing band plan warning system to include warnings for common amateur radio activities (QRP calling frequencies, SSTV, digital modes, CWOps CWT, nets). This creates a unified frequency warning system that helps operators avoid interference and find appropriate frequencies for their intended activity.

## Goals

1. Warn users when operating on/near special-purpose frequencies with mode mismatches
2. Provide informational notices when on matching activity frequencies
3. Warn about time-based events (CWOps CWT) only during active periods
4. Maintain license violation warnings as highest priority
5. Keep UI clean with single warning banner showing most important warning

## Data Sources

- QRP/SSTV/digital/net frequencies: https://www.k6ldf.com/calling-frequencies-for-all-bands-and-modes/
- CWOps CWT: https://cwops.org/cwops-tests/ (Wed 1300Z, 1900Z; Thu 0300Z, 0700Z)

## Data Model

### FrequencyActivity

New struct in `BandPlan.swift`:

```swift
struct FrequencyActivity: Sendable {
    enum ActivityType: String, Sendable {
        case qrpCalling      // QRP calling frequencies
        case ssbCalling      // General SSB calling
        case amCalling       // AM calling frequencies
        case fmSimplex       // FM simplex calling
        case sstv            // Slow-scan TV
        case digitalPSK      // PSK31/PSK modes
        case digitalFT       // FT8/FT4
        case cwtContest      // CWOps CWT (time-based)
        case net             // Scheduled nets
    }
    
    let type: ActivityType
    let band: String
    let centerMHz: Double
    let toleranceKHz: Double      // ± tolerance for matching
    let modes: Set<String>        // Expected modes for this activity
    let description: String
    let timeWindows: [TimeWindow]? // For time-based activities like CWT
}

struct TimeWindow: Sendable {
    let dayOfWeek: Int           // 1=Sunday, 4=Wednesday, 5=Thursday
    let startHourUTC: Int
    let startMinuteUTC: Int
    let durationMinutes: Int
    let bufferMinutes: Int       // Before/after buffer (15 min for CWT)
}
```

### Tolerance Values by Activity Type

| Activity | Tolerance |
|----------|-----------|
| Calling frequencies (QRP, SSB, AM) | ±2 kHz |
| Digital modes (FT8, PSK31) | ±3 kHz |
| SSTV | ±3 kHz |
| CWT contest range | 25-45 kHz from band edge |
| Net frequencies | ±5 kHz |

### Activity Frequency Data

#### QRP CW Calling Frequencies
| Band | Frequency (MHz) |
|------|-----------------|
| 160m | 1.810 |
| 80m | 3.560 |
| 40m | 7.030 (Note: conflicts with IOTA, will use 7.040) |
| 30m | 10.106 |
| 20m | 14.060 |
| 17m | 18.080 |
| 15m | 21.060 |
| 12m | 24.906 |
| 10m | 28.060 |
| 6m | 50.060 |
| 2m | 144.060 |

#### QRP SSB Calling Frequencies
| Band | Frequency (MHz) |
|------|-----------------|
| 160m | 1.910 |
| 80m | 3.985 |
| 40m | 7.285 |
| 20m | 14.285 |
| 17m | 18.130 |
| 15m | 21.385 |
| 12m | 24.950 |
| 10m | 28.385 |
| 6m | 50.885 |
| 2m | 144.285 |

#### SSTV Frequencies
| Band | Frequency (MHz) |
|------|-----------------|
| 80m | 3.845 |
| 40m | 7.171 |
| 20m | 14.230, 14.233, 14.236 |
| 15m | 21.340 |
| 10m | 28.680 |

#### Digital Mode Frequencies (FT8/FT4)
| Band | Frequency (MHz) |
|------|-----------------|
| 160m | 1.840 |
| 80m | 3.573 |
| 40m | 7.074 |
| 30m | 10.136 |
| 20m | 14.074 |
| 17m | 18.100 |
| 15m | 21.074 |
| 12m | 24.915 |
| 10m | 28.074 |
| 6m | 50.313 |

#### PSK31 Frequencies
| Band | Frequency (MHz) |
|------|-----------------|
| 160m | 1.838 |
| 80m | 3.580 |
| 40m | 7.035 |
| 30m | 10.142 |
| 20m | 14.070 |
| 17m | 18.100 |
| 15m | 21.080 |
| 12m | 24.920 |
| 10m | 28.120 |

#### AM Calling Frequencies
| Band | Frequency (MHz) |
|------|-----------------|
| 80m | 3.885 |
| 40m | 7.290 |
| 20m | 14.286 |

#### FM Simplex Frequencies
| Band | Frequency (MHz) |
|------|-----------------|
| 10m | 29.600 |
| 6m | 52.525 |
| 2m | 146.520 |
| 70cm | 446.000 |

#### Net Frequencies
| Net | Band | Frequency (MHz) | Mode |
|-----|------|-----------------|------|
| County Hunters | 20m | 14.336 | SSB |
| County Hunters | 40m | 7.188 | SSB |

#### CWOps CWT Ranges
| Band | Range (MHz) | From band edge |
|------|-------------|----------------|
| 160m | 1.828-1.845 | 28-45 kHz |
| 80m | 3.528-3.545 | 28-45 kHz |
| 40m | 7.028-7.045 | 28-45 kHz |
| 20m | 14.028-14.045 | 28-45 kHz |
| 15m | 21.028-21.045 | 28-45 kHz |
| 10m | 28.028-28.045 | 28-45 kHz |

**CWT Time Windows (with 15-min buffer):**
- Wednesday 1245Z-1415Z (1300Z session)
- Wednesday 1845Z-2015Z (1900Z session)
- Thursday 0245Z-0415Z (0300Z session)
- Thursday 0645Z-0815Z (0700Z session)

## Unified Warning System

### FrequencyWarning Type

Replace `BandPlanViolation` with unified `FrequencyWarning`:

```swift
struct FrequencyWarning: Sendable {
    enum WarningType: Sendable {
        // License violations (high priority)
        case noPrivileges
        case wrongMode
        case outOfBand
        
        // Activity warnings (medium priority)
        case activityConflict   // Mode mismatch with expected activity
        case activityCrowded    // Time-based event active (CWT, etc.)
        
        // Informational (low priority)
        case unusualFrequency   // Existing - CW in phone segment
        case activityInfo       // Matching activity - "You're on QRP freq!"
    }
    
    let type: WarningType
    let message: String
    let suggestion: String?
    let activity: FrequencyActivity?
    
    var priority: Int {
        switch type {
        case .noPrivileges, .outOfBand: 0
        case .wrongMode: 1
        case .activityConflict, .activityCrowded: 2
        case .unusualFrequency: 3
        case .activityInfo: 4
        }
    }
}
```

### Warning Examples

| Scenario | Type | Message |
|----------|------|---------|
| CW on 14.230 | activityConflict | "14.230 MHz is the SSTV calling frequency" / "You're in CW mode - SSTV uses USB" |
| SSB on 14.074 | activityConflict | "14.074 MHz is the FT8 frequency" / "FT8 uses USB with digital software" |
| CW on 14.060 | activityInfo | "14.060 MHz is the QRP CW calling frequency" |
| CW on 7.030 during CWT | activityCrowded | "CWOps CWT is active until 1400Z" / "Expect heavy CW traffic 7.028-7.045 MHz" |
| SSB on 14.336 | activityInfo | "14.336 MHz is the County Hunters Net frequency" |

## Service Layer

### BandPlanService Extensions

```swift
extension BandPlanService {
    /// Full frequency validation - returns all applicable warnings sorted by priority
    static func validateFrequency(
        frequencyMHz: Double,
        mode: String,
        license: LicenseClass
    ) -> [FrequencyWarning]
    
    /// Check for activity-related warnings
    private static func checkActivityWarnings(
        frequencyMHz: Double,
        mode: String
    ) -> [FrequencyWarning]
    
    /// Check if currently within a CWT time window (with 15-min buffer)
    static func isWithinCWTWindow() -> Bool
    
    /// Find activities near a frequency
    static func activitiesNear(frequencyMHz: Double) -> [FrequencyActivity]
}
```

## UI Changes

### FrequencyWarningBanner

Rename `LicenseWarningBanner.swift` to `FrequencyWarningBanner.swift`:

```swift
struct FrequencyWarningBanner: View {
    let warning: FrequencyWarning
    let onDismiss: (() -> Void)?
    
    // Color scheme by warning type:
    // - noPrivileges: orange background, orange icon
    // - wrongMode, outOfBand: red background, red icon
    // - activityConflict, activityCrowded: yellow background, amber icon
    // - unusualFrequency, activityInfo: blue background, blue icon
}
```

### LoggerView Integration

```swift
private var currentWarning: FrequencyWarning? {
    guard let session = sessionManager?.activeSession,
          let freq = session.frequency else { return nil }
    
    let warnings = BandPlanService.validateFrequency(
        frequencyMHz: freq,
        mode: session.mode,
        license: userLicenseClass
    )
    
    return warnings.first { $0.message != dismissedWarning }
}
```

## Nearby Operators (Separate Feature)

Nearby operator detection will NOT use the warning banner. Instead, enhance the existing `FrequencyActivityView` panel to highlight crowded frequencies when the user has selected one. This keeps the warning banner focused on "you might be doing something wrong" rather than informational clutter.

## File Changes

| File | Change |
|------|--------|
| `CarrierWave/Models/BandPlan.swift` | Add `FrequencyActivity`, `TimeWindow` structs and activity data |
| `CarrierWave/Services/BandPlanService.swift` | Add `FrequencyWarning` type, `validateFrequency()`, activity checking |
| `CarrierWave/Views/Logger/LicenseWarningBanner.swift` | Rename to `FrequencyWarningBanner.swift`, update for unified warnings |
| `CarrierWave/Views/Logger/LoggerView.swift` | Update to use `FrequencyWarning` and new banner |
| `docs/FILE_INDEX.md` | Update file reference |

## Backward Compatibility

- `BandPlanViolation` will be deprecated but remain functional
- Existing `validate()` method will internally delegate to new `validateFrequency()`
- No breaking changes to external API

## Testing Considerations

- Unit tests for activity matching with various tolerances
- Unit tests for CWT time window detection across timezone boundaries
- Unit tests for warning priority sorting
- UI tests for banner display and dismissal
