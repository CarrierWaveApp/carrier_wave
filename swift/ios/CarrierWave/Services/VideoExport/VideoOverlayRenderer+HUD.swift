// Video Overlay Renderer — HUD
//
// HUD strip drawing with density-aware row layout.

import CoreGraphics
import CoreText
import Foundation

// MARK: - VideoHUDState

nonisolated struct VideoHUDState {
    let callsign: String
    let parkReference: String?
    let frequency: String
    let mode: String
    let elapsedTime: TimeInterval
    let parkName: String?
    let equipmentLine: String?
    let qsoCount: Int
    let qsoRate: String?
}

// MARK: - HUD

nonisolated extension VideoOverlayRenderer {
    /// Height in pixels for a HUD of the given density. Returns 0 for `.off`.
    static func hudHeight(for density: HUDDensity) -> CGFloat {
        switch density {
        case .full: 80
        case .compact: 44
        case .minimal: 36
        case .off: 0
        }
    }

    /// Draws a semi-transparent HUD strip at the top of the frame.
    /// Row count depends on density: full = 2 rows, compact/minimal = 1 row.
    static func drawHUD(
        in context: CGContext,
        state: VideoHUDState,
        palette: VideoThemePalette,
        density: HUDDensity
    ) {
        let height = hudHeight(for: density)
        guard height > 0 else {
            return
        }
        let hudRect = CGRect(x: 0, y: 0, width: videoWidth, height: height)
        context.setFillColor(palette.hudBackground)
        context.fill(hudRect)

        drawHUDRow1(in: context, state: state, hudHeight: height, palette: palette, density: density)
        if density == .full {
            drawHUDRow2(in: context, state: state, hudHeight: height, palette: palette)
        }
    }

    /// Row 1: Callsign (bold) | Park Ref | Freq Mode | Elapsed Time
    private static func drawHUDRow1(
        in context: CGContext, state: VideoHUDState, hudHeight: CGFloat,
        palette: VideoThemePalette, density: HUDDensity
    ) {
        let font = makeFont(name: "SFProText-Regular", fallback: "HelveticaNeue", size: 16)
        let boldFont = makeFont(name: "SFProText-Bold", fallback: "HelveticaNeue-Bold", size: 16)
        let padding: CGFloat = 16
        let rowHeight = density == .full ? hudHeight / 2 : hudHeight
        let rowY: CGFloat = 0
        let primary = TextColor.raw(palette.primaryText)

        let callsignRect = CGRect(x: padding, y: rowY, width: 200, height: rowHeight)
        drawCenteredText(
            state.callsign, in: context, rect: callsignRect,
            font: boldFont, color: primary, alignment: .left
        )

        var freqX = padding + 200 + 8
        if density != .minimal, let park = state.parkReference {
            let parkRect = CGRect(x: freqX, y: rowY, width: 160, height: rowHeight)
            drawCenteredText(park, in: context, rect: parkRect, font: font, color: primary, alignment: .left)
            freqX += 168
        }

        if density != .minimal {
            let freqModeText = "\(state.frequency) \(state.mode)"
            let freqRect = CGRect(x: freqX, y: rowY, width: 220, height: rowHeight)
            drawCenteredText(freqModeText, in: context, rect: freqRect, font: font, color: primary, alignment: .left)
        }

        let timeText = formatElapsedTime(state.elapsedTime)
        let timeRect = CGRect(x: videoWidth - 160 - padding, y: rowY, width: 160, height: rowHeight)
        drawCenteredText(timeText, in: context, rect: timeRect, font: font, color: primary, alignment: .right)
    }

    /// Row 2 (dimmer): Park Name | Equipment | QSO count + rate/hr
    private static func drawHUDRow2(
        in context: CGContext, state: VideoHUDState, hudHeight: CGFloat, palette: VideoThemePalette
    ) {
        let font = makeFont(name: "SFProText-Regular", fallback: "HelveticaNeue", size: 13)
        let dimColor = TextColor.raw(palette.secondaryText)
        let padding: CGFloat = 16
        let rowHeight = hudHeight / 2
        let rowY = hudHeight / 2

        var cursorX = padding
        if let parkName = state.parkName {
            let parkRect = CGRect(x: cursorX, y: rowY, width: 360, height: rowHeight)
            drawCenteredText(parkName, in: context, rect: parkRect, font: font, color: dimColor, alignment: .left)
            cursorX += 368
        }

        if let equip = state.equipmentLine {
            let equipRect = CGRect(x: cursorX, y: rowY, width: 400, height: rowHeight)
            drawCenteredText(equip, in: context, rect: equipRect, font: font, color: dimColor, alignment: .left)
        }

        var qsoText = "\(state.qsoCount) QSO\(state.qsoCount == 1 ? "" : "s")"
        if let rate = state.qsoRate {
            qsoText += " · \(rate)"
        }
        let qsoRect = CGRect(x: videoWidth - 240 - padding, y: rowY, width: 240, height: rowHeight)
        drawCenteredText(qsoText, in: context, rect: qsoRect, font: font, color: dimColor, alignment: .right)
    }
}
