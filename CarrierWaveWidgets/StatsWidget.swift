import AppIntents
import SwiftUI
import WidgetKit

// MARK: - StatsMetricType

enum StatsMetricType: String, CaseIterable, AppEnum {
    case onAirStreak
    case activationStreak
    case hunterStreak
    case cwStreak
    case phoneStreak
    case digitalStreak
    case qsosWeek
    case qsosMonth
    case qsosYear
    case activationsMonth
    case activationsYear
    case huntsWeek
    case huntsMonth
    case newDXCCYear

    // MARK: Internal

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Metric")

    static var caseDisplayRepresentations: [StatsMetricType: DisplayRepresentation] {
        [
            .onAirStreak: "On-Air Streak",
            .activationStreak: "Activation Streak",
            .hunterStreak: "Hunter Streak",
            .cwStreak: "CW Streak",
            .phoneStreak: "Phone Streak",
            .digitalStreak: "Digital Streak",
            .qsosWeek: "QSOs This Week",
            .qsosMonth: "QSOs This Month",
            .qsosYear: "QSOs This Year",
            .activationsMonth: "Activations This Month",
            .activationsYear: "Activations This Year",
            .huntsWeek: "Parks Hunted This Week",
            .huntsMonth: "Parks Hunted This Month",
            .newDXCCYear: "New DXCC This Year",
        ]
    }

    var icon: String {
        switch self {
        case .onAirStreak: "flame.fill"
        case .activationStreak: "leaf.fill"
        case .hunterStreak: "binoculars.fill"
        case .cwStreak: "waveform.path"
        case .phoneStreak: "mic.fill"
        case .digitalStreak: "desktopcomputer"
        case .qsosWeek,
             .qsosMonth,
             .qsosYear:
            "antenna.radiowaves.left.and.right"
        case .activationsMonth,
             .activationsYear: "leaf"
        case .huntsWeek,
             .huntsMonth: "binoculars"
        case .newDXCCYear: "globe"
        }
    }

    var isStreak: Bool {
        switch self {
        case .onAirStreak,
             .activationStreak,
             .hunterStreak,
             .cwStreak,
             .phoneStreak,
             .digitalStreak:
            true
        default:
            false
        }
    }

    var shortLabel: String {
        switch self {
        case .onAirStreak: "On-Air"
        case .activationStreak: "Activation"
        case .hunterStreak: "Hunter"
        case .cwStreak: "CW"
        case .phoneStreak: "Phone"
        case .digitalStreak: "Digital"
        case .qsosWeek: "QSOs / Week"
        case .qsosMonth: "QSOs / Month"
        case .qsosYear: "QSOs / Year"
        case .activationsMonth: "Activations"
        case .activationsYear: "Activations"
        case .huntsWeek: "Hunts / Week"
        case .huntsMonth: "Hunts / Month"
        case .newDXCCYear: "New DXCC"
        }
    }
}

// MARK: - StatsWidgetIntent

struct StatsWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Stats Widget"
    static let description: IntentDescription = "Choose which metric to display."

    @Parameter(title: "Metric", default: .onAirStreak)
    var metric: StatsMetricType
}

// MARK: - StatsEntry

struct StatsEntry: TimelineEntry {
    let date: Date
    let metric: StatsMetricType
    let value: Int
    let secondaryValue: Int? // longest streak for streak types
    let isAtRisk: Bool
}

// MARK: - StatsTimelineProvider

struct StatsTimelineProvider: AppIntentTimelineProvider {
    // MARK: Internal

    func placeholder(in _: Context) -> StatsEntry {
        StatsEntry(
            date: Date(), metric: .onAirStreak,
            value: 5, secondaryValue: 12, isAtRisk: false
        )
    }

    func snapshot(
        for configuration: StatsWidgetIntent, in _: Context
    ) async -> StatsEntry {
        readEntry(for: configuration.metric)
    }

    func timeline(
        for configuration: StatsWidgetIntent, in _: Context
    ) async -> Timeline<StatsEntry> {
        let entry = readEntry(for: configuration.metric)
        // Refresh every hour
        let nextUpdate = Date().addingTimeInterval(60 * 60)
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    // MARK: Private

    private struct ResolvedMetric {
        let value: Int
        let secondary: Int?
        let atRisk: Bool
    }

    private func readEntry(for metric: StatsMetricType) -> StatsEntry {
        let streaks = WidgetDataReader.readStreaks()
        let counts = WidgetDataReader.readCounts()

        let resolved = resolveMetric(
            metric, streaks: streaks, counts: counts
        )

        return StatsEntry(
            date: Date(), metric: metric,
            value: resolved.value, secondaryValue: resolved.secondary, isAtRisk: resolved.atRisk
        )
    }

    private func resolveMetric(
        _ metric: StatsMetricType,
        streaks: WidgetStreakSnapshot?,
        counts: WidgetCountSnapshot?
    ) -> ResolvedMetric {
        switch metric {
        case .onAirStreak:
            ResolvedMetric(value: streaks?.onAirCurrent ?? 0, secondary: streaks?.onAirLongest,
                           atRisk: streaks?.onAirAtRisk ?? false)
        case .activationStreak:
            ResolvedMetric(value: streaks?.activationCurrent ?? 0, secondary: streaks?.activationLongest,
                           atRisk: streaks?.activationAtRisk ?? false)
        case .hunterStreak:
            ResolvedMetric(value: streaks?.hunterCurrent ?? 0, secondary: streaks?.hunterLongest,
                           atRisk: streaks?.hunterAtRisk ?? false)
        case .cwStreak:
            ResolvedMetric(value: streaks?.cwCurrent ?? 0, secondary: nil, atRisk: false)
        case .phoneStreak:
            ResolvedMetric(value: streaks?.phoneCurrent ?? 0, secondary: nil, atRisk: false)
        case .digitalStreak:
            ResolvedMetric(value: streaks?.digitalCurrent ?? 0, secondary: nil, atRisk: false)
        case .qsosWeek:
            ResolvedMetric(value: counts?.qsosWeek ?? 0, secondary: nil, atRisk: false)
        case .qsosMonth:
            ResolvedMetric(value: counts?.qsosMonth ?? 0, secondary: nil, atRisk: false)
        case .qsosYear:
            ResolvedMetric(value: counts?.qsosYear ?? 0, secondary: nil, atRisk: false)
        case .activationsMonth:
            ResolvedMetric(value: counts?.activationsMonth ?? 0, secondary: nil, atRisk: false)
        case .activationsYear:
            ResolvedMetric(value: counts?.activationsYear ?? 0, secondary: nil, atRisk: false)
        case .huntsWeek:
            ResolvedMetric(value: counts?.huntsWeek ?? 0, secondary: nil, atRisk: false)
        case .huntsMonth:
            ResolvedMetric(value: counts?.huntsMonth ?? 0, secondary: nil, atRisk: false)
        case .newDXCCYear:
            ResolvedMetric(value: counts?.newDXCCYear ?? 0, secondary: nil, atRisk: false)
        }
    }
}

// MARK: - StatsWidgetSmallView

struct StatsWidgetSmallView: View {
    let entry: StatsEntry

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: entry.metric.icon)
                .font(.title3)
                .foregroundStyle(entry.isAtRisk ? .orange : .blue)

            Text("\(entry.value)")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(entry.isAtRisk ? .orange : .primary)

            Text(entry.metric.shortLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if entry.metric.isStreak {
                if let best = entry.secondaryValue, best > 0 {
                    Text("Best: \(best)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if entry.isAtRisk {
                    Text("At Risk!")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding()
    }
}

// MARK: - StatsWidgetAccessoryCircularView

struct StatsWidgetAccessoryCircularView: View {
    let entry: StatsEntry

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: entry.metric.icon)
                .font(.caption)
            Text("\(entry.value)")
                .font(.title3.weight(.bold))
        }
    }
}

// MARK: - StatsWidgetAccessoryRectangularView

struct StatsWidgetAccessoryRectangularView: View {
    let entry: StatsEntry

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.metric.icon)
                .font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.metric.shortLabel)
                    .font(.caption2.weight(.semibold))
                HStack(spacing: 4) {
                    Text("\(entry.value)")
                        .font(.caption.weight(.bold))
                    if entry.metric.isStreak, let best = entry.secondaryValue, best > 0 {
                        Text("(best \(best))")
                            .font(.caption2)
                    }
                }
            }
            Spacer()
        }
    }
}

// MARK: - StatsWidget

struct StatsWidget: Widget {
    let kind = "StatsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind, intent: StatsWidgetIntent.self,
            provider: StatsTimelineProvider()
        ) { entry in
            Group {
                switch entry.widgetFamily {
                case .accessoryCircular:
                    StatsWidgetAccessoryCircularView(entry: entry)
                case .accessoryRectangular:
                    StatsWidgetAccessoryRectangularView(entry: entry)
                default:
                    StatsWidgetSmallView(entry: entry)
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(URL(string: WidgetShared.DeepLink.dashboard))
        }
        .configurationDisplayName("Stats & Streaks")
        .description("Track your on-air streaks, QSO counts, and more.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Preview

private extension StatsEntry {
    var widgetFamily: WidgetFamily {
        .systemSmall
    }
}
