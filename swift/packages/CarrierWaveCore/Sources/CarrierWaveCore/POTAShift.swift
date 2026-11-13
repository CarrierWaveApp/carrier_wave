//
//  POTAShift.swift
//  CarrierWaveCore
//
//  POTA shift calculation for early and late shifts based on park longitude.
//

import Foundation

// MARK: - POTAShift

/// POTA shift types and time window calculations.
///
/// Late Shift: 8-hour window starting at 18:00 UTC, adjusted by longitude.
/// Early Shift: 6-hour window starting at 02:00 UTC, adjusted by longitude.
///
/// Adjustment formula: `baseHour - round(longitude / 15)` gives UTC start hour.
public enum POTAShift: String, Sendable, CaseIterable {
    case late
    case early

    // MARK: Public

    /// Duration of the shift in hours.
    public var durationHours: Int {
        switch self {
        case .late: 8
        case .early: 6
        }
    }

    /// Display label for the shift.
    public var displayLabel: String {
        switch self {
        case .late: "Late Shift"
        case .early: "Early Shift"
        }
    }

    // MARK: - Shift Window Calculation

    /// Calculate the UTC start hour for this shift at the given longitude.
    /// Formula: `baseHour - round(longitude / 15)`
    public func startHourUTC(longitude: Double) -> Int {
        let base = baseHour
        let offset = Int((longitude / 15.0).rounded())
        // Normalize to 0-23 range
        return ((base - offset) % 24 + 24) % 24
    }

    /// Calculate the full shift window (start and end dates) for a given UTC date and longitude.
    /// The window is anchored to the UTC date, so it may span into the next day.
    public func window(for utcDate: Date, longitude: Double) -> ShiftWindow {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!

        let startHour = startHourUTC(longitude: longitude)
        let dayStart = cal.startOfDay(for: utcDate)

        let shiftStart = cal.date(byAdding: .hour, value: startHour, to: dayStart)!
        let shiftEnd = cal.date(byAdding: .hour, value: durationHours, to: shiftStart)!

        return ShiftWindow(shift: self, start: shiftStart, end: shiftEnd)
    }

    /// Check if a given date falls within this shift window for a park at the given longitude.
    public func contains(date: Date, utcDate: Date, longitude: Double) -> Bool {
        let win = window(for: utcDate, longitude: longitude)
        return date >= win.start && date < win.end
    }

    // MARK: Private

    private var baseHour: Int {
        switch self {
        case .late: 18
        case .early: 2
        }
    }
}

// MARK: - ShiftWindow

/// A concrete time window for a POTA shift.
public struct ShiftWindow: Sendable {
    public let shift: POTAShift
    public let start: Date
    public let end: Date

    /// Format the window as "HH:mm – HH:mm UTC"
    public var formattedRange: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return "\(fmt.string(from: start)) – \(fmt.string(from: end)) UTC"
    }

    /// Check if a date falls within this window.
    public func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }
}

// MARK: - Shift Helpers

public extension POTAShift {
    /// Compute both shift windows for a given UTC date and longitude.
    static func windows(for utcDate: Date, longitude: Double) -> [ShiftWindow] {
        allCases.map { $0.window(for: utcDate, longitude: longitude) }
    }

    /// Find which shift (if any) a timestamp falls within, for a park at the given longitude.
    static func activeShift(
        at date: Date, utcDate: Date, longitude: Double
    ) -> POTAShift? {
        allCases.first { $0.contains(date: date, utcDate: utcDate, longitude: longitude) }
    }
}
