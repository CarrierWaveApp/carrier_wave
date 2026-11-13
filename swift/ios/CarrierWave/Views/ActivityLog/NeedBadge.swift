// Need Badge
//
// Compact chip displayed on spot rows when the spot matches an operator need.
// Color-coded by priority: high (blue), medium (purple), low (teal).

import SwiftUI

// MARK: - NeedBadge

struct NeedBadge: View {
    // MARK: Internal

    let need: MatchedNeed

    var body: some View {
        Text(shortLabel)
            .font(.caption2.weight(.bold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .accessibilityLabel(need.label)
    }

    // MARK: Private

    private var shortLabel: String {
        switch need.category {
        case .dxccEntity:
            "NEW DXCC"
        case let .dxccBandSlot(_, band):
            "DXCC \(band)"
        case let .wasState(state),
             let .wasStateMode(state, _):
            "WAS \(state)"
        case .potaNewPark:
            "NEW PARK"
        case let .potaActivatorState(state):
            "HUNT \(state)"
        case .potaActivatorEntity:
            "HUNT DXCC"
        case .wwffNewReference:
            "NEW WWFF"
        case let .custom(_, label):
            label.prefix(12).uppercased()
        }
    }

    private var foregroundColor: Color {
        switch need.priority {
        case .high: .white
        case .medium: .purple
        case .low: .teal
        }
    }

    private var backgroundColor: Color {
        switch need.priority {
        case .high: .blue
        case .medium: .purple.opacity(0.15)
        case .low: .teal.opacity(0.15)
        }
    }
}

// MARK: - NeedBadgeRow

/// Horizontal row of need badges for a spot, showing up to 3.
struct NeedBadgeRow: View {
    let needs: [MatchedNeed]

    var body: some View {
        if needs.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 4) {
                ForEach(Array(needs.prefix(3))) { need in
                    NeedBadge(need: need)
                }
                if needs.count > 3 {
                    Text("+\(needs.count - 3)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
