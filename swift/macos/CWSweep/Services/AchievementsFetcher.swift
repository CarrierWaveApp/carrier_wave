import CarrierWaveData
import Foundation

// MARK: - AchievementsFetcher

/// Tiny URLSession-backed reader for the public achievements endpoints.
/// Sweep has no full ActivitiesClient port yet — this stays read-only and
/// avoids needing an auth token for the catalog viewer.
enum AchievementsFetcher {
    // MARK: Internal

    enum FetcherError: LocalizedError {
        case invalidURL
        case serverError

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case .invalidURL: "Invalid server URL"
            case .serverError: "Server error"
            }
        }
    }

    static func fetchCatalog() async throws -> [Achievement] {
        let url = try url(path: "/v1/achievements")
        let envelope: APIEnvelope<AchievementCatalogResponse> = try await get(url)
        return envelope.data.achievements
    }

    static func fetchAwards(for callsign: String) async throws -> [UserAchievement] {
        let normalized = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        guard !normalized.isEmpty else {
            return []
        }
        let url = try url(path: "/v1/users/\(normalized)/achievements")
        let envelope: APIEnvelope<UserAchievementsResponse> = try await get(url)
        return envelope.data.awards
    }

    // MARK: Private

    private static let defaultURL = "https://activities.carrierwave.app"

    private static var baseURL: String {
        let override = UserDefaults.standard.string(forKey: "activitiesServerURLOverride") ?? ""
        let raw = override.isEmpty ? defaultURL : override
        var result = raw
        while result.hasSuffix("/") {
            result = String(result.dropLast())
        }
        return result
    }

    private static func url(path: String) throws -> URL {
        guard let url = URL(string: baseURL + path) else {
            throw FetcherError.invalidURL
        }
        return url
    }

    private static func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw FetcherError.serverError
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - APIEnvelope

private struct APIEnvelope<T: Decodable>: Decodable {
    let data: T
}
