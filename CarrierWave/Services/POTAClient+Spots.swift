// POTA spots and spot comments API extension
//
// Provides functionality to fetch active POTA spots and spot comments
// for activations.

import Foundation
import SwiftUI

// MARK: - POTASpot

/// A spot from the POTA spotting system
struct POTASpot: Decodable, Identifiable, Sendable {
    // MARK: Internal

    let spotId: Int64
    let activator: String
    let frequency: String
    let mode: String
    let reference: String
    let parkName: String?
    let spotTime: String
    let spotter: String
    let comments: String?
    let source: String?
    let name: String?
    let locationDesc: String?

    nonisolated var id: Int64 {
        spotId
    }

    /// Parse frequency string to kHz
    nonisolated var frequencyKHz: Double? {
        Double(frequency)
    }

    /// Parse spot time to Date
    nonisolated var timestamp: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: spotTime) {
            return date
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: spotTime)
    }

    /// Time ago string
    nonisolated var timeAgo: String {
        guard let timestamp else {
            return ""
        }
        let seconds = Date().timeIntervalSince(timestamp)
        if seconds < 60 {
            return "\(Int(seconds))s ago"
        } else if seconds < 3_600 {
            return "\(Int(seconds / 60))m ago"
        } else {
            return "\(Int(seconds / 3_600))h ago"
        }
    }

    /// Color based on spot freshness
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

    /// Check if this is an automated spot (from RBN or similar)
    nonisolated var isAutomatedSpot: Bool {
        guard let source = source?.uppercased() else {
            return false
        }
        // RBN = Reverse Beacon Network (automated CW/FT8 decoder)
        return source == "RBN"
    }

    /// Check if this is a human-generated spot
    nonisolated var isHumanSpot: Bool {
        !isAutomatedSpot
    }

    /// Check if this spot is a self-spot for the given user callsign
    nonisolated func isSelfSpot(userCallsign: String) -> Bool {
        let normalizedUser = Self.normalizeCallsign(userCallsign)
        let normalizedSpot = Self.normalizeCallsign(activator)
        return normalizedUser == normalizedSpot
    }

    // MARK: Private

    /// Normalize callsign by removing portable suffixes and uppercasing
    nonisolated private static func normalizeCallsign(_ callsign: String) -> String {
        let upper = callsign.uppercased()
        // Remove common portable suffixes: /P, /M, /QRP, /0-9, etc.
        if let slashIndex = upper.firstIndex(of: "/") {
            return String(upper[..<slashIndex])
        }
        return upper
    }
}

// MARK: - POTASpotComment

/// A comment on a POTA spot
struct POTASpotComment: Decodable, Identifiable, Sendable {
    let spotId: Int64
    let spotter: String
    let comments: String?
    let spotTime: String
    let source: String?

    nonisolated var id: Int64 {
        spotId
    }

    /// Parse spot time to Date
    nonisolated var timestamp: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: spotTime) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: spotTime)
    }

    /// Time ago string
    nonisolated var timeAgo: String {
        guard let timestamp else {
            return ""
        }
        let seconds = Date().timeIntervalSince(timestamp)
        if seconds < 60 {
            return "\(Int(seconds))s ago"
        } else if seconds < 3_600 {
            return "\(Int(seconds / 60))m ago"
        } else {
            return "\(Int(seconds / 3_600))h ago"
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

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw POTAError.fetchFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw POTAError.fetchFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        return try JSONDecoder().decode([POTASpot].self, from: data)
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
