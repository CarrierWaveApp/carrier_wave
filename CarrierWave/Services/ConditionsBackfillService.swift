import CarrierWaveData
import Foundation
import SwiftData

/// One-time backfill: parse existing text-based solar/weather fields on ActivationMetadata
/// into structured fields (kIndex, SFI, temperature, etc.).
actor ConditionsBackfillService {
    // MARK: Lifecycle

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Internal

    struct BackfillResult: Sendable {
        let solarUpdated: Int
        let weatherUpdated: Int
    }

    let container: ModelContainer

    /// Run the backfill. Returns counts of metadata records updated.
    func backfill() throws -> BackfillResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let allMetadata = try context.fetch(FetchDescriptor<ActivationMetadata>())

        var solarUpdated = 0
        var weatherUpdated = 0

        for metadata in allMetadata {
            if parseSolar(metadata) {
                solarUpdated += 1
            }
            if parseWeather(metadata) {
                weatherUpdated += 1
            }
        }

        if solarUpdated > 0 || weatherUpdated > 0 {
            try context.save()
        }

        return BackfillResult(solarUpdated: solarUpdated, weatherUpdated: weatherUpdated)
    }

    // MARK: Private

    /// Parse solar text like "K-index: 2.3 | SFI: 145 | Sunspots: 12" into structured fields.
    /// Returns true if metadata was updated.
    private func parseSolar(_ metadata: ActivationMetadata) -> Bool {
        guard !metadata.hasSolarData,
              let text = metadata.solarConditions, !text.isEmpty
        else {
            return false
        }

        if let match = text.firstMatch(of: /K-index:\s*([\d.]+)/) {
            metadata.solarKIndex = Double(match.1)
        }
        if let match = text.firstMatch(of: /SFI:\s*(\d+)/) {
            metadata.solarFlux = Double(match.1)
        }
        if let match = text.firstMatch(of: /Sunspots:\s*(\d+)/) {
            metadata.solarSunspots = Int(match.1)
        }

        // Derive propagation rating from K-index
        if let kIndex = metadata.solarKIndex {
            metadata.solarPropagationRating = propagationRating(for: kIndex)
        }

        return metadata.hasSolarData
    }

    /// Parse weather text like "72°F, Partly Cloudy, Wind: 5 mph N, Humidity: 60%"
    /// into structured fields. Returns true if metadata was updated.
    private func parseWeather(_ metadata: ActivationMetadata) -> Bool {
        guard !metadata.hasWeatherData,
              let text = metadata.weather, !text.isEmpty
        else {
            return false
        }

        // Temperature: "72°F" or "72\u{00B0}F"
        if let match = text.firstMatch(of: /(\d+)[\u{00B0}°]F/) {
            let tempF = Double(match.1) ?? 0
            metadata.weatherTemperatureF = tempF
            metadata.weatherTemperatureC = (tempF - 32) * 5 / 9
        }

        // Wind: "Wind: 5 mph N" or "Wind: 5 mph"
        if let match = text.firstMatch(of: /Wind:\s*(\d+)\s*mph\s*([NSEW]+)?/) {
            metadata.weatherWindSpeed = Double(match.1)
            if let dir = match.2 {
                metadata.weatherWindDirection = String(dir)
            }
        }

        // Humidity: "Humidity: 60%"
        if let match = text.firstMatch(of: /Humidity:\s*(\d+)%/) {
            metadata.weatherHumidity = Int(match.1)
        }

        // Description: second comma-separated part (after temp, before Wind/Humidity)
        let parts = text.components(separatedBy: ", ")
        if parts.count >= 2 {
            let desc = parts[1]
            // Only use if it's not a Wind: or Humidity: field
            if !desc.hasPrefix("Wind:"), !desc.hasPrefix("Humidity:") {
                metadata.weatherDescription = desc
            }
        }

        return metadata.hasWeatherData
    }

    /// Derive propagation rating from K-index (matches SolarConditions.propagationRating)
    private func propagationRating(for kIndex: Double) -> String {
        switch kIndex {
        case 0 ..< 2: "Excellent"
        case 2 ..< 3: "Good"
        case 3 ..< 4: "Fair"
        case 4 ..< 5: "Poor"
        default: "Very Poor"
        }
    }
}
