import Foundation

// MARK: - ActivitiesClient Activities Extension

extension ActivitiesClient {
    // MARK: - Report Activity

    /// Report a notable activity to the server
    func reportActivity(
        activity: ReportActivityRequest,
        sourceURL: String,
        authToken: String
    ) async throws -> ReportedActivityDTO {
        guard let url = URL(string: sourceURL + "/v1/activities") else {
            throw ActivitiesError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder.activitiesEncoder.encode(activity)

        let (data, response) = try await performActivityRequest(request)
        try validateActivityResponse(response, data: data)

        let apiResponse = try JSONDecoder.activitiesDecoder.decode(
            APIResponse<ReportedActivityDTO>.self,
            from: data
        )
        return apiResponse.data
    }

    // MARK: - Get Feed

    /// Fetch activity feed (friends + clubs)
    func getFeed(
        sourceURL: String,
        authToken: String,
        filter: FeedFilterType? = nil,
        limit: Int = 50,
        before: String? = nil
    ) async throws -> FeedResponseDTO {
        guard var components = URLComponents(string: sourceURL + "/v1/feed") else {
            throw ActivitiesError.invalidServerURL
        }

        var queryItems: [URLQueryItem] = []
        queryItems.append(URLQueryItem(name: "limit", value: String(limit)))

        if let filter {
            queryItems.append(URLQueryItem(name: "filter", value: filter.queryValue))
        }
        if let before {
            queryItems.append(URLQueryItem(name: "before", value: before))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw ActivitiesError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performActivityRequest(request)
        try validateActivityResponse(response, data: data)

        let apiResponse = try JSONDecoder.activitiesDecoder.decode(
            APIResponse<FeedResponseDTO>.self,
            from: data
        )
        return apiResponse.data
    }

    // MARK: Private

    private func performActivityRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw ActivitiesError.networkError(error)
        }
    }

    private func validateActivityResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ActivitiesError.invalidResponse("Not an HTTP response")
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder.activitiesDecoder.decode(
                APIErrorResponse.self,
                from: data
            ) {
                throw ActivitiesError.from(
                    apiCode: errorResponse.error.code,
                    message: errorResponse.error.message
                )
            }

            let message = String(data: data, encoding: .utf8)
            throw ActivitiesError.serverError(httpResponse.statusCode, message)
        }
    }
}

// MARK: - ReportActivityRequest

struct ReportActivityRequest: Codable {
    var type: String
    var timestamp: Date
    var details: ReportActivityDetails
}

// MARK: - ReportActivityDetails

struct ReportActivityDetails: Codable {
    var entityName: String?
    var entityCode: String?
    var band: String?
    var mode: String?
    var workedCallsign: String?
    var distanceKm: Double?
    var parkReference: String?
    var parkName: String?
    var qsoCount: Int?
    var streakDays: Int?
    var challengeId: String?
    var challengeName: String?
    var tierName: String?
    var recordType: String?
    var recordValue: String?

    // Session summary fields (for sessionCompleted)
    var sessionDurationMinutes: Int?
    var sessionBands: [String]?
    var sessionModes: [String]?
    var sessionDXCCCount: Int?
    var sessionFarthestKm: Double?
    var sessionActivationType: String?
    var sessionMyGrid: String?
    var sessionRig: String?
    var sessionAntenna: String?
    var sessionContactGrids: [ContactGridEntry]?
    var sessionTimeline: [TimelineEntry]?
}

// MARK: - ReportedActivityDTO

struct ReportedActivityDTO: Codable {
    var id: UUID
    var callsign: String
    var activityType: String
    var timestamp: Date
    var details: ReportActivityDetails
}

// MARK: - FeedFilterType

enum FeedFilterType {
    case friends
    case club(UUID)

    // MARK: Internal

    var queryValue: String {
        switch self {
        case .friends:
            "friends"
        case let .club(id):
            "club:\(id.uuidString)"
        }
    }
}

// MARK: - FeedResponseDTO

struct FeedResponseDTO: Codable {
    var items: [FeedItemDTO]
    var pagination: FeedPaginationDTO
}

// MARK: - FeedItemDTO

struct FeedItemDTO: Codable {
    var id: UUID
    var callsign: String
    var userId: String?
    var displayName: String?
    var activityType: String
    var timestamp: Date
    var details: ReportActivityDetails
}

// MARK: - FeedPaginationDTO

struct FeedPaginationDTO: Codable {
    var hasMore: Bool
    var nextCursor: String?
}
