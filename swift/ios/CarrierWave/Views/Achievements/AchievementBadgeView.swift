import CarrierWaveData
import SwiftUI

// MARK: - AchievementBadgeView

/// Renders a single achievement as a square tile. Earned tiles show their accent
/// color; unearned tiles are dimmed. Secret unearned tiles render as a placeholder.
struct AchievementBadgeView: View {
    // MARK: Internal

    let achievement: Achievement
    let earned: Bool

    var body: some View {
        VStack(spacing: 6) {
            iconCircle
            Text(displayName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let tier = achievement.tier, earned {
                Text(tier.rawValue.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 96)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(earned ? 1.0 : 0.45)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: Private

    private var displayName: String {
        if !earned, achievement.secret {
            return "Locked"
        }
        return achievement.name
    }

    private var accentColor: Color {
        achievement.accentHex.flatMap(Color.init(hex:)) ?? .accentColor
    }

    private var accessibilityLabel: String {
        if !earned, achievement.secret {
            return "Locked achievement"
        }
        let state = earned ? "earned" : "not yet earned"
        return "\(achievement.name), \(state). \(achievement.description)"
    }

    @ViewBuilder
    private var iconCircle: some View {
        let symbol = (!earned && achievement.secret) ? "lock.fill" : achievement.iconName
        Image(systemName: symbol)
            .font(.title2)
            .foregroundStyle(earned ? accentColor : Color.secondary)
            .frame(width: 44, height: 44)
            .background(Circle().fill(accentColor.opacity(earned ? 0.18 : 0.08)))
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.thinMaterial)
    }
}

// MARK: - Color hex helper

extension Color {
    init?(hex: String) {
        var trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") {
            trimmed.removeFirst()
        }
        guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else {
            return nil
        }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}

#Preview {
    VStack {
        AchievementBadgeView(
            achievement: .preview(id: "creator", name: "Creator", iconName: "hammer.fill"),
            earned: true
        )
        AchievementBadgeView(
            achievement: .preview(id: "qso-100", name: "Centurion", iconName: "antenna.radiowaves.left.and.right"),
            earned: false
        )
    }
    .padding()
}

extension Achievement {
    static func preview(id: String, name: String, iconName: String) -> Achievement {
        Achievement(
            id: id,
            name: name,
            description: "Preview description for \(name)",
            category: .activity,
            tier: nil,
            iconName: iconName,
            accentHex: "#4CAF50",
            awardMethod: .auto,
            secret: false,
            sortOrder: 0
        )
    }
}
