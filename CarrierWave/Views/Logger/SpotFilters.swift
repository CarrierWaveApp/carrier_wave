import SwiftUI

// MARK: - BandFilter

/// Band filter options for spots
enum BandFilter: String, CaseIterable, Identifiable {
    case all = "All Bands"
    case band160m = "160m"
    case band80m = "80m"
    case band60m = "60m"
    case band40m = "40m"
    case band30m = "30m"
    case band20m = "20m"
    case band17m = "17m"
    case band15m = "15m"
    case band12m = "12m"
    case band10m = "10m"
    case band6m = "6m"
    case band2m = "2m"

    // MARK: Internal

    var id: String {
        rawValue
    }

    var bandName: String? {
        if self == .all {
            return nil
        }
        return rawValue
    }

    static func from(bandName: String?) -> BandFilter {
        guard let name = bandName else {
            return .all
        }
        return allCases.first { $0.rawValue == name } ?? .all
    }
}

// MARK: - ModeFilter

/// Mode filter options for spots
enum ModeFilter: String, CaseIterable, Identifiable {
    case all = "All Modes"
    case cw = "CW"
    case ssb = "SSB"
    case ft8 = "FT8"
    case ft4 = "FT4"
    case digital = "Digital"

    // MARK: Internal

    var id: String {
        rawValue
    }

    var modeName: String? {
        if self == .all {
            return nil
        }
        return rawValue
    }

    static func from(modeName: String?) -> ModeFilter {
        guard let name = modeName?.uppercased() else {
            return .all
        }
        switch name {
        case "CW": return .cw
        case "SSB",
             "USB",
             "LSB":
            return .ssb
        case "FT8": return .ft8
        case "FT4": return .ft4
        default: return .all
        }
    }

    func matches(_ mode: String) -> Bool {
        switch self {
        case .all: true
        case .cw: mode.uppercased() == "CW"
        case .ssb: ["SSB", "USB", "LSB", "AM", "FM"].contains(mode.uppercased())
        case .ft8: mode.uppercased() == "FT8"
        case .ft4: mode.uppercased() == "FT4"
        case .digital:
            ["FT8", "FT4", "RTTY", "PSK31", "PSK", "JT65", "JT9", "DATA", "DIGITAL"]
                .contains(mode.uppercased())
        }
    }
}
