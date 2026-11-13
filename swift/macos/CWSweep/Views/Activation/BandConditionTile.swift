import SwiftUI

// MARK: - BandConditionTile

/// A single clickable band tile showing band name, day/night conditions, and selection state.
struct BandConditionTile: View {
    // MARK: Internal

    let bandName: String
    let dayCondition: String
    let nightCondition: String
    let isBest: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                HStack(spacing: 4) {
                    Text(bandName)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                    if isBest {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.yellow)
                    }
                }

                HStack(spacing: 2) {
                    Text(dayCondition)
                        .font(.system(size: 9))
                        .foregroundStyle(conditionColor(dayCondition))
                    Text("/")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(nightCondition)
                        .font(.system(size: 9))
                        .foregroundStyle(conditionColor(nightCondition))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.white.opacity(0.15),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: Private

    private func conditionColor(_ condition: String) -> Color {
        switch condition.lowercased() {
        case "excellent",
             "good":
            .green
        case "fair":
            .yellow
        case "poor",
             "closed":
            .red
        default:
            .secondary
        }
    }
}
