import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import Foundation

// MARK: - NOAAError

enum NOAAError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse(String)
    case noData
    case locationRequired
    case parsingError(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid API URL"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case let .invalidResponse(message):
            "Invalid response: \(message)"
        case .noData:
            "No data received"
        case .locationRequired:
            "Location is required for weather data"
        case let .parsingError(message):
            "Failed to parse response: \(message)"
        }
    }
}

// MARK: - SolarConditions

/// Solar conditions from NOAA SWPC
struct SolarConditions {
    let kIndex: Double
    let aIndex: Int?
    let solarFlux: Double?
    let sunspots: Int?
    let bandConditions: String?
    let timestamp: Date

    /// Propagation rating based on K-index
    var propagationRating: String {
        switch kIndex {
        case 0 ..< 2: "Excellent"
        case 2 ..< 3: "Good"
        case 3 ..< 4: "Fair"
        case 4 ..< 5: "Poor"
        default: "Very Poor"
        }
    }

    /// Color for the propagation rating
    var propagationColor: String {
        switch kIndex {
        case 0 ..< 2: "green"
        case 2 ..< 3: "blue"
        case 3 ..< 4: "yellow"
        case 4 ..< 5: "orange"
        default: "red"
        }
    }

    /// Description of conditions
    var description: String {
        var parts: [String] = []
        parts.append("K-index: \(String(format: "%.1f", kIndex))")
        if let flux = solarFlux {
            parts.append("SFI: \(Int(flux))")
        }
        if let spots = sunspots {
            parts.append("Sunspots: \(spots)")
        }
        return parts.joined(separator: " | ")
    }
}

// MARK: - WeatherConditions

/// Weather conditions from Open-Meteo
struct WeatherConditions {
    let temperature: Double // Fahrenheit
    let temperatureCelsius: Double
    let humidity: Int?
    let windSpeed: Double? // mph
    let windDirection: String?
    let description: String
    let icon: String?
    let timestamp: Date

    /// Formatted temperature string using user's unit preference
    var formattedTemperature: String {
        UnitFormatter.temperature(temperature)
    }

    /// Formatted wind string using user's unit preference
    var formattedWind: String? {
        guard let speed = windSpeed else {
            return nil
        }
        return UnitFormatter.windSpeed(speed, direction: windDirection)
    }
}

// MARK: - NOAAClient

/// Client for solar (HamQSL) and weather (Open-Meteo) APIs
actor NOAAClient {
    // MARK: Lifecycle

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }

    // MARK: Internal

    /// Fetch current solar conditions from HamQSL (N0NBH)
    func fetchSolarConditions() async throws -> SolarConditions {
        // Check cache first
        if let cached = cachedSolar, Date().timeIntervalSince(cachedSolarTime ?? .distantPast) < 300 {
            return cached
        }

        // Fetch from HamQSL
        guard let url = URL(string: hamQSLURL) else {
            throw NOAAError.invalidURL
        }

        let (data, response) = try await performRequest(url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw NOAAError.invalidResponse("Failed to fetch solar data from HamQSL")
        }

        // Parse XML response
        let conditions = try parseSolarXML(data)

        cachedSolar = conditions
        cachedSolarTime = Date()

        return conditions
    }

    /// Fetch weather for a location using Open-Meteo (worldwide coverage)
    func fetchWeather(latitude: Double, longitude: Double) async throws -> WeatherConditions {
        // Check cache (keyed by rounded coordinates)
        let cacheKey = "\(Int(latitude * 10))_\(Int(longitude * 10))"
        if let cached = cachedWeather[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < 600
        {
            return cached
        }

        let conditions = try await fetchOpenMeteoWeather(latitude: latitude, longitude: longitude)

        cachedWeather[cacheKey] = conditions
        return conditions
    }

    /// Fetch weather using a grid square
    func fetchWeather(grid: String) async throws -> WeatherConditions {
        guard let (lat, lon) = gridToCoordinates(grid) else {
            throw NOAAError.parsingError("Invalid grid square: \(grid)")
        }
        return try await fetchWeather(latitude: lat, longitude: lon)
    }

    // MARK: Private

    /// WMO weather interpretation codes → descriptions
    private static let wmoDescriptions: [Int: String] = [
        0: "Clear sky", 1: "Mainly clear", 2: "Partly cloudy", 3: "Overcast",
        45: "Foggy", 48: "Foggy",
        51: "Drizzle", 53: "Drizzle", 55: "Drizzle",
        56: "Freezing drizzle", 57: "Freezing drizzle",
        61: "Rain", 63: "Rain", 65: "Rain",
        66: "Freezing rain", 67: "Freezing rain",
        71: "Snow", 73: "Snow", 75: "Snow", 77: "Snow grains",
        80: "Rain showers", 81: "Rain showers", 82: "Rain showers",
        85: "Snow showers", 86: "Snow showers",
        95: "Thunderstorm", 96: "Thunderstorm with hail", 99: "Thunderstorm with hail",
    ]

    private let hamQSLURL = "https://www.hamqsl.com/solarxml.php"
    private let openMeteoBaseURL = "https://api.open-meteo.com/v1/forecast"

    private let session: URLSession

    // Caches
    private var cachedSolar: SolarConditions?
    private var cachedSolarTime: Date?
    private var cachedWeather: [String: WeatherConditions] = [:]

    // MARK: - Weather (Open-Meteo)

    /// Fetch weather from Open-Meteo (worldwide, single request, no API key)
    private func fetchOpenMeteoWeather(
        latitude: Double,
        longitude: Double
    ) async throws -> WeatherConditions {
        let lat = String(format: "%.4f", latitude)
        let lon = String(format: "%.4f", longitude)
        let params = "latitude=\(lat)&longitude=\(lon)"
            + "&current=temperature_2m,relative_humidity_2m"
            + ",wind_speed_10m,wind_direction_10m,weather_code"
            + "&temperature_unit=fahrenheit&wind_speed_unit=mph"

        guard let url = URL(string: "\(openMeteoBaseURL)?\(params)") else {
            throw NOAAError.invalidURL
        }

        let (data, response) = try await performRequest(url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw NOAAError.invalidResponse("Failed to fetch weather from Open-Meteo")
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let current = json["current"] as? [String: Any]
        else {
            throw NOAAError.parsingError("Could not parse Open-Meteo response")
        }

        let tempF = current["temperature_2m"] as? Double ?? 0
        let tempC = (tempF - 32) * 5 / 9
        let humidity = current["relative_humidity_2m"] as? Int
        let windSpeed = current["wind_speed_10m"] as? Double
        let windDegrees = current["wind_direction_10m"] as? Double
        let weatherCode = current["weather_code"] as? Int ?? 0

        return WeatherConditions(
            temperature: tempF,
            temperatureCelsius: tempC,
            humidity: humidity,
            windSpeed: windSpeed,
            windDirection: windDegrees.map { degreesToCardinal($0) },
            description: Self.wmoDescriptions[weatherCode] ?? "Unknown",
            icon: nil,
            timestamp: Date()
        )
    }

    /// Convert wind degrees to cardinal direction
    private func degreesToCardinal(_ degrees: Double) -> String {
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                          "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let idx = Int((degrees + 11.25).truncatingRemainder(dividingBy: 360) / 22.5)
        return directions[min(idx, directions.count - 1)]
    }

    // MARK: - Solar (HamQSL)

    /// Parse HamQSL solar XML response
    private func parseSolarXML(_ data: Data) throws -> SolarConditions {
        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw NOAAError.parsingError("Could not decode XML data")
        }

        // Extract values using simple string parsing (XML is simple and consistent)
        let kIndex = extractXMLValue(from: xmlString, tag: "kindex").flatMap { Double($0) } ?? 0
        let aIndex = extractXMLValue(from: xmlString, tag: "aindex").flatMap { Int($0) }
        let solarFlux = extractXMLValue(from: xmlString, tag: "solarflux").flatMap { Double($0) }
        let sunspots = extractXMLValue(from: xmlString, tag: "sunspots").flatMap { Int($0) }

        let bandConditions = extractBandConditions(from: xmlString)

        return SolarConditions(
            kIndex: kIndex,
            aIndex: aIndex,
            solarFlux: solarFlux,
            sunspots: sunspots,
            bandConditions: bandConditions,
            timestamp: Date()
        )
    }

    /// Extract HF band conditions from HamQSL XML.
    /// Returns a JSON string like `{"80m-40m":{"day":"Poor","night":"Good"},...}`
    /// or nil if no band data found.
    private func extractBandConditions(from xml: String) -> String? {
        let pattern = #"<band name="([^"]+)" time="([^"]+)">([^<]+)</band>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let matches = regex.matches(
            in: xml, options: [],
            range: NSRange(xml.startIndex..., in: xml)
        )

        guard !matches.isEmpty else {
            return nil
        }

        var bands: [String: [String: String]] = [:]
        for match in matches {
            guard let nameRange = Range(match.range(at: 1), in: xml),
                  let timeRange = Range(match.range(at: 2), in: xml),
                  let valueRange = Range(match.range(at: 3), in: xml)
            else {
                continue
            }
            let name = String(xml[nameRange]).trimmingCharacters(in: .whitespaces)
            let time = String(xml[timeRange]).trimmingCharacters(in: .whitespaces)
            let value = String(xml[valueRange]).trimmingCharacters(in: .whitespaces)
            bands[name, default: [:]][time] = value
        }

        guard !bands.isEmpty,
              let data = try? JSONSerialization.data(
                  withJSONObject: bands, options: [.sortedKeys]
              ),
              let json = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return json
    }

    /// Extract a value from XML by tag name
    private func extractXMLValue(from xml: String, tag: String) -> String? {
        let pattern = "<\(tag)>([^<]*)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(
                  in: xml,
                  options: [],
                  range: NSRange(xml.startIndex..., in: xml)
              ),
              let valueRange = Range(match.range(at: 1), in: xml)
        else {
            return nil
        }
        return String(xml[valueRange]).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Networking

    private func performRequest(_ url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.setValue("CarrierWave/1.0", forHTTPHeaderField: "User-Agent")

        do {
            return try await session.data(for: request)
        } catch {
            throw NOAAError.networkError(error)
        }
    }

    // MARK: - Grid Square

    /// Convert a Maidenhead grid square to approximate coordinates
    private func gridToCoordinates(_ grid: String) -> (Double, Double)? {
        let upper = grid.uppercased()
        guard upper.count >= 4 else {
            return nil
        }

        let chars = Array(upper)

        // Field (first 2 chars: A-R for longitude, A-R for latitude)
        guard let lon1 = chars[0].asciiValue, let lat1 = chars[1].asciiValue,
              lon1 >= 65, lon1 <= 82, lat1 >= 65, lat1 <= 82
        else {
            return nil
        }

        // Square (next 2 chars: 0-9)
        guard let lon2 = chars[2].wholeNumberValue, let lat2 = chars[3].wholeNumberValue else {
            return nil
        }

        var longitude = Double(lon1 - 65) * 20 - 180
        longitude += Double(lon2) * 2
        longitude += 1 // Center of square

        var latitude = Double(lat1 - 65) * 10 - 90
        latitude += Double(lat2)
        latitude += 0.5 // Center of square

        // Subsquare (optional, chars 5-6)
        if upper.count >= 6 {
            if let lon3 = chars[4].asciiValue, let lat3 = chars[5].asciiValue,
               lon3 >= 65, lon3 <= 88, lat3 >= 65, lat3 <= 88
            {
                longitude += Double(lon3 - 65) * (2.0 / 24.0) + (1.0 / 24.0)
                latitude += Double(lat3 - 65) * (1.0 / 24.0) + (0.5 / 24.0)
            }
        }

        return (latitude, longitude)
    }
}
