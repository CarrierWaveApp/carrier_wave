// Band Plan Model
//
// US amateur radio band plan data with license class privileges.
// BandPlan.segments delegates to `cw-domain::band_plan` via the UniFFI surface.
// TimeWindow, FrequencyActivity, and CWTRange remain Swift-only (view-layer
// scheduling data not yet ported to Rust).

import CarrierWaveCwFfi
import Foundation

// MARK: - LicenseClass

/// US FCC amateur radio license classes. Segment filtering in
/// `BandPlan.segments` is keyed on this enum, so this type only makes
/// sense for operators in the USA. For non-USA operators, use
/// `AmateurLicenseScheme` to decide whether to apply privilege
/// filtering at all before consulting this enum.
public enum LicenseClass: String, Codable, CaseIterable, Sendable {
    case technician = "Technician"
    case general = "General"
    case extra = "Extra"

    // MARK: Public

    /// Display name for the license class
    public var displayName: String {
        rawValue
    }

    /// Short abbreviation
    public var abbreviation: String {
        switch self {
        case .technician: "T"
        case .general: "G"
        case .extra: "E"
        }
    }
}

// MARK: - BandSegment

/// A segment of a band with specific privileges
public struct BandSegment: Sendable {
    // MARK: Lifecycle

    public init(
        band: String,
        startMHz: Double,
        endMHz: Double,
        modes: Set<String>,
        minimumLicense: LicenseClass,
        notes: String?
    ) {
        self.band = band
        self.startMHz = startMHz
        self.endMHz = endMHz
        self.modes = modes
        self.minimumLicense = minimumLicense
        self.notes = notes
    }

    // MARK: Public

    public let band: String
    public let startMHz: Double
    public let endMHz: Double
    public let modes: Set<String>
    public let minimumLicense: LicenseClass
    public let notes: String?

    /// Check if a frequency falls within this segment
    public func contains(frequencyMHz: Double) -> Bool {
        frequencyMHz >= startMHz && frequencyMHz <= endMHz
    }

    /// Check if a mode is allowed in this segment
    public func allowsMode(_ mode: String) -> Bool {
        modes.contains(mode.uppercased()) || modes.contains("ALL")
    }
}

// MARK: - TimeWindow

/// A recurring time window for scheduled activities (e.g., CWOps CWT)
public struct TimeWindow: Sendable {
    // MARK: Lifecycle

    public init(
        dayOfWeek: Int,
        startHourUTC: Int,
        startMinuteUTC: Int,
        durationMinutes: Int,
        bufferMinutes: Int
    ) {
        self.dayOfWeek = dayOfWeek
        self.startHourUTC = startHourUTC
        self.startMinuteUTC = startMinuteUTC
        self.durationMinutes = durationMinutes
        self.bufferMinutes = bufferMinutes
    }

    // MARK: Public

    /// Day of week (1=Sunday, 2=Monday, ..., 7=Saturday)
    public let dayOfWeek: Int
    public let startHourUTC: Int
    public let startMinuteUTC: Int
    public let durationMinutes: Int
    /// Buffer before/after the window to warn users
    public let bufferMinutes: Int

    /// Check if a given date falls within this time window (including buffer)
    public func contains(date: Date) -> Bool {
        let calendar = Calendar(identifier: .gregorian)
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!

        let components = utcCalendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = components.weekday,
              let hour = components.hour,
              let minute = components.minute
        else {
            return false
        }

        // Check if day matches
        guard weekday == dayOfWeek else {
            return false
        }

        // Convert to minutes since midnight for easier comparison
        let currentMinutes = hour * 60 + minute
        let windowStart = startHourUTC * 60 + startMinuteUTC - bufferMinutes
        let windowEnd = startHourUTC * 60 + startMinuteUTC + durationMinutes + bufferMinutes

        return currentMinutes >= windowStart && currentMinutes <= windowEnd
    }
}

// MARK: - FrequencyActivity

/// A special-purpose frequency or frequency range for common activities
public struct FrequencyActivity: Sendable {
    // MARK: Lifecycle

    public init(
        type: ActivityType,
        band: String,
        centerMHz: Double,
        toleranceKHz: Double,
        modes: Set<String>,
        description: String,
        timeWindows: [TimeWindow]?
    ) {
        self.type = type
        self.band = band
        self.centerMHz = centerMHz
        self.toleranceKHz = toleranceKHz
        self.modes = modes
        self.description = description
        self.timeWindows = timeWindows
    }

    // MARK: Public

    /// Type of activity
    public enum ActivityType: String, Sendable {
        case qrpCW = "QRP CW"
        case qrpSSB = "QRP SSB"
        case ssbCalling = "SSB Calling"
        case amCalling = "AM Calling"
        case fmSimplex = "FM Simplex"
        case sstv = "SSTV"
        case digitalFT = "FT8/FT4"
        case digitalPSK = "PSK31"
        case rtty = "RTTY"
        case cwtContest = "CWOps CWT"
        case net = "Net"
    }

    public let type: ActivityType
    public let band: String
    public let centerMHz: Double
    /// ± tolerance in kHz for matching
    public let toleranceKHz: Double
    /// Expected modes for this activity
    public let modes: Set<String>
    public let description: String
    /// For time-based activities like CWT
    public let timeWindows: [TimeWindow]?

    /// Check if a frequency is within tolerance of this activity
    public func matches(frequencyMHz: Double) -> Bool {
        let distanceKHz = abs(frequencyMHz - centerMHz) * 1_000
        return distanceKHz <= toleranceKHz
    }

    /// Check if the activity is currently active (for time-based activities)
    public func isActive(at date: Date = Date()) -> Bool {
        guard let windows = timeWindows else {
            return true
        }
        return windows.contains { $0.contains(date: date) }
    }

    /// Check if a mode matches the expected modes for this activity
    public func matchesMode(_ mode: String) -> Bool {
        let normalizedMode = mode.uppercased()
        // Check direct match
        if modes.contains(normalizedMode) {
            return true
        }
        // Check phone mode variants
        if modes.contains("SSB"), ["LSB", "USB", "PHONE"].contains(normalizedMode) {
            return true
        }
        if modes.contains("USB"), normalizedMode == "SSB" {
            return true
        }
        // Check digital mode variants
        if modes.contains("DATA"),
           ["FT8", "FT4", "PSK31", "PSK", "RTTY", "JTTY", "JS8", "WSPR"].contains(normalizedMode)
        {
            return true
        }
        return false
    }
}

// MARK: - CWTRange

/// A CWT frequency range (defined as offset from band edge)
public struct CWTRange: Sendable {
    // MARK: Lifecycle

    public init(band: String, bandEdgeMHz: Double, startOffsetKHz: Double, endOffsetKHz: Double) {
        self.band = band
        self.bandEdgeMHz = bandEdgeMHz
        self.startOffsetKHz = startOffsetKHz
        self.endOffsetKHz = endOffsetKHz
    }

    // MARK: Public

    public let band: String
    public let bandEdgeMHz: Double
    public let startOffsetKHz: Double
    public let endOffsetKHz: Double

    public var startMHz: Double {
        bandEdgeMHz + startOffsetKHz / 1_000
    }

    public var endMHz: Double {
        bandEdgeMHz + endOffsetKHz / 1_000
    }

    public func contains(frequencyMHz: Double) -> Bool {
        frequencyMHz >= startMHz && frequencyMHz <= endMHz
    }
}

// MARK: - BandPlan

/// US amateur radio band plan
public enum BandPlan {
    public static let segments: [BandSegment] = bandPlanSegments().map { seg in
        BandSegment(
            band: seg.band,
            startMHz: seg.startMhz,
            endMHz: seg.endMhz,
            modes: Set(seg.modes),
            minimumLicense: liftLicenseClass(seg.minimumLicense),
            notes: seg.notes
        )
    }
}

// MARK: - Private helpers

private extension BandPlan {
    static func liftLicenseClass(_ ffi: FfiLicenseClass) -> LicenseClass {
        switch ffi {
        case .technician: .technician
        case .general: .general
        case .extra: .extra
        }
    }
}
