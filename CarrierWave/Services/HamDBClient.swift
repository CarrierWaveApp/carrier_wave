// HamDB API Client
//
// Provides license class lookup for US amateur radio callsigns via HamDB.org.
// HamDB is a free, no-authentication-required callsign lookup service.

import Foundation

// MARK: - HamDBClient

/// Client for the HamDB.org API
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
    /// - Parameter callsign: The callsign to look up
    /// - Returns: License lookup result, or nil if not found
    func lookup(callsign: String) async throws -> HamDBLicense? {
        let normalizedCallsign = callsign.uppercased().trimmingCharacters(in: .whitespaces)

        guard !normalizedCallsign.isEmpty else {
            return nil
        }

        let urlString = "\(baseURL)/\(normalizedCallsign)/json/CarrierWave"

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

        // HamDB returns "NOT_FOUND" message when callsign doesn't exist
        guard decoded.hamdb.messages?.status != "NOT_FOUND" else {
            return nil
        }

        return decoded.hamdb.callsign
    }

    /// Look up just the license class for a callsign
    /// - Parameter callsign: The callsign to look up
    /// - Returns: License class string (e.g., "E", "G", "T"), or nil if not found
    func lookupLicenseClass(callsign: String) async throws -> LicenseClass? {
        guard let license = try await lookup(callsign: callsign) else {
            return nil
        }

        return license.parsedLicenseClass
    }

    // MARK: Private

    private let baseURL = "https://api.hamdb.org/v1"
    private let session: URLSession
}

// MARK: - HamDBError

/// Errors from HamDB API
enum HamDBError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid HamDB API URL"
        case .invalidResponse:
            "Invalid response from HamDB"
        case let .httpError(statusCode):
            "HamDB returned HTTP \(statusCode)"
        case let .decodingError(error):
            "Failed to decode HamDB response: \(error.localizedDescription)"
        }
    }
}

// MARK: - HamDBResponse

/// Root response from HamDB API
struct HamDBResponse: Sendable {
    let hamdb: HamDBData
}

// MARK: Decodable

extension HamDBResponse: Decodable {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hamdb = try container.decode(HamDBData.self, forKey: .hamdb)
    }

    private enum CodingKeys: String, CodingKey {
        case hamdb
    }
}

// MARK: - HamDBData

/// Container for HamDB data
struct HamDBData: Codable, Sendable {
    let version: String?
    let callsign: HamDBLicense?
    let messages: HamDBMessages?
}

// MARK: - HamDBMessages

/// Status messages from HamDB
struct HamDBMessages: Codable, Sendable {
    let status: String?
}

// MARK: - HamDBLicense

/// License information from HamDB
struct HamDBLicense: Codable, Sendable {
    /// The callsign
    let call: String?

    /// License class code (E, G, T, A, N)
    let `class`: String?

    /// License expiration date
    let expires: String?

    /// License grant date
    let grant: String?

    /// Operator's first name
    let fname: String?

    /// Operator's middle initial
    let mi: String?

    /// Operator's last name
    let name: String?

    /// Operator's suffix (Jr, Sr, etc.)
    let suffix: String?

    /// Street address
    let addr1: String?

    /// Address line 2
    let addr2: String?

    /// City
    let city: String?

    /// State
    let state: String?

    /// ZIP code
    let zip: String?

    /// Country
    let country: String?

    /// Grid square
    let grid: String?

    /// Latitude
    let lat: String?

    /// Longitude
    let lon: String?

    /// FRN (FCC Registration Number)
    let frn: String?

    /// Full name (first + last)
    nonisolated var fullName: String? {
        let parts = [fname, name].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Parse the license class code into our LicenseClass enum
    nonisolated var parsedLicenseClass: LicenseClass? {
        guard let classCode = self.class?.uppercased() else {
            return nil
        }

        switch classCode {
        case "E":
            return .extra
        case "G":
            return .general
        case "T":
            return .technician
        case "A":
            // Advanced class (grandfathered, equivalent to Extra for privileges)
            return .extra
        case "N":
            // Novice class (grandfathered, limited privileges - treat as Technician)
            return .technician
        default:
            return nil
        }
    }
}
