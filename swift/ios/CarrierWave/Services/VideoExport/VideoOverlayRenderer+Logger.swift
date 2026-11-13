// Video Overlay Renderer — Logger Panel
//
// Draws the per-replay logger overlay: a corner-anchored card that holds the
// freshly-logged QSO, then flies it into its map marker.

import CoreGraphics
import CoreText
import Foundation

nonisolated extension VideoOverlayRenderer {
    static func drawLoggerOverlay(
        in context: CGContext,
        state: VideoLoggerOverlayState,
        palette: VideoThemePalette
    ) {
        switch state.phase {
        case .panel:
            drawPanelCard(in: context, state: state, scale: 1.0, opacity: 1.0, palette: palette)
        case let .flying(progress):
            drawFlyingCard(in: context, state: state, progress: progress, palette: palette)
        }
    }

    private static func drawFlyingCard(
        in context: CGContext,
        state: VideoLoggerOverlayState,
        progress: CGFloat,
        palette: VideoThemePalette
    ) {
        guard let landing = state.landingPoint else {
            drawPanelCard(in: context, state: state, scale: 1.0, opacity: 1.0, palette: palette)
            return
        }
        let center = VideoLoggerOverlayInterpolator.currentCenter(
            panel: state.panelRect, landing: landing, progress: progress
        )
        let scale = VideoLoggerOverlayInterpolator.currentScale(progress: progress)
        let opacity = VideoLoggerOverlayInterpolator.currentOpacity(progress: progress)
        let movedRect = CGRect(
            x: center.x - state.panelRect.width / 2,
            y: center.y - state.panelRect.height / 2,
            width: state.panelRect.width,
            height: state.panelRect.height
        )
        let moved = VideoLoggerOverlayState(
            qso: state.qso,
            phase: .panel,
            panelRect: movedRect,
            panelRegionIndex: state.panelRegionIndex,
            landingPoint: state.landingPoint
        )
        drawPanelCard(in: context, state: moved, scale: scale, opacity: opacity, palette: palette)
    }

    private static func drawPanelCard(
        in context: CGContext,
        state: VideoLoggerOverlayState,
        scale: CGFloat,
        opacity: CGFloat,
        palette: VideoThemePalette
    ) {
        guard opacity > 0.01 else {
            return
        }
        context.saveGState()
        context.setAlpha(opacity)
        applyTransform(in: context, around: state.panelRect, scale: scale)
        let accent = modeAccentColor(state.qso.mode)
        drawPanelBackground(in: context, rect: state.panelRect, palette: palette)
        drawPanelAccent(in: context, rect: state.panelRect, color: accent)
        drawPanelText(in: context, rect: state.panelRect, qso: state.qso, accent: accent, palette: palette)
        context.restoreGState()
    }

    private static func applyTransform(in context: CGContext, around rect: CGRect, scale: CGFloat) {
        let centerX = rect.midX
        let centerY = rect.midY
        context.translateBy(x: centerX, y: centerY)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -centerX, y: -centerY)
    }
}

// MARK: - Panel Pieces

nonisolated extension VideoOverlayRenderer {
    private static let panelCornerRadius: CGFloat = 10
    private static let panelAccentWidth: CGFloat = 5
    private static let panelInset: CGFloat = 14

    private static func drawPanelBackground(
        in context: CGContext, rect: CGRect, palette: VideoThemePalette
    ) {
        let path = CGPath(
            roundedRect: rect,
            cornerWidth: panelCornerRadius,
            cornerHeight: panelCornerRadius,
            transform: nil
        )
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 4), blur: 18, color: shadowColor)
        context.addPath(path)
        context.setFillColor(palette.cardBackground)
        context.fillPath()
        context.restoreGState()
    }

    private static func drawPanelAccent(in context: CGContext, rect: CGRect, color: CGColor) {
        let stripeRect = CGRect(
            x: rect.origin.x, y: rect.origin.y,
            width: panelAccentWidth, height: rect.height
        )
        let clipPath = CGPath(
            roundedRect: rect,
            cornerWidth: panelCornerRadius,
            cornerHeight: panelCornerRadius,
            transform: nil
        )
        context.saveGState()
        context.addPath(clipPath)
        context.clip()
        context.setFillColor(color)
        context.fill(stripeRect)
        context.restoreGState()
    }

    private static func drawPanelText(
        in context: CGContext, rect: CGRect, qso: VideoQSOSnapshot,
        accent: CGColor, palette: VideoThemePalette
    ) {
        let textOriginX = rect.origin.x + panelAccentWidth + panelInset
        let textWidth = rect.width - panelAccentWidth - panelInset * 2
        let labelRect = CGRect(
            x: textOriginX, y: rect.origin.y + panelInset,
            width: textWidth, height: 14
        )
        let callRect = CGRect(
            x: textOriginX, y: rect.origin.y + panelInset + 16,
            width: textWidth, height: 32
        )
        let detailRect = CGRect(
            x: textOriginX, y: rect.origin.y + panelInset + 52,
            width: textWidth, height: 18
        )
        drawCenteredText(
            "LOGGED",
            in: context,
            rect: labelRect,
            font: makeFont(name: "SFProText-Semibold", fallback: "HelveticaNeue-Medium", size: 11),
            color: .raw(palette.secondaryText),
            alignment: .left
        )
        drawCenteredText(
            qso.callsign,
            in: context,
            rect: callRect,
            font: makeFont(name: "SFProText-Bold", fallback: "HelveticaNeue-Bold", size: 26),
            color: .raw(palette.primaryText),
            alignment: .left
        )
        drawCenteredText(
            buildDetailLine(qso: qso),
            in: context,
            rect: detailRect,
            font: makeFont(name: "SFProText-Regular", fallback: "HelveticaNeue", size: 13),
            color: .raw(accent),
            alignment: .left
        )
    }

    private static func buildDetailLine(qso: VideoQSOSnapshot) -> String {
        var parts = ["\(qso.band) \(qso.mode)"]
        if let sent = qso.rstSent, let rcvd = qso.rstReceived {
            parts.append("↑\(sent) ↓\(rcvd)")
        }
        if let ref = qso.theirParkRef ?? qso.sotaRef ?? qso.wwffRef {
            parts.append(ref)
        }
        return parts.joined(separator: " · ")
    }

    private static let shadowColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.35)
}
