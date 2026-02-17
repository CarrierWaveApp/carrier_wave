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
    }

    /// Deep link URLs
    enum DeepLink {
        static let activityLog = "carrierwave://activitylog"
        static let dashboard = "carrierwave://dashboard"
        static let logger = "carrierwave://logger"
    }

    static let appGroupID = "group.com.jsvana.FullDuplex"
    static let suiteName = appGroupID
}

// MARK: - WidgetStreakSnapshot

/// Pre-computed streak data for the widget
struct WidgetStreakSnapshot: Codable, Sendable {
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
}

// MARK: - WidgetCountSnapshot

/// Pre-computed count data for the widget
struct WidgetCountSnapshot: Codable, Sendable {
    let qsosWeek: Int
    let qsosMonth: Int
    let qsosYear: Int
    let activationsMonth: Int
    let activationsYear: Int
    let huntsWeek: Int
    let huntsMonth: Int
    let newDXCCYear: Int
    let updatedAt: Date
}

// MARK: - WidgetSessionSnapshot

/// Current session data for the widget
struct WidgetSessionSnapshot: Codable, Sendable {
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

// MARK: - WidgetDataWriter

/// Writes pre-computed data to shared UserDefaults for widget consumption.
/// Call from the main app after stats computation or session state changes.
enum WidgetDataWriter {
    // MARK: Internal

    static func writeStreaks(_ snapshot: WidgetStreakSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults?.set(data, forKey: WidgetShared.Key.streakData)
        WidgetCenter.shared.reloadTimelines(ofKind: "StatsWidget")
    }

    static func writeCounts(_ snapshot: WidgetCountSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults?.set(data, forKey: WidgetShared.Key.countData)
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

    // MARK: Private

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: WidgetShared.suiteName)
    }
}
