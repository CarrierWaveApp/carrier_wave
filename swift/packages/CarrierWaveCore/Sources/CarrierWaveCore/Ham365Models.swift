import Foundation

// MARK: - Ham365DXpedition

/// A DXpedition entry parsed from Ham365.net's calendar HTML.
public struct Ham365DXpedition: Sendable, Identifiable, Equatable {
    // MARK: Lifecycle

    public init(
        callsign: String,
        entity: String,
        activeDays: Set<Int>,
        isOnAir: Bool,
        month: Int,
        year: Int
    ) {
        self.callsign = callsign
        self.entity = entity
        self.activeDays = activeDays
        self.isOnAir = isOnAir
        self.month = month
        self.year = year
    }

    // MARK: Public

    /// The DXpedition callsign (e.g. "3Y0K")
    public let callsign: String

    /// DXCC entity name (e.g. "Bouvet Is.")
    public let entity: String

    /// Day numbers (1-31) when the DXpedition is active
    public let activeDays: Set<Int>

    /// Whether onair.gif is present in the header (currently transmitting)
    public let isOnAir: Bool

    /// Calendar month (1-12)
    public let month: Int

    /// Calendar year
    public let year: Int

    public var id: String {
        callsign
    }

    /// Whether the DXpedition is active today
    public var isActiveToday: Bool {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        guard components.year == year, components.month == month,
              let day = components.day
        else {
            return false
        }
        return activeDays.contains(day)
    }

    /// Callsign variants to search for on RBN.
    ///
    /// DXpedition operators may be spotted under different callsign forms:
    /// - The primary callsign as-is (e.g. "3Y0K")
    /// - Slash-separated parts (e.g. "PJ7/K1XX" → also try "K1XX" and "PJ7")
    /// - The base call when a portable suffix is present (e.g. "VK0HI/P" → "VK0HI")
    public var searchCallsigns: [String] {
        var variants: [String] = [callsign]
        let parts = callsign.split(separator: "/").map(String.init)
        if parts.count == 2 {
            // Add both halves: for "PJ7/K1XX" → try "K1XX" and "PJ7"
            // For "VP8/G0ABC" → try "G0ABC" and "VP8"
            for part in parts where part != callsign {
                variants.append(part)
            }
        }
        return variants
    }

    /// Human-readable date range summary (e.g. "Mar 1–15")
    public var dateRange: String {
        guard let minDay = activeDays.min(), let maxDay = activeDays.max() else {
            return ""
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        var components = DateComponents()
        components.month = month
        components.year = year
        let monthName = formatter.monthSymbols[month - 1]
        let abbreviated = String(monthName.prefix(3))
        if minDay == maxDay {
            return "\(abbreviated) \(minDay)"
        }
        return "\(abbreviated) \(minDay)–\(maxDay)"
    }
}
