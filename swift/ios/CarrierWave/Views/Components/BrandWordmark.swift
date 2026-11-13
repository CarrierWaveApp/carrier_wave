import SwiftUI
import UIKit

// MARK: - BrandWordmark

/// Quiet leading-toolbar logotype for Home.
///
/// Reads as a brand mark, not a screen heading — it never competes with the
/// screen's hero (`HomeHeroCard`) and costs zero scroll height. The radio-waves
/// glyph is the app's established radio mark (shared with the logger/band UI);
/// the single purple glyph is the only accent, so the wordmark itself stays in
/// the neutral label color (60-30-10).
struct BrandWordmark: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.purple)
            Text("CARRIER WAVE")
                .font(.subheadline.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(.primary)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Carrier Wave")
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    NavigationStack {
        Color(.systemGroupedBackground)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { BrandWordmark() }
            }
    }
}
