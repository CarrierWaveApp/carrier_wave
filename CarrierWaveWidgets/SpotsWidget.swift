import AppIntents
import SwiftUI
import WidgetKit

// MARK: - SpotsWidgetIntent

struct SpotsWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Spots Widget"
    static let description: IntentDescription = "Show live POTA and RBN spots."

    @Parameter(title: "Source", default: .both)
    var source: SpotSourceFilter

    @Parameter(title: "Bands", default: [])
    var bands: [SpotBandFilter]

    @Parameter(title: "Modes", default: [])
    var modes: [SpotModeFilter]
}

// MARK: - SpotsEntry

struct SpotsEntry: TimelineEntry {
    let date: Date
    let spots: [WidgetSpot]
    let totalSpotCount: Int
    let source: SpotSourceFilter
    let bands: [SpotBandFilter]
    let modes: [SpotModeFilter]
}

// MARK: - SpotsTimelineProvider

struct SpotsTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> SpotsEntry {
        SpotsEntry(
            date: Date(), spots: [], totalSpotCount: 0,
            source: .both, bands: [], modes: []
        )
    }

    func snapshot(
        for configuration: SpotsWidgetIntent, in _: Context
    ) async -> SpotsEntry {
        let result = await SpotsFetcher.fetch(
            source: configuration.source,
            bands: configuration.bands,
            modes: configuration.modes
        )
        return SpotsEntry(
            date: Date(), spots: result.spots,
            totalSpotCount: result.totalCount,
            source: configuration.source,
            bands: configuration.bands, modes: configuration.modes
        )
    }

    func timeline(
        for configuration: SpotsWidgetIntent, in _: Context
    ) async -> Timeline<SpotsEntry> {
        let result = await SpotsFetcher.fetch(
            source: configuration.source,
            bands: configuration.bands,
            modes: configuration.modes
        )
        let entry = SpotsEntry(
            date: Date(), spots: result.spots,
            totalSpotCount: result.totalCount,
            source: configuration.source,
            bands: configuration.bands, modes: configuration.modes
        )
        // Refresh every 5 minutes
        let nextUpdate = Date().addingTimeInterval(5 * 60)
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}

// MARK: - SpotsWidgetMediumView

struct SpotsWidgetMediumView: View {
    // MARK: Internal

    let entry: SpotsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            headerRow
            if entry.spots.isEmpty {
                spotsEmptyState(font: .caption, iconFont: .title3)
            } else {
                let displayCount = min(entry.spots.count, 5)
                ForEach(entry.spots.prefix(displayCount), id: \.id) { spot in
                    spotRow(spot)
                }
                if entry.totalSpotCount > displayCount {
                    moreIndicator(
                        remaining: entry.totalSpotCount - displayCount,
                        font: .caption2
                    )
                }
                Spacer(minLength: 0)
            }
        }
        .padding()
    }

    // MARK: Private

    private var sourceLabel: String {
        switch entry.source {
        case .both: "All"
        case .pota: "POTA"
        case .rbn: "RBN"
        }
    }

    private var headerRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.caption)
                .foregroundStyle(.blue)
            Text("Spots")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            filterBadges(font: .caption2)
        }
    }

    private func spotRow(_ spot: WidgetSpot) -> some View {
        HStack(spacing: 0) {
            Circle()
                .fill(spot.ageColor)
                .frame(width: 5, height: 5)
                .padding(.trailing, 4)

            Text(spot.callsign)
                .font(.caption2.weight(.semibold).monospaced())
                .lineLimit(1)
                .frame(width: 64, alignment: .leading)

            Text(spot.frequencyDisplay)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)

            Text(spot.mode)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            Text(spot.sourceLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(spot.timeAgo)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
    }

    private func filterBadges(font: Font) -> some View {
        HStack(spacing: 3) {
            Text(sourceLabel)
                .font(font)
                .foregroundStyle(.tertiary)
            if entry.bands.count > 2 {
                Text("\(entry.bands.count) bands")
                    .font(font.weight(.medium))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(.blue.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                ForEach(entry.bands, id: \.self) { band in
                    Text(band.shortLabel)
                        .font(font.weight(.medium))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(.blue.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            if entry.modes.count > 2 {
                Text("\(entry.modes.count) modes")
                    .font(font.weight(.medium))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(.purple.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                ForEach(entry.modes, id: \.self) { mode in
                    Text(mode.shortLabel)
                        .font(font.weight(.medium))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(.purple.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
        }
    }
}

// MARK: - SpotsWidgetLargeView

struct SpotsWidgetLargeView: View {
    // MARK: Internal

    let entry: SpotsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerRow
                .padding(.bottom, 2)
            if entry.spots.isEmpty {
                spotsEmptyState(font: .subheadline, iconFont: .largeTitle)
            } else {
                let displayCount = min(entry.spots.count, 8)
                ForEach(entry.spots.prefix(displayCount), id: \.id) { spot in
                    spotRow(spot)
                    if spot.id != entry.spots.prefix(displayCount).last?.id {
                        Divider()
                    }
                }
                if entry.totalSpotCount > displayCount {
                    moreIndicator(
                        remaining: entry.totalSpotCount - displayCount,
                        font: .caption2
                    )
                }
                Spacer(minLength: 0)
            }
        }
        .padding()
    }

    // MARK: Private

    private var sourceLabel: String {
        switch entry.source {
        case .both: "All"
        case .pota: "POTA"
        case .rbn: "RBN"
        }
    }

    private var headerRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.subheadline)
                .foregroundStyle(.blue)
            Text("Spots")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            filterBadges
        }
    }

    private var filterBadges: some View {
        HStack(spacing: 4) {
            Text(sourceLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if entry.bands.count > 2 {
                Text("\(entry.bands.count) bands")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.blue.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                ForEach(entry.bands, id: \.self) { band in
                    Text(band.shortLabel)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.blue.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            if entry.modes.count > 2 {
                Text("\(entry.modes.count) modes")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.purple.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                ForEach(entry.modes, id: \.self) { mode in
                    Text(mode.shortLabel)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.purple.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
        }
    }

    private func spotRow(_ spot: WidgetSpot) -> some View {
        HStack(spacing: 0) {
            Circle()
                .fill(spot.ageColor)
                .frame(width: 7, height: 7)
                .padding(.trailing, 6)

            Text(spot.callsign)
                .font(.caption.weight(.semibold).monospaced())
                .lineLimit(1)
                .frame(width: 72, alignment: .leading)

            Text(spot.frequencyDisplay)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)

            Text(spot.mode)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)

            Text(spot.sourceLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(spot.timeAgo)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Shared Helpers

func moreIndicator(remaining: Int, font: Font) -> some View {
    HStack {
        Spacer()
        Text("+\(remaining) more in app")
            .font(font.weight(.medium))
            .foregroundStyle(.blue)
    }
}

func spotsEmptyState(font: Font, iconFont: Font) -> some View {
    VStack {
        Spacer()
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(iconFont)
                    .foregroundStyle(.secondary)
                Text("No active spots")
                    .font(font)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        Spacer()
    }
}

// MARK: - SpotsWidget

struct SpotsWidget: Widget {
    let kind = "SpotsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind, intent: SpotsWidgetIntent.self,
            provider: SpotsTimelineProvider()
        ) { entry in
            Group {
                switch entry.widgetFamily {
                case .systemLarge:
                    SpotsWidgetLargeView(entry: entry)
                default:
                    SpotsWidgetMediumView(entry: entry)
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(URL(string: WidgetShared.DeepLink.activityLog))
        }
        .configurationDisplayName("Radio Spots")
        .description("Live POTA activator and RBN spots with band and mode filters.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Preview

private extension SpotsEntry {
    var widgetFamily: WidgetFamily {
        .systemMedium
    }
}
