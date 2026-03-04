// Band Chart Legend View
//
// Color key for the visual band chart, parameterized by display mode.

import CarrierWaveData
import SwiftUI

// MARK: - BandChartLegendView

struct BandChartLegendView: View {
    // MARK: Internal

    let displayMode: BandChartDisplayMode

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                switch displayMode {
                case .byClass:
                    legendItem("Extra", color: .purple)
                    legendItem("General", color: .blue)
                    legendItem("Tech", color: .green)
                case .byMode:
                    legendItem("CW", color: .blue)
                    legendItem("CW+Dig", color: .teal)
                    legendItem("Phone", color: .green)
                    legendItem("Digital", color: .orange)
                    legendItem("AM", color: .yellow)
                    legendItem("FM", color: .cyan)
                }
            }
        }
    }

    // MARK: Private

    private func legendItem(_ label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(Capsule())
    }
}
