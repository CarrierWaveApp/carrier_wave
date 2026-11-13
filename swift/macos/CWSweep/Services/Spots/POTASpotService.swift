import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - POTASpotError

enum POTASpotError: Error, LocalizedError {
    case notAuthenticated
    case invalidURL
    case postFailed(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Not authenticated with POTA — log in via Carrier Wave iOS app"
        case .invalidURL:
            "Invalid POTA API URL"
        case let .postFailed(message):
            "POTA spot post failed: \(message)"
        }
    }
}

// MARK: - SpotParameters

/// Groups the parameters needed for a POTA self-spot.
struct SpotParameters {
    var callsign: String
    var reference: String
    var frequencyKHz: Double
    var mode: String
    var comment: String?
}

// MARK: - POTASpotService

/// MainActor-bound service for posting self-spots to POTA API with re-spot timer support.
@MainActor
@Observable
final class POTASpotService {
    // MARK: Internal

    /// Next scheduled re-spot date (nil if timer is not active).
    var nextSpotDate: Date?

    /// Comment used for the current session.
    var sessionComment: String = ""

    /// Whether the re-spot timer is currently running.
    var isReSpotTimerActive: Bool {
        reSpotTask != nil
    }

    // MARK: - Session Lifecycle

    /// Configure the service for a new activation session.
    func configureForSession(
        callsign: String,
        reference: String,
        frequencyKHz: Double,
        mode: String,
        commentTemplate: String
    ) {
        sessionCallsign = callsign
        sessionReference = reference
        sessionFrequencyKHz = frequencyKHz
        sessionMode = mode
        sessionCommentTemplate = commentTemplate

        let band = BandUtilities.deriveBand(from: frequencyKHz) ?? ""
        sessionComment = resolveComment(
            template: commentTemplate,
            mode: mode,
            band: band,
            park: reference,
            callsign: callsign
        )
    }

    /// End the session and stop any active re-spot timer.
    func endSession() {
        stopReSpotTimer()
        sessionCallsign = nil
        sessionReference = nil
        sessionFrequencyKHz = nil
        sessionMode = nil
        sessionCommentTemplate = nil
        sessionComment = ""
        nextSpotDate = nil
    }

    // MARK: - Spot Posting

    /// Post a self-spot to the POTA API.
    func postSpot(
        callsign: String,
        reference: String,
        frequencyKHz: Double,
        mode: String,
        comment: String?
    ) async throws -> Bool {
        guard let token = try? KeychainHelper.shared.readString(for: KeychainHelper.Keys.potaIdToken) else {
            throw POTASpotError.notAuthenticated
        }

        guard let url = URL(string: "https://api.pota.app/spot") else {
            throw POTASpotError.invalidURL
        }

        let body = SpotRequestBody(
            activator: callsign,
            spotter: callsign,
            frequency: String(format: "%.1f", frequencyKHz),
            reference: reference,
            mode: mode,
            comments: comment ?? ""
        )

        let request = try buildSpotRequest(url: url, token: token, body: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw POTASpotError.postFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw POTASpotError.postFailed("HTTP \(httpResponse.statusCode): \(bodyText)")
        }

        return true
    }

    /// Post a spot using the current session state.
    func postCurrentSpot(overrideComment: String? = nil) async throws -> Bool {
        guard
            let callsign = sessionCallsign,
            let reference = sessionReference,
            let frequencyKHz = sessionFrequencyKHz,
            let mode = sessionMode
        else {
            throw POTASpotError.notAuthenticated
        }

        let comment = overrideComment ?? sessionComment
        return try await postSpot(
            callsign: callsign,
            reference: reference,
            frequencyKHz: frequencyKHz,
            mode: mode,
            comment: comment
        )
    }

    // MARK: - Re-Spot Timer

    /// Start a periodic re-spot timer using a `SpotParameters` value.
    func startReSpotTimer(intervalMinutes: Int, parameters: SpotParameters) {
        stopReSpotTimer()
        scheduleNextSpot(intervalMinutes: intervalMinutes)

        reSpotTask = Task { [weak self] in
            let intervalNanos = UInt64(intervalMinutes) * 60 * 1_000_000_000
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: intervalNanos)
                } catch {
                    break
                }
                guard !Task.isCancelled else {
                    break
                }
                _ = try? await self?.postSpot(
                    callsign: parameters.callsign,
                    reference: parameters.reference,
                    frequencyKHz: parameters.frequencyKHz,
                    mode: parameters.mode,
                    comment: parameters.comment
                )
                if !Task.isCancelled {
                    self?.scheduleNextSpot(intervalMinutes: intervalMinutes)
                }
            }
        }
    }

    /// Cancel the active re-spot timer.
    func stopReSpotTimer() {
        reSpotTask?.cancel()
        reSpotTask = nil
        nextSpotDate = nil
    }

    // MARK: - Comment Token Substitution

    /// Replace [MODE], [BAND], [PARK], [CALL] tokens in a comment template.
    func resolveComment(
        template: String,
        mode: String,
        band: String,
        park: String,
        callsign: String
    ) -> String {
        template
            .replacingOccurrences(of: "[MODE]", with: mode)
            .replacingOccurrences(of: "[BAND]", with: band)
            .replacingOccurrences(of: "[PARK]", with: park)
            .replacingOccurrences(of: "[CALL]", with: callsign)
    }

    // MARK: Private

    private var sessionCallsign: String?
    private var sessionReference: String?
    private var sessionFrequencyKHz: Double?
    private var sessionMode: String?
    private var sessionCommentTemplate: String?
    private var reSpotTask: Task<Void, Never>?

    private func scheduleNextSpot(intervalMinutes: Int) {
        nextSpotDate = Date().addingTimeInterval(Double(intervalMinutes) * 60)
    }

    private func buildSpotRequest(
        url: URL,
        token: String,
        body: SpotRequestBody
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }
}

// MARK: - SpotRequestBody

private struct SpotRequestBody: Encodable {
    let activator: String
    let spotter: String
    let frequency: String
    let reference: String
    let mode: String
    let comments: String
}
