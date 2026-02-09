//
//  ActivationMetadata.swift
//  CarrierWave
//

import Foundation
import SwiftData

/// Stores metadata for POTA activations (title, power, weather, solar conditions)
/// Keyed by park reference + date (UTC start of day)
@Model
final class ActivationMetadata {
    // MARK: Lifecycle

    init(
        parkReference: String,
        date: Date,
        title: String? = nil,
        watts: Int? = nil,
        weather: String? = nil,
        solarConditions: String? = nil,
        averageWPM: Int? = nil
    ) {
        self.parkReference = parkReference
        // Normalize to start of day in UTC
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        self.date = calendar.startOfDay(for: date)
        self.title = title
        self.watts = watts
        self.weather = weather
        self.solarConditions = solarConditions
        self.averageWPM = averageWPM
    }

    // MARK: Internal

    // Default values required for SwiftData lightweight migration
    var parkReference = ""
    var date = Date()
    var title: String?
    var watts: Int?
    var weather: String?
    var solarConditions: String?
    /// Average CW speed from RBN spots during activation
    var averageWPM: Int?
}
