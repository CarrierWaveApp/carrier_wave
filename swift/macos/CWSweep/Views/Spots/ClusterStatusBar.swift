import SwiftUI

// MARK: - ClusterStatusBar

/// Displays parsed solar weather and cluster filter configuration in a compact bar
struct ClusterStatusBar: View {
    // MARK: Internal

    let solarWeather: [SolarWeatherEntry]
    let solarFetchedAt: Date?
    let filterConfig: ClusterFilterConfig?
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            solarSection

            if filterConfig != nil {
                Divider()
                    .frame(height: 20)
                filterSection
            }

            Spacer()

            refreshButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.background.secondary)
    }

    // MARK: Private

    private var solarSection: some View {
        HStack(spacing: 6) {
            Image(systemName: "sun.max")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let latest = solarWeather.first {
                metricPill("S", value: "\(latest.sfi)", color: sfiColor(latest.sfi))
                metricPill("A", value: "\(latest.aIndex)", color: aIndexColor(latest.aIndex))
                metricPill("K", value: "\(latest.kIndex)", color: kIndexColor(latest.kIndex))

                Text(latest.forecast)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 120)

                ageLabel
            }
        }
    }

    @ViewBuilder
    private var ageLabel: some View {
        if let fetchedAt = solarFetchedAt {
            TimelineView(.periodic(from: .now, by: 10)) { context in
                let age = Int(context.date.timeIntervalSince(fetchedAt))
                Text(formattedAge(age))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var filterSection: some View {
        HStack(spacing: 4) {
            if let config = filterConfig {
                if let count = config.count {
                    filterPill("\(count)")
                }
                if !config.mode.isEmpty {
                    filterPill(config.mode)
                }
                if config.output == "ON" {
                    filterPill("OUT", active: true)
                }
                if !config.filter.isEmpty {
                    filterPill(config.filter)
                }
            }
        }
    }

    private var refreshButton: some View {
        Button {
            onRefresh()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.caption2)
        }
        .buttonStyle(.borderless)
        .help("Refresh solar data and filters")
    }

    // MARK: - Pill Views

    private func metricPill(
        _ label: String,
        value: String,
        color: Color
    ) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption2.bold().monospacedDigit())
                .foregroundStyle(color)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
    }

    private func filterPill(_ text: String, active: Bool = true) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(active ? .primary : .tertiary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        active
                            ? Color.accentColor.opacity(0.1)
                            : Color.secondary.opacity(0.05)
                    )
            )
    }

    // MARK: - Color Helpers

    private func sfiColor(_ sfi: Int) -> Color {
        if sfi >= 150 {
            return .green
        }
        if sfi >= 100 {
            return .yellow
        }
        if sfi >= 70 {
            return .orange
        }
        return .red
    }

    private func aIndexColor(_ ai: Int) -> Color {
        if ai <= 7 {
            return .green
        }
        if ai <= 15 {
            return .yellow
        }
        if ai <= 30 {
            return .orange
        }
        return .red
    }

    private func kIndexColor(_ ki: Int) -> Color {
        if ki <= 2 {
            return .green
        }
        if ki <= 4 {
            return .yellow
        }
        if ki <= 6 {
            return .orange
        }
        return .red
    }

    private func formattedAge(_ seconds: Int) -> String {
        if seconds < 60 {
            "<1m"
        } else if seconds < 3_600 {
            "\(seconds / 60)m"
        } else {
            "\(seconds / 3_600)h\((seconds % 3_600) / 60)m"
        }
    }
}
