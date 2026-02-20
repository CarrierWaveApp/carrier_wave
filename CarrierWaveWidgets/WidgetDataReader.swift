import Foundation

// MARK: - WidgetShared

enum WidgetShared {
    enum Key {
        static let streakData = "widget.streakData"
        static let countData = "widget.countData"
        static let sessionData = "widget.sessionData"
        static let solarData = "widget.solarData"
        static let spotsData = "widget.spotsData"
    }

    enum DeepLink {
        static let activityLog = "carrierwave://activitylog"
        static let dashboard = "carrierwave://dashboard"
        static let logger = "carrierwave://logger"
    }

    static let appGroupID = "group.com.jsvana.FullDuplex"
    static let suiteName = appGroupID
}

// MARK: - WidgetStreakSnapshot

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

// MARK: - WidgetSolarSnapshot

struct WidgetSolarSnapshot: Codable, Sendable {
    let kIndex: Double?
    let aIndex: Int?
    let solarFlux: Double?
    let sunspots: Int?
    let propagationRating: String?
    let updatedAt: Date
}

// MARK: - WidgetSpotSnapshot

struct WidgetSpotSnapshot: Codable, Sendable {
    let spots: [WidgetSpot]
    let updatedAt: Date
}

// MARK: - WidgetSpot

struct WidgetSpot: Codable, Sendable, Identifiable {
    let id: String
    let callsign: String
    let frequencyMHz: Double
    let mode: String
    let band: String
    let timestamp: Date
    let source: String
    let parkRef: String?
    let parkName: String?
    let snr: Int?
}

// MARK: - WidgetDataReader

enum WidgetDataReader {
    // MARK: Internal

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

    static func readSolar() -> WidgetSolarSnapshot? {
        guard let data = defaults?.data(forKey: WidgetShared.Key.solarData) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetSolarSnapshot.self, from: data)
    }

    static func readSpots() -> WidgetSpotSnapshot? {
        guard let data = defaults?.data(forKey: WidgetShared.Key.spotsData) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetSpotSnapshot.self, from: data)
    }

    // MARK: Private

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: WidgetShared.suiteName)
    }
}
