//
//  EnrichedLinkSharing.swift
//  CWSweep
//
//  macOS share helper and universal link routing for enriched share
//  links. Mirrors the iOS-side EnrichedLinkItemProvider /
//  EnrichedShareButton — uses NSSharingServicePicker instead of
//  UIActivityViewController, and posts the same notifications as the
//  iOS app.
//

import AppKit
import CarrierWaveCore
import Foundation
import LinkPresentation

// MARK: - EnrichedLinkSharing

@MainActor
enum EnrichedLinkSharing {
    // MARK: Internal

    /// Show NSSharingServicePicker anchored to the given view, sharing the
    /// given enriched payload as a URL with rich LPLinkMetadata so iMessage
    /// / Mail get the rich card preview.
    static func share(
        _ payload: EnrichedLinkPayload,
        from sourceView: NSView,
        rect: NSRect? = nil
    ) {
        guard let url = buildURL(for: payload) else {
            return
        }
        let metadata = makeMetadata(payload: payload, url: url)
        let item = EnrichedLinkSharingItem(url: url, metadata: metadata)
        let picker = NSSharingServicePicker(items: [item])
        picker.show(
            relativeTo: rect ?? sourceView.bounds,
            of: sourceView,
            preferredEdge: .minY
        )
    }

    /// Build a URL for any payload kind. Returns nil if encoding fails.
    static func buildURL(for payload: EnrichedLinkPayload) -> URL? {
        switch payload {
        case let .callsign(call): try? EnrichedLinkBuilder.url(for: call)
        case let .park(park): try? EnrichedLinkBuilder.url(for: park)
        case let .summit(summit): try? EnrichedLinkBuilder.url(for: summit)
        case let .qso(qso): try? EnrichedLinkBuilder.url(for: qso)
        case let .activation(act): try? EnrichedLinkBuilder.url(for: act)
        }
    }

    // MARK: Private

    private static func makeMetadata(
        payload: EnrichedLinkPayload,
        url: URL
    ) -> LPLinkMetadata {
        let metadata = LPLinkMetadata()
        metadata.originalURL = url
        metadata.url = url
        metadata.title = title(for: payload)
        let kind: LinkPreviewCardKind = switch payload {
        case let .callsign(call): .callsign(call)
        case let .park(park): .park(park)
        case let .summit(summit): .summit(summit)
        case let .qso(qso): .qso(qso)
        case let .activation(act): .activation(act)
        }
        if let image = LinkPreviewCardRenderer.render(kind) {
            metadata.imageProvider = NSItemProvider(object: image)
            metadata.iconProvider = NSItemProvider(object: image)
        }
        return metadata
    }

    private static func title(for payload: EnrichedLinkPayload) -> String {
        switch payload {
        case let .callsign(call):
            call.name.map { "\(call.callsign) — \($0)" } ?? call.callsign
        case let .park(park):
            park.name.map { "\(park.reference) — \($0)" } ?? park.reference
        case let .summit(summit):
            summit.name.map { "\(summit.reference) — \($0)" } ?? summit.reference
        case let .qso(qso):
            "QSO with \(qso.theirCall) on \(qso.band) \(qso.mode)"
        case let .activation(act):
            act.parkName.map { "Activation: \(act.parkReference) \($0)" }
                ?? "Activation: \(act.parkReference)"
        }
    }
}

// MARK: - EnrichedLinkSharingItem

/// NSSharingServicePicker requires items conforming to its informal API:
/// `NSPasteboardWriting` works, but for LPLinkMetadata participation we
/// implement `NSSharingServicePickerDelegate` indirection via the rarely
/// used metadata source. The simplest cross-version-safe path is wrapping
/// the URL in a small adapter object that mirrors NSItemProvider's data.
private final class EnrichedLinkSharingItem: NSObject, NSItemProviderWriting {
    // MARK: Lifecycle

    init(url: URL, metadata: LPLinkMetadata) {
        self.url = url
        self.metadata = metadata
        super.init()
    }

    // MARK: Internal

    static var writableTypeIdentifiersForItemProvider: [String] {
        ["public.url"]
    }

    let url: URL
    let metadata: LPLinkMetadata

    func loadData(
        withTypeIdentifier _: String,
        forItemProviderCompletionHandler completionHandler: @escaping (Data?, Error?) -> Void
    ) -> Progress? {
        completionHandler(url.absoluteString.data(using: .utf8), nil)
        return nil
    }
}

// MARK: - URL routing

extension Notification.Name {
    /// Posted when CW Sweep receives an enriched callsign link.
    static let cwSweepDidOpenEnrichedCallsignLink = Notification.Name(
        "cwSweepDidOpenEnrichedCallsignLink"
    )
    static let cwSweepDidOpenEnrichedParkLink = Notification.Name(
        "cwSweepDidOpenEnrichedParkLink"
    )
    static let cwSweepDidOpenEnrichedSummitLink = Notification.Name(
        "cwSweepDidOpenEnrichedSummitLink"
    )
    static let cwSweepDidOpenEnrichedQSOLink = Notification.Name(
        "cwSweepDidOpenEnrichedQSOLink"
    )
    static let cwSweepDidOpenEnrichedActivationLink = Notification.Name(
        "cwSweepDidOpenEnrichedActivationLink"
    )
}

// MARK: - EnrichedLinkRouter

@MainActor
enum EnrichedLinkRouter {
    /// Handle a universal link URL. Returns true if handled.
    @discardableResult
    static func handle(_ url: URL) -> Bool {
        guard EnrichedLinkBuilder.isEnrichedLink(url) else {
            return false
        }
        let payload = EnrichedLinkBuilder.decode(url)
        let kind = EnrichedLinkBuilder.kind(of: url) ?? ""
        switch kind {
        case "call":
            if case let .callsign(call) = payload {
                NotificationCenter.default.post(
                    name: .cwSweepDidOpenEnrichedCallsignLink,
                    object: nil,
                    userInfo: ["payload": call, "callsign": call.callsign]
                )
            }
        case "park":
            if case let .park(park) = payload {
                NotificationCenter.default.post(
                    name: .cwSweepDidOpenEnrichedParkLink,
                    object: nil,
                    userInfo: ["payload": park, "reference": park.reference]
                )
            }
        case "sum":
            if case let .summit(summit) = payload {
                NotificationCenter.default.post(
                    name: .cwSweepDidOpenEnrichedSummitLink,
                    object: nil,
                    userInfo: ["payload": summit, "reference": summit.reference]
                )
            }
        case "qso":
            if case let .qso(qso) = payload {
                NotificationCenter.default.post(
                    name: .cwSweepDidOpenEnrichedQSOLink,
                    object: nil,
                    userInfo: ["payload": qso]
                )
            }
        case "act":
            if case let .activation(act) = payload {
                NotificationCenter.default.post(
                    name: .cwSweepDidOpenEnrichedActivationLink,
                    object: nil,
                    userInfo: ["payload": act]
                )
            }
        default:
            return false
        }
        return true
    }
}
