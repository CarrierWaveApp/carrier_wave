// POTA maintenance window utilities
//
// Helpers for detecting and displaying POTA's daily maintenance window
// (2330-0400 UTC) when uploads are unavailable.

import CarrierWaveData
import Foundation

extension POTAClient {
    /// Check if current time is within POTA maintenance window (2330-0400 UTC daily)
    static func isInMaintenanceWindow(at date: Date = Date()) -> Bool {
        let calendar = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(identifier: "UTC") else {
            return false
        }
        let components = calendar.dateComponents(in: utc, from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0

        // Maintenance window: 2330-0400 UTC
        // This spans midnight, so we check:
        // - 23:30 to 23:59 (hour 23, minute >= 30)
        // - 00:00 to 03:59 (hour 0-3)
        if hour == 23, minute >= 30 {
            return true
        }
        if hour >= 0, hour < 4 {
            return true
        }
        return false
    }

    /// Calculate time remaining until maintenance window ends (returns nil if not in maintenance)
    static func maintenanceTimeRemaining(at date: Date = Date()) -> TimeInterval? {
        guard isInMaintenanceWindow(at: date) else {
            return nil
        }

        let calendar = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(identifier: "UTC") else {
            return nil
        }

        var endComponents = calendar.dateComponents(in: utc, from: date)
        let hour = endComponents.hour ?? 0

        // If we're before midnight (23:30-23:59), end time is 04:00 next day
        // If we're after midnight (00:00-03:59), end time is 04:00 same day
        if hour == 23 {
            // Move to next day
            if let nextDay = calendar.date(byAdding: .day, value: 1, to: date) {
                endComponents = calendar.dateComponents(in: utc, from: nextDay)
            }
        }

        endComponents.hour = 4
        endComponents.minute = 0
        endComponents.second = 0

        guard let endDate = calendar.date(from: endComponents) else {
            return nil
        }

        return endDate.timeIntervalSince(date)
    }

    /// Format time remaining as a human-readable string
    static func formatMaintenanceTimeRemaining(at date: Date = Date()) -> String? {
        guard let remaining = maintenanceTimeRemaining(at: date) else {
            return nil
        }

        let hours = Int(remaining) / 3_600
        let minutes = (Int(remaining) % 3_600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
