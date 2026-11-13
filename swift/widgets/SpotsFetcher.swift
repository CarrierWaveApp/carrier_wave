import Foundation

// MARK: - SpotsFetcher

/// Fetches POTA, SOTA, and RBN spots directly from public APIs
enum SpotsFetcher {
    // MARK: Internal

    /// Returns (displayed spots, total matching count)
    static func fetch(
        source: SpotSourceFilter,
        bands: [SpotBandFilter] = [],
        modes: [SpotModeFilter] = []
    ) async -> (spots: [WidgetSpot], totalCount: Int) {
        var spots: [WidgetSpot] = []

        if source == .both || source == .pota, let pota = await fetchPOTASpots() {
            spots.append(contentsOf: pota)
        }

        if source == .both || source == .sota, let sota = await fetchSOTASpots() {
            spots.append(contentsOf: sota)
        }

        if source == .both || source == .rbn, let rbn = await fetchRBNSpots() {
            spots.append(contentsOf: rbn)
        }

        let deduped = deduplicateByCallsign(spots)

        let filtered = deduped.filter { spot in
            let bandMatch = bands.isEmpty || bands.contains { $0.matches(spot.frequencyKHz) }
            let modeMatch = modes.isEmpty || modes.contains { $0.matches(spot.mode) }
            return bandMatch && modeMatch
        }

        let sorted = filtered.sorted { $0.timestamp > $1.timestamp }
        return (spots: Array(sorted.prefix(10)), totalCount: sorted.count)
    }

    // MARK: Private

    private static let potaSpotsURL = "https://api.pota.app/spot/activator"
    private static let rbnBaseURL = "https://activities.carrierwave.app/v1/rbn"
    private static let sotaBaseURL = "https://api2.sota.org.uk/api"

    // MARK: - SOTA

    /// SOTA kill-switch: the SOTAwatch v2 API shuts down 2026-08-31 and its
    /// replacement requires prior approval before use. Remove once the
    /// migration to the new API lands.
    private static let sotaTemporarilyDisabled = true

    /// Groups spots by callsign, keeping the most recent and averaging SNR/WPM
    private static func deduplicateByCallsign(_ spots: [WidgetSpot]) -> [WidgetSpot] {
        let grouped = Dictionary(grouping: spots) { $0.callsign.uppercased() }
        return grouped.values.compactMap { group in
            guard let newest = group.max(by: { $0.timestamp < $1.timestamp }) else {
                return nil
            }
            guard group.count > 1 else {
                return newest
            }
            let avgSNR = averageValue(group.compactMap(\.snr))
            let avgWPM = averageValue(group.compactMap(\.wpm))
            return WidgetSpot(
                id: newest.id, callsign: newest.callsign,
                frequencyKHz: newest.frequencyKHz, mode: newest.mode,
                timestamp: newest.timestamp, source: newest.source,
                parkRef: newest.parkRef, parkName: newest.parkName,
                summitRef: newest.summitRef, summitName: newest.summitName,
                snr: avgSNR ?? newest.snr, wpm: avgWPM ?? newest.wpm
            )
        }
    }

    private static func averageValue(_ values: [Int]) -> Int? {
        guard !values.isEmpty else {
            return nil
        }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }

    // MARK: - POTA

    private static func fetchPOTASpots() async -> [WidgetSpot]? {
        guard let data = await fetchData(from: potaSpotsURL) else {
            return nil
        }

        struct POTASpotDTO: Decodable {
            let spotId: Int64
            let activator: String
            let frequency: String
            let mode: String
            let reference: String
            let parkName: String?
            /// The rebuilt POTA API (October 2026) leaves `parkName` null and
            /// carries the park name in `name`.
            let name: String?
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
                parkRef: dto.reference, parkName: dto.parkName ?? dto.name,
                summitRef: nil, summitName: nil,
                snr: nil, wpm: nil
            )
        }
    }

    private static func fetchSOTASpots() async -> [WidgetSpot]? {
        guard !sotaTemporarilyDisabled, let data = await fetchData(
            from: "\(sotaBaseURL)/spots/20/all",
            accept: "application/json"
        ), let dtos = try? JSONDecoder().decode([SOTASpotDTO].self, from: data) else {
            return nil
        }

        let cutoff = Date().addingTimeInterval(-30 * 60)
        return dtos.compactMap { mapSOTASpot($0, cutoff: cutoff) }
    }

    private static func mapSOTASpot(_ dto: SOTASpotDTO, cutoff: Date) -> WidgetSpot? {
        let freqKHz = (Double(dto.frequency) ?? 0) * 1_000
        guard freqKHz > 0 else {
            return nil
        }

        let timestamp = parseSpotTime(dto.timeStamp) ?? Date()
        guard timestamp > cutoff else {
            return nil
        }

        let summitRef = "\(dto.associationCode)/\(dto.summitCode)"
        let summitName = dto.summitDetails.components(separatedBy: ",")
            .first?.trimmingCharacters(in: .whitespaces)

        return WidgetSpot(
            id: "sota-\(dto.id)", callsign: dto.activatorCallsign,
            frequencyKHz: freqKHz, mode: dto.mode,
            timestamp: timestamp, source: .sota,
            parkRef: nil, parkName: nil,
            summitRef: summitRef, summitName: summitName,
            snr: nil, wpm: nil
        )
    }

    // MARK: - RBN

    private static func fetchRBNSpots() async -> [WidgetSpot]? {
        guard let data = await fetchData(from: "\(rbnBaseURL)/spots?limit=20") else {
            return nil
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
                parkRef: nil, parkName: nil,
                summitRef: nil, summitName: nil,
                snr: dto.snr, wpm: dto.wpm
            )
        }
    }

    // MARK: - Networking

    private static func fetchData(from urlString: String, accept: String? = nil) async -> Data? {
        guard let url = URL(string: urlString) else {
            return nil
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        if let accept {
            request.setValue(accept, forHTTPHeaderField: "Accept")
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200
        else {
            return nil
        }
        return data
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

// MARK: - SOTASpotDTO

private struct SOTASpotDTO: Decodable {
    enum CodingKeys: String, CodingKey {
        case id
        case activatorCallsign
        case associationCode
        case summitCode
        case summitDetails
        case frequency
        case mode
        case timeStamp
    }

    let id: Int
    let activatorCallsign: String
    let associationCode: String
    let summitCode: String
    let summitDetails: String
    let frequency: String
    let mode: String
    let timeStamp: String
}

// MARK: - RBNResponseDTO

private struct RBNResponseDTO: Decodable {
    let spots: [RBNSpotDTO]
}

// MARK: - RBNSpotDTO

private struct RBNSpotDTO: Decodable {
    let id: Int
    let callsign: String
    let frequency: Double
    let mode: String
    let timestamp: Date
    let snr: Int
    let wpm: Int?
}
