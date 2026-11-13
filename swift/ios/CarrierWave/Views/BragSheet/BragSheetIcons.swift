import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - BragSheetIcons

/// Maps the shared Rust `iconKey` semantic keys (derived per category in
/// `cw-domain`) to SF Symbols. The platform UIs own the symbol choice; Rust
/// only ships the semantic key. Mirrors the old `BragSheetStatType.systemImage`
/// category switch.
enum BragSheetIcons {
    static func symbol(for iconKey: String) -> String {
        switch iconKey {
        case "number": "number"
        case "gauge": "gauge.with.needle"
        case "bearing": "location.north.line"
        case "bolt": "bolt"
        case "globe": "globe"
        case "trophy": "trophy"
        case "flame": "flame"
        case "tree": "tree"
        case "waveform": "waveform"
        case "antenna": "antenna.radiowaves.left.and.right"
        case "sparkles": "sparkles"
        default: "number"
        }
    }
}

// MARK: - FfiBragStatValue Display Helpers

/// Display helpers ported from the deleted `BragSheetStatValue` Swift enum.
/// The hero value and subtitle stay host-formatted so the user's mi/km unit
/// preference (`UnitFormatter`) still applies; the structured value comes from
/// the shared Rust `computeBrag`.
extension FfiBragStatValue {
    /// Whether this stat has meaningful data to display.
    var hasData: Bool {
        if case .noData = self {
            return false
        }
        return true
    }

    /// Whether this stat can be shown on a share card (has data and a single-value summary).
    var isShareable: Bool {
        hasData && heroValue != "--"
    }

    /// Primary display string for the hero row (large number).
    var heroValue: String {
        switch self {
        case let .count(value): "\(value)"
        case let .distance(km): UnitFormatter.distanceCompact(km)
        case let .duration(seconds): Self.formatDurationCompact(seconds)
        case let .rate(value, _): String(format: "%.0f", value)
        case let .contact(callsign, _, _): callsign
        case let .power(watts, _, _, _): "\(Int(watts))W"
        case let .efficiency(wattsPerMile, _): String(format: "%.3f", wattsPerMile)
        case let .progress(current, total): "\(current)/\(total)"
        case let .streak(current, _): "\(current)d"
        case let .dayOfWeek(day, _): day
        case let .callsignCount(callsign, _): callsign
        case let .timeOfDay(unixSeconds): Self.formatUTCTime(unixSeconds)
        case let .parkDetail(park, _, _): park
        case let .wpm(words): "\(words)"
        case let .rst(value, _): value
        case .bandTable,
             .modeStreakList: "--"
        case .noData: "--"
        }
    }

    /// Secondary text displayed below the hero value.
    var subtitleDisplay: String? {
        switch self {
        case .count: "contacts"
        case let .distance(km): UnitFormatter.distance(km)
        case let .duration(seconds): Self.formatDurationSpelled(seconds)
        case let .rate(_, label): label
        case let .contact(_, distKm, band):
            Self.contactSubtitle(distanceKm: distKm, band: band)
        case let .power(_, call, distKm, band):
            Self.powerSubtitle(callsign: call, distanceKm: distKm, band: band)
        case let .efficiency(_, detail): detail
        case let .progress(_, total): "of \(total) worked"
        case let .streak(_, longest): "Best: \(longest)d"
        case .bandTable: nil
        case let .dayOfWeek(_, count): "\(count) QSOs"
        case let .callsignCount(_, count): "\(count) contacts"
        case .timeOfDay: nil
        case let .parkDetail(_, date, count):
            Self.parkDetailSubtitle(date: date, count: count)
        case .modeStreakList: nil
        case .wpm: "WPM"
        case let .rst(_, detail): detail
        case .noData: nil
        }
    }

    // MARK: Private

    private static func contactSubtitle(distanceKm: Double?, band: String?) -> String {
        var parts: [String] = []
        if let band {
            parts.append(band)
        }
        if let distKm = distanceKm {
            parts.append(UnitFormatter.distance(distKm))
        }
        return parts.joined(separator: " · ")
    }

    private static func powerSubtitle(
        callsign: String, distanceKm: Double?, band: String?
    ) -> String {
        var parts = [callsign]
        if let band {
            parts.append(band)
        }
        if let distKm = distanceKm {
            parts.append(UnitFormatter.distance(distKm))
        }
        return parts.joined(separator: " · ")
    }

    private static func parkDetailSubtitle(date: String?, count: Int64) -> String {
        var parts: [String] = []
        if let date, !date.isEmpty {
            parts.append(date)
        }
        parts.append("\(count) QSOs")
        return parts.joined(separator: " · ")
    }

    private static func formatDurationSpelled(_ seconds: Double) -> String {
        let totalMinutes = Int(seconds / 60)
        if totalMinutes < 60 {
            return "\(totalMinutes) minutes"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if minutes == 0 {
            return "\(hours) hours"
        }
        return "\(hours)h \(minutes)m"
    }

    private static func formatDurationCompact(_ seconds: Double) -> String {
        let totalMinutes = Int(seconds / 60)
        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hours)h\(minutes)m"
    }

    private static func formatUTCTime(_ unixSeconds: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(unixSeconds))
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date) + "Z"
    }
}
