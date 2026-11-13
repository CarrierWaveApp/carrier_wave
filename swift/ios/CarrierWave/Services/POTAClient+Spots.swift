// POTA spots and spot comments API extension
//
// Provides functionality to fetch active POTA spots and spot comments
// for activations.

import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftUI

// MARK: - POTASpot + ageColor

extension POTASpot {
    /// Color based on spot freshness.
    nonisolated var ageColor: Color {
        guard let timestamp else {
            return .secondary
        }
        let seconds = Date().timeIntervalSince(timestamp)
        switch seconds {
        case ..<120:
            return .green // < 2 minutes: very fresh
        case ..<600:
            return .blue // 2-10 minutes: recent
        case ..<1_800:
            return .orange // 10-30 minutes: getting stale
        default:
            return .secondary // > 30 minutes: old
        }
    }
}

// MARK: - POTAClient Spots Extension

extension POTAClient {
    /// Fetch all currently active POTA spots (no auth required)
    func fetchActiveSpots() async throws -> [POTASpot] {
        guard let url = URL(string: "\(baseURL)/spot/activator") else {
            throw POTAError.fetchFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw POTAError.fetchFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw POTAError.fetchFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        guard let json = String(data: data, encoding: .utf8) else {
            throw POTAError.fetchFailed("Could not decode response body")
        }
        guard let spots = POTASpot.decodeResponse(json) else {
            throw POTAError.fetchFailed("Failed to decode POTA spots")
        }
        return spots
    }

    /// Fetch spots for a specific callsign from active spots
    func fetchSpots(for callsign: String) async throws -> [POTASpot] {
        let allSpots = try await fetchActiveSpots()
        let upper = callsign.uppercased()
        return allSpots.filter { $0.activator.uppercased() == upper }
    }

    /// Fetch spot comments for an activation (no auth required)
    /// - Parameters:
    ///   - activator: The activator's callsign
    ///   - parkRef: The park reference (e.g., "K-1234")
    func fetchSpotComments(activator: String, parkRef: String) async throws -> [POTASpotComment] {
        let encodedActivator =
            activator.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            ) ?? activator
        let encodedPark =
            parkRef.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            ) ?? parkRef

        guard
            let url = URL(
                string: "\(baseURL)/spot/comments/\(encodedActivator)/\(encodedPark)"
            )
        else {
            throw POTAError.fetchFailed("Invalid URL")
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw POTAError.fetchFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            // 404 likely means no comments yet, return empty array
            if httpResponse.statusCode == 404 {
                return []
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            throw POTAError.fetchFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        return try JSONDecoder().decode([POTASpotComment].self, from: data)
    }
}
