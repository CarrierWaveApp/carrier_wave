import Foundation

// MARK: - APIError

enum APIError: LocalizedError {
    case notConfigured
    case invalidURL
    case httpError(statusCode: Int, message: String)
    case decodingError(Error)
    case networkError(Error)
    case cancelled

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Server not configured"
        case .invalidURL:
            "Invalid server URL"
        case let .httpError(code, message):
            "HTTP \(code): \(message)"
        case let .decodingError(error):
            "Decoding error: \(error.localizedDescription)"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case .cancelled:
            nil
        }
    }

    var isCancellation: Bool {
        if case .cancelled = self {
            return true
        }
        return false
    }
}

extension Error {
    var isCancellation: Bool {
        if self is CancellationError {
            return true
        }
        if let urlError = self as? URLError, urlError.code == .cancelled {
            return true
        }
        if let apiError = self as? APIError, apiError.isCancellation {
            return true
        }
        return false
    }
}

// MARK: - APIErrorResponse

struct APIErrorResponse: Decodable {
    let error: APIErrorDetail
}

// MARK: - APIErrorDetail

struct APIErrorDetail: Decodable {
    let code: String
    let message: String
}

// MARK: - DataWrapper

struct DataWrapper<T: Decodable>: Decodable {
    let data: T
}

// MARK: - APIClient

class APIClient {
    // MARK: Lifecycle

    init(config: ServerConfig) {
        self.config = config
    }

    // MARK: Internal

    let config: ServerConfig

    // MARK: - Core Request Methods

    func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem]? = nil) async throws -> T {
        let request = try buildRequest(method: "GET", path: path, queryItems: queryItems)
        return try await execute(request)
    }

    func getWrapped<T: Decodable>(_ path: String, queryItems: [URLQueryItem]? = nil) async throws -> T {
        let wrapper: DataWrapper<T> = try await get(path, queryItems: queryItems)
        return wrapper.data
    }

    func post<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        var request = try buildRequest(method: "POST", path: path)
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await execute(request)
    }

    func put<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        var request = try buildRequest(method: "PUT", path: path)
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await execute(request)
    }

    func delete(_ path: String) async throws {
        let request = try buildRequest(method: "DELETE", path: path)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            return
        }
        if http.statusCode >= 400 {
            let message = parseErrorMessage(from: data) ?? "Request failed"
            throw APIError.httpError(statusCode: http.statusCode, message: message)
        }
    }

    // MARK: - Health & Dashboard

    func getHealth() async throws -> HealthResponse {
        try await get("/v1/health")
    }

    func getChallenges(limit: Int = 100) async throws -> ChallengesListResponse {
        try await getWrapped("/v1/challenges", queryItems: [
            URLQueryItem(name: "limit", value: "\(limit)"),
        ])
    }

    func getSpots(limit: Int = 1) async throws -> SpotsListResponse {
        try await get("/v1/spots", queryItems: [
            URLQueryItem(name: "limit", value: "\(limit)"),
        ])
    }

    // MARK: - Aggregator Status

    func getPotaSyncStatus() async throws -> PotaSyncStatusResponse {
        try await getWrapped("/v1/pota/stats/status")
    }

    func getParkBoundariesStatus() async throws -> ParkBoundariesStatusResponse {
        try await getWrapped("/v1/parks/boundaries/status")
    }

    func getTrailStatus() async throws -> TrailStatusResponse {
        try await getWrapped("/v1/trails/status")
    }

    // MARK: - Programs (Admin)

    func getPrograms() async throws -> ProgramListResponse {
        try await getWrapped("/v1/admin/programs")
    }

    func createProgram(_ request: CreateProgramRequest) async throws -> ProgramResponse {
        let wrapper: DataWrapper<ProgramResponse> = try await post("/v1/admin/programs", body: request)
        return wrapper.data
    }

    func updateProgram(slug: String, _ request: UpdateProgramRequest) async throws -> ProgramResponse {
        let wrapper: DataWrapper<ProgramResponse> = try await put("/v1/admin/programs/\(slug)", body: request)
        return wrapper.data
    }

    func deleteProgram(slug: String) async throws {
        try await delete("/v1/admin/programs/\(slug)")
    }

    // MARK: - Clubs (Admin)

    func getClubs() async throws -> [ClubAdminResponse] {
        let wrapper: DataWrapper<[ClubAdminResponse]> = try await get("/v1/admin/clubs")
        return wrapper.data
    }

    func getClubMembers(clubId: String) async throws -> [ClubMemberAdminResponse] {
        let wrapper: DataWrapper<[ClubMemberAdminResponse]> = try await get("/v1/admin/clubs/\(clubId)/members")
        return wrapper.data
    }

    func createClub(_ request: CreateClubRequest) async throws -> ClubAdminResponse {
        let wrapper: DataWrapper<ClubAdminResponse> = try await post("/v1/admin/clubs", body: request)
        return wrapper.data
    }

    func updateClub(id: String, _ request: UpdateClubRequest) async throws -> ClubAdminResponse {
        let wrapper: DataWrapper<ClubAdminResponse> = try await put("/v1/admin/clubs/\(id)", body: request)
        return wrapper.data
    }

    func deleteClub(id: String) async throws {
        try await delete("/v1/admin/clubs/\(id)")
    }

    func addClubMembers(clubId: String, members: [AddMemberEntry]) async throws {
        let _: DataWrapper<[ClubMemberAdminResponse]> = try await post(
            "/v1/admin/clubs/\(clubId)/members",
            body: AddMembersRequest(members: members)
        )
    }

    func removeClubMember(clubId: String, callsign: String) async throws {
        try await delete("/v1/admin/clubs/\(clubId)/members/\(callsign)")
    }

    func importNotesMembers(clubId: String) async throws -> ImportNotesResponse {
        let wrapper: DataWrapper<ImportNotesResponse> = try await post(
            "/v1/admin/clubs/\(clubId)/import-notes",
            body: EmptyBody()
        )
        return wrapper.data
    }

    // MARK: - Events (Admin)

    func getEvents(status: String? = nil, limit: Int = 50) async throws -> EventsListResponse {
        var items = [
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        if let status {
            items.append(URLQueryItem(name: "status", value: status))
        }
        return try await getWrapped("/v1/admin/events", queryItems: items)
    }

    func getEvent(id: String) async throws -> EventDetailResponse {
        let wrapper: DataWrapper<EventDetailResponse> = try await get("/v1/admin/events/\(id)")
        return wrapper.data
    }

    func reviewEvent(id: String, action: String, reason: String? = nil) async throws -> EventDetailResponse {
        let body = ReviewEventRequest(action: action, reason: reason)
        let wrapper: DataWrapper<EventDetailResponse> = try await put("/v1/admin/events/\(id)/review", body: body)
        return wrapper.data
    }

    func updateEvent(id: String, _ request: UpdateEventRequest) async throws -> EventDetailResponse {
        let wrapper: DataWrapper<EventDetailResponse> = try await put("/v1/admin/events/\(id)", body: request)
        return wrapper.data
    }

    func deleteEvent(id: String) async throws {
        try await delete("/v1/admin/events/\(id)")
    }

    func getSubmitterHistory(callsign: String) async throws -> SubmitterStatsResponse {
        try await getWrapped("/v1/admin/events/submitter/\(callsign)")
    }

    // MARK: - Admin Stats

    func getAdminStats() async throws -> AdminStatsResponse {
        try await getWrapped("/v1/admin/stats")
    }

    func getUserCountsByHour(days: Int = 30) async throws -> [UserCountByHour] {
        try await getWrapped("/v1/admin/stats/users-by-hour", queryItems: [
            URLQueryItem(name: "days", value: "\(days)"),
        ])
    }

    // MARK: - Telemetry (Admin)

    func getTelemetrySummary(days: Int = 7, service: String? = nil,
                             category: String? = nil) async throws -> TelemetrySummaryResponse
    {
        var items = [URLQueryItem(name: "days", value: "\(days)")]
        if let service {
            items.append(URLQueryItem(name: "service", value: service))
        }
        if let category {
            items.append(URLQueryItem(name: "category", value: category))
        }
        return try await getWrapped("/v1/admin/telemetry/upload-errors", queryItems: items)
    }

    // MARK: - Challenges (Admin)

    func createChallenge(_ body: [String: Any]) async throws {
        // Uses raw JSON for flexible challenge configuration
        var request = try buildRequest(method: "POST", path: "/v1/admin/challenges")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            return
        }
        if http.statusCode >= 400 {
            let message = parseErrorMessage(from: data) ?? "Request failed"
            throw APIError.httpError(statusCode: http.statusCode, message: message)
        }
    }

    func deleteChallenge(id: String) async throws {
        try await delete("/v1/admin/challenges/\(id)")
    }

    // MARK: Private

    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        dec.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            // Try ISO8601 with fractional seconds first, then without
            let formatters: [ISO8601DateFormatter] = {
                let f1 = ISO8601DateFormatter()
                f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let f2 = ISO8601DateFormatter()
                f2.formatOptions = [.withInternetDateTime]
                return [f1, f2]
            }()
            for formatter in formatters {
                if let date = formatter.date(from: str) {
                    return date
                }
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(str)")
        }
        return dec
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    private func buildRequest(method: String, path: String, queryItems: [URLQueryItem]? = nil) throws -> URLRequest {
        guard config.isConfigured else {
            throw APIError.notConfigured
        }

        guard var components = URLComponents(string: config.baseURL + path) else {
            throw APIError.invalidURL
        }
        if let queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(config.adminToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        return request
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if error.isCancellation {
                throw APIError.cancelled
            }
            throw APIError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        if http.statusCode >= 400 {
            let message = parseErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
            throw APIError.httpError(statusCode: http.statusCode, message: message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func parseErrorMessage(from data: Data) -> String? {
        try? JSONDecoder().decode(APIErrorResponse.self, from: data).error.message
    }
}
