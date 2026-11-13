// Weather Radar Service
//
// Fetches active NWS alerts and provides the tile URL template for the
// NEXRAD CONUS base-reflectivity radar layer hosted by Iowa State's
// mesonet (free, no API key, OpenStreetMap-style {z}/{x}/{y}).
//
// US only — NWS and NEXRAD don't cover anywhere else.

import CarrierWaveData
import CoreLocation
import Foundation

// MARK: - NWSAlertSeverity

nonisolated enum NWSAlertSeverity: String {
    case extreme = "Extreme"
    case severe = "Severe"
    case moderate = "Moderate"
    case minor = "Minor"
    case unknown = "Unknown"

    // MARK: Lifecycle

    init(raw: String?) {
        self = NWSAlertSeverity(rawValue: raw ?? "") ?? .unknown
    }

    // MARK: Internal

    /// Priority for sorting (higher = more severe).
    var priority: Int {
        switch self {
        case .extreme: 4
        case .severe: 3
        case .moderate: 2
        case .minor: 1
        case .unknown: 0
        }
    }
}

// MARK: - NWSAlert

nonisolated struct NWSAlert: Identifiable {
    let id: String
    let event: String
    let headline: String?
    let severity: NWSAlertSeverity
    let areaDescription: String?
    let sent: Date?
    let expires: Date?
}

// MARK: - WeatherRadarServiceError

nonisolated enum WeatherRadarServiceError: Error, LocalizedError {
    case invalidURL
    case invalidResponse(String)
    case parsingError(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid API URL"
        case let .invalidResponse(msg): "Invalid response: \(msg)"
        case let .parsingError(msg): "Failed to parse response: \(msg)"
        }
    }
}

// MARK: - WeatherRadarService

actor WeatherRadarService {
    // MARK: Lifecycle

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }

    // MARK: Internal

    /// NEXRAD CONUS base-reflectivity tile template (XYZ / WebMercator).
    /// Source: Iowa Environmental Mesonet — refreshes every ~5 minutes.
    static let radarTileURLTemplate =
        "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913/{z}/{x}/{y}.png"

    /// Attribution string shown over the radar map.
    static let radarAttribution = "Radar: NOAA NEXRAD via Iowa State Mesonet"

    /// Fetch active NWS alerts for a coordinate. Returns alerts sorted by severity (most
    /// severe first). US points only; outside the US the API returns an empty list.
    func fetchAlerts(latitude: Double, longitude: Double) async throws -> [NWSAlert] {
        let cacheKey = "\(Int(latitude * 10))_\(Int(longitude * 10))"
        if let cached = cachedAlerts[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < 120
        {
            return cached.alerts
        }

        let lat = String(format: "%.4f", latitude)
        let lon = String(format: "%.4f", longitude)
        guard let url = URL(string: "\(alertsBaseURL)?point=\(lat),\(lon)") else {
            throw WeatherRadarServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("CarrierWave/1.0 (radar)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw WeatherRadarServiceError.invalidResponse("HTTP \(code)")
        }

        let alerts = try parseAlerts(data)
        let sorted = alerts.sorted { $0.severity.priority > $1.severity.priority }
        cachedAlerts[cacheKey] = (sorted, Date())
        return sorted
    }

    // MARK: Private

    private let alertsBaseURL = "https://api.weather.gov/alerts/active"
    private let session: URLSession

    private var cachedAlerts: [String: (alerts: [NWSAlert], timestamp: Date)] = [:]

    private func parseAlerts(_ data: Data) throws -> [NWSAlert] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]]
        else {
            throw WeatherRadarServiceError.parsingError("Missing features array")
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFraction = ISO8601DateFormatter()
        isoNoFraction.formatOptions = [.withInternetDateTime]

        func parseDate(_ raw: String?) -> Date? {
            guard let raw, !raw.isEmpty else {
                return nil
            }
            return iso.date(from: raw) ?? isoNoFraction.date(from: raw)
        }

        return features.compactMap { feature -> NWSAlert? in
            guard let props = feature["properties"] as? [String: Any] else {
                return nil
            }
            let id = (feature["id"] as? String)
                ?? (props["id"] as? String)
                ?? UUID().uuidString
            guard let event = props["event"] as? String else {
                return nil
            }
            return NWSAlert(
                id: id,
                event: event,
                headline: props["headline"] as? String,
                severity: NWSAlertSeverity(raw: props["severity"] as? String),
                areaDescription: props["areaDesc"] as? String,
                sent: parseDate(props["sent"] as? String),
                expires: parseDate(props["expires"] as? String)
            )
        }
    }
}
