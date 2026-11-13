import SwiftUI

// MARK: - ContestBandScopeView + Waterfall

extension ContestBandScopeView {
    /// Draw the active radio's waterfall rotated 90° into the band scope.
    /// Frequency bins map to y-axis, time lines map to x-columns (newest on left).
    /// Reads from `radioManager.waterfallStore` so it works for SCU-LAN10,
    /// FlexRadio, or any future producer.
    func drawWaterfall(ctx: GraphicsContext, size: CGSize, band: BandEdge) {
        let store = radioManager.waterfallStore
        let lines = store.magnitudes
        guard !lines.isEmpty, store.activeBinCount > 0 else {
            return
        }

        let centerKHz = store.centerFrequencyMHz * 1_000
        guard centerKHz > 0 else {
            return
        }

        let scopeSpanKHz = store.spanKHz > 0 ? store.spanKHz : 100
        let totalBins = store.activeBinCount

        // Frequency range of the scope data
        let scopeLowKHz = centerKHz - scopeSpanKHz / 2
        let scopeHighKHz = centerKHz + scopeSpanKHz / 2

        // Only render if scope overlaps the displayed band
        guard scopeHighKHz > band.lowerKHz, scopeLowKHz < band.upperKHz else {
            return
        }

        let plotW = size.width
        // Fixed column width — data fills from the left edge rightward.
        let lineWidth: CGFloat = max(1.0, plotW / CGFloat(store.maxLines))

        // Pre-compute y position for each bin's frequency
        let kHzPerBin = scopeSpanKHz / Double(totalBins)

        for (lineIdx, line) in lines.enumerated() {
            let xPos = CGFloat(lineIdx) * lineWidth
            guard xPos < size.width else {
                break
            }

            let safeBins = min(totalBins, line.count)
            for binIdx in 0 ..< safeBins {
                let binFreqKHz = scopeLowKHz + Double(binIdx) * kHzPerBin
                guard binFreqKHz >= band.lowerKHz - kHzPerBin,
                      binFreqKHz <= band.upperKHz + kHzPerBin
                else {
                    continue
                }

                let yPosition = yPosForFreq(binFreqKHz, band: band, height: size.height)
                let yPositionNext = yPosForFreq(binFreqKHz + kHzPerBin, band: band, height: size.height)
                let binHeight = max(1, abs(yPositionNext - yPosition))

                let minY = min(yPosition, yPositionNext)
                guard minY < size.height, minY + binHeight > 0 else {
                    continue
                }

                let rect = CGRect(x: xPos, y: minY, width: ceil(lineWidth), height: ceil(binHeight))
                ctx.fill(Path(rect), with: .color(waterfallColor(for: line[binIdx])))
            }
        }
    }

    func waterfallColor(for magnitude: Float) -> Color {
        let val = Double(min(1.0, max(0.0, magnitude)))
        if val < 0.05 {
            return Color(red: 0, green: 0, blue: 0.08)
        } else if val < 0.15 {
            let frac = (val - 0.05) / 0.1
            return Color(red: 0, green: 0, blue: 0.08 + frac * 0.25)
        } else if val < 0.35 {
            let frac = (val - 0.15) / 0.2
            return Color(red: 0, green: frac * 0.4, blue: 0.33 + frac * 0.3)
        } else if val < 0.55 {
            let frac = (val - 0.35) / 0.2
            return Color(red: 0, green: 0.4 + frac * 0.6, blue: 0.63 - frac * 0.3)
        } else if val < 0.75 {
            let frac = (val - 0.55) / 0.2
            return Color(red: frac * 0.8, green: 1.0, blue: 0.33 - frac * 0.33)
        } else if val < 0.9 {
            let frac = (val - 0.75) / 0.15
            return Color(red: 0.8 + frac * 0.2, green: 1.0 - frac * 0.5, blue: 0)
        } else {
            let frac = (val - 0.9) / 0.1
            return Color(red: 1.0, green: 0.5 - frac * 0.3, blue: frac * 0.5)
        }
    }
}
