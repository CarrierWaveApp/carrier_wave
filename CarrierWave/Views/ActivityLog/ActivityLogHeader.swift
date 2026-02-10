import SwiftUI

// MARK: - ActivityLogHeader

/// Header for the Activity Log view showing daily counter and station profile info.
struct ActivityLogHeader: View {
    // MARK: Internal

    let todayQSOCount: Int
    let todayBands: Set<String>
    let todayModes: Set<String>
    let profileName: String?
    let profileSummary: String?
    let grid: String?
    let onSwitchProfile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            dailyCounterBar
            profileBar
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    private var dailyCounterBar: some View {
        HStack(spacing: 4) {
            Text("Today:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("\(todayQSOCount)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(todayQSOCount > 0 ? .green : .primary)

            Text("QSO\(todayQSOCount == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("·")
                .foregroundStyle(.secondary)

            Text("\(todayBands.count) band\(todayBands.count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var profileBar: some View {
        HStack {
            if let profileName {
                Text(profileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let profileSummary, !profileSummary.isEmpty {
                Text("·")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(profileSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let grid, !grid.isEmpty {
                Label(grid, systemImage: "mappin")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Switch") {
                onSwitchProfile()
            }
            .font(.caption.weight(.medium))
            .buttonStyle(.bordered)
            .accessibilityLabel("Switch station profile")
        }
    }
}
