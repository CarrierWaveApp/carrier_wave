//
//  CarrierWaveApp+EnrichedLinks.swift
//  CarrierWave
//
//  Universal link handling for enriched share links
//  (https://carrierwave.app/link/<kind>/<id>). Decodes the fragment
//  payload and posts notifications that detail views can subscribe to in
//  order to deeplink the recipient straight to the relevant context.
//

import CarrierWaveCore
import Foundation

// MARK: - Notification names

extension Notification.Name {
    /// Posted when an enriched callsign link is opened. UserInfo:
    /// `callsign: String`, `payload: CallsignPayload`.
    static let didOpenEnrichedCallsignLink = Notification.Name(
        "didOpenEnrichedCallsignLink"
    )
    /// Posted when an enriched park link is opened. UserInfo:
    /// `reference: String`, `payload: ParkPayload`.
    static let didOpenEnrichedParkLink = Notification.Name(
        "didOpenEnrichedParkLink"
    )
    /// Posted when an enriched QSO link is opened. UserInfo:
    /// `payload: QSOPayload`.
    static let didOpenEnrichedQSOLink = Notification.Name(
        "didOpenEnrichedQSOLink"
    )
    /// Posted when an enriched activation link is opened. UserInfo:
    /// `payload: ActivationPayload`.
    static let didOpenEnrichedActivationLink = Notification.Name(
        "didOpenEnrichedActivationLink"
    )
}

extension CarrierWaveApp {
    /// Handle a Carrier Wave enriched-share universal link. Falls back to
    /// posting a kind-only notification if the fragment is missing or
    /// malformed (the recipient still gets navigated to the right detail
    /// area, just with less context).
    func handleEnrichedLinkURL(_ url: URL) {
        let payload = EnrichedLinkBuilder.decode(url)
        let kind = EnrichedLinkBuilder.kind(of: url) ?? ""
        let identifier = EnrichedLinkBuilder.identifier(of: url) ?? ""

        switch kind {
        case "call":
            postCallsignNotification(payload: payload, fallbackId: identifier)
        case "park":
            postParkNotification(payload: payload, fallbackId: identifier)
        case "qso":
            if case let .qso(qso) = payload {
                NotificationCenter.default.post(
                    name: .didOpenEnrichedQSOLink,
                    object: nil,
                    userInfo: ["payload": qso]
                )
            }
        case "act":
            if case let .activation(act) = payload {
                NotificationCenter.default.post(
                    name: .didOpenEnrichedActivationLink,
                    object: nil,
                    userInfo: ["payload": act]
                )
            }
        default:
            break
        }
    }

    private func postCallsignNotification(
        payload: EnrichedLinkPayload?,
        fallbackId: String
    ) {
        var userInfo: [String: Any] = [:]
        if case let .callsign(call) = payload {
            userInfo["callsign"] = call.callsign
            userInfo["payload"] = call
        } else {
            // Fragment was missing or unreadable. Restore `/` from `-` so
            // KD9LSV-P routes to KD9LSV/P. The path identifier is best-effort.
            let restored = fallbackId.replacingOccurrences(of: "-", with: "/")
            userInfo["callsign"] = restored
        }
        NotificationCenter.default.post(
            name: .didOpenEnrichedCallsignLink,
            object: nil,
            userInfo: userInfo
        )
    }

    private func postParkNotification(
        payload: EnrichedLinkPayload?,
        fallbackId: String
    ) {
        var userInfo: [String: Any] = [:]
        if case let .park(park) = payload {
            userInfo["reference"] = park.reference
            userInfo["payload"] = park
        } else {
            let restored = fallbackId.replacingOccurrences(of: "-", with: "/")
            userInfo["reference"] = restored
        }
        NotificationCenter.default.post(
            name: .didOpenEnrichedParkLink,
            object: nil,
            userInfo: userInfo
        )
    }
}
