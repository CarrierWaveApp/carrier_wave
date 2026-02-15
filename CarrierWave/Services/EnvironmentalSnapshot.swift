import Foundation

/// Lightweight, Sendable snapshot of environmental conditions for charting.
/// Fetched from LoggingSession and ActivationMetadata on a background actor,
/// then sent to the main thread for Swift Charts rendering.
struct EnvironmentalSnapshot: Sendable, Identifiable {
    let id: UUID
    let timestamp: Date

    // Location context
    let gridSquare: String? // 4- or 6-char Maidenhead grid

    // Source info
    let sessionId: UUID?
    let parkReference: String?

    // Solar fields
    let solarKIndex: Double?
    let solarFlux: Double?
    let solarSunspots: Int?
    let solarPropagationRating: String?

    // Weather fields
    let weatherTemperatureF: Double?
    let weatherTemperatureC: Double?
    let weatherHumidity: Int?
    let weatherWindSpeed: Double?
    let weatherWindDirection: String?
    let weatherDescription: String?

    var hasSolarData: Bool { solarKIndex != nil }
    var hasWeatherData: Bool { weatherTemperatureF != nil }
}
