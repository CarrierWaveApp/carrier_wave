// SOTA Summit
//
// Lightweight struct representing a SOTA summit from the
// summitslist.csv database. Mirrors POTAPark for consistency.

import CarrierWaveData
import Foundation

// MARK: - SOTASummit

/// Full summit metadata from SOTA summitslist.csv
struct SOTASummit: Codable {
    let code: String // "W4C/CM-001"
    let name: String // "Mount Mitchell"
    let associationName: String // "USA - North Carolina"
    let regionName: String // "Western NC Mountains"
    let altitudeM: Int
    let altitudeFt: Int
    let latitude: Double?
    let longitude: Double?
    let points: Int
    let bonusPoints: Int
    let activationCount: Int
    let lastActivationDate: String? // "dd/MM/yyyy" from CSV
    let lastActivationCall: String? // Callsign of last activator
    let grid: String?

    /// Last activation date formatted for display (e.g., "15 Mar 2024")
    var formattedLastActivation: String? {
        guard let dateStr = lastActivationDate, !dateStr.isEmpty else {
            return nil
        }
        let parser = DateFormatter()
        parser.dateFormat = "dd/MM/yyyy"
        parser.timeZone = TimeZone(identifier: "UTC")
        guard let date = parser.date(from: dateStr) else {
            return nil
        }
        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .none
        return display.string(from: date)
    }

    /// Days since last activation, for freshness display
    var daysSinceLastActivation: Int? {
        guard let dateStr = lastActivationDate, !dateStr.isEmpty else {
            return nil
        }
        let parser = DateFormatter()
        parser.dateFormat = "dd/MM/yyyy"
        parser.timeZone = TimeZone(identifier: "UTC")
        guard let date = parser.date(from: dateStr) else {
            return nil
        }
        return Calendar.current.dateComponents(
            [.day], from: date, to: Date()
        ).day
    }

    /// URL to view this summit on SOTL.as
    var sotlasURL: URL? {
        URL(string: "https://sotl.as/summits/\(code)")
    }

    /// Association prefix (e.g., "W4C" from "W4C/CM-001")
    var associationPrefix: String {
        guard let slashIndex = code.firstIndex(of: "/") else {
            return code
        }
        return String(code[code.startIndex ..< slashIndex])
    }

    /// Region code (e.g., "CM" from "W4C/CM-001")
    var regionCode: String? {
        guard let slashIndex = code.firstIndex(of: "/"),
              let dashIndex = code.lastIndex(of: "-")
        else {
            return nil
        }
        let afterSlash = code.index(after: slashIndex)
        guard afterSlash < dashIndex else {
            return nil
        }
        return String(code[afterSlash ..< dashIndex])
    }
}
