import Foundation

// MARK: - WatchNetworkService

/// Lightweight network fetchers for Watch-side solar and spots data.
/// Falls back to App Group data if network requests fail.
enum WatchNetworkService {
    // MARK: Internal

    // MARK: - Solar

    /// Fetch solar conditions directly from HamQSL
    static func fetchSolar() async -> WatchSolarSnapshot? {
        guard let url = URL(string: "https://www.hamqsl.com/solarxml.php") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let xml = String(data: data, encoding: .utf8)
            else {
                return nil
            }
            return parseSolarXML(xml)
        } catch {
            return nil
        }
    }

    // MARK: - POTA Spots

    /// Fetch active POTA spots (public, no auth)
    static func fetchPOTASpots(limit: Int = 20) async -> [WatchSpot] {
        guard let url = URL(string: "https://api.pota.app/spot/activator") else {
            return []
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return []
            }
            let spots = try JSONDecoder().decode([POTASpotDTO].self, from: data)
            return Array(spots.compactMap { $0.toWatchSpot() }.prefix(limit))
        } catch {
            return []
        }
    }

    // MARK: Private

    private static func parseSolarXML(_ xml: String) -> WatchSolarSnapshot? {
        let kIndex = extractValue(from: xml, tag: "kindex").flatMap { Double($0) }
        let aIndex = extractValue(from: xml, tag: "aindex").flatMap { Int($0) }
        let solarFlux = extractValue(from: xml, tag: "solarflux").flatMap { Double($0) }
        let sunspots = extractValue(from: xml, tag: "sunspots").flatMap { Int($0) }

        guard kIndex != nil || solarFlux != nil else {
            return nil
        }

        let propagation: String? = kIndex.map { k in
            switch k {
            case ..<2: "Excellent"
            case ..<3: "Good"
            case ..<4: "Fair"
            case ..<5: "Poor"
            default: "Very Poor"
            }
        }

        return WatchSolarSnapshot(
            kIndex: kIndex,
            aIndex: aIndex,
            solarFlux: solarFlux,
            sunspots: sunspots,
            propagationRating: propagation,
            updatedAt: Date()
        )
    }

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

// MARK: - POTASpotDTO

/// Minimal DTO for POTA spot API response
private struct POTASpotDTO: Decodable {
    // MARK: Internal

    let activator: String
    let frequency: String
    let mode: String
    let reference: String
    let parkName: String?
    let spotTime: String
    let source: String?

    func toWatchSpot() -> WatchSpot? {
        guard let freqKHz = Double(frequency) else {
            return nil
        }
        let freqMHz = freqKHz / 1_000
        let band = Self.bandFromFrequency(freqMHz)
        let timestamp = Self.parseTimestamp(spotTime)

        return WatchSpot(
            id: "\(activator)-\(reference)-\(frequency)",
            callsign: activator,
            frequencyMHz: freqMHz,
            mode: mode,
            band: band,
            timestamp: timestamp ?? Date(),
            source: "pota",
            parkRef: reference,
            parkName: parkName,
            snr: nil
        )
    }

    // MARK: Private

    private static func bandFromFrequency(_ mhz: Double) -> String {
        switch mhz {
        case 1.8 ..< 2.0: "160m"
        case 3.5 ..< 4.0: "80m"
        case 5.3 ..< 5.5: "60m"
        case 7.0 ..< 7.3: "40m"
        case 10.1 ..< 10.15: "30m"
        case 14.0 ..< 14.35: "20m"
        case 18.068 ..< 18.168: "17m"
        case 21.0 ..< 21.45: "15m"
        case 24.89 ..< 24.99: "12m"
        case 28.0 ..< 29.7: "10m"
        case 50.0 ..< 54.0: "6m"
        case 144.0 ..< 148.0: "2m"
        case 420.0 ..< 450.0: "70cm"
        default: "\(Int(mhz))MHz"
        }
    }

    private static func parseTimestamp(_ spotTime: String) -> Date? {
        let formatter = ISO8601DateFormatter()

        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: spotTime) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: spotTime) {
            return date
        }

        // POTA timestamps lack Z suffix but are UTC
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        if let date = formatter.date(from: spotTime) {
            return date
        }

        formatter.formatOptions = [
            .withFullDate, .withTime, .withColonSeparatorInTime, .withFractionalSeconds,
        ]
        return formatter.date(from: spotTime)
    }
}
