import SwiftData
import SwiftUI

// MARK: - ActivityLogCard

/// Dashboard card for the activity log. Shows either a setup prompt (no log exists)
/// or today's stats with a tap-to-open action.
struct ActivityLogCard: View {
    // MARK: Internal

    let activeLog: ActivityLog?
    let todayQSOCount: Int
    let todayBands: Set<String>
    let profileSummary: String?
    let grid: String?
    let showSetup: () -> Void

    var body: some View {
        if let log = activeLog {
            activeCard(log: log)
        } else {
            setupCard
        }
    }

    // MARK: Private

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .font(.title3)
                    .foregroundStyle(.blue)
                Text("Hunter Log")
                    .font(.headline)
            }

            Text("Track daily contacts while hunting spots. No session start/stop needed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                showSetup()
            } label: {
                Text("Set Up Hunter Log")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func activeCard(log: ActivityLog) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "scope")
                    .font(.title3)
                    .foregroundStyle(.blue)
                Text("Hunter Log")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Stat boxes row
            HStack(spacing: 8) {
                miniStatBox(
                    value: "\(todayQSOCount)",
                    label: "QSOs\ntoday",
                    valueColor: todayQSOCount > 0 ? .green : .primary
                )
                miniStatBox(
                    value: "\(todayBands.count)",
                    label: "Bands\ntoday",
                    valueColor: .primary
                )
            }

            // Profile + grid info
            if let profileSummary, !profileSummary.isEmpty {
                HStack {
                    Text(profileSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if let grid, !grid.isEmpty {
                        Label(grid, systemImage: "mappin")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func miniStatBox(
        value: String,
        label: String,
        valueColor: Color
    ) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(valueColor)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
