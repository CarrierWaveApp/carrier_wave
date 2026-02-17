import Foundation

// MARK: - Shared Constants (must stay in sync with WidgetDataWriter in main app)

enum WidgetShared {
    static let appGroupID = "group.com.jsvana.FullDuplex"
    static let suiteName = appGroupID

    enum Key {
        static let streakData = "widget.streakData"
        static let countData = "widget.countData"
        static let sessionData = "widget.sessionData"
    }

    enum DeepLink {
        static let activityLog = "carrierwave://activitylog"
        static let dashboard = "carrierwave://dashboard"
        static let logger = "carrierwave://logger"
    }
}

// MARK: - Shared Codable Types (must stay in sync with WidgetDataWriter)

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

// MARK: - WidgetDataReader

enum WidgetDataReader {
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: WidgetShared.suiteName)
    }

    static func readStreaks() -> WidgetStreakSnapshot? {
        guard let data = defaults?.data(forKey: WidgetShared.Key.streakData) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetStreakSnapshot.self, from: data)
    }

    static func readCounts() -> WidgetCountSnapshot? {
        guard let data = defaults?.data(forKey: WidgetShared.Key.countData) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetCountSnapshot.self, from: data)
    }

    static func readSession() -> WidgetSessionSnapshot? {
        guard let data = defaults?.data(forKey: WidgetShared.Key.sessionData) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetSessionSnapshot.self, from: data)
    }
}
