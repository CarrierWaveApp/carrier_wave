import SwiftUI
import WidgetKit

// MARK: - SolarData

/// Lightweight solar conditions fetched directly by the widget
struct SolarData: Sendable {
    static let placeholder = SolarData(
        kIndex: 2.0, aIndex: 5, solarFlux: 150, sunspots: 80, timestamp: Date()
    )

    let kIndex: Double
    let aIndex: Int?
    let solarFlux: Double?
    let sunspots: Int?
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

    var propagationColor: Color {
        switch kIndex {
        case 0 ..< 2: .green
        case 2 ..< 3: .blue
        case 3 ..< 4: .yellow
        case 4 ..< 5: .orange
        default: .red
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

        return SolarData(
            kIndex: kIndex, aIndex: aIndex, solarFlux: solarFlux,
            sunspots: sunspots, timestamp: Date()
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
}

// MARK: - SolarEntry

struct SolarEntry: TimelineEntry {
    let date: Date
    let solar: SolarData?
}

// MARK: - SolarTimelineProvider

struct SolarTimelineProvider: TimelineProvider {
    func placeholder(in _: Context) -> SolarEntry {
        SolarEntry(date: Date(), solar: .placeholder)
    }

    func getSnapshot(in _: Context, completion: @escaping (SolarEntry) -> Void) {
        Task {
            let solar = await SolarFetcher.fetch()
            completion(SolarEntry(date: Date(), solar: solar ?? .placeholder))
        }
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<SolarEntry>) -> Void) {
        Task {
            let solar = await SolarFetcher.fetch()
            let entry = SolarEntry(date: Date(), solar: solar)
            // Refresh every 30 minutes
            let nextUpdate = Date().addingTimeInterval(30 * 60)
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }
}

// MARK: - SolarWidgetSmallView

struct SolarWidgetSmallView: View {
    // MARK: Internal

    let solar: SolarData?

    var body: some View {
        if let solar {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "sun.max.fill")
                        .font(.caption)
                        .foregroundStyle(solar.propagationColor)
                    Text("Solar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 8) {
                    metricRow("K", value: String(format: "%.0f", solar.kIndex),
                              color: solar.propagationColor)
                    if let sfi = solar.solarFlux {
                        metricRow("SFI", value: "\(Int(sfi))", color: .blue)
                    }
                    if let aIdx = solar.aIndex {
                        metricRow("A", value: "\(aIdx)", color: .blue)
                    }
                }

                Spacer(minLength: 0)

                Text(solar.propagationRating)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(solar.propagationColor)
            }
            .padding()
        } else {
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
    }

    // MARK: Private

    private func metricRow(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)
            Spacer()
            Text(value)
                .font(.title3.weight(.bold).monospaced())
                .foregroundStyle(color)
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
                    .font(.title3.weight(.bold))
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

    var body: some View {
        if let solar {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Solar")
                        .font(.caption2.weight(.semibold))
                    Text(solar.propagationRating)
                        .font(.caption2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("K \(String(format: "%.0f", solar.kIndex))")
                        .font(.caption.weight(.bold).monospaced())
                    if let sfi = solar.solarFlux {
                        Text("SFI \(Int(sfi))")
                            .font(.caption2.monospaced())
                    }
                }
            }
        } else {
            Text("Solar: --")
                .font(.caption)
        }
    }
}

// MARK: - SolarWidget

struct SolarWidget: Widget {
    let kind = "SolarWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SolarTimelineProvider()) { entry in
            Group {
                switch entry.widgetFamily {
                case .accessoryCircular:
                    SolarWidgetAccessoryCircularView(solar: entry.solar)
                case .accessoryRectangular:
                    SolarWidgetAccessoryRectangularView(solar: entry.solar)
                default:
                    SolarWidgetSmallView(solar: entry.solar)
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Solar Conditions")
        .description("Current K-index, SFI, and propagation rating.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Preview

private extension SolarEntry {
    var widgetFamily: WidgetFamily {
        // Default for preview
        .systemSmall
    }
}
