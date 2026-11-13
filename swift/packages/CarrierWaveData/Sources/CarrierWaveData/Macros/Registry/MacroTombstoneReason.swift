import Foundation

// MARK: - MacroTombstoneReason

/// Canonical tombstone reasons the server can emit, plus the locally
/// authored "user-deleted" reason used by the Mine-tab swipe-to-delete.
/// The string values match what the server stores so the polling actor
/// can stamp them onto `RadioMacro.tombstoneReason` without translation.
public enum MacroTombstoneReason: String, Sendable, CaseIterable {
    case withdrawn
    case adminRemoved = "admin_removed"
    case authorDeleted = "author_deleted"
    case userDeleted = "user-deleted"

    // MARK: Public

    public var headlineLabel: String {
        switch self {
        case .withdrawn: "Withdrawn by author"
        case .adminRemoved: "Removed by moderators"
        case .authorDeleted: "Author deleted account"
        case .userDeleted: "Deleted from library"
        }
    }

    /// `true` when the tombstone originated server-side and the row
    /// should still be visible in the Mine tab so the user can decide
    /// whether to delete it locally or keep it as a read-only artifact.
    public var isServerOriginated: Bool {
        switch self {
        case .withdrawn,
             .adminRemoved,
             .authorDeleted: true
        case .userDeleted: false
        }
    }

    /// Best-effort parse — unknown reason strings get the most generic
    /// label so we never crash on a future server reason.
    public static func from(raw: String?) -> MacroTombstoneReason? {
        guard let raw else {
            return nil
        }
        return Self(rawValue: raw)
    }
}
