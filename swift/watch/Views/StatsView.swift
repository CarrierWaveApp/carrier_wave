import SwiftUI

/// Quick stats page showing streaks and counts.
struct StatsView: View {
    // MARK: Internal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                headerRow
                if let streaks {
                    streakSection(streaks)
                }
                if let counts {
                    countSection(counts)
                }
                if streaks == nil, counts == nil {
                    noDataView
                }
            }
            .padding(.horizontal, 4)
        }
        .onAppear {
            streaks = SharedDataReader.readStreaks()
            counts = SharedDataReader.readCounts()
        }
    }

    // MARK: Private

    @State private var streaks: WatchStreakSnapshot?
    @State private var counts: WatchCountSnapshot?

    private var headerRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "chart.bar.fill")
                .font(.caption)
                .foregroundStyle(.blue)
            Text("Stats")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var noDataView: some View {
        VStack(spacing: 8) {
            Text("No stats yet")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Open Carrier Wave on iPhone")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 16)
    }

    // MARK: - Streaks

    private func streakSection(_ streaks: WatchStreakSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            streakRow(
                label: "On Air",
                current: streaks.onAirCurrent,
                longest: streaks.onAirLongest,
                atRisk: streaks.onAirAtRisk
            )
            streakRow(
                label: "Activations",
                current: streaks.activationCurrent,
                longest: streaks.activationLongest,
                atRisk: streaks.activationAtRisk
            )
            streakRow(
                label: "Hunts",
                current: streaks.hunterCurrent,
                longest: streaks.hunterLongest,
                atRisk: streaks.hunterAtRisk
            )
        }
    }

    private func streakRow(
        label: String, current: Int, longest: Int, atRisk: Bool
    ) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(current)d")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(atRisk ? .orange : .primary)
            Text("/ \(longest)d")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Counts

    private func countSection(_ counts: WatchCountSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            countRow(label: "QSOs this week", value: counts.qsosWeek)
            countRow(label: "QSOs this month", value: counts.qsosMonth)
            countRow(label: "Activations", value: counts.activationsMonth)
            countRow(label: "Hunts this week", value: counts.huntsWeek)
        }
    }

    private func countRow(label: String, value: Int) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(value)")
                .font(.system(.caption, design: .rounded, weight: .bold))
        }
    }
}
