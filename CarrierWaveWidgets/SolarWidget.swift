import AppIntents
import SwiftUI
import WidgetKit

// MARK: - SolarData

/// Lightweight solar conditions fetched directly by the widget
struct SolarData: Sendable {
    static let placeholder = SolarData(
        kIndex: 2.0, aIndex: 5, solarFlux: 150, sunspots: 80,
        bandConditions: [
            "80m-40m": BandCondition(day: "Good", night: "Fair"),
            "30m-20m": BandCondition(day: "Good", night: "Fair"),
            "17m-15m": BandCondition(day: "Good", night: "Poor"),
            "12m-10m": BandCondition(day: "Fair", night: "Poor"),
        ],
        timestamp: Date()
    )

    let kIndex: Double
    let aIndex: Int?
    let solarFlux: Double?
    let sunspots: Int?
    let bandConditions: [String: BandCondition]
    let timestamp: Date

    var propagationRating: String {
        switch kIndex {
        case 0 ..< 2: "Excellent"
        case 2 ..< 3: "Good"
        case 3 ..< 4: "Fair"
        case 4 ..< 5: "Poor"
        default: "Very Poor"
        }
    }

    var kDescription: String {
        switch kIndex {
        case 0 ..< 3: "Quiet"
        case 3 ..< 4: "Unsettled"
        case 4 ..< 5: "Active"
        default: "Storm"
        }
    }

    var sfiDescription: String {
        guard let sfi = solarFlux else {
            return "N/A"
        }
        switch sfi {
        case 0 ..< 70: return "Poor"
        case 70 ..< 90: return "Low"
        case 90 ..< 120: return "Good"
        case 120 ..< 200: return "Very Good"
        default: return "Excellent"
        }
    }

    var aIndexDescription: String {
        guard let aIdx = aIndex else {
            return "N/A"
        }
        switch aIdx {
        case 0 ..< 7: return "Quiet"
        case 7 ..< 15: return "Unsettled"
        case 15 ..< 30: return "Active"
        case 30 ..< 50: return "Storm"
        default: return "Severe"
        }
    }
}

// MARK: - SolarFetcher

/// Fetches solar conditions from HamQSL XML API
enum SolarFetcher {
    // MARK: Internal

    static func fetch() async -> SolarData? {
        guard let url = URL(string: hamQSLURL) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("CarrierWave-Widget/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let xml = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        let kIndex = extractValue(from: xml, tag: "kindex").flatMap { Double($0) } ?? 0
        let aIndex = extractValue(from: xml, tag: "aindex").flatMap { Int($0) }
        let solarFlux = extractValue(from: xml, tag: "solarflux").flatMap { Double($0) }
        let sunspots = extractValue(from: xml, tag: "sunspots").flatMap { Int($0) }
        let bandConditions = extractBandConditions(from: xml)

        return SolarData(
            kIndex: kIndex, aIndex: aIndex, solarFlux: solarFlux,
            sunspots: sunspots, bandConditions: bandConditions, timestamp: Date()
        )
    }

    // MARK: Private

    private static let hamQSLURL = "https://www.hamqsl.com/solarxml.php"

    private static func extractValue(from xml: String, tag: String) -> String? {
        let pattern = "<\(tag)>([^<]*)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(
                  in: xml, options: [],
                  range: NSRange(xml.startIndex..., in: xml)
              ),
              let range = Range(match.range(at: 1), in: xml)
        else {
            return nil
        }
        return String(xml[range]).trimmingCharacters(in: .whitespaces)
    }

    private static func extractBandConditions(from xml: String) -> [String: BandCondition] {
        let pattern = #"<band\s+name="([^"]*)"\s+time="([^"]*)">([^<]*)</band>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [:]
        }

        var days: [String: String] = [:]
        var nights: [String: String] = [:]
        let range = NSRange(xml.startIndex..., in: xml)

        regex.enumerateMatches(in: xml, options: [], range: range) { match, _, _ in
            guard let result = match,
                  let nr = Range(result.range(at: 1), in: xml),
                  let tr = Range(result.range(at: 2), in: xml),
                  let cr = Range(result.range(at: 3), in: xml)
            else {
                return
            }
            let name = String(xml[nr])
            let cond = String(xml[cr]).trimmingCharacters(in: .whitespaces)
            if String(xml[tr]) == "day" {
                days[name] = cond
            } else {
                nights[name] = cond
            }
        }

        var result: [String: BandCondition] = [:]
        for name in Set(days.keys).union(nights.keys) {
            result[name] = BandCondition(
                day: days[name] ?? "N/A", night: nights[name] ?? "N/A"
            )
        }
        return result
    }
}

// MARK: - SolarEntry

struct SolarEntry: TimelineEntry {
    let date: Date
    let solar: SolarData?
    let band: SolarBand
}

// MARK: - SolarTimelineProvider

struct SolarTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> SolarEntry {
        SolarEntry(date: Date(), solar: .placeholder, band: .band30m20m)
    }

    func snapshot(
        for configuration: SolarWidgetIntent, in _: Context
    ) async -> SolarEntry {
        let solar = await SolarFetcher.fetch()
        return SolarEntry(date: Date(), solar: solar ?? .placeholder, band: configuration.band)
    }

    func timeline(
        for configuration: SolarWidgetIntent, in _: Context
    ) async -> Timeline<SolarEntry> {
        let solar = await SolarFetcher.fetch()
        let entry = SolarEntry(date: Date(), solar: solar, band: configuration.band)
        let nextUpdate = Date().addingTimeInterval(30 * 60)
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}

// MARK: - SolarWidgetSmallView

struct SolarWidgetSmallView: View {
    // MARK: Internal

    let solar: SolarData?
    let band: SolarBand

    var body: some View {
        if let solar {
            VStack(spacing: 4) {
                headerRow(solar)
                kaRow(solar)
                sfiBandRow(solar)
                Spacer(minLength: 0)
            }
            .padding(4)
        } else {
            noDataView
        }
    }

    // MARK: Private

    private var noDataView: some View {
        VStack(spacing: 8) {
            Image(systemName: "sun.max.trianglebadge.exclamationmark")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No Data")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func headerRow(_ solar: SolarData) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "sun.max.fill")
                .font(.caption)
                .foregroundStyle(.yellow)
            Text("Solar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if let condition = solar.bandConditions[band.rawValue] {
                Text(condition.day)
                    .font(.caption.weight(.semibold))
            }
        }
    }

    private func kaRow(_ solar: SolarData) -> some View {
        HStack(spacing: 8) {
            halfMetric(
                label: "K", value: String(format: "%.0f", solar.kIndex),
                gauge: .kIndex(solar.kIndex)
            )
            if let aIdx = solar.aIndex {
                halfMetric(
                    label: "A", value: "\(aIdx)",
                    gauge: .aIndex(aIdx)
                )
            }
        }
    }

    private func halfMetric(
        label: String, value: String,
        gauge: WidgetSegmentGauge.Metric
    ) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.caption.weight(.bold).monospacedDigit())
            }
            WidgetSegmentGauge(metric: gauge)
        }
    }

    private func sfiBandRow(_ solar: SolarData) -> some View {
        HStack(spacing: 8) {
            if let sfi = solar.solarFlux {
                VStack(spacing: 2) {
                    HStack {
                        Text("SFI")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(sfi))")
                            .font(.caption.weight(.bold).monospacedDigit())
                    }
                    WidgetSegmentGauge(metric: .sfi(sfi))
                }
            }
            if let condition = solar.bandConditions[band.rawValue] {
                VStack(spacing: 2) {
                    HStack {
                        Text(band.rawValue)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    BandStoplightGauge(condition: condition.day)
                }
            }
        }
    }
}

// MARK: - SolarWidgetAccessoryCircularView

struct SolarWidgetAccessoryCircularView: View {
    let solar: SolarData?

    var body: some View {
        if let solar {
            Gauge(value: min(solar.kIndex, 9), in: 0 ... 9) {
                Text("K")
            } currentValueLabel: {
                Text(String(format: "%.0f", solar.kIndex))
                    .font(.system(.title3, design: .rounded, weight: .heavy))
            }
            .gaugeStyle(.accessoryCircular)
        } else {
            Image(systemName: "sun.max.fill")
                .font(.title3)
        }
    }
}

// MARK: - SolarWidgetAccessoryRectangularView

struct SolarWidgetAccessoryRectangularView: View {
    let solar: SolarData?
    let band: SolarBand

    var body: some View {
        if let solar {
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text("Solar")
                        .fontWeight(.bold)
                    Spacer()
                    Text(solar.propagationRating)
                        .fontWeight(.semibold)
                }
                .font(.headline)

                HStack {
                    Text("K \(String(format: "%.0f", solar.kIndex))")
                        .fontWeight(.bold)
                    if let aIdx = solar.aIndex {
                        Text("A \(aIdx)")
                            .fontWeight(.bold)
                    }
                    Spacer()
                    if let sfi = solar.solarFlux {
                        Text("SFI \(Int(sfi))")
                            .fontWeight(.bold)
                    }
                }
                .font(.caption.monospacedDigit())

                HStack {
                    Text(band.rawValue)
                        .fontWeight(.semibold)
                    Spacer()
                    if let cond = solar.bandConditions[band.rawValue] {
                        Text("\(cond.day) / \(cond.night)")
                            .fontWeight(.semibold)
                    }
                }
                .font(.caption)
            }
        } else {
            Text("Solar: --")
                .font(.caption.weight(.semibold))
        }
    }
}

// MARK: - SolarWidgetAccessoryInlineView

struct SolarWidgetAccessoryInlineView: View {
    let solar: SolarData?
    let band: SolarBand

    var body: some View {
        if let solar {
            let k = String(format: "%.0f", solar.kIndex)
            if let cond = solar.bandConditions[band.rawValue] {
                Text("\u{2600} K \(k) \u{00B7} \(band.rawValue) \(cond.day)")
            } else if let sfi = solar.solarFlux {
                Text("\u{2600} K \(k) \u{00B7} SFI \(Int(sfi))")
            } else {
                Text("\u{2600} K \(k) \u{00B7} \(solar.propagationRating)")
            }
        } else {
            Text("\u{2600} Solar: --")
        }
    }
}

// MARK: - SolarWidgetEntryView

struct SolarWidgetEntryView: View {
    @Environment(\.widgetFamily) var widgetFamily

    let entry: SolarEntry

    var body: some View {
        switch widgetFamily {
        case .accessoryCircular:
            SolarWidgetAccessoryCircularView(solar: entry.solar)
        case .accessoryRectangular:
            SolarWidgetAccessoryRectangularView(solar: entry.solar, band: entry.band)
        case .accessoryInline:
            SolarWidgetAccessoryInlineView(solar: entry.solar, band: entry.band)
        default:
            SolarWidgetSmallView(solar: entry.solar, band: entry.band)
        }
    }
}

// MARK: - SolarWidget

struct SolarWidget: Widget {
    let kind = "SolarWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind, intent: SolarWidgetIntent.self,
            provider: SolarTimelineProvider()
        ) { entry in
            SolarWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Solar Conditions")
        .description("Current K-index, SFI, and propagation rating.")
        .supportedFamilies([
            .systemSmall, .accessoryCircular,
            .accessoryRectangular, .accessoryInline,
        ])
    }
}
