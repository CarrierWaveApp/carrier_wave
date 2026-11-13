import CarrierWaveCwFfi
import Foundation

// MARK: - Submode Validation (ADIF 3.1.7)

nonisolated public extension ADIFCatalog {
    /// Maps each valid ADIF 3.1.7 submode to its required parent mode.
    /// Used to validate that a SUBMODE field is legal for the accompanying MODE.
    /// Sourced from the shared Rust catalog (`cw_domain::adif_catalog`).
    static var submodeParents: [String: String] {
        var result: [String: String] = [:]
        for entry in adifSubmodeParents() {
            result[entry.submode] = entry.parentMode
        }
        return result
    }

    /// Fast lookup: given a submode code, return the required parent mode (or nil if unknown).
    static func parentMode(forSubmode submode: String) -> String? {
        adifParentModeForSubmode(submode: submode)
    }

    /// Check whether a code is a recognized submode of any parent mode.
    static func isSubmode(_ code: String) -> Bool {
        adifIsSubmode(code: code)
    }
}
