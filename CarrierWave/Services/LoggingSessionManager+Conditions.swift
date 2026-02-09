import Foundation
import SwiftData

/// Extension for auto-recording solar/weather conditions at POTA session start
extension LoggingSessionManager {
    /// Auto-record solar and weather conditions for the current POTA activation
    func recordConditions() {
        guard autoRecordConditions,
              let session = activeSession,
              session.activationType == .pota,
              let parkRef = session.parkReference, !parkRef.isEmpty
        else {
            return
        }

        let grid = session.myGrid
        let sessionDate = session.startedAt

        Task {
            let noaaClient = NOAAClient()

            // Fetch solar conditions
            var solarText: String?
            do {
                let conditions = try await noaaClient.fetchSolarConditions()
                solarText = conditions.description
            } catch {
                // Solar fetch failed, continue with weather
            }

            // Fetch weather if grid is available
            var weatherText: String?
            if let grid, !grid.isEmpty {
                do {
                    let conditions = try await noaaClient.fetchWeather(grid: grid)
                    weatherText = Self.formatWeatherForMetadata(conditions)
                } catch {
                    // Weather fetch failed, continue with what we have
                }
            }

            // Store into ActivationMetadata on the main actor
            guard solarText != nil || weatherText != nil else {
                return
            }
            await MainActor.run {
                storeConditionsMetadata(
                    parkRef: parkRef,
                    date: sessionDate,
                    solar: solarText,
                    weather: weatherText
                )
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

    /// Format weather conditions as a compact string for ActivationMetadata
    private static func formatWeatherForMetadata(_ conditions: WeatherConditions) -> String {
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

    /// Store solar/weather conditions into ActivationMetadata
    private func storeConditionsMetadata(
        parkRef: String,
        date: Date,
        solar: String?,
        weather: String?
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

        // Only overwrite if we got data and there's nothing stored yet
        if let solar, metadata.solarConditions == nil || metadata.solarConditions?.isEmpty == true {
            metadata.solarConditions = solar
        }
        if let weather, metadata.weather == nil || metadata.weather?.isEmpty == true {
            metadata.weather = weather
        }

        try? modelContext.save()
    }
}
