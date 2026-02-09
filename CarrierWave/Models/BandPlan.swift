// Band Plan Model
//
// US amateur radio band plan data with license class privileges.

import Foundation

// MARK: - LicenseClass

/// US amateur radio license classes
enum LicenseClass: String, Codable, CaseIterable, Sendable {
    case technician = "Technician"
    case general = "General"
    case extra = "Extra"

    // MARK: Internal

    /// Display name for the license class
    var displayName: String {
        rawValue
    }

    /// Short abbreviation
    var abbreviation: String {
        switch self {
        case .technician: "T"
        case .general: "G"
        case .extra: "E"
        }
    }
}

// MARK: - BandSegment

/// A segment of a band with specific privileges
struct BandSegment: Sendable {
    let band: String
    let startMHz: Double
    let endMHz: Double
    let modes: Set<String>
    let minimumLicense: LicenseClass
    let notes: String?

    /// Check if a frequency falls within this segment
    func contains(frequencyMHz: Double) -> Bool {
        frequencyMHz >= startMHz && frequencyMHz <= endMHz
    }

    /// Check if a mode is allowed in this segment
    func allowsMode(_ mode: String) -> Bool {
        modes.contains(mode.uppercased()) || modes.contains("ALL")
    }
}

// MARK: - TimeWindow

/// A recurring time window for scheduled activities (e.g., CWOps CWT)
struct TimeWindow: Sendable {
    /// Day of week (1=Sunday, 2=Monday, ..., 7=Saturday)
    let dayOfWeek: Int
    let startHourUTC: Int
    let startMinuteUTC: Int
    let durationMinutes: Int
    /// Buffer before/after the window to warn users
    let bufferMinutes: Int

    /// Check if a given date falls within this time window (including buffer)
    func contains(date: Date) -> Bool {
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
struct FrequencyActivity: Sendable {
    /// Type of activity
    enum ActivityType: String, Sendable {
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

    let type: ActivityType
    let band: String
    let centerMHz: Double
    /// ± tolerance in kHz for matching
    let toleranceKHz: Double
    /// Expected modes for this activity
    let modes: Set<String>
    let description: String
    /// For time-based activities like CWT
    let timeWindows: [TimeWindow]?

    /// Check if a frequency is within tolerance of this activity
    func matches(frequencyMHz: Double) -> Bool {
        let distanceKHz = abs(frequencyMHz - centerMHz) * 1_000
        return distanceKHz <= toleranceKHz
    }

    /// Check if the activity is currently active (for time-based activities)
    func isActive(at date: Date = Date()) -> Bool {
        guard let windows = timeWindows else {
            return true
        }
        return windows.contains { $0.contains(date: date) }
    }

    /// Check if a mode matches the expected modes for this activity
    func matchesMode(_ mode: String) -> Bool {
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
           ["FT8", "FT4", "PSK31", "PSK", "RTTY", "JS8", "WSPR"].contains(normalizedMode)
        {
            return true
        }
        return false
    }
}

// MARK: - CWTRange

/// A CWT frequency range (defined as offset from band edge)
struct CWTRange: Sendable {
    let band: String
    let bandEdgeMHz: Double
    let startOffsetKHz: Double
    let endOffsetKHz: Double

    var startMHz: Double {
        bandEdgeMHz + startOffsetKHz / 1_000
    }

    var endMHz: Double {
        bandEdgeMHz + endOffsetKHz / 1_000
    }

    func contains(frequencyMHz: Double) -> Bool {
        frequencyMHz >= startMHz && frequencyMHz <= endMHz
    }
}

// MARK: - BandPlan

/// US amateur radio band plan
enum BandPlan {
    // MARK: - HF Bands

    static let segments: [BandSegment] = [
        // 160 meters (1.8-2.0 MHz)
        BandSegment(
            band: "160m", startMHz: 1.800, endMHz: 2.000, modes: ["CW", "DATA"],
            minimumLicense: .extra, notes: "Extra only"
        ),
        BandSegment(
            band: "160m", startMHz: 1.800, endMHz: 2.000, modes: ["CW", "DATA"],
            minimumLicense: .general, notes: nil
        ),

        // 80 meters (3.5-4.0 MHz)
        BandSegment(
            band: "80m", startMHz: 3.500, endMHz: 3.600, modes: ["CW", "DATA"],
            minimumLicense: .extra, notes: "Extra CW/Data"
        ),
        BandSegment(
            band: "80m", startMHz: 3.525, endMHz: 3.600, modes: ["CW", "DATA"],
            minimumLicense: .general, notes: "General CW/Data"
        ),
        BandSegment(
            band: "80m", startMHz: 3.525, endMHz: 3.600, modes: ["CW"],
            minimumLicense: .technician, notes: "Tech CW only"
        ),
        BandSegment(
            band: "80m", startMHz: 3.800, endMHz: 4.000, modes: ["SSB", "PHONE"],
            minimumLicense: .extra, notes: "Extra Phone"
        ),
        BandSegment(
            band: "80m", startMHz: 3.800, endMHz: 4.000, modes: ["SSB", "PHONE"],
            minimumLicense: .general, notes: "General Phone"
        ),

        // 60 meters (5 MHz) - Channelized
        BandSegment(
            band: "60m", startMHz: 5.332, endMHz: 5.332, modes: ["USB", "CW", "DATA"],
            minimumLicense: .general, notes: "Channel 1"
        ),
        BandSegment(
            band: "60m", startMHz: 5.348, endMHz: 5.348, modes: ["USB", "CW", "DATA"],
            minimumLicense: .general, notes: "Channel 2"
        ),
        BandSegment(
            band: "60m", startMHz: 5.358, endMHz: 5.358, modes: ["USB", "CW", "DATA"],
            minimumLicense: .general, notes: "Channel 3"
        ),
        BandSegment(
            band: "60m", startMHz: 5.373, endMHz: 5.373, modes: ["USB", "CW", "DATA"],
            minimumLicense: .general, notes: "Channel 4"
        ),
        BandSegment(
            band: "60m", startMHz: 5.405, endMHz: 5.405, modes: ["USB", "CW", "DATA"],
            minimumLicense: .general, notes: "Channel 5"
        ),

        // 40 meters (7.0-7.3 MHz)
        BandSegment(
            band: "40m", startMHz: 7.000, endMHz: 7.025, modes: ["CW", "DATA"],
            minimumLicense: .extra, notes: "Extra CW/Data"
        ),
        BandSegment(
            band: "40m", startMHz: 7.025, endMHz: 7.125, modes: ["CW", "DATA"],
            minimumLicense: .general, notes: "General CW/Data"
        ),
        BandSegment(
            band: "40m", startMHz: 7.025, endMHz: 7.125, modes: ["CW"],
            minimumLicense: .technician, notes: "Tech CW only"
        ),
        BandSegment(
            band: "40m", startMHz: 7.125, endMHz: 7.175, modes: ["SSB", "PHONE"],
            minimumLicense: .extra, notes: "Extra Phone"
        ),
        BandSegment(
            band: "40m", startMHz: 7.175, endMHz: 7.300, modes: ["SSB", "PHONE"],
            minimumLicense: .general, notes: "General Phone"
        ),

        // 30 meters (10.1-10.15 MHz) - CW and Data only
        BandSegment(
            band: "30m", startMHz: 10.100, endMHz: 10.150, modes: ["CW", "DATA"],
            minimumLicense: .general, notes: "CW/Data only"
        ),

        // 20 meters (14.0-14.35 MHz)
        BandSegment(
            band: "20m", startMHz: 14.000, endMHz: 14.025, modes: ["CW", "DATA"],
            minimumLicense: .extra, notes: "Extra CW/Data"
        ),
        BandSegment(
            band: "20m", startMHz: 14.025, endMHz: 14.150, modes: ["CW", "DATA"],
            minimumLicense: .general, notes: "General CW/Data"
        ),
        BandSegment(
            band: "20m", startMHz: 14.150, endMHz: 14.175, modes: ["SSB", "PHONE"],
            minimumLicense: .extra, notes: "Extra Phone"
        ),
        BandSegment(
            band: "20m", startMHz: 14.175, endMHz: 14.225, modes: ["SSB", "PHONE"],
            minimumLicense: .extra, notes: "Extra Phone"
        ),
        BandSegment(
            band: "20m", startMHz: 14.225, endMHz: 14.350, modes: ["SSB", "PHONE"],
            minimumLicense: .general, notes: "General Phone"
        ),

        // 17 meters (18.068-18.168 MHz)
        BandSegment(
            band: "17m", startMHz: 18.068, endMHz: 18.110, modes: ["CW", "DATA"],
            minimumLicense: .general, notes: "CW/Data"
        ),
        BandSegment(
            band: "17m", startMHz: 18.110, endMHz: 18.168, modes: ["SSB", "PHONE"],
            minimumLicense: .general, notes: "Phone"
        ),

        // 15 meters (21.0-21.45 MHz)
        BandSegment(
            band: "15m", startMHz: 21.000, endMHz: 21.025, modes: ["CW", "DATA"],
            minimumLicense: .extra, notes: "Extra CW/Data"
        ),
        BandSegment(
            band: "15m", startMHz: 21.025, endMHz: 21.200, modes: ["CW", "DATA"],
            minimumLicense: .general, notes: "General CW/Data"
        ),
        BandSegment(
            band: "15m", startMHz: 21.025, endMHz: 21.200, modes: ["CW"],
            minimumLicense: .technician, notes: "Tech CW only"
        ),
        BandSegment(
            band: "15m", startMHz: 21.200, endMHz: 21.225, modes: ["SSB", "PHONE"],
            minimumLicense: .extra, notes: "Extra Phone"
        ),
        BandSegment(
            band: "15m", startMHz: 21.225, endMHz: 21.275, modes: ["SSB", "PHONE"],
            minimumLicense: .extra, notes: "Extra Phone"
        ),
        BandSegment(
            band: "15m", startMHz: 21.275, endMHz: 21.450, modes: ["SSB", "PHONE"],
            minimumLicense: .general, notes: "General Phone"
        ),

        // 12 meters (24.89-24.99 MHz)
        BandSegment(
            band: "12m", startMHz: 24.890, endMHz: 24.930, modes: ["CW", "DATA"],
            minimumLicense: .general, notes: "CW/Data"
        ),
        BandSegment(
            band: "12m", startMHz: 24.930, endMHz: 24.990, modes: ["SSB", "PHONE"],
            minimumLicense: .general, notes: "Phone"
        ),

        // 10 meters (28.0-29.7 MHz)
        BandSegment(
            band: "10m", startMHz: 28.000, endMHz: 28.300, modes: ["CW", "DATA"],
            minimumLicense: .general, notes: "CW/Data"
        ),
        BandSegment(
            band: "10m", startMHz: 28.000, endMHz: 28.300, modes: ["CW", "DATA"],
            minimumLicense: .technician, notes: "Tech CW only"
        ),
        BandSegment(
            band: "10m", startMHz: 28.300, endMHz: 28.500, modes: ["CW", "SSB", "PHONE"],
            minimumLicense: .general, notes: "CW/Phone"
        ),
        BandSegment(
            band: "10m", startMHz: 28.300, endMHz: 28.500, modes: ["CW", "SSB", "PHONE"],
            minimumLicense: .technician, notes: "Tech CW/Phone"
        ),

        // VHF/UHF (Technician+ full privileges)
        BandSegment(
            band: "6m", startMHz: 50.000, endMHz: 54.000, modes: ["ALL"],
            minimumLicense: .technician, notes: nil
        ),
        BandSegment(
            band: "2m", startMHz: 144.000, endMHz: 148.000, modes: ["ALL"],
            minimumLicense: .technician, notes: nil
        ),
        BandSegment(
            band: "70cm", startMHz: 420.000, endMHz: 450.000, modes: ["ALL"],
            minimumLicense: .technician, notes: nil
        ),
    ]

    // MARK: - Common CW Frequencies

    static let cwCallingFrequencies: [String: Double] = [
        "160m": 1.810,
        "80m": 3.560,
        "40m": 7.030,
        "30m": 10.116,
        "20m": 14.060,
        "17m": 18.080,
        "15m": 21.060,
        "12m": 24.910,
        "10m": 28.060,
    ]

    // MARK: - Common SSB Frequencies

    static let ssbCallingFrequencies: [String: Double] = [
        "80m": 3.885,
        "40m": 7.185,
        "20m": 14.285,
        "17m": 18.145,
        "15m": 21.385,
        "12m": 24.950,
        "10m": 28.400,
    ]
}
