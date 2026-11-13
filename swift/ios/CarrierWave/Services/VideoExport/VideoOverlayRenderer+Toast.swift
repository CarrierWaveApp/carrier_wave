// Video Overlay Renderer — Toast Cards
//
// Toast card drawing with RST quality coloring for video export overlays.

import CoreGraphics
import CoreText
import Foundation

// MARK: - Toast Card

nonisolated extension VideoOverlayRenderer {
    /// Draws a toast card at the bottom of the frame showing QSO info.
    static func drawToastCard(
        in context: CGContext,
        toast: ToastCardState,
        palette: VideoThemePalette
    ) {
        let cardWidth: CGFloat = 600
        let cardHeight: CGFloat = 60
        let bottomMargin: CGFloat = 40
        let cornerRadius: CGFloat = 12

        let xOrigin = (videoWidth - cardWidth) / 2
        let fullyVisibleY = videoHeight - cardHeight - bottomMargin
        let offscreenY = videoHeight
        let yOrigin = offscreenY - (offscreenY - fullyVisibleY) * toast.slideProgress

        let cardRect = CGRect(x: xOrigin, y: yOrigin, width: cardWidth, height: cardHeight)
        let path = CGPath(roundedRect: cardRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        context.saveGState()
        context.addPath(path)
        context.clip()
        context.setFillColor(palette.cardBackground)
        context.fill(cardRect)
        context.restoreGState()

        drawToastContent(in: context, toast: toast, cardRect: cardRect, palette: palette)
    }

    /// Draws the text content inside a toast card.
    static func drawToastContent(
        in context: CGContext,
        toast: ToastCardState,
        cardRect: CGRect,
        palette: VideoThemePalette
    ) {
        let padding: CGFloat = 16
        let boldFont = makeFont(name: "SFProText-Bold", fallback: "HelveticaNeue-Bold", size: 18)
        let font = makeFont(name: "SFProText-Regular", fallback: "HelveticaNeue", size: 14)
        var cursorX = cardRect.origin.x + padding
        let primary = TextColor.raw(palette.primaryText)
        let secondary = TextColor.raw(palette.secondaryText)

        // Callsign (bold)
        let callRect = CGRect(x: cursorX, y: cardRect.origin.y, width: 180, height: cardRect.height)
        drawCenteredText(toast.text, in: context, rect: callRect, font: boldFont, color: primary, alignment: .left)
        cursorX += 188

        // Name
        if let name = toast.name?.capitalized {
            let nameRect = CGRect(x: cursorX, y: cardRect.origin.y, width: 140, height: cardRect.height)
            drawCenteredText(
                name, in: context, rect: nameRect,
                font: font, color: secondary, alignment: .left
            )
            cursorX += 148
        }

        // RST sent/received with quality color
        drawToastRST(in: context, toast: toast, cursorX: &cursorX, cardRect: cardRect, font: font)

        // Park reference (right side)
        if let park = toast.parkRef {
            let parkRect = CGRect(
                x: cardRect.maxX - 160 - padding,
                y: cardRect.origin.y, width: 160, height: cardRect.height
            )
            drawCenteredText(
                park, in: context, rect: parkRect,
                font: font, color: .custom(0.4, 0.8, 0.4, 1), alignment: .right
            )
        }
    }

    private static func drawToastRST(
        in context: CGContext,
        toast: ToastCardState,
        cursorX: inout CGFloat,
        cardRect: CGRect,
        font: CTFont
    ) {
        guard let sent = toast.rstSent, let rcvd = toast.rstReceived else {
            return
        }
        let rstText = "↑\(sent) ↓\(rcvd)"
        let rstColor = rstCGColor(rstSent: sent, rstReceived: rcvd)
        let rstRect = CGRect(x: cursorX, y: cardRect.origin.y, width: 120, height: cardRect.height)
        drawCenteredText(rstText, in: context, rect: rstRect, font: font, color: rstColor, alignment: .left)
        cursorX += 128
    }
}

// MARK: - RST Quality Color

nonisolated extension VideoOverlayRenderer {
    /// RST quality color matching the map's RSTColorHelper logic.
    /// Green >= 55, Yellow >= 45, Red < 45.
    static func rstCGColor(rstSent: String, rstReceived: String) -> TextColor {
        let avg = averageRST(rstSent, rstReceived)
        if avg >= 55 {
            return .custom(0.20, 0.78, 0.35, 1) // green
        } else if avg >= 45 {
            return .custom(1.0, 0.84, 0.0, 1) // yellow
        } else {
            return .custom(1.0, 0.27, 0.23, 1) // red
        }
    }

    /// RST quality color as CardLineColor for callsign cards.
    static func rstCardColor(rstSent: String, rstReceived: String) -> CardLineColor {
        let avg = averageRST(rstSent, rstReceived)
        if avg >= 55 {
            return .custom(0.20, 0.78, 0.35, 1) // green
        } else if avg >= 45 {
            return .custom(1.0, 0.84, 0.0, 1) // yellow
        } else {
            return .custom(1.0, 0.27, 0.23, 1) // red
        }
    }

    private static func averageRST(_ sent: String, _ received: String) -> Int {
        let sv = parseRST(sent) ?? 59
        let rv = parseRST(received) ?? 59
        return (sv + rv) / 2
    }

    private static func parseRST(_ rst: String) -> Int? {
        let digits = rst.filter(\.isNumber)
        guard digits.count >= 2 else {
            return digits.count == 1 ? (Int(digits)! * 10) : nil // swiftlint:disable:this force_unwrapping
        }
        return Int(String(digits.prefix(2)))
    }
}
