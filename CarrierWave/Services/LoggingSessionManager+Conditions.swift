import Foundation
import SwiftData

// MARK: - FetchedConditions

/// Fetched solar/weather conditions from NOAA
private struct FetchedConditions {
    var solarText: String?
    var weatherText: String?
    var solarData: SolarConditions?
    var weatherData: WeatherConditions?
}

/// Extension for auto-recording solar/weather conditions at session start
extension LoggingSessionManager {
    /// Auto-record solar and weather conditions for the current session (all types)
    func recordConditions() {
        guard autoRecordConditions,
              let session = activeSession
        else {
            return
        }

        let grid = session.myGrid
        let sessionDate = session.startedAt
        let parkRef = session.parkReference
        let isPOTA = session.activationType == .pota && parkRef != nil && !parkRef!.isEmpty

        Task {
            let conditions = await fetchConditions(grid: grid)

            guard conditions.solarText != nil || conditions.weatherText != nil else {
                return
            }

            await MainActor.run {
                storeConditionsOnSession(
                    session: session,
                    solar: conditions.solarText,
                    weather: conditions.weatherText,
                    solarData: conditions.solarData,
                    weatherData: conditions.weatherData
                )

                if isPOTA, let parkRef {
                    storeConditionsMetadata(
                        parkRef: parkRef,
                        date: sessionDate,
                        solar: conditions.solarText,
                        weather: conditions.weatherText,
                        solarData: conditions.solarData,
                        weatherData: conditions.weatherData
                    )
                }
            }
        }
    }

    /// Fetch solar and weather conditions from NOAA
    private func fetchConditions(grid: String?) async -> FetchedConditions {
        let noaaClient = NOAAClient()
        var result = FetchedConditions()

        do {
            let solar = try await noaaClient.fetchSolarConditions()
            result.solarText = solar.description
            result.solarData = solar
        } catch {
            // Solar fetch failed, continue with weather
        }

        if let grid, !grid.isEmpty {
            do {
                let weather = try await noaaClient.fetchWeather(grid: grid)
                result.weatherText = Self.formatWeatherForMetadata(weather)
                result.weatherData = weather
            } catch {
                // Weather fetch failed, continue with what we have
            }
        }

        return result
    }

    // MARK: - Private Helpers

    /// Whether to auto-record solar/weather conditions at session start (from settings)
    /// Defaults to true
    private var autoRecordConditions: Bool {
        if UserDefaults.standard.object(forKey: "autoRecordConditions") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "autoRecordConditions")
    }

    /// Format weather conditions as a compact string
    static func formatWeatherForMetadata(_ conditions: WeatherConditions) -> String {
        var parts: [String] = []
        parts.append(conditions.formattedTemperature)
        parts.append(conditions.description)
        if let wind = conditions.formattedWind {
            parts.append("Wind: \(wind)")
        }
        if let humidity = conditions.humidity {
            parts.append("Humidity: \(humidity)%")
        }
        return parts.joined(separator: ", ")
    }

    /// Store solar/weather conditions directly on the LoggingSession
    private func storeConditionsOnSession(
        session: LoggingSession,
        solar: String?,
        weather: String?,
        solarData: SolarConditions?,
        weatherData: WeatherConditions?
    ) {
        if let solar, session.solarConditions == nil {
            session.solarConditions = solar
        }
        if let weather, session.weather == nil {
            session.weather = weather
        }

        if let solarData, !session.hasSolarData {
            session.solarKIndex = solarData.kIndex
            session.solarFlux = solarData.solarFlux
            session.solarSunspots = solarData.sunspots
            session.solarPropagationRating = solarData.propagationRating
            session.solarTimestamp = solarData.timestamp
        }

        if let weatherData, !session.hasWeatherData {
            session.weatherTemperatureF = weatherData.temperature
            session.weatherTemperatureC = weatherData.temperatureCelsius
            session.weatherHumidity = weatherData.humidity
            session.weatherWindSpeed = weatherData.windSpeed
            session.weatherWindDirection = weatherData.windDirection
            session.weatherDescription = weatherData.description
            session.weatherTimestamp = weatherData.timestamp
        }

        try? modelContext.save()
    }

    /// Store solar/weather conditions into ActivationMetadata (POTA only)
    private func storeConditionsMetadata(
        parkRef: String,
        date: Date,
        solar: String?,
        weather: String?,
        solarData: SolarConditions? = nil,
        weatherData: WeatherConditions? = nil
    ) {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let normalizedDate = calendar.startOfDay(for: date)

        // Find or create metadata for this park/date
        let descriptor = FetchDescriptor<ActivationMetadata>()
        let allMetadata = (try? modelContext.fetch(descriptor)) ?? []
        let existing = allMetadata.first {
            $0.parkReference == parkRef && $0.date == normalizedDate
        }

        let metadata: ActivationMetadata
        if let existing {
            metadata = existing
        } else {
            metadata = ActivationMetadata(parkReference: parkRef, date: normalizedDate)
            modelContext.insert(metadata)
        }

        if let solar, metadata.solarConditions == nil || metadata.solarConditions?.isEmpty == true {
            metadata.solarConditions = solar
        }
        if let weather, metadata.weather == nil || metadata.weather?.isEmpty == true {
            metadata.weather = weather
        }

        if let solarData, !metadata.hasSolarData {
            metadata.solarKIndex = solarData.kIndex
            metadata.solarFlux = solarData.solarFlux
            metadata.solarSunspots = solarData.sunspots
            metadata.solarPropagationRating = solarData.propagationRating
            metadata.solarTimestamp = solarData.timestamp
        }

        if let weatherData, !metadata.hasWeatherData {
            metadata.weatherTemperatureF = weatherData.temperature
            metadata.weatherTemperatureC = weatherData.temperatureCelsius
            metadata.weatherHumidity = weatherData.humidity
            metadata.weatherWindSpeed = weatherData.windSpeed
            metadata.weatherWindDirection = weatherData.windDirection
            metadata.weatherDescription = weatherData.description
            metadata.weatherTimestamp = weatherData.timestamp
        }

        try? modelContext.save()
    }
}
