//
//  EnrichedLinkItemProvider.swift
//  CarrierWave
//
//  UIActivityItemSource that produces an LPLinkMetadata-rich share item
//  for an enriched link payload. The metadata travels with the message
//  in iMessage / Mail / Notes — recipients see the rich card immediately
//  without the receiving app needing to fetch the URL.
//
//  See docs/plans/2026-04-07-imessage-enriched-text-design.md.
//

import CarrierWaveCore
import LinkPresentation
import UIKit

@MainActor
final class EnrichedLinkItemProvider: NSObject, UIActivityItemSource {
    // MARK: Lifecycle

    init?(payload: EnrichedLinkPayload) {
        guard let url = Self.buildURL(for: payload) else {
            return nil
        }
        self.payload = payload
        self.url = url
        cardImage = LinkPreviewCardRenderer.render(Self.cardKind(for: payload))
        super.init()
    }

    // MARK: Internal

    let url: URL

    func activityViewControllerPlaceholderItem(
        _: UIActivityViewController
    ) -> Any {
        url
    }

    func activityViewController(
        _: UIActivityViewController,
        itemForActivityType _: UIActivity.ActivityType?
    ) -> Any? {
        url
    }

    func activityViewControllerLinkMetadata(
        _: UIActivityViewController
    ) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.originalURL = url
        metadata.url = url
        metadata.title = title
        if let cardImage {
            metadata.imageProvider = NSItemProvider(object: cardImage)
            metadata.iconProvider = NSItemProvider(object: cardImage)
        }
        return metadata
    }

    // MARK: Private

    private let payload: EnrichedLinkPayload
    private let cardImage: UIImage?

    private var title: String {
        switch payload {
        case let .callsign(call):
            if let name = call.name {
                "\(call.callsign) — \(name)"
            } else {
                call.callsign
            }
        case let .park(park):
            if let name = park.name {
                "\(park.reference) — \(name)"
            } else {
                park.reference
            }
        case let .summit(summit):
            if let name = summit.name {
                "\(summit.reference) — \(name)"
            } else {
                summit.reference
            }
        case let .qso(qso):
            "QSO with \(qso.theirCall) on \(qso.band) \(qso.mode)"
        case let .activation(act):
            if let name = act.parkName {
                "Activation: \(act.parkReference) \(name)"
            } else {
                "Activation: \(act.parkReference)"
            }
        }
    }

    private static func cardKind(
        for payload: EnrichedLinkPayload
    ) -> LinkPreviewCardKind {
        switch payload {
        case let .callsign(call): .callsign(call)
        case let .park(park): .park(park)
        case let .summit(summit): .summit(summit)
        case let .qso(qso): .qso(qso)
        case let .activation(act): .activation(act)
        }
    }

    private static func buildURL(for payload: EnrichedLinkPayload) -> URL? {
        switch payload {
        case let .callsign(call): try? EnrichedLinkBuilder.url(for: call)
        case let .park(park): try? EnrichedLinkBuilder.url(for: park)
        case let .summit(summit): try? EnrichedLinkBuilder.url(for: summit)
        case let .qso(qso): try? EnrichedLinkBuilder.url(for: qso)
        case let .activation(act): try? EnrichedLinkBuilder.url(for: act)
        }
    }
}
