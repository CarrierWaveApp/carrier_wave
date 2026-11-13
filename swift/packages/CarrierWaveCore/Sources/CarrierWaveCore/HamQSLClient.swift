import Foundation

// MARK: - HamQSLError

public enum HamQSLError: Error, LocalizedError {
    case invalidResponse
    case httpError(Int)
    case parseError

    // MARK: Public

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid response from HamQSL"
        case let .httpError(code):
            "HamQSL returned HTTP \(code)"
        case .parseError:
            "Failed to parse HamQSL solar XML"
        }
    }
}

// MARK: - HamQSLBandCondition

/// Band condition for a specific band group (day and night).
public struct HamQSLBandCondition: Sendable {
    // MARK: Lifecycle

    public init(bandName: String, day: String, night: String) {
        self.bandName = bandName
        self.day = day
        self.night = night
    }

    // MARK: Public

    /// Band group name (e.g., "80m-40m", "30m-20m", "17m-15m", "12m-10m")
    public let bandName: String

    /// Daytime condition: "Good", "Fair", or "Poor"
    public let day: String

    /// Nighttime condition: "Good", "Fair", or "Poor"
    public let night: String
}

// MARK: - HamQSLSolarData

/// Structured solar conditions and band propagation from HamQSL.
public struct HamQSLSolarData: Sendable {
    // MARK: Lifecycle

    public init(
        kIndex: Double,
        aIndex: Int?,
        solarFlux: Double?,
        sunspots: Int?,
        bandConditions: [HamQSLBandCondition],
        timestamp: Date
    ) {
        self.kIndex = kIndex
        self.aIndex = aIndex
        self.solarFlux = solarFlux
        self.sunspots = sunspots
        self.bandConditions = bandConditions
        self.timestamp = timestamp
    }

    // MARK: Public

    public let kIndex: Double
    public let aIndex: Int?
    public let solarFlux: Double?
    public let sunspots: Int?
    public let bandConditions: [HamQSLBandCondition]
    public let timestamp: Date

    /// Overall propagation rating based on K-index.
    nonisolated public var propagationRating: String {
        switch kIndex {
        case ..<2: "Excellent"
        case ..<3: "Good"
        case ..<4: "Fair"
        case ..<5: "Poor"
        default: "Very Poor"
        }
    }

    /// Convert HamQSL grouped band conditions into per-band `BandPropagation`.
    ///
    /// Expands groups like "80m-40m" into individual bands, selects day or
    /// night condition based on `utcHour`, and maps the text rating to
    /// `PropagationQuality`. Bands not covered by HamQSL (160m, 60m) fall
    /// back to `PropagationEstimator`.
    nonisolated public func bandPropagation(utcHour: Int) -> [BandPropagation] {
        let isDaytime = utcHour >= 6 && utcHour <= 20

        // Map each HamQSL group to its individual bands
        let groupExpansion: [String: [String]] = [
            "80m-40m": ["80m", "40m"],
            "30m-20m": ["30m", "20m"],
            "17m-15m": ["17m", "15m"],
            "12m-10m": ["12m", "10m"],
        ]

        // Build lookup: individual band → quality
        var bandQuality: [String: PropagationQuality] = [:]
        for condition in bandConditions {
            let rating = isDaytime ? condition.day : condition.night
            let quality = Self.parseQuality(rating)
            if let bands = groupExpansion[condition.bandName] {
                for band in bands {
                    bandQuality[band] = quality
                }
            }
        }

        // Ordered list of all HF bands
        let allBands = [
            "160m", "80m", "60m", "40m", "30m",
            "20m", "17m", "15m", "12m", "10m",
        ]

        // For uncovered bands (160m, 60m), use PropagationEstimator
        var estimatorResults: [String: BandPropagation] = [:]
        if let sfi = solarFlux {
            for bp in PropagationEstimator.estimate(
                sfi: sfi, kIndex: kIndex, utcHour: utcHour
            ) {
                estimatorResults[bp.band] = bp
            }
        }

        return allBands.compactMap { band in
            if let quality = bandQuality[band] {
                return BandPropagation(
                    band: band, quality: quality, mufEstimateMHz: nil
                )
            } else if let fallback = estimatorResults[band] {
                return fallback
            }
            return nil
        }
    }

    // MARK: Private

    private static func parseQuality(_ rating: String) -> PropagationQuality {
        switch rating.lowercased() {
        case "good": .good
        case "fair": .fair
        case "poor": .poor
        default: .closed
        }
    }
}

// MARK: - HamQSLClient

/// Client for the HamQSL solar XML API.
/// Provides structured solar indices and per-band propagation conditions.
public actor HamQSLClient {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    /// Fetch current solar conditions and band propagation.
    /// Caches results for 15 minutes to avoid excessive requests.
    public func fetchSolarData() async throws -> HamQSLSolarData {
        // Return cached data if fresh
        if let cached = cachedData,
           Date().timeIntervalSince(cached.timestamp) < cacheInterval
        {
            return cached
        }

        guard let url = URL(string: apiURL) else {
            throw HamQSLError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("CarrierWave/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw HamQSLError.invalidResponse
        }

        guard http.statusCode == 200 else {
            throw HamQSLError.httpError(http.statusCode)
        }

        guard let xml = String(data: data, encoding: .utf8) else {
            throw HamQSLError.parseError
        }

        let result = parse(xml: xml)
        cachedData = result
        return result
    }

    // MARK: Private

    private let apiURL = "https://www.hamqsl.com/solarxml.php"

    /// Cache interval: 15 minutes
    private let cacheInterval: TimeInterval = 900

    private var cachedData: HamQSLSolarData?

    private func parse(xml: String) -> HamQSLSolarData {
        let kIndex = extractValue(from: xml, tag: "kindex").flatMap { Double($0) } ?? 0
        let aIndex = extractValue(from: xml, tag: "aindex").flatMap { Int($0) }
        let solarFlux = extractValue(from: xml, tag: "solarflux").flatMap { Double($0) }
        let sunspots = extractValue(from: xml, tag: "sunspots").flatMap { Int($0) }
        let bandConditions = extractBandConditions(from: xml)

        return HamQSLSolarData(
            kIndex: kIndex,
            aIndex: aIndex,
            solarFlux: solarFlux,
            sunspots: sunspots,
            bandConditions: bandConditions,
            timestamp: Date()
        )
    }

    private func extractValue(from xml: String, tag: String) -> String? {
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

    private func extractBandConditions(from xml: String) -> [HamQSLBandCondition] {
        let pattern = #"<band\s+name="([^"]*)"\s+time="([^"]*)">([^<]*)</band>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        var days: [String: String] = [:]
        var nights: [String: String] = [:]
        let range = NSRange(xml.startIndex..., in: xml)

        regex.enumerateMatches(in: xml, options: [], range: range) { match, _, _ in
            guard let result = match,
                  let nameRange = Range(result.range(at: 1), in: xml),
                  let timeRange = Range(result.range(at: 2), in: xml),
                  let condRange = Range(result.range(at: 3), in: xml)
            else {
                return
            }
            let name = String(xml[nameRange])
            let cond = String(xml[condRange]).trimmingCharacters(in: .whitespaces)
            if String(xml[timeRange]) == "day" {
                days[name] = cond
            } else {
                nights[name] = cond
            }
        }

        // Build in standard band order
        let bandOrder = ["80m-40m", "30m-20m", "17m-15m", "12m-10m"]
        let allNames = Set(days.keys).union(nights.keys)

        var conditions: [HamQSLBandCondition] = []
        for name in bandOrder where allNames.contains(name) {
            conditions.append(HamQSLBandCondition(
                bandName: name,
                day: days[name] ?? "N/A",
                night: nights[name] ?? "N/A"
            ))
        }
        // Add any unexpected bands not in standard order
        for name in allNames.sorted() where !bandOrder.contains(name) {
            conditions.append(HamQSLBandCondition(
                bandName: name,
                day: days[name] ?? "N/A",
                night: nights[name] ?? "N/A"
            ))
        }
        return conditions
    }
}
