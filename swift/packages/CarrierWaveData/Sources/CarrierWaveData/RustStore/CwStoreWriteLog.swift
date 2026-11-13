import Foundation

/// In-memory ring buffer of cw-store write-path diagnostics, surfaced in the
/// Data Migration screen. The write seam records failures here (the iOS logging
/// rule forbids `os_log`/`print` from app code). Capped so it never grows
/// unbounded. Not persisted — diagnostics for the current session only.
///
/// Hoisted into `CarrierWaveData` so both the iOS app and CW Sweep share one
/// diagnostics buffer (the cw-store mirror lives here too).
@MainActor
public final class CwStoreWriteLog {
    // MARK: Public

    public static let shared = CwStoreWriteLog()

    public private(set) var entries: [String] = []

    public func record(_ message: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        entries.append("\(stamp)  \(message)")
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
    }

    // MARK: Private

    private let limit = 50
}
