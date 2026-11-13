// Video Overlay Renderer
//
// Core Graphics drawing helpers for video export overlays.
// Pure CG — no SwiftUI, no MapKit.

import CoreGraphics
import CoreText
import Foundation

// MARK: - VideoOverlayRenderer

nonisolated enum VideoOverlayRenderer {
    static let videoWidth: CGFloat = 1_920
    static let videoHeight: CGFloat = 1_080
}

// MARK: - QSO Markers

nonisolated extension VideoOverlayRenderer {
    /// Draws an accent-colored filled circle with a stroked outline at the given screen point.
    static func drawQSOMarker(
        in context: CGContext, at point: CGPoint, opacity: CGFloat, palette: VideoThemePalette
    ) {
        let radius: CGFloat = 6
        let strokeWidth: CGFloat = 1.5
        let circleRect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        context.saveGState()
        context.setAlpha(opacity)
        context.setFillColor(palette.accent)
        context.fillEllipse(in: circleRect)
        context.setStrokeColor(palette.accentStroke)
        context.setLineWidth(strokeWidth)
        context.strokeEllipse(in: circleRect)
        context.restoreGState()
    }

    /// Draws a rich callsign card above the given screen point.
    static func drawCallsignCard(
        in context: CGContext, qso: VideoQSOSnapshot,
        at point: CGPoint, opacity: CGFloat, palette: VideoThemePalette
    ) {
        let lines = buildCardLines(qso: qso, palette: palette)
        let lineHeight: CGFloat = 18
        let padding: CGFloat = 8
        let accentWidth: CGFloat = 4
        let maxWidth: CGFloat = 280
        let cardHeight = CGFloat(lines.count) * lineHeight + padding * 2
        let cardWidth = maxWidth
        let cornerRadius: CGFloat = 6

        let cardRect = CGRect(
            x: point.x - cardWidth / 2,
            y: point.y - 20 - cardHeight,
            width: cardWidth, height: cardHeight
        )

        let accentColor = modeAccentColor(qso.mode)

        context.saveGState()
        context.setAlpha(opacity)
        drawCardBackground(in: context, rect: cardRect, cornerRadius: cornerRadius, palette: palette)
        drawAccentStripe(in: context, rect: cardRect, width: accentWidth, color: accentColor)
        let textInset = cardRect.insetBy(dx: accentWidth, dy: 0)
            .offsetBy(dx: accentWidth / 2, dy: 0)
        let layout = CardTextLayout(
            rect: textInset, padding: padding, lineHeight: lineHeight, accentColor: accentColor
        )
        drawCardTextLines(in: context, lines: lines, layout: layout, palette: palette)
        context.restoreGState()
    }

    private static func buildCardLines(qso: VideoQSOSnapshot, palette: VideoThemePalette) -> [CardLine] {
        var lines: [CardLine] = []

        // Line 1: Callsign (bold) in theme primary text color
        lines.append(CardLine(text: qso.callsign, bold: true, size: 14, color: .primary))

        // Line 1b: RST with quality color
        if let sent = qso.rstSent, let rcvd = qso.rstReceived {
            let rstColor = rstCardColor(rstSent: sent, rstReceived: rcvd)
            lines.append(CardLine(text: "↑\(sent) ↓\(rcvd)", bold: false, size: 12, color: rstColor))
        }

        // Line 2: Name + emoji + club
        let nameParts = [qso.clubEmoji, qso.name?.capitalized, qso.clubName].compactMap { $0 }
        if !nameParts.isEmpty {
            lines.append(CardLine(
                text: nameParts.joined(separator: " "),
                bold: false, size: 12, color: .custom(0.85, 0.85, 0.85, 1)
            ))
        }

        // Line 3: Band/mode badge + special ref + Nth QSO badge
        var line3Parts = ["\(qso.band) \(qso.mode)"]
        let ref = qso.theirParkRef ?? qso.sotaRef ?? qso.wwffRef
        if let ref {
            line3Parts.append(ref)
        }
        if qso.priorQSOCount > 0 {
            line3Parts.append("QSO #\(qso.priorQSOCount + 1)")
        }
        lines.append(CardLine(
            text: line3Parts.joined(separator: " · "),
            bold: false, size: 11, color: .useAccent
        ))

        return lines
    }

    struct CardLine {
        let text: String
        let bold: Bool
        let size: CGFloat
        let color: CardLineColor
    }

    enum CardLineColor {
        case primary
        case secondary
        case useAccent
        case custom(CGFloat, CGFloat, CGFloat, CGFloat)
    }

    private static func drawCardBackground(
        in context: CGContext, rect: CGRect, cornerRadius: CGFloat, palette: VideoThemePalette
    ) {
        let path = CGPath(
            roundedRect: rect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        context.addPath(path)
        context.setFillColor(palette.cardBackground)
        context.fillPath()
    }

    struct CardTextLayout {
        let rect: CGRect
        let padding: CGFloat
        let lineHeight: CGFloat
        let accentColor: CGColor
    }

    private static func drawCardTextLines(
        in context: CGContext, lines: [CardLine], layout: CardTextLayout, palette: VideoThemePalette
    ) {
        for (idx, line) in lines.enumerated() {
            let fontName = line.bold ? "SFProText-Bold" : "SFProText-Regular"
            let fallback = line.bold ? "HelveticaNeue-Bold" : "HelveticaNeue"
            let font = makeFont(name: fontName, fallback: fallback, size: line.size)
            let textRect = CGRect(
                x: layout.rect.origin.x + layout.padding,
                y: layout.rect.origin.y + layout.padding + CGFloat(idx) * layout.lineHeight,
                width: layout.rect.width - layout.padding * 2,
                height: layout.lineHeight
            )
            let textColor = resolveCardLineColor(line.color, accentColor: layout.accentColor, palette: palette)
            drawCenteredText(line.text, in: context, rect: textRect, font: font, color: textColor, alignment: .left)
        }
    }

    private static func resolveCardLineColor(
        _ color: CardLineColor, accentColor: CGColor, palette: VideoThemePalette
    ) -> TextColor {
        switch color {
        case .primary:
            return .raw(palette.primaryText)
        case .secondary:
            return .raw(palette.secondaryText)
        case .useAccent:
            let comps = accentColor.components ?? [1, 1, 1, 1]
            let red = !comps.isEmpty ? comps[0] : 1
            let green = comps.count > 1 ? comps[1] : 1
            let blue = comps.count > 2 ? comps[2] : 1
            return .custom(red, green, blue, 0.9)
        case let .custom(red, green, blue, alpha):
            return .custom(red, green, blue, alpha)
        }
    }

    /// Draws a colored accent stripe on the left edge of the card.
    private static func drawAccentStripe(
        in context: CGContext, rect: CGRect, width: CGFloat, color: CGColor
    ) {
        let stripeRect = CGRect(x: rect.origin.x, y: rect.origin.y, width: width, height: rect.height)
        let path = CGMutablePath()
        path.addRoundedRect(
            in: CGRect(x: rect.origin.x, y: rect.origin.y, width: width + 6, height: rect.height),
            cornerWidth: 6, cornerHeight: 6
        )
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.setFillColor(color)
        context.fill(stripeRect)
        context.restoreGState()
    }

    /// Returns a CG accent color for a given mode string.
    static func modeAccentColor(_ mode: String) -> CGColor {
        switch mode.uppercased() {
        case "CW":
            CGColor(red: 0.7, green: 0.5, blue: 1.0, alpha: 1) // purple
        case "SSB",
             "USB",
             "LSB",
             "AM",
             "FM":
            CGColor(red: 0.3, green: 0.75, blue: 0.45, alpha: 1) // green
        case "FT8",
             "FT4":
            CGColor(red: 1.0, green: 0.65, blue: 0.2, alpha: 1) // orange
        case "RTTY",
             "PSK31",
             "JS8":
            CGColor(red: 0.3, green: 0.7, blue: 0.9, alpha: 1) // cyan
        default:
            CGColor(red: 0.5, green: 0.7, blue: 1.0, alpha: 1) // blue
        }
    }
}

// MARK: - GeodesicArcShape

nonisolated struct GeodesicArcShape {
    let start: CGPoint
    let end: CGPoint
    let controlHeight: CGFloat
}

nonisolated extension VideoOverlayRenderer {
    /// Draws a quadratic Bezier arc between two screen points.
    static func drawGeodesicArc(
        in context: CGContext,
        shape: GeodesicArcShape,
        opacity: CGFloat,
        palette: VideoThemePalette
    ) {
        let midX = (shape.start.x + shape.end.x) / 2
        let midY = (shape.start.y + shape.end.y) / 2
        let controlPoint = CGPoint(x: midX, y: midY - shape.controlHeight)

        context.saveGState()
        context.setAlpha(opacity)
        context.setStrokeColor(palette.arcColor)
        context.setLineWidth(2)
        context.setLineCap(.round)
        context.move(to: shape.start)
        context.addQuadCurve(to: shape.end, control: controlPoint)
        context.strokePath()
        context.restoreGState()
    }
}

// MARK: - Spot Pulses

nonisolated extension VideoOverlayRenderer {
    /// Draws a water-droplet ping: center splash + single expanding ripple.
    static func drawSpotPulse(
        in context: CGContext, at point: CGPoint, pulseProgress: CGFloat, palette: VideoThemePalette
    ) {
        let maxRadius: CGFloat = 40
        let pulseColor = palette.spotPulse

        context.saveGState()

        // Center splash: small filled circle that fades out by progress 0.3
        let splashRadius: CGFloat = 4
        let splashOpacity = max(0, 1.0 - pulseProgress / 0.3)
        if splashOpacity > 0 {
            let splashRect = CGRect(
                x: point.x - splashRadius, y: point.y - splashRadius,
                width: splashRadius * 2, height: splashRadius * 2
            )
            context.setAlpha(splashOpacity)
            context.setFillColor(pulseColor)
            context.fillEllipse(in: splashRect)
        }

        // Expanding ripple: sqrt easing for natural water-drop spread
        let rippleRadius = maxRadius * sqrt(pulseProgress)
        if rippleRadius > 0 {
            let rippleOpacity = 1.0 - pulseProgress
            let fillOpacity = 0.15 * rippleOpacity
            let rippleRect = CGRect(
                x: point.x - rippleRadius, y: point.y - rippleRadius,
                width: rippleRadius * 2, height: rippleRadius * 2
            )
            // Filled ripple disc
            context.setAlpha(fillOpacity)
            context.setFillColor(pulseColor)
            context.fillEllipse(in: rippleRect)
            // Stroke ring
            context.setAlpha(rippleOpacity)
            context.setStrokeColor(pulseColor)
            context.setLineWidth(1.5)
            context.strokeEllipse(in: rippleRect)
        }

        context.restoreGState()
    }
}

// MARK: - Private Helpers

nonisolated extension VideoOverlayRenderer {
    enum TextAlignment {
        case center
        case left
        case right
    }

    private static let whiteCGColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)

    enum TextColor {
        case white
        case custom(CGFloat, CGFloat, CGFloat, CGFloat)
        case raw(CGColor)

        // MARK: Internal

        var cgColor: CGColor {
            switch self {
            case .white:
                VideoOverlayRenderer.whiteCGColor
            case let .custom(red, green, blue, alpha):
                CGColor(red: red, green: green, blue: blue, alpha: alpha)
            case let .raw(color):
                color
            }
        }
    }

    /// Cached fonts keyed by "name-size". Avoids expensive CTFontCreateWithName every frame.
    /// Only accessed from VideoExportActor's pipeline — single-threaded access.
    nonisolated(unsafe) private static var fontCache: [String: CTFont] = [:]

    static func makeFont(name: String, fallback: String, size: CGFloat) -> CTFont {
        let key = "\(name)-\(Int(size))"
        if let cached = fontCache[key] {
            return cached
        }
        let primary = CTFontCreateWithName(name as CFString, size, nil)
        let primaryName = CTFontCopyPostScriptName(primary) as String
        let font: CTFont = if primaryName == name {
            primary
        } else {
            CTFontCreateWithName(fallback as CFString, size, nil)
        }
        fontCache[key] = font
        return font
    }

    static func formatElapsedTime(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    static func drawCenteredText(
        _ text: String,
        in context: CGContext,
        rect: CGRect,
        font: CTFont,
        color: TextColor = .white,
        alignment: TextAlignment = .center
    ) {
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color.cgColor,
        ]
        let attrString = CFAttributedStringCreate(
            nil,
            text as CFString,
            attributes as CFDictionary
        )!
        let line = CTLineCreateWithAttributedString(attrString)
        let lineBounds = CTLineGetBoundsWithOptions(line, [])

        let textX: CGFloat = switch alignment {
        case .center:
            rect.origin.x + (rect.width - lineBounds.width) / 2
        case .left:
            rect.origin.x
        case .right:
            rect.origin.x + rect.width - lineBounds.width
        }
        let textY = rect.origin.y + (rect.height - lineBounds.height) / 2 + abs(lineBounds.origin.y)

        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: textX, y: textY)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
