// swiftlint:disable function_body_length
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
            "Invalid NOAA API URL"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case let .invalidResponse(message):
            "Invalid response: \(message)"
        case .noData:
            "No data received from NOAA"
        case .locationRequired:
            "Location is required for weather data"
        case let .parsingError(message):
            "Failed to parse response: \(message)"
        }
    }
}

// MARK: - SolarConditions

/// Solar conditions from NOAA SWPC
struct SolarConditions: Sendable {
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

/// Weather conditions from NOAA
struct WeatherConditions: Sendable {
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

/// Client for NOAA APIs (weather and solar)
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

    /// Fetch weather for a location
    func fetchWeather(latitude: Double, longitude: Double) async throws -> WeatherConditions {
        // Check cache (keyed by rounded coordinates)
        let cacheKey = "\(Int(latitude * 10))_\(Int(longitude * 10))"
        if let cached = cachedWeather[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < 600
        {
            return cached
        }

        // Step 1: Get the forecast URL for this location
        let pointsURL = URL(string: "\(weatherBaseURL)/points/\(latitude),\(longitude)")!

        let (pointsData, pointsResponse) = try await performRequest(pointsURL)

        guard let httpResponse = pointsResponse as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw NOAAError.invalidResponse("Failed to fetch weather point data")
        }

        guard
            let pointsJson = try? JSONSerialization.jsonObject(with: pointsData) as? [String: Any],
            let properties = pointsJson["properties"] as? [String: Any],
            let forecastHourlyURLString = properties["forecastHourly"] as? String,
            let forecastURL = URL(string: forecastHourlyURLString)
        else {
            throw NOAAError.parsingError("Could not parse weather points data")
        }

        // Step 2: Fetch the hourly forecast
        let (forecastData, forecastResponse) = try await performRequest(forecastURL)

        guard let httpForecastResponse = forecastResponse as? HTTPURLResponse,
              httpForecastResponse.statusCode == 200
        else {
            throw NOAAError.invalidResponse("Failed to fetch forecast data")
        }

        guard
            let forecastJson = try? JSONSerialization.jsonObject(with: forecastData)
            as? [String: Any],
            let forecastProperties = forecastJson["properties"] as? [String: Any],
            let periods = forecastProperties["periods"] as? [[String: Any]],
            let current = periods.first
        else {
            throw NOAAError.parsingError("Could not parse forecast data")
        }

        // Parse current conditions
        let temperature = current["temperature"] as? Double ?? 0
        let temperatureUnit = current["temperatureUnit"] as? String ?? "F"
        let tempF = temperatureUnit == "C" ? (temperature * 9 / 5 + 32) : temperature
        let tempC = temperatureUnit == "C" ? temperature : ((temperature - 32) * 5 / 9)

        let windSpeedString = current["windSpeed"] as? String ?? "0 mph"
        let windSpeed = Double(windSpeedString.components(separatedBy: " ").first ?? "0")

        let conditions = WeatherConditions(
            temperature: tempF,
            temperatureCelsius: tempC,
            humidity: (current["relativeHumidity"] as? [String: Any])?["value"] as? Int,
            windSpeed: windSpeed,
            windDirection: current["windDirection"] as? String,
            description: current["shortForecast"] as? String ?? "Unknown",
            icon: current["icon"] as? String,
            timestamp: Date()
        )

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

    private let hamQSLURL = "https://www.hamqsl.com/solarxml.php"
    private let weatherBaseURL = "https://api.weather.gov"

    private let session: URLSession

    // Caches
    private var cachedSolar: SolarConditions?
    private var cachedSolarTime: Date?
    private var cachedWeather: [String: WeatherConditions] = [:]

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

    private func performRequest(_ url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.setValue("CarrierWave/1.0", forHTTPHeaderField: "User-Agent")

        do {
            return try await session.data(for: request)
        } catch {
            throw NOAAError.networkError(error)
        }
    }

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
