//
//  TOTAWinterDetector.swift
//  CarrierWaveCore
//
//  Hemisphere-aware winter detection for the TOTA +20% winter bonus.
//  Pure: no UIKit, no SwiftData. The rules don't define "winter" precisely;
//  this matches our docs (Northern hemisphere months 12/1/2, Southern 6/7/8,
//  equator-adjacent never).
//

import Foundation

public enum TOTAWinterDetector: Sendable {
    /// Returns whether the given date qualifies as "winter" for TOTA bonus
    /// purposes given the activation latitude.
    /// - Parameters:
    ///   - latitude: Decimal degrees, +N / -S. nil → assume northern.
    ///   - date: Anchor timestamp (typically `LoggingSession.startedAt`). UTC.
    /// - Returns: true when the date is in the hemisphere's winter window.
    public static func isWinter(latitude: Double?, date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let month = calendar.component(.month, from: date)

        guard let lat = latitude else {
            // No coordinate → assume northern hemisphere.
            return month == 12 || month == 1 || month == 2
        }
        // Equator-adjacent: no meaningful winter regardless of date.
        if abs(lat) < 5 {
            return false
        }
        if lat >= 0 {
            return month == 12 || month == 1 || month == 2
        }
        return month == 6 || month == 7 || month == 8
    }
}
