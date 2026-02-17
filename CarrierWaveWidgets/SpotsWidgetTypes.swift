import AppIntents
import SwiftUI

// MARK: - SpotSourceFilter

enum SpotSourceFilter: String, CaseIterable, AppEnum {
    case both
    case pota
    case rbn

    // MARK: Internal

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Source")

    static var caseDisplayRepresentations: [SpotSourceFilter: DisplayRepresentation] {
        [
            .both: "POTA + RBN",
            .pota: "POTA Only",
            .rbn: "RBN Only",
        ]
    }
}

// MARK: - SpotBandFilter

enum SpotBandFilter: String, CaseIterable, AppEnum {
    case band160m
    case band80m
    case band40m
    case band30m
    case band20m
    case band17m
    case band15m
    case band12m
    case band10m
    case band6m
    case band2m

    // MARK: Internal

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Band")

    static var caseDisplayRepresentations: [SpotBandFilter: DisplayRepresentation] {
        [
            .band160m: "160m", .band80m: "80m", .band40m: "40m",
            .band30m: "30m", .band20m: "20m", .band17m: "17m",
            .band15m: "15m", .band12m: "12m", .band10m: "10m",
            .band6m: "6m", .band2m: "2m",
        ]
    }

    /// Frequency range in kHz for this band (min, max)
    var frequencyRange: (Double, Double) {
        switch self {
        case .band160m: (1_800, 2_000)
        case .band80m: (3_500, 4_000)
        case .band40m: (7_000, 7_300)
        case .band30m: (10_100, 10_150)
        case .band20m: (14_000, 14_350)
        case .band17m: (18_068, 18_168)
        case .band15m: (21_000, 21_450)
        case .band12m: (24_890, 24_990)
        case .band10m: (28_000, 29_700)
        case .band6m: (50_000, 54_000)
        case .band2m: (144_000, 148_000)
        }
    }

    /// Short label for header badges
    var shortLabel: String {
        switch self {
        case .band160m: "160m"
        case .band80m: "80m"
        case .band40m: "40m"
        case .band30m: "30m"
        case .band20m: "20m"
        case .band17m: "17m"
        case .band15m: "15m"
        case .band12m: "12m"
        case .band10m: "10m"
        case .band6m: "6m"
        case .band2m: "2m"
        }
    }

    func matches(_ frequencyKHz: Double) -> Bool {
        let (min, max) = frequencyRange
        return frequencyKHz >= min && frequencyKHz < max
    }
}

// MARK: - SpotModeFilter

enum SpotModeFilter: String, CaseIterable, AppEnum {
    case cw
    case ssb
    case ft8
    case ft4
    case digital

    // MARK: Internal

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Mode")

    static var caseDisplayRepresentations: [SpotModeFilter: DisplayRepresentation] {
        [
            .cw: "CW", .ssb: "SSB", .ft8: "FT8",
            .ft4: "FT4", .digital: "Digital",
        ]
    }

    var shortLabel: String {
        switch self {
        case .cw: "CW"
        case .ssb: "SSB"
        case .ft8: "FT8"
        case .ft4: "FT4"
        case .digital: "Digital"
        }
    }

    func matches(_ mode: String) -> Bool {
        let upper = mode.uppercased()
        switch self {
        case .cw: return upper == "CW"
        case .ssb: return ["SSB", "USB", "LSB", "AM", "FM"].contains(upper)
        case .ft8: return upper == "FT8"
        case .ft4: return upper == "FT4"
        case .digital:
            return ["FT8", "FT4", "RTTY", "PSK31", "PSK", "JT65", "JT9", "DATA"]
                .contains(upper)
        }
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
        if seconds < 60 {
            return "\(Int(seconds))s"
        }
        if seconds < 3_600 {
            return "\(Int(seconds / 60))m"
        }
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
    // MARK: Internal

    /// Returns (displayed spots, total matching count)
    static func fetch(
        source: SpotSourceFilter,
        bands: [SpotBandFilter] = [],
        modes: [SpotModeFilter] = []
    ) async -> (spots: [WidgetSpot], totalCount: Int) {
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

        // Empty array = all (no filter)
        let filtered = spots.filter { spot in
            let bandMatch = bands.isEmpty || bands.contains { $0.matches(spot.frequencyKHz) }
            let modeMatch = modes.isEmpty || modes.contains { $0.matches(spot.mode) }
            return bandMatch && modeMatch
        }

        let sorted = filtered.sorted { $0.timestamp > $1.timestamp }
        return (spots: Array(sorted.prefix(10)), totalCount: sorted.count)
    }

    // MARK: Private

    private static let potaSpotsURL = "https://api.pota.app/spot/activator"
    private static let rbnBaseURL = "https://vailrerbn.com/api/v1"

    private static func fetchPOTASpots() async -> [WidgetSpot]? {
        guard let url = URL(string: potaSpotsURL) else {
            return nil
        }

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
            guard let freqKHz = Double(dto.frequency) else {
                return nil
            }
            let timestamp = parseSpotTime(dto.spotTime) ?? Date()
            guard timestamp > cutoff else {
                return nil
            }
            return WidgetSpot(
                id: "pota-\(dto.spotId)", callsign: dto.activator,
                frequencyKHz: freqKHz, mode: dto.mode,
                timestamp: timestamp, source: .pota,
                parkRef: dto.reference, snr: nil
            )
        }
    }

    private static func fetchRBNSpots() async -> [WidgetSpot]? {
        guard let url = URL(string: "\(rbnBaseURL)/spots?limit=20") else {
            return nil
        }

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
        if let date = formatter.date(from: spotTime) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: spotTime) {
            return date
        }
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: spotTime)
    }
}
