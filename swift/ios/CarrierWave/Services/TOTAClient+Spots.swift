// TOTA spots fetch (public read, no auth required).
//
// GET https://icneuzxitdqtofutxbla.supabase.co/functions/v1/spots
//   Anonymous: 30 req/min/IP. With x-api-key: 120 req/min.
//   Cache-Control: public, max-age=15. Caller must not poll faster than 30s.

import UIKit

extension TOTAClient {
    /// Fetch recent TOTA spots. Defaults match the website's Spots page (last 30 minutes).
    /// - Parameters:
    ///   - since: Returns spots created at/after this timestamp. Overrides `activeHours`.
    ///   - activeHours: Lookback window in hours (default 0.5, max 168).
    ///   - callSign: Filter to a single operator.
    ///   - limit: Max results (default 50, server cap 200).
    func fetchSpots(
        since: Date? = nil,
        activeHours: Double? = nil,
        callSign: String? = nil,
        limit: Int? = nil
    ) async throws -> [TOTASpot] {
        var query: [URLQueryItem] = []

        if let since {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            query.append(URLQueryItem(name: "since", value: formatter.string(from: since)))
        } else if let activeHours {
            let clamped = min(max(activeHours, 0), 168)
            query.append(URLQueryItem(name: "active_hours", value: String(clamped)))
        }

        if let callSign, !callSign.isEmpty {
            query.append(URLQueryItem(name: "call_sign", value: callSign.uppercased()))
        }

        if let limit {
            let clamped = min(max(limit, 1), 200)
            query.append(URLQueryItem(name: "limit", value: String(clamped)))
        }

        let request = try makeRequest(path: "/spots", method: "GET", query: query)
        let data = try await executeRequest(request)

        do {
            let decoded = try Self.makeDecoder().decode(TOTASpotsResponse.self, from: data)
            return decoded.spots
        } catch {
            throw TOTAError.decodingFailed(error)
        }
    }

    /// Convenience: fetch only spots for a given callsign within the last `hours` hours.
    func fetchSpots(for callSign: String, hours: Double = 4) async throws -> [TOTASpot] {
        try await fetchSpots(activeHours: hours, callSign: callSign)
    }
}
