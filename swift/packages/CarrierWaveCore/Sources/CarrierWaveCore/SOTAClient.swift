import Foundation

// MARK: - SOTAError

public enum SOTAError: Error, LocalizedError {
    case invalidResponse
    case httpError(Int, String?)
    case invalidSummitCode
    case invalidFrequency
    case encodingFailed
    case temporarilyDisabled

    // MARK: Public

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from SOTA API"
        case .temporarilyDisabled:
            return "SOTA spotting is temporarily disabled"
        case let .httpError(code, body):
            if let body, !body.isEmpty {
                return "SOTA API returned HTTP \(code): \(body)"
            }
            return "SOTA API returned HTTP \(code)"
        case .invalidSummitCode:
            return "Invalid SOTA summit code (expected ASSOC/REGION-NUM, e.g. W6/CT-021)"
        case .invalidFrequency:
            return "Invalid frequency for SOTA spot"
        case .encodingFailed:
            return "Failed to encode SOTA spot request"
        }
    }
}

// MARK: - SOTAClient

/// Client for the SOTAwatch API (api2.sota.org.uk).
/// Fetches active spots for SOTA activators.
public actor SOTAClient {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    /// Global SOTA kill-switch: the SOTAwatch v2 API shuts down 2026-08-31
    /// and its replacement (api-db2) requires prior approval under its terms
    /// of service before any client may connect. While true, `fetchSpots`
    /// returns no spots and `postSpot` throws `.temporarilyDisabled`. Flip
    /// back to false once the migration to the new API lands.
    public static let isTemporarilyDisabled = true

    /// Fetch the most recent SOTA spots.
    /// - Parameters:
    ///   - count: Maximum number of spots to fetch (default 50, API max 200).
    ///   - association: Association filter, e.g. "W4C". Pass nil for all associations.
    /// - Returns: Array of SOTA spots, newest first.
    public func fetchSpots(count: Int = 50, association: String? = nil) async throws -> [SOTASpot] {
        guard !Self.isTemporarilyDisabled else {
            return []
        }
        let filter = association ?? "all"
        guard let url = URL(string: "\(baseURL)/spots/\(count)/\(filter)") else {
            throw SOTAError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw SOTAError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw SOTAError.httpError(http.statusCode, String(data: data, encoding: .utf8))
        }

        guard let json = String(data: data, encoding: .utf8) else {
            throw SOTAError.invalidResponse
        }
        guard let spots = SOTASpot.decodeResponse(json) else {
            throw SOTAError.invalidResponse
        }
        return spots
    }

    /// Post a self-spot (or respot) to SOTAwatch.
    ///
    /// SOTAwatch's spots POST is currently public — no API key. The body fields
    /// match what the website itself submits.
    ///
    /// - Parameters:
    ///   - activatorCallsign: Callsign of the station on the summit.
    ///   - spotterCallsign: Callsign of the spotter (use the activator's callsign for self-spots).
    ///   - summitCode: Full summit reference, e.g. "W6/CT-021".
    ///   - frequencyMHz: Frequency in MHz (e.g. 14.062). Sent as a fixed-format string.
    ///   - mode: Operating mode, uppercased before sending (e.g. "CW", "SSB", "FT8").
    ///   - comments: Optional spot comment.
    public func postSpot(
        activatorCallsign: String,
        spotterCallsign: String,
        summitCode: String,
        frequencyMHz: Double,
        mode: String,
        comments: String? = nil
    ) async throws {
        guard !Self.isTemporarilyDisabled else {
            throw SOTAError.temporarilyDisabled
        }
        let trimmedSummit = summitCode.uppercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedSummit.contains("/"), trimmedSummit.contains("-") else {
            throw SOTAError.invalidSummitCode
        }
        guard frequencyMHz > 0 else {
            throw SOTAError.invalidFrequency
        }

        guard let url = URL(string: "\(baseURL)/spots") else {
            throw SOTAError.invalidResponse
        }

        let body: [String: String] = [
            "activatorCallsign": activatorCallsign.uppercased(),
            "spotterCallsign": spotterCallsign.uppercased(),
            "summitCode": trimmedSummit,
            "frequency": Self.formatFrequency(frequencyMHz),
            "mode": mode.uppercased(),
            "comments": comments ?? "",
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw SOTAError.encodingFailed
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SOTAError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw SOTAError.httpError(http.statusCode, String(data: data, encoding: .utf8))
        }
    }

    /// Fetch spots for a specific activator callsign (filters client-side).
    /// - Parameters:
    ///   - callsign: The activator's callsign.
    ///   - count: Number of recent spots to search through (default 50).
    /// - Returns: Spots matching the activator callsign.
    public func fetchSpots(for callsign: String, count: Int = 50) async throws -> [SOTASpot] {
        let allSpots = try await fetchSpots(count: count)
        let upper = callsign.uppercased()
        return allSpots.filter { $0.activatorCallsign.uppercased() == upper }
    }

    // MARK: Internal

    /// Format a frequency for the SOTA spot endpoint. SOTAwatch expects MHz as a
    /// decimal string. Trim trailing zeros so e.g. 14.062 stays "14.062".
    nonisolated static func formatFrequency(_ mhz: Double) -> String {
        let formatted = String(format: "%.5f", mhz)
        var stripped = formatted
        while stripped.last == "0" {
            stripped.removeLast()
        }
        if stripped.last == "." {
            stripped.removeLast()
        }
        return stripped
    }

    // MARK: Private

    private let baseURL = "https://api2.sota.org.uk/api"
}
