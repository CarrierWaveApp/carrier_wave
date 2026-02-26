// SOTA Summit
//
// Lightweight struct representing a SOTA summit from the
// summitslist.csv database. Mirrors POTAPark for consistency.

import Foundation

// MARK: - SOTASummit

/// Full summit metadata from SOTA summitslist.csv
struct SOTASummit: Sendable {
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
    let grid: String?

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
