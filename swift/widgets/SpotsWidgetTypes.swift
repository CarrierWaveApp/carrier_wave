import AppIntents
import SwiftUI

// MARK: - SpotSourceFilter

enum SpotSourceFilter: String, CaseIterable, AppEnum {
    case both
    case pota
    case sota
    case rbn

    // MARK: Internal

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Source")

    static var caseDisplayRepresentations: [SpotSourceFilter: DisplayRepresentation] {
        [
            .both: "All Sources",
            .pota: "POTA Only",
            .sota: "SOTA Only",
            .rbn: "RBN Only",
        ]
    }
}

// MARK: - SpotBandFilter

enum SpotBandFilter: String, CaseIterable, AppEnum {
    case band160m
    case band80m
    case band40m
    case band30m
    case band20m
    case band17m
    case band15m
    case band12m
    case band10m
    case band6m
    case band2m

    // MARK: Internal

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Band")

    static var caseDisplayRepresentations: [SpotBandFilter: DisplayRepresentation] {
        [
            .band160m: "160m", .band80m: "80m", .band40m: "40m",
            .band30m: "30m", .band20m: "20m", .band17m: "17m",
            .band15m: "15m", .band12m: "12m", .band10m: "10m",
            .band6m: "6m", .band2m: "2m",
        ]
    }

    /// Frequency range in kHz for this band (min, max)
    var frequencyRange: (Double, Double) {
        switch self {
        case .band160m: (1_800, 2_000)
        case .band80m: (3_500, 4_000)
        case .band40m: (7_000, 7_300)
        case .band30m: (10_100, 10_150)
        case .band20m: (14_000, 14_350)
        case .band17m: (18_068, 18_168)
        case .band15m: (21_000, 21_450)
        case .band12m: (24_890, 24_990)
        case .band10m: (28_000, 29_700)
        case .band6m: (50_000, 54_000)
        case .band2m: (144_000, 148_000)
        }
    }

    /// Short label for header badges
    var shortLabel: String {
        switch self {
        case .band160m: "160m"
        case .band80m: "80m"
        case .band40m: "40m"
        case .band30m: "30m"
        case .band20m: "20m"
        case .band17m: "17m"
        case .band15m: "15m"
        case .band12m: "12m"
        case .band10m: "10m"
        case .band6m: "6m"
        case .band2m: "2m"
        }
    }

    func matches(_ frequencyKHz: Double) -> Bool {
        let (min, max) = frequencyRange
        return frequencyKHz >= min && frequencyKHz < max
    }
}

// MARK: - SpotModeFilter

enum SpotModeFilter: String, CaseIterable, AppEnum {
    case cw
    case ssb
    case ft8
    case ft4
    case digital

    // MARK: Internal

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Mode")

    static var caseDisplayRepresentations: [SpotModeFilter: DisplayRepresentation] {
        [
            .cw: "CW", .ssb: "SSB", .ft8: "FT8",
            .ft4: "FT4", .digital: "Digital",
        ]
    }

    var shortLabel: String {
        switch self {
        case .cw: "CW"
        case .ssb: "SSB"
        case .ft8: "FT8"
        case .ft4: "FT4"
        case .digital: "Digital"
        }
    }

    func matches(_ mode: String) -> Bool {
        let upper = mode.uppercased()
        switch self {
        case .cw: return upper == "CW"
        case .ssb: return ["SSB", "USB", "LSB", "AM", "FM"].contains(upper)
        case .ft8: return upper == "FT8"
        case .ft4: return upper == "FT4"
        case .digital:
            return ["FT8", "FT4", "RTTY", "PSK31", "PSK", "JT65", "JT9", "DATA"]
                .contains(upper)
        }
    }
}

// MARK: - WidgetSpot

/// Lightweight spot model for widget display
struct WidgetSpot: Identifiable {
    enum Source { case pota, sota, rbn }

    let id: String
    let callsign: String
    let frequencyKHz: Double
    let mode: String
    let timestamp: Date
    let source: Source
    let parkRef: String?
    let parkName: String?
    let summitRef: String?
    let summitName: String?
    let snr: Int?
    let wpm: Int?

    var band: String? {
        let mhz = frequencyKHz / 1_000.0
        switch mhz {
        case 1.8 ..< 2.0: return "160m"
        case 3.5 ..< 4.0: return "80m"
        case 5.3 ..< 5.4: return "60m"
        case 7.0 ..< 7.3: return "40m"
        case 10.1 ..< 10.15: return "30m"
        case 14.0 ..< 14.35: return "20m"
        case 18.068 ..< 18.168: return "17m"
        case 21.0 ..< 21.45: return "15m"
        case 24.89 ..< 24.99: return "12m"
        case 28.0 ..< 29.7: return "10m"
        case 50.0 ..< 54.0: return "6m"
        case 144.0 ..< 148.0: return "2m"
        default: return nil
        }
    }

    var activityIcon: String {
        switch source {
        case .pota: "leaf.fill"
        case .sota: "mountain.2.fill"
        case .rbn: "dot.radiowaves.right"
        }
    }

    var activityColor: Color {
        switch source {
        case .pota: .green
        case .sota: .orange
        case .rbn: .blue
        }
    }

    /// Reference label (park or summit ref)
    var referenceLabel: String? {
        switch source {
        case .pota: parkRef
        case .sota: summitRef
        case .rbn: nil
        }
    }

    /// Detail text for second line (park name, summit name, or RBN signal info)
    var detailText: String? {
        switch source {
        case .pota:
            if let ref = parkRef {
                let name = parkName.map { " \u{2014} \($0)" } ?? ""
                return "\(ref)\(name)"
            }
            return nil
        case .sota:
            if let ref = summitRef {
                let name = summitName.map { " \u{2014} \($0)" } ?? ""
                return "\(ref)\(name)"
            }
            return nil
        case .rbn:
            let parts = [
                snr.map { "\($0) dB" },
                wpm.map { "\($0) wpm" },
            ].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
        }
    }

    var frequencyDisplay: String {
        String(format: "%.1f", frequencyKHz)
    }

    var timeAgo: String {
        let seconds = Date().timeIntervalSince(timestamp)
        if seconds < 60 {
            return "\(Int(seconds))s"
        }
        if seconds < 3_600 {
            return "\(Int(seconds / 60))m"
        }
        return "\(Int(seconds / 3_600))h"
    }

    var ageColor: Color {
        let seconds = Date().timeIntervalSince(timestamp)
        switch seconds {
        case ..<120: return .green
        case ..<600: return .blue
        case ..<1_800: return .orange
        default: return .secondary
        }
    }

    var sourceLabel: String {
        switch source {
        case .pota: return parkRef ?? "POTA"
        case .sota: return summitRef ?? "SOTA"
        case .rbn:
            let parts = [
                snr.map { "\($0) dB" },
                wpm.map { "\($0) wpm" },
            ].compactMap { $0 }
            return parts.isEmpty ? "RBN" : parts.joined(separator: " ")
        }
    }
}
