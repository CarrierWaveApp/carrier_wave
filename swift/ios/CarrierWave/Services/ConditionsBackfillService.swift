import CarrierWaveData
import Foundation
import SwiftData

/// One-time backfill: parse existing text-based solar/weather fields on ActivationMetadata
/// into structured fields (kIndex, SFI, temperature, etc.).
///
/// Façade over `BatchedRewrite`. Each metadata row's mutation is decided locally
/// from its own `solarConditions` / `weather` strings.
actor ConditionsBackfillService {
    // MARK: Lifecycle

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Internal

    struct BackfillResult {
        let solarUpdated: Int
        let weatherUpdated: Int
    }

    let container: ModelContainer

    /// Run the backfill. Returns counts of metadata records updated.
    func backfill() async throws -> BackfillResult {
        let counters = Counters()

        _ = try await BatchedRewrite<ActivationMetadata>(
            label: "conditions.backfill",
            container: container
        ) { meta, _ in
            var changed = false
            if Self.parseSolar(meta) {
                counters.solarUpdated += 1
                changed = true
            }
            if Self.parseWeather(meta) {
                counters.weatherUpdated += 1
                changed = true
            }
            return changed
        }.run()

        return BackfillResult(
            solarUpdated: counters.solarUpdated,
            weatherUpdated: counters.weatherUpdated
        )
    }

    // MARK: Private

    private final class Counters: @unchecked Sendable {
        var solarUpdated = 0
        var weatherUpdated = 0
    }

    /// Parse solar text like "K-index: 2.3 | SFI: 145 | Sunspots: 12" into structured fields.
    /// Returns true if metadata was updated.
    private static func parseSolar(_ metadata: ActivationMetadata) -> Bool {
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

        if let kIndex = metadata.solarKIndex {
            metadata.solarPropagationRating = propagationRating(for: kIndex)
        }

        return metadata.hasSolarData
    }

    /// Parse weather text into structured fields. Returns true if metadata was updated.
    private static func parseWeather(_ metadata: ActivationMetadata) -> Bool {
        guard !metadata.hasWeatherData,
              let text = metadata.weather, !text.isEmpty
        else {
            return false
        }

        if let match = text.firstMatch(of: /(\d+)[\u{00B0}°]F/) {
            let tempF = Double(match.1) ?? 0
            metadata.weatherTemperatureF = tempF
            metadata.weatherTemperatureC = (tempF - 32) * 5 / 9
        }

        if let match = text.firstMatch(of: /Wind:\s*(\d+)\s*mph\s*([NSEW]+)?/) {
            metadata.weatherWindSpeed = Double(match.1)
            if let dir = match.2 {
                metadata.weatherWindDirection = String(dir)
            }
        }

        if let match = text.firstMatch(of: /Humidity:\s*(\d+)%/) {
            metadata.weatherHumidity = Int(match.1)
        }

        let parts = text.components(separatedBy: ", ")
        if parts.count >= 2 {
            let desc = parts[1]
            if !desc.hasPrefix("Wind:"), !desc.hasPrefix("Humidity:") {
                metadata.weatherDescription = desc
            }
        }

        return metadata.hasWeatherData
    }

    private static func propagationRating(for kIndex: Double) -> String {
        switch kIndex {
        case 0 ..< 2: "Excellent"
        case 2 ..< 3: "Good"
        case 3 ..< 4: "Fair"
        case 4 ..< 5: "Poor"
        default: "Very Poor"
        }
    }
}
