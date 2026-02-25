//
//  FT8WaterfallView.swift
//  CarrierWave
//

import SwiftUI

struct FT8WaterfallView: View {
    // MARK: Internal

    let data: FT8WaterfallData

    var body: some View {
        // Snapshot @MainActor data before entering Canvas rendering thread
        let rows = data.magnitudes
        let bins = data.frequencyBins

        Canvas { context, size in
            guard !rows.isEmpty, bins > 0 else {
                return
            }

            let rowHeight = size.height / CGFloat(min(rows.count, 60))
            let binWidth = size.width / CGFloat(bins)

            for (rowIdx, row) in rows.suffix(60).enumerated() {
                for (binIdx, magnitude) in row.enumerated() {
                    let rect = CGRect(
                        x: CGFloat(binIdx) * binWidth,
                        y: CGFloat(rowIdx) * rowHeight,
                        width: binWidth + 1,
                        height: rowHeight + 1
                    )
                    context.fill(
                        Path(rect),
                        with: .color(waterfallColor(magnitude))
                    )
                }
            }
        }
        .background(Color.black)
    }

    // MARK: Private

    private func waterfallColor(_ magnitude: Float) -> Color {
        let value = Double(magnitude)
        if value < 0.25 {
            return Color(red: 0, green: 0, blue: value * 4)
        } else if value < 0.5 {
            let blend = (value - 0.25) * 4
            return Color(red: 0, green: blend, blue: 1.0 - blend)
        } else if value < 0.75 {
            let blend = (value - 0.5) * 4
            return Color(red: blend, green: 1.0, blue: 0)
        } else {
            let blend = (value - 0.75) * 4
            return Color(red: 1.0, green: 1.0 - blend, blue: 0)
        }
    }
}
