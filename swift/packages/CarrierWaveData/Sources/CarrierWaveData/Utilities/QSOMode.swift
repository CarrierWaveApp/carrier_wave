import Foundation

// MARK: - QSOMode

/// Shared constants for QSO mode classification.
public enum QSOMode {
    /// Pseudo-modes Ham2K PoLo writes into the operation log when the operator
    /// types a command into the "Their Call" field. PoLo stores each as a
    /// QSO-shaped row whose `mode` is the command word:
    ///
    /// - `WEATHER` / `SOLAR` — conditions snapshot (annotation)
    /// - `NOTE` and the to-do marker — free-form annotations
    /// - `START` — activation timer start marker
    /// - `BREAK` — location/line break marker (rove operations)
    ///
    /// These are NOT actual QSOs and must be excluded from sync, uploads,
    /// pending-upload counts, statistics, maps, and all user-facing aggregation.
    /// This set is the single source of truth (CAR-278) — never hardcode the
    /// literals elsewhere.
    public static let metadataModes: Set<String> = [
        "WEATHER", "SOLAR", "NOTE", "TODO", "START", "BREAK",
    ]

    /// Returns true if the given mode represents activation metadata rather than a real QSO.
    public static func isMetadata(_ mode: String) -> Bool {
        metadataModes.contains(mode.uppercased())
    }
}
