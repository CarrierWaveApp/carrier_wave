//
//  LinkPreviewCardRenderer.swift
//  CarrierWaveCore
//
//  Renders a LinkPreviewCardView to a PlatformImage using SwiftUI's
//  ImageRenderer (iOS 16+/macOS 13+). Cross-platform — no UIKit/AppKit
//  imports beyond the PlatformImage typealias.
//

import SwiftUI

// MARK: - LinkPreviewCardRenderer

@MainActor
public enum LinkPreviewCardRenderer {
    /// Render a card for the given payload kind. Returns nil if rendering
    /// fails (extremely rare on supported platforms).
    public static func render(_ kind: LinkPreviewCardKind) -> PlatformImage? {
        let view = LinkPreviewCardView(kind: kind)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        renderer.isOpaque = true
        #if canImport(UIKit)
            return renderer.uiImage
        #elseif canImport(AppKit)
            return renderer.nsImage
        #else
            return nil
        #endif
    }

    /// Convenience overloads for each payload kind.
    public static func render(callsign payload: CallsignPayload) -> PlatformImage? {
        render(.callsign(payload))
    }

    public static func render(park payload: ParkPayload) -> PlatformImage? {
        render(.park(payload))
    }

    public static func render(qso payload: QSOPayload) -> PlatformImage? {
        render(.qso(payload))
    }

    public static func render(activation payload: ActivationPayload) -> PlatformImage? {
        render(.activation(payload))
    }
}
