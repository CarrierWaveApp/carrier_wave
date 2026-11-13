import AppIntents
import SwiftUI
import WidgetKit

// MARK: - SpotsWidgetIntent

struct SpotsWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Spots Widget"
    static let description: IntentDescription = "Show live POTA, SOTA, and RBN spots."

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
        let nextUpdate = Date().addingTimeInterval(5 * 60)
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}

// MARK: - SpotsWidgetSmallView

struct SpotsWidgetSmallView: View {
    // MARK: Internal

    let entry: SpotsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            spotsHeader(font: .caption2, iconFont: .caption2)
            if entry.spots.isEmpty {
                spotsEmptyState(font: .caption2, iconFont: .title3)
            } else {
                let displayCount = min(entry.spots.count, 4)
                Spacer(minLength: 0)
                ForEach(entry.spots.prefix(displayCount), id: \.id) { spot in
                    smallSpotRow(spot)
                    Spacer(minLength: 0)
                }
                if entry.totalSpotCount > displayCount {
                    moreIndicator(
                        remaining: entry.totalSpotCount - displayCount,
                        font: .system(size: 9)
                    )
                }
            }
        }
    }

    // MARK: Private

    private func smallSpotRow(_ spot: WidgetSpot) -> some View {
        HStack(spacing: 0) {
            Image(systemName: spot.activityIcon)
                .font(.system(size: 7))
                .foregroundStyle(spot.activityColor)
                .frame(width: 12)

            Text(spot.callsign)
                .font(.caption2.weight(.semibold).monospaced())
                .lineLimit(1)

            Spacer(minLength: 3)

            if let band = spot.band {
                Text(band)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .padding(.trailing, 2)
            }
            Text(spot.mode)
                .font(.system(size: 9).weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }
}

// MARK: - SpotsWidgetMediumView

struct SpotsWidgetMediumView: View {
    // MARK: Internal

    let entry: SpotsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                spotsHeader(font: .caption, iconFont: .caption)
                Spacer()
                spotsFilterBadges(entry: entry, font: .caption2)
            }
            if entry.spots.isEmpty {
                spotsEmptyState(font: .caption, iconFont: .title3)
            } else {
                let displayCount = min(entry.spots.count, 5)
                Spacer(minLength: 0)
                ForEach(entry.spots.prefix(displayCount), id: \.id) { spot in
                    mediumSpotRow(spot)
                    Spacer(minLength: 0)
                }
                if entry.totalSpotCount > displayCount {
                    moreIndicator(
                        remaining: entry.totalSpotCount - displayCount,
                        font: .caption2
                    )
                }
            }
        }
    }

    // MARK: Private

    private func mediumSpotRow(_ spot: WidgetSpot) -> some View {
        HStack(spacing: 0) {
            Image(systemName: spot.activityIcon)
                .font(.system(size: 8))
                .foregroundStyle(spot.activityColor)
                .frame(width: 14)

            Text(spot.callsign)
                .font(.caption2.weight(.semibold).monospaced())
                .lineLimit(1)
                .frame(width: 64, alignment: .leading)

            if let ref = spot.referenceLabel {
                Text(ref)
                    .font(.system(size: 9).weight(.medium))
                    .foregroundStyle(spot.activityColor)
                    .lineLimit(1)
                    .frame(maxWidth: 60, alignment: .leading)
            } else if let snr = spot.snr {
                Text("\(snr)dB")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            Spacer(minLength: 3)

            if let band = spot.band {
                Text(band)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .padding(.trailing, 3)
            }
            Text(spot.mode)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize()
                .padding(.trailing, 3)

            Text(spot.timeAgo)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .fixedSize()
        }
    }
}

// MARK: - SpotsWidgetLargeView

struct SpotsWidgetLargeView: View {
    // MARK: Internal

    let entry: SpotsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                spotsHeader(font: .subheadline, iconFont: .subheadline)
                Spacer()
                spotsFilterBadges(entry: entry, font: .caption2)
            }
            .padding(.bottom, 2)
            if entry.spots.isEmpty {
                spotsEmptyState(font: .subheadline, iconFont: .largeTitle)
            } else {
                let displayCount = min(entry.spots.count, 8)
                ForEach(entry.spots.prefix(displayCount), id: \.id) { spot in
                    largeSpotRow(spot)
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
    }

    // MARK: Private

    private func largeSpotRow(_ spot: WidgetSpot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 0) {
                Image(systemName: spot.activityIcon)
                    .font(.system(size: 9))
                    .foregroundStyle(spot.activityColor)
                    .frame(width: 16)

                Text(spot.callsign)
                    .font(.caption.weight(.semibold).monospaced())
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let band = spot.band {
                    Text(band)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)
                }
                Text(spot.mode)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                if let detail = spot.detailText {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(spot.activityColor)
                        .lineLimit(1)
                } else {
                    Text(spot.frequencyDisplay)
                        .font(.system(size: 10).monospaced())
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(spot.timeAgo)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 16)
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Shared Helpers

func spotsHeader(font: Font, iconFont: Font) -> some View {
    HStack(spacing: 4) {
        Image(systemName: "antenna.radiowaves.left.and.right")
            .font(iconFont)
            .foregroundStyle(.blue)
        Text("Spots")
            .font(font.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

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

func spotsFilterBadges(entry: SpotsEntry, font: Font) -> some View {
    HStack(spacing: 3) {
        Text(spotsSourceLabel(entry.source))
            .font(font)
            .foregroundStyle(.tertiary)
        if entry.bands.count > 2 {
            filterPill("\(entry.bands.count) bands", font: font, color: .blue)
        } else {
            ForEach(entry.bands, id: \.self) { band in
                filterPill(band.shortLabel, font: font, color: .blue)
            }
        }
        if entry.modes.count > 2 {
            filterPill("\(entry.modes.count) modes", font: font, color: .purple)
        } else {
            ForEach(entry.modes, id: \.self) { mode in
                filterPill(mode.shortLabel, font: font, color: .purple)
            }
        }
    }
}

private func spotsSourceLabel(_ source: SpotSourceFilter) -> String {
    switch source {
    case .both: "All"
    case .pota: "POTA"
    case .sota: "SOTA"
    case .rbn: "RBN"
    }
}

private func filterPill(_ text: String, font: Font, color: Color) -> some View {
    Text(text)
        .font(font.weight(.medium))
        .padding(.horizontal, 3)
        .padding(.vertical, 1)
        .background(color.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 3))
}

// MARK: - SpotsWidgetEntryView

struct SpotsWidgetEntryView: View {
    @Environment(\.widgetFamily) var widgetFamily

    let entry: SpotsEntry

    var body: some View {
        switch widgetFamily {
        case .systemSmall:
            SpotsWidgetSmallView(entry: entry)
        case .systemLarge:
            SpotsWidgetLargeView(entry: entry)
        default:
            SpotsWidgetMediumView(entry: entry)
        }
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
            SpotsWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: WidgetShared.DeepLink.activityLog))
        }
        .configurationDisplayName("Radio Spots")
        .description("Live POTA, SOTA, and RBN spots with band and mode filters.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
