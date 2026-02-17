import AppIntents
import SwiftUI
import WidgetKit

// MARK: - SpotSourceFilter

enum SpotSourceFilter: String, CaseIterable, AppEnum {
    case both
    case pota
    case rbn

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Source")

    static var caseDisplayRepresentations: [SpotSourceFilter: DisplayRepresentation] {
        [
            .both: "POTA + RBN",
            .pota: "POTA Only",
            .rbn: "RBN Only",
        ]
    }
}

// MARK: - WidgetSpot

/// Lightweight spot model for widget display
struct WidgetSpot: Identifiable, Sendable {
    enum Source: Sendable { case pota, rbn }

    let id: String
    let callsign: String
    let frequencyKHz: Double
    let mode: String
    let timestamp: Date
    let source: Source
    let parkRef: String?
    let snr: Int?

    var frequencyDisplay: String {
        String(format: "%.1f", frequencyKHz)
    }

    var timeAgo: String {
        let seconds = Date().timeIntervalSince(timestamp)
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3_600 { return "\(Int(seconds / 60))m" }
        return "\(Int(seconds / 3_600))h"
    }

    var ageColor: Color {
        let seconds = Date().timeIntervalSince(timestamp)
        switch seconds {
        case ..<120: return .green
        case ..<600: return .blue
        case ..<1_800: return .orange
        default: return .secondary
        }
    }

    var sourceLabel: String {
        switch source {
        case .pota: parkRef ?? "POTA"
        case .rbn: snr.map { "\($0) dB" } ?? "RBN"
        }
    }
}

// MARK: - SpotsFetcher

/// Fetches POTA and RBN spots directly from public APIs
enum SpotsFetcher {
    private static let potaSpotsURL = "https://api.pota.app/spot/activator"
    private static let rbnBaseURL = "https://vailrerbn.com/api/v1"

    static func fetch(source: SpotSourceFilter) async -> [WidgetSpot] {
        var spots: [WidgetSpot] = []

        if source == .both || source == .pota {
            if let pota = await fetchPOTASpots() {
                spots.append(contentsOf: pota)
            }
        }

        if source == .both || source == .rbn {
            if let rbn = await fetchRBNSpots() {
                spots.append(contentsOf: rbn)
            }
        }

        return spots
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(10)
            .map { $0 }
    }

    private static func fetchPOTASpots() async -> [WidgetSpot]? {
        guard let url = URL(string: potaSpotsURL) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200
        else {
            return nil
        }

        struct POTASpotDTO: Decodable {
            let spotId: Int64
            let activator: String
            let frequency: String
            let mode: String
            let reference: String
            let parkName: String?
            let spotTime: String
        }

        guard let dtos = try? JSONDecoder().decode([POTASpotDTO].self, from: data) else {
            return nil
        }

        let cutoff = Date().addingTimeInterval(-30 * 60)
        return dtos.compactMap { dto in
            guard let freqKHz = Double(dto.frequency) else { return nil }
            let timestamp = parseSpotTime(dto.spotTime) ?? Date()
            guard timestamp > cutoff else { return nil }
            return WidgetSpot(
                id: "pota-\(dto.spotId)", callsign: dto.activator,
                frequencyKHz: freqKHz, mode: dto.mode,
                timestamp: timestamp, source: .pota,
                parkRef: dto.reference, snr: nil
            )
        }
    }

    private static func fetchRBNSpots() async -> [WidgetSpot]? {
        guard let url = URL(string: "\(rbnBaseURL)/spots?limit=20") else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200
        else {
            return nil
        }

        struct RBNResponseDTO: Decodable {
            let spots: [RBNSpotDTO]
        }

        struct RBNSpotDTO: Decodable {
            let id: Int
            let callsign: String
            let frequency: Double
            let mode: String
            let timestamp: Date
            let snr: Int
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Try wrapped response first, then bare array
        let spots: [RBNSpotDTO]
        if let wrapped = try? decoder.decode(RBNResponseDTO.self, from: data) {
            spots = wrapped.spots
        } else if let bare = try? decoder.decode([RBNSpotDTO].self, from: data) {
            spots = bare
        } else {
            return nil
        }

        return spots.map { dto in
            WidgetSpot(
                id: "rbn-\(dto.id)", callsign: dto.callsign,
                frequencyKHz: dto.frequency, mode: dto.mode,
                timestamp: dto.timestamp, source: .rbn,
                parkRef: nil, snr: dto.snr
            )
        }
    }

    private static func parseSpotTime(_ spotTime: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: spotTime) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: spotTime) { return date }
        // POTA sometimes omits Z suffix
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: spotTime)
    }
}

// MARK: - SpotsWidgetIntent

struct SpotsWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Spots Widget"
    static var description: IntentDescription = "Show live POTA and RBN spots."

    @Parameter(title: "Source", default: .both)
    var source: SpotSourceFilter
}

// MARK: - SpotsEntry

struct SpotsEntry: TimelineEntry {
    let date: Date
    let spots: [WidgetSpot]
    let source: SpotSourceFilter
}

// MARK: - SpotsTimelineProvider

struct SpotsTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> SpotsEntry {
        SpotsEntry(date: Date(), spots: [], source: .both)
    }

    func snapshot(
        for configuration: SpotsWidgetIntent, in _: Context
    ) async -> SpotsEntry {
        let spots = await SpotsFetcher.fetch(source: configuration.source)
        return SpotsEntry(date: Date(), spots: spots, source: configuration.source)
    }

    func timeline(
        for configuration: SpotsWidgetIntent, in _: Context
    ) async -> Timeline<SpotsEntry> {
        let spots = await SpotsFetcher.fetch(source: configuration.source)
        let entry = SpotsEntry(date: Date(), spots: spots, source: configuration.source)
        // Refresh every 15 minutes
        let nextUpdate = Date().addingTimeInterval(15 * 60)
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}

// MARK: - SpotsWidgetMediumView

struct SpotsWidgetMediumView: View {
    let entry: SpotsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text("Spots")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(sourceLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if entry.spots.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("No active spots")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                ForEach(entry.spots.prefix(4)) { spot in
                    spotRow(spot)
                }
                Spacer(minLength: 0)
            }
        }
        .padding()
    }

    private var sourceLabel: String {
        switch entry.source {
        case .both: "POTA + RBN"
        case .pota: "POTA"
        case .rbn: "RBN"
        }
    }

    private func spotRow(_ spot: WidgetSpot) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(spot.ageColor)
                .frame(width: 6, height: 6)

            Text(spot.callsign)
                .font(.caption.weight(.semibold).monospaced())
                .lineLimit(1)

            Text(spot.frequencyDisplay)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)

            Spacer()

            Text(spot.sourceLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(spot.timeAgo)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - SpotsWidgetLargeView

struct SpotsWidgetLargeView: View {
    let entry: SpotsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.subheadline)
                    .foregroundStyle(.blue)
                Text("Spots")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(sourceLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 4)

            if entry.spots.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No active spots")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                ForEach(entry.spots.prefix(8)) { spot in
                    spotRow(spot)
                    if spot.id != entry.spots.prefix(8).last?.id {
                        Divider()
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding()
    }

    private var sourceLabel: String {
        switch entry.source {
        case .both: "POTA + RBN"
        case .pota: "POTA"
        case .rbn: "RBN"
        }
    }

    private func spotRow(_ spot: WidgetSpot) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(spot.ageColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(spot.callsign)
                    .font(.subheadline.weight(.semibold).monospaced())
                    .lineLimit(1)
                Text("\(spot.frequencyDisplay) kHz  \(spot.mode)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(spot.sourceLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(spot.timeAgo)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
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
        .description("Live POTA activator and RBN spots.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Preview

private extension SpotsEntry {
    var widgetFamily: WidgetFamily {
        .systemMedium
    }
}
