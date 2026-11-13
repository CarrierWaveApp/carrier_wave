import Foundation
import OSLog

// MARK: - Account & Callsign Management

extension ActivitiesClient {
    /// The callsign that was last used to register or sync with the server.
    /// Used to detect callsign drift and proactively sync changes.
    nonisolated static let registeredCallsignKey = "activitiesRegisteredCallsign"
    nonisolated static let claimedCallsignsKey = "activitiesClaimedCallsigns"

    // MARK: - Callsign Change

    /// Update the authenticated user's callsign on the activities server.
    /// The server atomically updates the callsign across all tables.
    func changeCallsign(to newCallsign: String) async throws -> String {
        let authToken = try await preferredAuthToken()
        let url = try buildURL(baseURL, path: "/v1/account/callsign")
        var request = try buildRequest(url: url, method: "PUT", authToken: authToken)

        let body = ChangeCallsignRequest(newCallsign: newCallsign)
        request.httpBody = try JSONEncoder.activitiesEncoder.encode(body)

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        let apiResponse = try JSONDecoder.activitiesDecoder.decode(
            APIResponse<ChangeCallsignResponse>.self,
            from: data
        )
        return apiResponse.data.callsign
    }

    // MARK: - Claim Previous Account

    /// Merge data from a previous callsign's server account into the current user.
    /// Transfers friendships, challenges, and activity history.
    func claimPreviousAccount(previousCallsign: String) async throws -> Bool {
        let authToken = try await preferredAuthToken()
        let url = try buildURL(baseURL, path: "/v1/account/claim-previous")
        var request = try buildRequest(url: url, method: "POST", authToken: authToken)

        let body = ClaimPreviousRequest(previousCallsign: previousCallsign)
        request.httpBody = try JSONEncoder.activitiesEncoder.encode(body)

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        let apiResponse = try JSONDecoder.activitiesDecoder.decode(
            APIResponse<ClaimPreviousResponse>.self,
            from: data
        )
        return apiResponse.data.merged
    }

    // MARK: - Callsign Drift Detection

    /// If the current callsign differs from the last registered callsign,
    /// call the server's change-callsign endpoint to keep them in sync.
    /// If that fails, try claiming the old account's data via merge.
    /// Returns true when the server accepted a callsign change on this call
    /// (the server revokes outstanding access tokens when it does).
    @discardableResult
    func syncCallsignDriftIfNeeded(currentCallsign: String) async -> Bool {
        guard !currentCallsign.isEmpty else {
            return false
        }

        let registered = (
            UserDefaults.standard.string(forKey: Self.registeredCallsignKey) ?? ""
        ).uppercased()

        // No recorded callsign yet — try claiming previous callsigns
        guard !registered.isEmpty else {
            UserDefaults.standard.set(currentCallsign, forKey: Self.registeredCallsignKey)
            await claimPreviousCallsigns(currentCallsign: currentCallsign)
            return false
        }

        guard registered != currentCallsign else {
            // Even if callsign matches, try claiming any unclaimed previous callsigns
            await claimPreviousCallsigns(currentCallsign: currentCallsign)
            return false
        }

        // A change the server keeps rejecting (e.g. CALLSIGN_TAKEN) would
        // otherwise be retried on every request; once per launch is enough.
        guard Self.driftSyncFailedFor != currentCallsign else {
            return false
        }

        Self.logger.info(
            "Callsign drift detected: registered=\(registered) current=\(currentCallsign)"
        )

        do {
            let updated = try await changeCallsign(to: currentCallsign)
            UserDefaults.standard.set(updated, forKey: Self.registeredCallsignKey)
            Self.logger.info("Synced callsign drift to server: \(updated)")
            return true
        } catch {
            Self.logger.error("Failed to sync callsign drift: \(error)")
            Self.driftSyncFailedFor = currentCallsign
            // If change failed, try claiming the old registered account
            await claimPreviousCallsigns(currentCallsign: currentCallsign)
            return false
        }
    }

    /// Callsign whose drift sync already failed this launch; cleared by the
    /// next successful sync or app relaunch.
    private static var driftSyncFailedFor: String?

    /// Try to claim/merge data from any known previous callsigns.
    /// Skips callsigns that have already been successfully claimed.
    func claimPreviousCallsigns(currentCallsign: String) async {
        let aliasService = CallsignAliasService.shared
        let previous = aliasService.getPreviousCallsigns()

        guard !previous.isEmpty else {
            return
        }

        let alreadyClaimed = Set(
            UserDefaults.standard.stringArray(forKey: Self.claimedCallsignsKey) ?? []
        )

        var candidates = Set(previous.map { $0.uppercased() })
        candidates.remove(currentCallsign)
        candidates.subtract(alreadyClaimed)

        guard !candidates.isEmpty else {
            return
        }

        Self.logger.info(
            "Claiming previous accounts: \(candidates.sorted())"
        )

        var newlyClaimed = alreadyClaimed
        for oldCallsign in candidates.sorted() {
            do {
                let merged = try await claimPreviousAccount(previousCallsign: oldCallsign)
                if merged {
                    Self.logger.info("Merged previous account \(oldCallsign) into current")
                    newlyClaimed.insert(oldCallsign)
                }
            } catch {
                // userNotFound means no server account for that callsign — mark as done
                if let activitiesError = error as? ActivitiesError,
                   case .userNotFound = activitiesError
                {
                    newlyClaimed.insert(oldCallsign)
                } else {
                    Self.logger.error(
                        "Failed to claim \(oldCallsign): \(error)"
                    )
                }
            }
        }

        if newlyClaimed != alreadyClaimed {
            UserDefaults.standard.set(
                Array(newlyClaimed),
                forKey: Self.claimedCallsignsKey
            )
        }
    }
}
