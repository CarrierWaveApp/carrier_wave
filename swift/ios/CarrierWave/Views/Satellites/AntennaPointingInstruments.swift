import SwiftUI

// MARK: - PointingInstrumentStyle

/// Shared palette for the pointing instruments, following the app's design
/// language: orange is the selected-satellite / fly-to accent (as on the
/// sky dome), white scales on the dome's black background. The bug/diamond
/// convention itself is borrowed from the G1000.
nonisolated enum PointingInstrumentStyle {
    static let flyTo = Color.orange
    static let scaleWhite = Color.white.opacity(0.9)
}

// MARK: - PointingCompassTape

/// G1000-style heading-tape section of the compass: a ±45° window centered
/// on the antenna's boresight azimuth, with a fixed center lubber line and
/// an orange fly-to bug at the target azimuth (clamped to the edge, hollow,
/// when the target is outside the window).
struct PointingCompassTape: View {
    // MARK: Internal

    let pointingAzDeg: Double
    let targetAzDeg: Double

    var body: some View {
        Canvas { context, size in
            drawTicks(in: &context, size: size)
            drawBug(in: &context, size: size)
            drawLubber(in: &context, size: size)
        }
        .frame(height: 92)
        .accessibilityLabel(Text(String(
            format: "Compass: pointing %.0f degrees, target %.0f degrees",
            pointingAzDeg, targetAzDeg
        )))
    }

    // MARK: Private

    /// Half-width of the visible compass window, in degrees.
    private static let windowDeg = 45.0

    private var baselineOffset: CGFloat {
        24
    }

    private static func label(for degrees: Double) -> String {
        switch Int(degrees.rounded()) {
        case 0:
            "N"
        case 90:
            "E"
        case 180:
            "S"
        case 270:
            "W"
        default:
            String(Int(degrees.rounded()))
        }
    }

    private static func wrap180(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 {
            value -= 360
        }
        if value < -180 {
            value += 360
        }
        return value
    }

    private func xPosition(forDelta delta: Double, width: CGFloat) -> CGFloat {
        width / 2 + delta * (width / (2 * Self.windowDeg))
    }

    private func drawTicks(in context: inout GraphicsContext, size: CGSize) {
        let baseY = size.height - baselineOffset
        var line = Path()
        line.move(to: CGPoint(x: 0, y: baseY))
        line.addLine(to: CGPoint(x: size.width, y: baseY))
        context.stroke(line, with: .color(PointingInstrumentStyle.scaleWhite), lineWidth: 2)
        let start = (pointingAzDeg - Self.windowDeg)
        var degree = (start / 5).rounded(.up) * 5
        while degree <= pointingAzDeg + Self.windowDeg {
            let normalized = (degree.truncatingRemainder(dividingBy: 360) + 360)
                .truncatingRemainder(dividingBy: 360)
            let tickX = xPosition(forDelta: degree - pointingAzDeg, width: size.width)
            let isMajor = normalized.truncatingRemainder(dividingBy: 30) == 0
            let isMedium = normalized.truncatingRemainder(dividingBy: 10) == 0
            let height: CGFloat = isMajor ? 24 : (isMedium ? 16 : 9)
            var tick = Path()
            tick.move(to: CGPoint(x: tickX, y: baseY))
            tick.addLine(to: CGPoint(x: tickX, y: baseY - height))
            context.stroke(
                tick,
                with: .color(PointingInstrumentStyle.scaleWhite),
                lineWidth: isMajor ? 3 : 2
            )
            if isMajor {
                context.draw(
                    Text(Self.label(for: normalized))
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white),
                    at: CGPoint(x: tickX, y: baseY - height - 14)
                )
            }
            degree += 5
        }
    }

    /// Fly-to target bug on the baseline; clamped to the window edge and
    /// drawn hollow when the target is outside the visible section.
    private func drawBug(in context: inout GraphicsContext, size: CGSize) {
        let baseY = size.height - baselineOffset
        let delta = Self.wrap180(targetAzDeg - pointingAzDeg)
        let clamped = min(max(delta, -Self.windowDeg), Self.windowDeg)
        let bugX = xPosition(forDelta: clamped, width: size.width)
        var bug = Path()
        bug.move(to: CGPoint(x: bugX, y: baseY + 4))
        bug.addLine(to: CGPoint(x: bugX - 12, y: baseY + 20))
        bug.addLine(to: CGPoint(x: bugX + 12, y: baseY + 20))
        bug.closeSubpath()
        if clamped == delta {
            context.fill(bug, with: .color(PointingInstrumentStyle.flyTo))
        } else {
            context.stroke(bug, with: .color(PointingInstrumentStyle.flyTo), lineWidth: 3)
        }
    }

    private func drawLubber(in context: inout GraphicsContext, size: CGSize) {
        let baseY = size.height - baselineOffset
        let midX = size.width / 2
        var line = Path()
        line.move(to: CGPoint(x: midX, y: baseY - 30))
        line.addLine(to: CGPoint(x: midX, y: baseY + 2))
        context.stroke(line, with: .color(.white), lineWidth: 4)
        var pointer = Path()
        pointer.move(to: CGPoint(x: midX, y: baseY - 2))
        pointer.addLine(to: CGPoint(x: midX - 8, y: baseY + 12))
        pointer.addLine(to: CGPoint(x: midX + 8, y: baseY + 12))
        pointer.closeSubpath()
        context.fill(pointer, with: .color(.white))
    }
}

// MARK: - PointingElevationScale

/// G1000 glideslope-style vertical deviation indicator for elevation: the
/// fixed center line is the antenna's boresight elevation, dots mark ±10°
/// and ±20°, and the orange diamond is the satellite. Diamond above
/// center = tilt up. Hollow diamond pinned to the end when off-scale.
struct PointingElevationScale: View {
    // MARK: Internal

    /// Target elevation minus boresight elevation (positive = tilt up).
    let elErrorDeg: Double

    var body: some View {
        Canvas { context, size in
            drawScale(in: &context, size: size)
            drawDiamond(in: &context, size: size)
        }
        .frame(width: 44)
        .frame(maxHeight: 300)
        .accessibilityLabel(Text(String(format: "Elevation deviation %.0f degrees", elErrorDeg)))
    }

    // MARK: Private

    /// Half-height of the scale window, in degrees.
    private static let windowDeg = 30.0

    private func yPosition(forError error: Double, height: CGFloat) -> CGFloat {
        height / 2 - error * (height / (2 * Self.windowDeg))
    }

    private func drawScale(in context: inout GraphicsContext, size: CGSize) {
        let midX = size.width / 2
        for dotDeg in [-20.0, -10, 10, 20] {
            let dotY = yPosition(forError: dotDeg, height: size.height)
            let dot = Path(ellipseIn: CGRect(x: midX - 4, y: dotY - 4, width: 8, height: 8))
            context.stroke(dot, with: .color(PointingInstrumentStyle.scaleWhite), lineWidth: 2)
        }
        var center = Path()
        center.move(to: CGPoint(x: midX - 14, y: size.height / 2))
        center.addLine(to: CGPoint(x: midX + 14, y: size.height / 2))
        context.stroke(center, with: .color(.white), lineWidth: 4)
    }

    private func drawDiamond(in context: inout GraphicsContext, size: CGSize) {
        let midX = size.width / 2
        let clamped = min(max(elErrorDeg, -Self.windowDeg), Self.windowDeg)
        let midY = yPosition(forError: clamped, height: size.height)
        var diamond = Path()
        diamond.move(to: CGPoint(x: midX, y: midY - 12))
        diamond.addLine(to: CGPoint(x: midX + 10, y: midY))
        diamond.addLine(to: CGPoint(x: midX, y: midY + 12))
        diamond.addLine(to: CGPoint(x: midX - 10, y: midY))
        diamond.closeSubpath()
        if clamped == elErrorDeg {
            context.fill(diamond, with: .color(PointingInstrumentStyle.flyTo))
        } else {
            context.stroke(diamond, with: .color(PointingInstrumentStyle.flyTo), lineWidth: 3)
        }
    }
}

// MARK: - PointingCorrectionReadout

/// The far-visible numbers: how far to swing (left/right chevron) and how
/// far to tilt (up/down chevron), in degrees, tinted with the screen's
/// semantic status color.
struct PointingCorrectionReadout: View {
    // MARK: Internal

    let azErrorDeg: Double
    let elErrorDeg: Double
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            correctionLine(
                error: azErrorDeg,
                negativeSymbol: "chevron.left.2",
                positiveSymbol: "chevron.right.2"
            )
            correctionLine(
                error: elErrorDeg,
                negativeSymbol: "chevron.down.2",
                positiveSymbol: "chevron.up.2"
            )
        }
    }

    // MARK: Private

    private func correctionLine(
        error: Double,
        negativeSymbol: String,
        positiveSymbol: String
    ) -> some View {
        HStack(spacing: 14) {
            if error < 0 {
                Image(systemName: negativeSymbol)
            }
            Text(String(format: "%.0f°", abs(error)))
                .monospacedDigit()
            if error >= 0 {
                Image(systemName: positiveSymbol)
            }
        }
        .font(.system(size: 62, weight: .black))
        .monospacedDigit()
        .foregroundStyle(tint)
    }
}
