import Foundation

// MARK: - WatchShared

/// Shared constants and Codable types for Watch ↔ iPhone communication.
/// Mirrors the WidgetShared types from the main app — keep in sync.
enum WatchShared {
    enum Key {
        static let streakData = "widget.streakData"
        static let countData = "widget.countData"
        static let sessionData = "widget.sessionData"
        static let solarData = "widget.solarData"
        static let spotsData = "widget.spotsData"
    }

    static let appGroupID = "group.com.jsvana.FullDuplex"
}

// MARK: - WatchStreakSnapshot

struct WatchStreakSnapshot: Codable, Sendable {
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

// MARK: - WatchCountSnapshot

struct WatchCountSnapshot: Codable, Sendable {
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

// MARK: - WatchSessionSnapshot

struct WatchSessionSnapshot: Codable, Sendable {
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

// MARK: - WatchSolarSnapshot

struct WatchSolarSnapshot: Codable, Sendable {
    let kIndex: Double?
    let aIndex: Int?
    let solarFlux: Double?
    let sunspots: Int?
    let propagationRating: String?
    let updatedAt: Date
}

// MARK: - WatchSpotSnapshot

struct WatchSpotSnapshot: Codable, Sendable {
    let spots: [WatchSpot]
    let updatedAt: Date
}

// MARK: - WatchSpot

struct WatchSpot: Codable, Sendable, Identifiable {
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

// MARK: - SharedDataReader

/// Reads pre-computed data from the App Group shared UserDefaults.
/// Used by the Watch app to display data written by the iPhone app.
enum SharedDataReader {
    // MARK: Internal

    static func readStreaks() -> WatchStreakSnapshot? {
        read(WatchStreakSnapshot.self, forKey: WatchShared.Key.streakData)
    }

    static func readCounts() -> WatchCountSnapshot? {
        read(WatchCountSnapshot.self, forKey: WatchShared.Key.countData)
    }

    static func readSession() -> WatchSessionSnapshot? {
        read(WatchSessionSnapshot.self, forKey: WatchShared.Key.sessionData)
    }

    static func readSolar() -> WatchSolarSnapshot? {
        read(WatchSolarSnapshot.self, forKey: WatchShared.Key.solarData)
    }

    static func readSpots() -> WatchSpotSnapshot? {
        read(WatchSpotSnapshot.self, forKey: WatchShared.Key.spotsData)
    }

    // MARK: Private

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: WatchShared.appGroupID)
    }

    private static func read<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults?.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }
}
