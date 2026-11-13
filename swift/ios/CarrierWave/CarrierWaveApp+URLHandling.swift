import CarrierWaveCore
import CarrierWaveData
import Foundation
import UIKit

// MARK: - URL Handling

extension CarrierWaveApp {
    func handleURL(_ url: URL) {
        // Check if it's a qsy:// URI (inter-app ham radio interop)
        if url.scheme?.lowercased() == "qsy" {
            handleQSYURL(url)
            return
        }

        // Saved-query share link (cwquery://). Import unconditionally
        // so a query lands in the iCloud-Drive store even when the
        // experimental flag is off — users find it waiting next time
        // they enable Query Runner.
        if url.scheme?.lowercased() == SavedQueryURL.scheme {
            Task { @MainActor in
                await QueryRunnerServices.shared.importSharedURL(url)
            }
            return
        }

        // Phase 5 OAuth magic-link return (O4 universal-link path). Two forms:
        // - carrierwave://auth?code=XXX        (custom scheme — works today)
        // - https://*.carrierwave.app/link/auth?code=XXX  (universal link — once
        //   the associated-domains entitlement + AASA land in the infra step)
        // Checked before the enriched-link branch so `/link/auth` isn't swallowed.
        if isOAuthReturnURL(url) {
            handleOAuthReturnURL(url)
            return
        }

        // Check if it's an enriched share link (https://carrierwave.app/link/<kind>/<id>)
        if EnrichedLinkBuilder.isEnrichedLink(url) {
            handleEnrichedLinkURL(url)
            return
        }

        // Check if it's a friend invite link (carrierwave://invite/{token})
        if url.scheme == "carrierwave", url.host == "invite" {
            handleFriendInviteURL(url)
            return
        }

        // Check for HTTPS friend invite link (https://*.carrierwave.app/invite/{token})
        if let host = url.host, host.hasSuffix("carrierwave.app"),
           url.pathComponents.count >= 2, url.pathComponents[1] == "invite"
        {
            handleFriendInviteURL(url)
            return
        }

        // Check for widget deep links (carrierwave://activitylog, dashboard, hunt, logger)
        if url.scheme == "carrierwave",
           let host = url.host,
           ["activitylog", "conditions", "dashboard", "hunt", "logger"].contains(host)
        {
            NotificationCenter.default.post(
                name: .didReceiveWidgetDeepLink,
                object: nil,
                userInfo: ["target": host]
            )
            return
        }

        // Otherwise treat as ADIF file
        NotificationCenter.default.post(
            name: .didReceiveADIFFile,
            object: url
        )
    }

    func handleFriendInviteURL(_ url: URL) {
        // Parse invite token from URL
        // Formats:
        // - carrierwave://invite/{token}
        // - https://*.carrierwave.app/invite/{token}
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        var token: String?

        if url.scheme == "carrierwave" {
            // carrierwave://invite/{token} - token is in host or first path component
            if let host = url.host, host != "invite" {
                token = host
            } else if let first = pathComponents.first {
                token = first
            }
        } else {
            // https://*.carrierwave.app/invite/{token}
            if let inviteIndex = pathComponents.firstIndex(of: "invite"),
               inviteIndex + 1 < pathComponents.count
            {
                token = pathComponents[inviteIndex + 1]
            }
        }

        guard let inviteToken = token, !inviteToken.isEmpty else {
            return
        }

        NotificationCenter.default.post(
            name: .didReceiveFriendInvite,
            object: nil,
            userInfo: ["token": inviteToken]
        )
    }

    /// True for an OAuth magic-link return URL: the custom scheme, the
    /// `/link/auth` path, or the emailed `/v1/auth/verify/complete` verification
    /// endpoint (the Universal Link target) on a carrierwave.app host.
    func isOAuthReturnURL(_ url: URL) -> Bool {
        if url.scheme == "carrierwave", url.host == "auth" {
            return true
        }
        if let host = url.host, host.hasSuffix("carrierwave.app") {
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.first == "link", parts.dropFirst().first == "auth" {
                return true
            }
            return parts == ["v1", "auth", "verify", "complete"]
        }
        return false
    }

    /// Redeem the magic-link `code` against the pending verification (the PKCE
    /// verifier persisted by `OAuthClient.startVerification`). A foreign/stale
    /// link with no pending verification on this device can't mint tokens (F8) —
    /// it simply posts the failure notification.
    func handleOAuthReturnURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty
        else {
            return
        }
        Task { @MainActor in
            do {
                let outcome = try await ActivitiesClient().oauth.completeFromLink(code)
                switch outcome {
                case .signedIn,
                     .attachedToAccount:
                    NotificationCenter.default.post(name: .didCompleteOAuthVerification, object: nil)
                case .acknowledgedRemotely:
                    // Marked clicked here, but sign-in was started on another
                    // device, which finishes it via its own poll — nothing to do.
                    break
                case .notCompleted:
                    NotificationCenter.default.post(name: .didFailOAuthVerification, object: nil)
                }
            } catch {
                NotificationCenter.default.post(name: .didFailOAuthVerification, object: nil)
            }
        }
    }

    func handleQSYURL(_ url: URL) {
        guard let action = QSYURIParser.parse(url) else {
            return
        }

        switch action {
        case let .spot(params):
            postQSYSpotNotification(params)
        case let .tune(params):
            NotificationCenter.default.post(
                name: .didReceiveQSYTune,
                object: nil,
                userInfo: [
                    "frequencyMHz": params.frequencyMHz,
                    "mode": params.mode as Any,
                ]
            )
        case let .lookup(callsign):
            NotificationCenter.default.post(
                name: .didReceiveQSYLookup,
                object: nil,
                userInfo: ["callsign": callsign]
            )
        case let .importLog(importURL, _):
            NotificationCenter.default.post(
                name: .didReceiveADIFFile,
                object: importURL
            )
        case let .log(params):
            postQSYLogNotification(params)
        }
    }

    func postQSYSpotNotification(_ params: QSYSpotParams) {
        NotificationCenter.default.post(
            name: .didReceiveQSYSpot,
            object: nil,
            userInfo: [
                "callsign": params.callsign,
                "frequencyMHz": params.frequencyMHz,
                "mode": params.mode as Any,
                "grid": params.grid as Any,
                "ref": params.ref?.first as Any,
                "refType": params.refType?.first as Any,
                "source": params.source as Any,
                "comment": params.comment as Any,
            ]
        )
    }

    func postQSYLogNotification(_ params: QSYLogParams) {
        NotificationCenter.default.post(
            name: .didReceiveQSYLog,
            object: nil,
            userInfo: [
                "callsign": params.callsign,
                "frequencyMHz": params.frequencyMHz,
                "mode": params.mode,
                "rstSent": params.rstSent as Any,
                "rstReceived": params.rstReceived as Any,
                "grid": params.grid as Any,
                "ref": params.ref?.first as Any,
                "refType": params.refType?.first as Any,
                "time": params.time as Any,
                "contest": params.contest as Any,
                "srx": params.srx as Any,
                "stx": params.stx as Any,
                "source": params.source as Any,
                "comment": params.comment as Any,
            ]
        )
    }
}
