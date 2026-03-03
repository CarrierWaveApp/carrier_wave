import Foundation

// MARK: - ActivitiesClient Clubs Extension

extension ActivitiesClient {
    // MARK: - Club Endpoints

    /// Get list of clubs the user belongs to
    func getMyClubs(sourceURL: String, authToken: String) async throws -> [ClubDTO] {
        let url = try buildURL(sourceURL, path: "/v1/clubs")
        let request = try buildRequest(url: url, method: "GET", authToken: authToken)

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        let apiResponse = try JSONDecoder.activitiesDecoder.decode(
            APIResponse<[ClubDTO]>.self,
            from: data
        )
        return apiResponse.data
    }

    /// Get detailed information about a specific club
    func getClubDetails(
        clubId: UUID,
        sourceURL: String,
        authToken: String,
        includeMembers: Bool = true
    ) async throws -> ClubDetailDTO {
        guard var components = URLComponents(
            string: sourceURL + "/v1/clubs/\(clubId.uuidString)"
        ) else {
            throw ActivitiesError.invalidServerURL
        }

        components.queryItems = [
            URLQueryItem(name: "includeMembers", value: String(includeMembers)),
        ]

        guard let url = components.url else {
            throw ActivitiesError.invalidServerURL
        }

        let request = try buildRequest(url: url, method: "GET", authToken: authToken)

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        let apiResponse = try JSONDecoder.activitiesDecoder.decode(
            APIResponse<ClubDetailDTO>.self,
            from: data
        )
        return apiResponse.data
    }

    /// Get club activity feed
    func fetchClubActivity(
        clubId: UUID,
        sourceURL: String,
        authToken: String,
        cursor: String? = nil,
        limit: Int = 20
    ) async throws -> ClubActivityResponseDTO {
        guard var components = URLComponents(
            string: sourceURL + "/v1/clubs/\(clubId.uuidString)/activity"
        ) else {
            throw ActivitiesError.invalidServerURL
        }

        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw ActivitiesError.invalidServerURL
        }

        let request = try buildRequest(url: url, method: "GET", authToken: authToken)

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        let apiResponse = try JSONDecoder.activitiesDecoder.decode(
            APIResponse<ClubActivityResponseDTO>.self,
            from: data
        )
        return apiResponse.data
    }

    /// Get club member status (on-air, recently active, etc.)
    func fetchClubStatus(
        clubId: UUID,
        sourceURL: String,
        authToken: String
    ) async throws -> [MemberStatusDTO] {
        let url = try buildURL(
            sourceURL,
            path: "/v1/clubs/\(clubId.uuidString)/status"
        )
        let request = try buildRequest(url: url, method: "GET", authToken: authToken)

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        let apiResponse = try JSONDecoder.activitiesDecoder.decode(
            APIResponse<[MemberStatusDTO]>.self,
            from: data
        )
        return apiResponse.data
    }
}

// MARK: - ClubDTO

struct ClubDTO: Codable {
    var id: UUID
    var name: String
    var callsign: String?
    var description: String?
    var notesUrl: String?
    var notesTitle: String?
    var memberCount: Int
}

// MARK: - ClubDetailDTO

struct ClubDetailDTO: Codable {
    var id: UUID
    var name: String
    var callsign: String?
    var description: String?
    var notesUrl: String?
    var notesTitle: String?
    var members: [ClubMemberDTO]?
}

// MARK: - ClubMemberDTO

struct ClubMemberDTO: Codable {
    var callsign: String
    var role: String
    var joinedAt: Date?
    var lastSeenAt: Date?
    var lastGrid: String?
    var isCarrierWaveUser: Bool
}

// MARK: - ClubActivityResponseDTO

struct ClubActivityResponseDTO: Codable {
    var items: [ClubActivityItemDTO]
    var pagination: ClubActivityPaginationDTO
}

// MARK: - ClubActivityItemDTO

struct ClubActivityItemDTO: Codable, Identifiable {
    var id: UUID
    var callsign: String
    var activityType: String
    var timestamp: Date
    var details: ReportActivityDetails
    var createdAt: Date
}

// MARK: - ClubActivityPaginationDTO

struct ClubActivityPaginationDTO: Codable {
    var hasMore: Bool
    var nextCursor: String?
}

// MARK: - MemberStatusDTO

struct MemberStatusDTO: Codable {
    var callsign: String
    var status: MemberOnlineStatus
    var spotInfo: SpotInfoDTO?
    var lastSeenAt: Date?
}

// MARK: - MemberOnlineStatus

enum MemberOnlineStatus: String, Codable {
    case onAir
    case recentlyActive
    case inactive
}

// MARK: - SpotInfoDTO

struct SpotInfoDTO: Codable {
    var frequency: Double
    var mode: String?
    var source: String
    var spottedAt: Date
}
