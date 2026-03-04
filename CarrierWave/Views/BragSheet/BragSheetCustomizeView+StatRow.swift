import CarrierWaveData
import SwiftUI

// MARK: - BragStatCustomizeRow

/// A single stat row in the customize sheet.
/// Shows toggle for enabled and star button for hero promotion.
struct BragStatCustomizeRow: View {
    let stat: BragSheetStatType
    let isEnabled: Bool
    let isHero: Bool
    let heroCount: Int
    let onToggleEnabled: () -> Void
    let onToggleHero: () -> Void

    var body: some View {
        HStack {
            Toggle(isOn: Binding(
                get: { isEnabled },
                set: { _ in onToggleEnabled() }
            )) {
                Text(stat.displayName)
                    .font(.body)
            }

            if isEnabled {
                Button {
                    onToggleHero()
                } label: {
                    Image(systemName: isHero ? "star.fill" : "star")
                        .foregroundStyle(isHero ? .yellow : .secondary)
                        .font(.body)
                }
                .buttonStyle(.plain)
                .disabled(!isHero && heroCount >= 4)
                .opacity(!isHero && heroCount >= 4 ? 0.3 : 1.0)
                .accessibilityLabel(isHero ? "Remove from hero" : "Promote to hero")
            }
        }
    }
}
