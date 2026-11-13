import CarrierWaveData
import SwiftUI

// MARK: - ChipFlowLayout

/// A simple wrapping layout that places children in rows, breaking to the next line when needed
struct ChipFlowLayout: Layout {
    // MARK: Internal

    var spacing: CGFloat = 6

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.enumerated().reduce(CGFloat.zero) { total, pair in
            let rowHeight = pair.element.map(\.size.height).max() ?? 0
            return total + rowHeight + (pair.offset > 0 ? spacing : 0)
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var yOffset = bounds.minY
        for row in rows {
            let rowHeight = row.map(\.size.height).max() ?? 0
            var xOffset = bounds.minX
            for item in row {
                item.subview.place(
                    at: CGPoint(x: xOffset, y: yOffset),
                    proposal: ProposedViewSize(item.size)
                )
                xOffset += item.size.width + spacing
            }
            yOffset += rowHeight + spacing
        }
    }

    // MARK: Private

    private struct LayoutItem {
        let subview: LayoutSubview
        let size: CGSize
    }

    private func computeRows(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> [[LayoutItem]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutItem]] = [[]]
        var rowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let neededWidth = rowWidth > 0 ? size.width + spacing : size.width

            if rowWidth + neededWidth > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([])
                rowWidth = 0
            }

            rows[rows.count - 1].append(LayoutItem(subview: subview, size: size))
            rowWidth += rowWidth > 0 ? size.width + spacing : size.width
        }

        return rows
    }
}

// MARK: - DetailChip

struct DetailChip: View {
    let text: String
    var icon: String?
    var iconRotation: Double = 0

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2)
                    .rotationEffect(.degrees(iconRotation))
            }
            Text(text)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - MembershipChip

/// Chip rendering one organisation membership (e.g. "🎹 CWops #1532").
/// Tinted blue to set it apart from neutral location chips.
struct MembershipChip: View {
    // MARK: Internal

    let membership: CallsignEnrichmentMembership

    var body: some View {
        HStack(spacing: 4) {
            if let emoji = membership.emoji {
                Text(emoji)
            }
            Text(label)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Private

    private var label: String {
        if let number = membership.memberNumber, !number.isEmpty {
            return "\(membership.sourceName) #\(number)"
        }
        return membership.sourceName
    }

    private var accessibilityText: String {
        if let number = membership.memberNumber, !number.isEmpty {
            return "\(membership.sourceName) member number \(number)"
        }
        return "\(membership.sourceName) member"
    }
}

// MARK: - CompactCallsignBar

/// A compact single-line callsign info display for use above the keyboard
struct CompactCallsignBar: View {
    let info: CallsignInfo

    var body: some View {
        HStack(spacing: 8) {
            if let emoji = info.combinedEmoji {
                Text(emoji)
                    .font(.body)
            }

            if let name = info.displayName {
                Text(name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }

            if let state = info.state {
                Text(state)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Capsule())
            }

            if let grid = info.grid {
                Text(grid.prefix(4))
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .clipShape(Capsule())
            }

            Spacer()

            if let flag = CallsignFlagHelper.countryFlag(for: info.callsign) {
                Text(flag)
                    .font(.body)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
    }
}

// MARK: - CallsignLookupErrorBanner

/// Displays callsign lookup errors with actionable suggestions
struct CallsignLookupErrorBanner: View {
    // MARK: Internal

    let error: CallsignLookupError

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(error.errorDescription ?? "Lookup failed")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Shared helpers for both banner and compact bar
    static func icon(for error: CallsignLookupError) -> String {
        switch error {
        case .noQRZApiKey,
             .noSourcesConfigured:
            "gear.badge.questionmark"
        case .qrzAuthFailed:
            "key.slash"
        case .networkError:
            "wifi.slash"
        case .notFound:
            "magnifyingglass"
        }
    }

    static func iconColor(for error: CallsignLookupError) -> Color {
        switch error {
        case .noQRZApiKey,
             .noSourcesConfigured:
            .orange
        case .qrzAuthFailed:
            .red
        case .networkError:
            .yellow
        case .notFound:
            .secondary
        }
    }

    static func backgroundColor(for error: CallsignLookupError) -> Color {
        switch error {
        case .noQRZApiKey,
             .noSourcesConfigured:
            Color.orange.opacity(0.15)
        case .qrzAuthFailed:
            Color.red.opacity(0.15)
        case .networkError:
            Color.yellow.opacity(0.15)
        case .notFound:
            Color(.secondarySystemGroupedBackground)
        }
    }

    // MARK: Private

    private var icon: String {
        CallsignLookupErrorBanner.icon(for: error)
    }

    private var iconColor: Color {
        CallsignLookupErrorBanner.iconColor(for: error)
    }

    private var backgroundColor: Color {
        CallsignLookupErrorBanner.backgroundColor(for: error)
    }
}

// MARK: - CompactLookupErrorBar

/// Compact error display for use above the keyboard
struct CompactLookupErrorBar: View {
    let error: CallsignLookupError

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: CallsignLookupErrorBanner.icon(for: error))
                .foregroundStyle(CallsignLookupErrorBanner.iconColor(for: error))
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 2) {
                Text(error.errorDescription ?? "Lookup failed")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(CallsignLookupErrorBanner.backgroundColor(for: error))
    }
}
