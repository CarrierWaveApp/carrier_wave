import SwiftUI
import WidgetKit

// MARK: - HuntEntry

struct HuntEntry: TimelineEntry {
    let date: Date
    let solar: SolarData?
    let activeSpotCount: Int
}

// MARK: - HuntTimelineProvider

struct HuntTimelineProvider: TimelineProvider {
    // MARK: Internal

    func placeholder(in _: Context) -> HuntEntry {
        HuntEntry(date: Date(), solar: .placeholder, activeSpotCount: 9)
    }

    func getSnapshot(in _: Context, completion: @escaping (HuntEntry) -> Void) {
        completion(HuntEntry(date: Date(), solar: .placeholder, activeSpotCount: 9))
    }

    func getTimeline(
        in _: Context,
        completion: @escaping (Timeline<HuntEntry>) -> Void
    ) {
        Task {
            async let solarTask = SolarFetcher.fetch()
            async let spotsTask = SpotsFetcher.fetch(source: .both)
            let solar = await solarTask ?? appGroupSolarData()
            let spotCount = await spotsTask.totalCount
            let entry = HuntEntry(
                date: Date(), solar: solar, activeSpotCount: spotCount
            )
            // Refresh every 15 min — spot freshness matters more than solar
            let nextUpdate = Date().addingTimeInterval(15 * 60)
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    // MARK: Private

    private func appGroupSolarData() -> SolarData? {
        guard let snapshot = WidgetDataReader.readSolar() else {
            return nil
        }
        return SolarData(
            kIndex: snapshot.kIndex ?? 0,
            aIndex: snapshot.aIndex,
            solarFlux: snapshot.solarFlux,
            sunspots: snapshot.sunspots,
            bandConditions: [:],
            timestamp: snapshot.updatedAt
        )
    }
}

// MARK: - HuntWidgetSmallView

struct HuntWidgetSmallView: View {
    // MARK: Internal

    let solar: SolarData?
    let activeSpotCount: Int

    var body: some View {
        if let solar {
            VStack(spacing: 6) {
                headerRow(solar)
                gaugeRow(solar)
                Spacer(minLength: 0)
                bottomRow(solar)
            }
            .padding(4)
        } else {
            noDataView
        }
    }

    // MARK: Private

    private var noDataView: some View {
        VStack(spacing: 8) {
            Image(systemName: "binoculars")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No Data")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var spotsBadge: some View {
        VStack(spacing: 0) {
            Image(systemName: "binoculars.fill")
                .font(.system(size: 14))
                .foregroundStyle(.blue)
            Text("\(activeSpotCount)")
                .font(.system(.callout, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .frame(minWidth: 26)
    }

    private func headerRow(_ solar: SolarData) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "binoculars.fill")
                .font(.caption)
                .foregroundStyle(.blue)
            Text("Hunt")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            Text(solar.propagationRating)
                .font(.caption.weight(.bold))
                .foregroundStyle(PropagationLevel.rating(solar.propagationRating))
        }
    }

    private func gaugeRow(_ solar: SolarData) -> some View {
        HStack(spacing: 0) {
            let kLevel = PropagationLevel.kIndex(solar.kIndex)
            CircularMetricGauge(
                label: "K", value: String(format: "%.0f", solar.kIndex),
                level: kLevel.level, color: kLevel.color
            )

            if let aIdx = solar.aIndex {
                Spacer()
                let aLevel = PropagationLevel.aIndex(aIdx)
                CircularMetricGauge(
                    label: "A", value: "\(aIdx)",
                    level: aLevel.level, color: aLevel.color
                )
            }

            if let sfi = solar.solarFlux {
                Spacer()
                let sfiLevel = PropagationLevel.sfi(sfi)
                CircularMetricGauge(
                    label: "SFI", value: "\(Int(sfi))",
                    level: sfiLevel.level, color: sfiLevel.color
                )
            }
        }
    }

    private func bottomRow(_ solar: SolarData) -> some View {
        HStack(alignment: .center, spacing: 6) {
            allBandsGrid(solar)
            Spacer(minLength: 0)
            spotsBadge
        }
    }

    private func allBandsGrid(_ solar: SolarData) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 4, verticalSpacing: 2) {
            GridRow {
                bandCell(.band80m40m, solar)
                bandCell(.band30m20m, solar)
            }
            GridRow {
                bandCell(.band17m15m, solar)
                bandCell(.band12m10m, solar)
            }
        }
    }

    private func bandCell(_ band: SolarBand, _ solar: SolarData) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(
                    solar.bandConditions[band.rawValue]
                        .map { PropagationLevel.condition($0.day) } ?? .secondary
                )
                .frame(width: 7, height: 7)
            Text(shortLabel(for: band))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private func shortLabel(for band: SolarBand) -> String {
        switch band {
        case .band80m40m: "80/40"
        case .band30m20m: "30/20"
        case .band17m15m: "17/15"
        case .band12m10m: "12/10"
        }
    }
}

// MARK: - HuntWidgetEntryView

struct HuntWidgetEntryView: View {
    let entry: HuntEntry

    var body: some View {
        HuntWidgetSmallView(
            solar: entry.solar,
            activeSpotCount: entry.activeSpotCount
        )
    }
}

// MARK: - HuntWidget

struct HuntWidget: Widget {
    let kind = "HuntWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HuntTimelineProvider()) { entry in
            HuntWidgetEntryView(entry: entry)
                .widgetURL(URL(string: WidgetShared.DeepLink.hunt))
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Hunt")
        .description("Propagation, band conditions, and active spot count for hunters.")
        .supportedFamilies([.systemSmall])
    }
}
