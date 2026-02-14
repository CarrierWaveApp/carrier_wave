import Foundation
import SwiftData

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
            let noaaClient = NOAAClient()

            // Fetch solar conditions
            var solarText: String?
            var solarData: SolarConditions?
            do {
                let conditions = try await noaaClient.fetchSolarConditions()
                solarText = conditions.description
                solarData = conditions
            } catch {
                // Solar fetch failed, continue with weather
            }

            // Fetch weather if grid is available
            var weatherText: String?
            var weatherData: WeatherConditions?
            if let grid, !grid.isEmpty {
                do {
                    let conditions = try await noaaClient.fetchWeather(grid: grid)
                    weatherText = Self.formatWeatherForMetadata(conditions)
                    weatherData = conditions
                } catch {
                    // Weather fetch failed, continue with what we have
                }
            }

            guard solarText != nil || weatherText != nil else {
                return
            }

            await MainActor.run {
                // Store conditions on the session itself (all session types)
                storeConditionsOnSession(
                    session: session,
                    solar: solarText,
                    weather: weatherText,
                    solarData: solarData,
                    weatherData: weatherData
                )

                // For POTA sessions, also store into ActivationMetadata
                if isPOTA, let parkRef {
                    storeConditionsMetadata(
                        parkRef: parkRef,
                        date: sessionDate,
                        solar: solarText,
                        weather: weatherText,
                        solarData: solarData,
                        weatherData: weatherData
                    )
                }
            }
        }
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
