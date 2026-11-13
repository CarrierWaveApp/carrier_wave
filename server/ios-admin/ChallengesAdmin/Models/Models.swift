import Foundation

// MARK: - HealthResponse

struct HealthResponse: Decodable {
    let status: String
    let version: String
    let rbn: RbnHealth?
}

// MARK: - RbnHealth

struct RbnHealth: Decodable {
    let connected: Bool
    let spotsInStore: Int
    let oldestSpot: Date?
    let spotsPerMinute: Double
}

// MARK: - ChallengesListResponse

struct ChallengesListResponse: Decodable {
    let challenges: [ChallengeListItem]
    let total: Int
    let limit: Int
    let offset: Int
}

// MARK: - ChallengeListItem

struct ChallengeListItem: Decodable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let category: String
    let type: String
    let participantCount: Int
    let isActive: Bool
}

// MARK: - SpotsListResponse

struct SpotsListResponse: Decodable {
    let spots: [SpotItem]
    let pagination: SpotsPagination
}

// MARK: - SpotItem

struct SpotItem: Decodable, Identifiable {
    let id: String
    let callsign: String
    let programSlug: String?
    let source: String
    let frequencyKhz: Double?
    let mode: String?
    let reference: String?
    let referenceName: String?
    let spottedAt: Date?
}

// MARK: - SpotsPagination

struct SpotsPagination: Decodable {
    let hasMore: Bool
    let nextCursor: String?
}

// MARK: - PotaSyncStatusResponse

struct PotaSyncStatusResponse: Decodable {
    let totalParks: Int
    let parksFetched: Int
    let parksPending: Int
    let completionPercentage: Double
    let oldestFetch: Date?
    let newestFetch: Date?
    let warning: String?
}

// MARK: - ParkBoundariesStatusResponse

struct ParkBoundariesStatusResponse: Decodable {
    let totalParks: Int
    let totalCached: Int
    let unfetched: Int
    let completionPercentage: Int
    let byCountry: BoundaryCountryStats
    let exactMatches: Int
    let spatialMatches: Int
    let manualMatches: Int
    let noMatches: Int?
    let oldestFetch: String?
    let newestFetch: String?
}

// MARK: - BoundaryCountryStats

struct BoundaryCountryStats: Decodable {
    let us: BoundaryCountryStat
    let uk: BoundaryCountryStat
    let it: BoundaryCountryStat
    let pl: BoundaryCountryStat
}

// MARK: - BoundaryCountryStat

struct BoundaryCountryStat: Decodable {
    let totalParks: Int
}

// MARK: - TrailStatusResponse

struct TrailStatusResponse: Decodable {
    let totalCatalog: Int
    let totalCached: Int
    let unfetched: Int
    let completionPercentage: Int
    let exactMatches: Int
    let spatialMatches: Int
    let manualMatches: Int
    let oldestFetch: String?
    let newestFetch: String?
}

// MARK: - ProgramListResponse

struct ProgramListResponse: Decodable {
    let programs: [ProgramResponse]
    let version: Int64
}

// MARK: - ProgramResponse

struct ProgramResponse: Decodable, Identifiable {
    let slug: String
    let name: String
    let shortName: String
    let icon: String
    let iconUrl: String?
    let website: String?
    let serverBaseUrl: String?
    let referenceLabel: String
    let referenceFormat: String?
    let referenceExample: String?
    let multiRefAllowed: Bool
    let activationThreshold: Int?
    let supportsRove: Bool
    let capabilities: [String]
    let isActive: Bool

    var id: String {
        slug
    }
}

// MARK: - CreateProgramRequest

struct CreateProgramRequest: Encodable {
    let slug: String
    let name: String
    let shortName: String
    let icon: String
    var website: String?
    let referenceLabel: String
    var referenceFormat: String?
    var referenceExample: String?
    var multiRefAllowed: Bool = false
    var activationThreshold: Int?
    var supportsRove: Bool = false
    var capabilities: [String] = []
    var sortOrder: Int = 0
}

// MARK: - UpdateProgramRequest

struct UpdateProgramRequest: Encodable {
    var name: String?
    var shortName: String?
    var icon: String?
    var website: String?
    var referenceLabel: String?
    var referenceFormat: String?
    var referenceExample: String?
    var multiRefAllowed: Bool?
    var activationThreshold: Int?
    var supportsRove: Bool?
    var capabilities: [String]?
    var sortOrder: Int?
    var isActive: Bool?
}

// MARK: - ClubAdminResponse

struct ClubAdminResponse: Decodable, Identifiable {
    let id: String
    let name: String
    let callsign: String?
    let description: String?
    let notesUrl: String?
    let notesTitle: String?
    let memberCount: Int
    let createdAt: Date?
    let updatedAt: Date?
}

// MARK: - ClubMemberAdminResponse

struct ClubMemberAdminResponse: Decodable, Identifiable {
    let callsign: String
    let role: String
    let joinedAt: Date
    let lastSeenAt: Date?
    let lastGrid: String?
    let isCarrierWaveUser: Bool

    var id: String {
        callsign
    }
}

// MARK: - CreateClubRequest

struct CreateClubRequest: Encodable {
    let name: String
    var callsign: String?
    var description: String?
}

// MARK: - UpdateClubRequest

struct UpdateClubRequest: Encodable {
    var name: String?
    var callsign: Nullable<String>?
    var description: Nullable<String>?
    var notesUrl: Nullable<String>?
    var notesTitle: Nullable<String>?
}

// MARK: - Nullable

/// Wrapper that encodes as `null` instead of being skipped by JSONEncoder.
/// - `Nullable<String>?.none` → key omitted (don't update)
/// - `Nullable<String>?.some(.null)` → `"key": null` (clear to NULL)
/// - `Nullable<String>?.some(.value("x"))` → `"key": "x"` (set value)
enum Nullable<T: Encodable>: Encodable {
    case null
    case value(T)

    // MARK: Internal

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .value(wrapped):
            try container.encode(wrapped)
        }
    }
}

// MARK: - ImportNotesResponse

struct ImportNotesResponse: Decodable {
    let imported: Int
    let skipped: Int
    /// Members dropped because they left the notes file (newer servers only).
    let removed: Int?
    let callsigns: [String]
    let removedCallsigns: [String]?
}

// MARK: - AdminStatsResponse

struct AdminStatsResponse: Decodable {
    let totalUsers: Int
    let usersLast7Days: Int
    let usersLast30Days: Int
}

// MARK: - UserCountByHour

struct UserCountByHour: Decodable, Identifiable {
    let hour: Date
    let count: Int

    var id: Date {
        hour
    }
}

// MARK: - EmptyBody

struct EmptyBody: Encodable {}

// MARK: - EventsListResponse

struct EventsListResponse: Decodable {
    let events: [EventListItem]
    let total: Int
    let limit: Int
    let offset: Int
}

// MARK: - EventListItem

struct EventListItem: Decodable, Identifiable {
    let id: String
    let name: String
    let eventType: String
    let startDate: Date
    let endDate: Date?
    let timezone: String
    let venueName: String?
    let city: String
    let state: String?
    let country: String
    let latitude: Double
    let longitude: Double
    let cost: String?
    let submittedBy: String
    let status: String
    let createdAt: Date
    let distanceMeters: Double?
}

// MARK: - EventDetailResponse

struct EventDetailResponse: Decodable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let eventType: String
    let startDate: Date
    let endDate: Date?
    let timezone: String
    let venueName: String?
    let address: String
    let city: String
    let state: String?
    let country: String
    let latitude: Double
    let longitude: Double
    let cost: String?
    let url: String?
    let submittedBy: String
    let status: String
    let reviewedBy: String?
    let reviewedAt: Date?
    let rejectionReason: String?
    let createdAt: Date
    let updatedAt: Date
}

// MARK: - ReviewEventRequest

struct ReviewEventRequest: Encodable {
    let action: String
    var reason: String?
}

// MARK: - UpdateEventRequest

struct UpdateEventRequest: Encodable {
    var name: String?
    var description: String?
    var eventType: String?
    var timezone: String?
    var venueName: String?
    var address: String?
    var city: String?
    var state: String?
    var country: String?
    var latitude: Double?
    var longitude: Double?
    var cost: String?
    var url: String?
}

// MARK: - SubmitterStatsResponse

struct SubmitterStatsResponse: Decodable {
    let totalSubmitted: Int
    let totalApproved: Int
    let totalRejected: Int
    let totalPending: Int
}

// MARK: - AddMembersRequest

struct AddMembersRequest: Encodable {
    let members: [AddMemberEntry]
}

// MARK: - AddMemberEntry

struct AddMemberEntry: Encodable {
    let callsign: String
    let role: String
}

// MARK: - TelemetrySummaryResponse

struct TelemetrySummaryResponse: Decodable {
    let totalErrors: Int
    let totalAffectedQsos: Int
    let uniqueCallsigns: Int
    let byService: [ServiceErrorCount]
    let byCategory: [CategoryErrorCount]
    let dailyTrend: [DailyErrorCount]
    let recentErrors: [RecentError]
}

// MARK: - ServiceErrorCount

struct ServiceErrorCount: Decodable, Identifiable {
    let service: String
    let errorCount: Int
    let affectedQsos: Int

    var id: String {
        service
    }
}

// MARK: - CategoryErrorCount

struct CategoryErrorCount: Decodable, Identifiable {
    let category: String
    let errorCount: Int
    let affectedQsos: Int

    var id: String {
        category
    }
}

// MARK: - DailyErrorCount

struct DailyErrorCount: Decodable, Identifiable {
    let date: String
    let errorCount: Int
    let affectedQsos: Int

    var id: String {
        date
    }
}

// MARK: - RecentError

struct RecentError: Decodable, Identifiable {
    let service: String
    let category: String
    let messageHash: String
    let affectedCount: Int
    let isTransient: Bool
    let appVersion: String
    let osVersion: String
    let callsign: String
    let createdAt: Date

    var id: String {
        "\(callsign)-\(createdAt)-\(messageHash)"
    }
}
