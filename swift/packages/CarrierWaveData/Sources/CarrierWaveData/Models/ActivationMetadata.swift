import Foundation
import SwiftData

@Model
nonisolated public final class ActivationMetadata {
    // MARK: Lifecycle

    public init(
        parkReference: String,
        date: Date,
        title: String? = nil,
        watts: Int? = nil,
        weather: String? = nil,
        solarConditions: String? = nil,
        averageWPM: Int? = nil
    ) {
        self.parkReference = parkReference
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        self.date = calendar.startOfDay(for: date)
        self.title = title
        self.watts = watts
        self.weather = weather
        self.solarConditions = solarConditions
        self.averageWPM = averageWPM
    }

    // MARK: Public

    public var parkReference = ""
    public var date = Date()
    public var title: String?
    public var watts: Int?
    public var weather: String?
    public var solarConditions: String?
    public var averageWPM: Int?

    // Structured Solar Fields
    public var solarKIndex: Double?
    public var solarFlux: Double?
    public var solarSunspots: Int?
    public var solarPropagationRating: String?
    public var solarAIndex: Int?
    public var solarBandConditions: String?
    public var solarTimestamp: Date?

    // Structured Weather Fields
    public var weatherTemperatureF: Double?
    public var weatherTemperatureC: Double?
    public var weatherHumidity: Int?
    public var weatherWindSpeed: Double?
    public var weatherWindDirection: String?
    public var weatherDescription: String?
    public var weatherTimestamp: Date?

    public var cloudDirtyFlag: Bool = false

    public var hasSolarData: Bool {
        solarKIndex != nil || solarFlux != nil || solarSunspots != nil
    }

    public var hasWeatherData: Bool {
        weatherTemperatureF != nil
    }
}
