import CarrierWaveData
import Foundation
import WidgetKit

// MARK: - WidgetShared

/// Shared constants and Codable types used by both the main app and widget extension.
/// The widget extension duplicates these types — keep them in sync.
enum WidgetShared {
    /// UserDefaults keys
    enum Key {
        static let streakData = "widget.streakData"
        static let countData = "widget.countData"
        static let sessionData = "widget.sessionData"
        static let solarData = "widget.solarData"
        static let spaceWeatherData = "widget.spaceWeatherData"
        static let spotsData = "widget.spotsData"
    }

    /// Deep link URLs
    enum DeepLink {
        static let activityLog = "carrierwave://activitylog"
        static let conditions = "carrierwave://conditions"
        static let dashboard = "carrierwave://dashboard"
        static let logger = "carrierwave://logger"
    }

    static let appGroupID = "group.com.jsvana.FullDuplex"
    static let suiteName = appGroupID
}

// MARK: - WidgetStreakSnapshot

/// Pre-computed streak data for the widget
struct WidgetStreakSnapshot: Codable {
    let onAirCurrent: Int
    let onAirLongest: Int
    let onAirAtRisk: Bool
    let activationCurrent: Int
    let activationLongest: Int
    let activationAtRisk: Bool
    let hunterCurrent: Int
    let hunterLongest: Int
    let hunterAtRisk: Bool
    let cwCurrent: Int
    let phoneCurrent: Int
    let digitalCurrent: Int
    let updatedAt: Date

    /// Compare value-bearing fields, ignore `updatedAt`.
    /// Used by `WidgetDataWriter` to skip identical writes (CAR-244).
    func equalsIgnoringTimestamp(_ other: WidgetStreakSnapshot) -> Bool {
        onAirCurrent == other.onAirCurrent
            && onAirLongest == other.onAirLongest
            && onAirAtRisk == other.onAirAtRisk
            && activationCurrent == other.activationCurrent
            && activationLongest == other.activationLongest
            && activationAtRisk == other.activationAtRisk
            && hunterCurrent == other.hunterCurrent
            && hunterLongest == other.hunterLongest
            && hunterAtRisk == other.hunterAtRisk
            && cwCurrent == other.cwCurrent
            && phoneCurrent == other.phoneCurrent
            && digitalCurrent == other.digitalCurrent
    }
}

// MARK: - WidgetCountSnapshot

/// Pre-computed count data for the widget
struct WidgetCountSnapshot: Codable {
    let qsosWeek: Int
    let qsosMonth: Int
    let qsosYear: Int
    let activationsMonth: Int
    let activationsYear: Int
    let huntsWeek: Int
    let huntsMonth: Int
    let newDXCCYear: Int
    let updatedAt: Date

    /// Compare value-bearing fields, ignore `updatedAt`.
    /// Used by `WidgetDataWriter` to skip identical writes (CAR-244).
    func equalsIgnoringTimestamp(_ other: WidgetCountSnapshot) -> Bool {
        qsosWeek == other.qsosWeek
            && qsosMonth == other.qsosMonth
            && qsosYear == other.qsosYear
            && activationsMonth == other.activationsMonth
            && activationsYear == other.activationsYear
            && huntsWeek == other.huntsWeek
            && huntsMonth == other.huntsMonth
            && newDXCCYear == other.newDXCCYear
    }
}

// MARK: - WidgetSessionSnapshot

/// Current session data for the widget
struct WidgetSessionSnapshot: Codable {
    let isActive: Bool
    let parkReference: String?
    let parkName: String?
    let frequency: String?
    let mode: String?
    let qsoCount: Int
    let startedAt: Date?
    let lastCallsign: String?
    let activationType: String?
    let updatedAt: Date
}

// MARK: - WidgetSolarSnapshot

/// Solar conditions for Watch and widget consumption
struct WidgetSolarSnapshot: Codable {
    let kIndex: Double?
    let aIndex: Int?
    let solarFlux: Double?
    let sunspots: Int?
    let propagationRating: String?
    let updatedAt: Date
}

// MARK: - WidgetSpaceWeatherSnapshot

/// Compact summary of active space-weather events for widget consumption.
/// `worstImpactRaw` mirrors `RadioImpactLevel.rawValue` (0...4).
struct WidgetSpaceWeatherSnapshot: Codable {
    let worstImpactRaw: Int
    let eventCount: Int
    let headline: String
    let icon: String
    let updatedAt: Date
}

// MARK: - SharedSpotSnapshot

/// Recent spots for Watch/widget consumption via App Group
struct SharedSpotSnapshot: Codable {
    let spots: [SharedSpot]
    let updatedAt: Date
}

// MARK: - SharedSpot

/// A single spot in a format safe for Watch/widget consumption
struct SharedSpot: Codable, Identifiable {
    let id: String
    let callsign: String
    let frequencyMHz: Double
    let mode: String
    let band: String
    let timestamp: Date
    let source: String // "pota" or "rbn"
    let parkRef: String?
    let parkName: String?
    let snr: Int?
}

// MARK: - WidgetDataWriter

/// Writes pre-computed data to shared UserDefaults for widget/Watch consumption.
/// Call from the main app after stats computation or session state changes.
enum WidgetDataWriter {
    // MARK: Internal

    static func writeStreaks(_ snapshot: WidgetStreakSnapshot) {
        // CAR-244: writing the App-Group plist flushes the entire file, which
        // becomes a multi-MB burst at sync-tick frequency. Skip when the
        // value-bearing fields are unchanged.
        if let last = lastStreakSnapshot, last.equalsIgnoringTimestamp(snapshot) {
            return
        }
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults?.set(data, forKey: WidgetShared.Key.streakData)
        lastStreakSnapshot = snapshot
        WidgetCenter.shared.reloadTimelines(ofKind: "StatsWidget")
    }

    static func writeCounts(_ snapshot: WidgetCountSnapshot) {
        // CAR-244: see writeStreaks above.
        if let last = lastCountSnapshot, last.equalsIgnoringTimestamp(snapshot) {
            return
        }
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults?.set(data, forKey: WidgetShared.Key.countData)
        lastCountSnapshot = snapshot
        WidgetCenter.shared.reloadTimelines(ofKind: "StatsWidget")
    }

    static func writeSession(_ snapshot: WidgetSessionSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults?.set(data, forKey: WidgetShared.Key.sessionData)
        WidgetCenter.shared.reloadTimelines(ofKind: "ActiveSessionWidget")
    }

    /// Clear session data when no session is active
    static func clearSession() {
        let empty = WidgetSessionSnapshot(
            isActive: false, parkReference: nil, parkName: nil,
            frequency: nil, mode: nil, qsoCount: 0,
            startedAt: nil, lastCallsign: nil, activationType: nil,
            updatedAt: Date()
        )
        writeSession(empty)
    }

    static func writeSolar(_ snapshot: WidgetSolarSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults?.set(data, forKey: WidgetShared.Key.solarData)
        WidgetCenter.shared.reloadTimelines(ofKind: "SolarWidget")
    }

    static func writeSpaceWeather(_ snapshot: WidgetSpaceWeatherSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults?.set(data, forKey: WidgetShared.Key.spaceWeatherData)
        WidgetCenter.shared.reloadTimelines(ofKind: "SolarWidget")
    }

    static func writeSpots(_ snapshot: SharedSpotSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults?.set(data, forKey: WidgetShared.Key.spotsData)
    }

    // MARK: Private

    /// CAR-244: cached last-written snapshots so we can skip identical writes.
    /// Both fields are mutated only from the MainActor (the writers are called
    /// from `AsyncQSOStatistics` which is `@MainActor`).
    private static var lastStreakSnapshot: WidgetStreakSnapshot?
    private static var lastCountSnapshot: WidgetCountSnapshot?

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: WidgetShared.suiteName)
    }
}
