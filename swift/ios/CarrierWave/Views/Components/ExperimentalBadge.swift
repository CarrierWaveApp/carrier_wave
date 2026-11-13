import CarrierWaveData
import SwiftUI

// MARK: - ExperimentalBadge

/// Consistent badge for experimental features.
/// Use inline in navigation links, section headers, and buttons.
struct ExperimentalBadge: View {
    // MARK: Internal

    var feature: ExperimentalFeature?

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }

    // MARK: Private

    private var maturity: ExperimentalFeature.Maturity {
        feature?.maturity ?? .beta
    }

    private var label: String {
        maturity.label
    }

    private var color: Color {
        switch maturity {
        case .alpha: .red
        case .beta: .orange
        }
    }
}
