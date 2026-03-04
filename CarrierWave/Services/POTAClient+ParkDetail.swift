// POTA Park Detail API
//
// Public (unauthenticated) POTA API endpoints for park stats,
// leaderboards, and recent activations. Uses explicit nonisolated
// Decodable inits to avoid MainActor isolation in strict concurrency.

import CarrierWaveData
import Foundation

// MARK: - POTAParkStatsResponse

/// Park-level stats from /park/stats/{ref}
struct POTAParkStatsResponse: Decodable, Sendable {
    // MARK: Lifecycle

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reference = try container.decode(String.self, forKey: .reference)
        attempts = try container.decode(Int.self, forKey: .attempts)
        activations = try container.decode(Int.self, forKey: .activations)
        contacts = try container.decode(Int.self, forKey: .contacts)
    }

    // MARK: Internal

    let reference: String
    let attempts: Int
    let activations: Int
    let contacts: Int

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case reference
        case attempts
        case activations
        case contacts
    }
}

// MARK: - POTALeaderboardEntry

/// Leaderboard entry (callsign + count)
struct POTALeaderboardEntry: Decodable, Sendable, Identifiable {
    // MARK: Lifecycle

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callsign = try container.decode(String.self, forKey: .callsign)
        count = try container.decode(Int.self, forKey: .count)
    }

    // MARK: Internal

    let callsign: String
    let count: Int

    var id: String {
        callsign
    }

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case callsign
        case count
    }
}

// MARK: - POTAParkLeaderboardResponse

/// Leaderboard from /park/leaderboard/{ref}
struct POTAParkLeaderboardResponse: Decodable, Sendable {
    // MARK: Lifecycle

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activations = try container.decode([POTALeaderboardEntry].self, forKey: .activations)
        activatorQsos = try container.decode([POTALeaderboardEntry].self, forKey: .activatorQsos)
        hunterQsos = try container.decode([POTALeaderboardEntry].self, forKey: .hunterQsos)
    }

    // MARK: Internal

    let activations: [POTALeaderboardEntry]
    let activatorQsos: [POTALeaderboardEntry]
    let hunterQsos: [POTALeaderboardEntry]

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case activations
        case activatorQsos = "activator_qsos"
        case hunterQsos = "hunter_qsos"
    }
}

// MARK: - POTAParkActivationEntry

/// Single activation entry from /park/activations/{ref}
struct POTAParkActivationEntry: Decodable, Sendable, Identifiable {
    // MARK: Lifecycle

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeCallsign = try container.decode(String.self, forKey: .activeCallsign)
        qsoDate = try container.decode(String.self, forKey: .qsoDate)
        totalQSOs = try container.decode(Int.self, forKey: .totalQSOs)
        qsosCW = try container.decode(Int.self, forKey: .qsosCW)
        qsosDATA = try container.decode(Int.self, forKey: .qsosDATA)
        qsosPHONE = try container.decode(Int.self, forKey: .qsosPHONE)
    }

    // MARK: Internal

    let activeCallsign: String
    let qsoDate: String
    let totalQSOs: Int
    let qsosCW: Int
    let qsosDATA: Int
    let qsosPHONE: Int

    var id: String {
        "\(activeCallsign)-\(qsoDate)-\(totalQSOs)"
    }

    /// Parse "20260214" into a Date
    var date: Date? {
        Self.dateParser.date(from: qsoDate)
    }

    /// Format as "Feb 14"
    var formattedDate: String {
        guard let date else {
            return qsoDate
        }
        return Self.displayFormatter.string(from: date)
    }

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case activeCallsign
        case qsoDate = "qso_date"
        case totalQSOs
        case qsosCW
        case qsosDATA
        case qsosPHONE
    }

    private static let dateParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}

// MARK: - ParkDetailLoader

/// Fetches public park data from the POTA API
actor ParkDetailLoader {
    // MARK: Internal

    func fetchStats(reference: String) async throws -> POTAParkStatsResponse {
        let url = URL(string: "\(Self.baseURL)/park/stats/\(reference)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(POTAParkStatsResponse.self, from: data)
    }

    func fetchLeaderboard(
        reference: String, count: Int = 5
    ) async throws -> POTAParkLeaderboardResponse {
        let url = URL(string: "\(Self.baseURL)/park/leaderboard/\(reference)?count=\(count)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(POTAParkLeaderboardResponse.self, from: data)
    }

    func fetchActivations(
        reference: String, count: Int = 5
    ) async throws -> [POTAParkActivationEntry] {
        let url = URL(string: "\(Self.baseURL)/park/activations/\(reference)?count=\(count)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([POTAParkActivationEntry].self, from: data)
    }

    // MARK: Private

    private static let baseURL = "https://api.pota.app"
}
