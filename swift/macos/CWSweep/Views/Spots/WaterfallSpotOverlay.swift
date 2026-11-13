import SwiftUI

// MARK: - WaterfallSpotOverlay

/// Canvas strip showing filtered spot callsigns rotated 90 degrees at their
/// frequency positions. Sits above the waterfall with tick marks pointing down.
struct WaterfallSpotOverlay: View {
    // MARK: Internal

    let spots: [EnrichedSpot]
    let lowFreqMHz: Double
    let highFreqMHz: Double
    let colorMode: BandScopeColorMode
    let maxAgeMinutes: Int

    var body: some View {
        Canvas { context, size in
            drawSpotLabels(context: &context, size: size)
        }
        .frame(height: 60)
        .background(Color(white: 0.05))
    }

    // MARK: Private

    private static let tickHeight: CGFloat = 6

    private func xPosForFreq(_ freqMHz: Double, width: CGFloat) -> CGFloat? {
        let span = highFreqMHz - lowFreqMHz
        guard span > 0 else {
            return nil
        }
        let frac = (freqMHz - lowFreqMHz) / span
        return CGFloat(frac) * width
    }

    private func drawSpotLabels(context: inout GraphicsContext, size: CGSize) {
        let sorted = spots.sorted { $0.neededStatus < $1.neededStatus }
        // Overlap detection uses x-ranges accounting for rotated label width (~10px)
        let labelSlotWidth: CGFloat = 10
        var occupied: [(xMin: CGFloat, xMax: CGFloat)] = []

        for spot in sorted {
            guard let xPos = xPosForFreq(spot.spot.frequencyMHz, width: size.width) else {
                continue
            }

            let slotLeft = xPos - labelSlotWidth / 2
            let slotRight = xPos + labelSlotWidth / 2
            let overlaps = occupied.contains { slotLeft < $0.xMax && slotRight > $0.xMin }
            guard !overlaps else {
                continue
            }

            let color = SpotColorScheme.markerColor(for: spot, mode: colorMode, isWorkedToday: false)
            let opacity = SpotAgeFactor.opacity(for: spot, maxAgeMinutes: maxAgeMinutes)
            let isNeeded = spot.neededStatus == .newEntity || spot.neededStatus == .newBandSlot
            let weight: Font.Weight = isNeeded ? .bold : .medium
            let fontSize: CGFloat = isNeeded ? 9 : 8

            // Tick mark at bottom pointing into waterfall
            var tick = Path()
            tick.move(to: CGPoint(x: xPos, y: size.height - Self.tickHeight))
            tick.addLine(to: CGPoint(x: xPos, y: size.height))
            context.stroke(tick, with: .color(color.opacity(opacity * 0.8)), lineWidth: 1)

            // Rotated callsign label reading bottom-to-top
            let label = Text(spot.spot.callsign)
                .font(.system(size: fontSize, weight: weight, design: .monospaced))
                .foregroundStyle(color.opacity(opacity))
            let resolved = context.resolve(label)

            // Draw rotated: translate to position, rotate -90°, draw
            var labelContext = context
            let labelY = size.height - Self.tickHeight - 2
            labelContext.translateBy(x: xPos, y: labelY)
            labelContext.rotate(by: .degrees(-90))
            labelContext.draw(resolved, at: .zero, anchor: .leading)

            occupied.append((xMin: slotLeft - 1, xMax: slotRight + 1))
        }
    }
}
