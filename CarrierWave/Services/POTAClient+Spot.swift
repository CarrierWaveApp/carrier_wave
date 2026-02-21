// POTA self-spotting extension
//
// Provides functionality for activators to spot themselves on POTA.

import CarrierWaveCore
import Foundation

// MARK: - POTASpotRequest

/// Request payload for self-spotting on POTA
struct POTASpotRequest: Encodable {
    let activator: String
    let spotter: String
    let frequency: String
    let reference: String
    let mode: String
    let comments: String?
}

// MARK: - POTASpotResponse

/// Response from POTA spot endpoint
struct POTASpotResponse: Decodable {
    let count: Int?
    let message: String?
}

// MARK: - POTASpotError

enum POTASpotError: Error, LocalizedError {
    case notAuthenticated
    case invalidReference
    case invalidFrequency
    case spotFailed(String)
    case networkError(Error)
    case rateLimited

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Not authenticated with POTA"
        case .invalidReference:
            "Invalid park reference"
        case .invalidFrequency:
            "Invalid frequency"
        case let .spotFailed(reason):
            "Spot failed: \(reason)"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case .rateLimited:
            "Too many spots - please wait before spotting again"
        }
    }
}

// MARK: - POTAClient Spotting Extension

extension POTAClient {
    /// Post a self-spot to POTA
    /// - Parameters:
    ///   - callsign: The activator's callsign (your callsign)
    ///   - reference: The park reference (e.g., "K-1234")
    ///   - frequency: The frequency in kHz (e.g., 14060.0)
    ///   - mode: The operating mode (e.g., "CW", "SSB", "FT8")
    ///   - comments: Optional comments for the spot
    /// - Returns: True if the spot was successful
    func postSpot(
        callsign: String,
        reference: String,
        frequency: Double,
        mode: String,
        comments: String? = nil
    ) async throws -> Bool {
        let debugLog = SyncDebugLog.shared

        try validateSpotInputs(reference: reference, frequency: frequency, debugLog: debugLog)

        let token = try await authService.ensureValidToken()
        let normalizedRef = reference.uppercased()
        let frequencyString = formatFrequency(frequency)

        debugLog.info(
            "Posting self-spot: \(callsign) at \(normalizedRef) on \(frequencyString) \(mode)",
            service: .pota
        )

        let spotRequest = POTASpotRequest(
            activator: callsign.uppercased(),
            spotter: callsign.uppercased(),
            frequency: frequencyString,
            reference: normalizedRef,
            mode: mode.uppercased(),
            comments: comments
        )

        let request = try buildSpotURLRequest(token: token, body: spotRequest)
        return try await executeSpotRequest(request, debugLog: debugLog)
    }

    private func validateSpotInputs(
        reference: String,
        frequency: Double,
        debugLog: SyncDebugLog
    ) throws {
        guard validateParkReference(reference) else {
            debugLog.error("Invalid park reference for spot: \(reference)", service: .pota)
            throw POTASpotError.invalidReference
        }
        guard frequency > 0 else {
            debugLog.error("Invalid frequency for spot: \(frequency)", service: .pota)
            throw POTASpotError.invalidFrequency
        }
    }

    private func buildSpotURLRequest(token: String, body: POTASpotRequest) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/spot") else {
            throw POTASpotError.spotFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw POTASpotError.spotFailed("Failed to encode request")
        }

        return request
    }

    private func executeSpotRequest(
        _ request: URLRequest,
        debugLog: SyncDebugLog
    ) async throws -> Bool {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw POTASpotError.spotFailed("Invalid response")
            }

            return try handleSpotResponse(
                statusCode: httpResponse.statusCode, data: data, debugLog: debugLog
            )
        } catch let error as POTASpotError {
            throw error
        } catch {
            debugLog.error("Network error posting spot: \(error)", service: .pota)
            throw POTASpotError.networkError(error)
        }
    }

    private func handleSpotResponse(
        statusCode: Int,
        data: Data,
        debugLog: SyncDebugLog
    ) throws -> Bool {
        switch statusCode {
        case 200,
             201:
            debugLog.info("Self-spot posted successfully", service: .pota)
            return true
        case 401,
             403:
            authService.invalidateToken()
            throw POTASpotError.notAuthenticated
        case 429:
            debugLog.warning("Rate limited on spot request", service: .pota)
            throw POTASpotError.rateLimited
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            debugLog.error(
                "Spot failed: HTTP \(statusCode) - \(body)", service: .pota
            )
            throw POTASpotError.spotFailed("HTTP \(statusCode)")
        }
    }

    /// Format frequency for POTA spot (kHz with decimal)
    private func formatFrequency(_ frequencyKHz: Double) -> String {
        // POTA expects frequency in kHz format (e.g., "14060.0")
        if frequencyKHz == frequencyKHz.rounded() {
            return String(format: "%.1f", frequencyKHz)
        }
        return String(format: "%.3f", frequencyKHz)
    }
}
