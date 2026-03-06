import Foundation

// MARK: - HamDBError

enum HamDBError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid HamDB API URL"
        case .invalidResponse:
            "Invalid response from HamDB"
        case let .httpError(statusCode):
            "HamDB returned HTTP \(statusCode)"
        }
    }
}

// MARK: - HamDBClient

/// Client for the HamDB.org API — provides grid square and license lookups.
actor HamDBClient {
    // MARK: Lifecycle

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        session = URLSession(configuration: config)
    }

    // MARK: Internal

    /// Look up license information for a callsign
    func lookup(callsign: String) async throws -> HamDBLicense? {
        let normalizedCallsign = callsign.uppercased().trimmingCharacters(in: .whitespaces)
        guard !normalizedCallsign.isEmpty else {
            return nil
        }

        let urlString = "\(baseURL)/\(normalizedCallsign)/json/CWSweep"
        guard let url = URL(string: urlString) else {
            throw HamDBError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HamDBError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw HamDBError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(HamDBResponse.self, from: data)

        guard decoded.hamdb.messages?.status != "NOT_FOUND" else {
            return nil
        }

        return decoded.hamdb.callsign
    }

    // MARK: Private

    private let baseURL = "https://api.hamdb.org/v1"
    private let session: URLSession
}

// MARK: - HamDBResponse

struct HamDBResponse: Decodable, Sendable {
    let hamdb: HamDBData
}

// MARK: - HamDBData

struct HamDBData: Codable, Sendable {
    let version: String?
    let callsign: HamDBLicense?
    let messages: HamDBMessages?
}

// MARK: - HamDBMessages

struct HamDBMessages: Codable, Sendable {
    let status: String?
}

// MARK: - HamDBLicense

/// License information from HamDB
struct HamDBLicense: Codable, Sendable {
    let call: String?
    let `class`: String?
    let expires: String?
    let fname: String?
    let name: String?
    let city: String?
    let state: String?
    let zip: String?
    let country: String?
    let grid: String?
    let lat: String?
    let lon: String?

    /// Full name (first + last)
    nonisolated var fullName: String? {
        let parts = [fname, name].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
