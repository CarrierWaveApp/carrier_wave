import CarrierWaveData
import SwiftUI

// MARK: - ContactCountTier

enum ContactCountTier {
    case bronze
    case silver
    case gold

    // MARK: Lifecycle

    init?(count: Int) {
        switch count {
        case 50...:
            self = .gold
        case 25 ..< 50:
            self = .silver
        case 10 ..< 25:
            self = .bronze
        default:
            return nil
        }
    }

    // MARK: Internal

    var color: Color {
        switch self {
        case .bronze:
            .brown
        case .silver:
            .gray
        case .gold:
            .yellow
        }
    }
}

// MARK: - ContactCountBadge

struct ContactCountBadge: View {
    // MARK: Internal

    let count: Int
    var showLabel: Bool = false

    var body: some View {
        if let tier {
            badgeCapsule(tier: tier)
        } else if showLabel {
            plainLabelChip
        } else {
            plainCount
        }
    }

    // MARK: Private

    private var tier: ContactCountTier? {
        ContactCountTier(count: count)
    }

    private var plainLabelChip: some View {
        Text("\(count) prev QSO\(count == 1 ? "" : "s")")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var plainCount: some View {
        Text("\u{00d7}\(count)")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .fixedSize()
    }

    private func badgeCapsule(tier: ContactCountTier) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "shield.fill")
                .font(.caption2)
            Text("\u{00d7}\(count)")
                .font(.caption.weight(.medium))
            if showLabel {
                Text("prev QSO\(count == 1 ? "" : "s")")
                    .font(.caption)
            }
        }
        .fixedSize()
        .foregroundStyle(tier.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tier.color.opacity(0.15))
        .clipShape(Capsule())
    }
}
