import Foundation

// MARK: - MultiCallsignLookupState

/// Represents the lookup state for a single callsign in a multi-callsign entry
enum MultiCallsignLookupState: Equatable {
    /// Lookup is in progress
    case loading(callsign: String)
    /// Lookup completed with a result
    case found(info: CallsignInfo, previousQSOCount: Int)
    /// Callsign was not found in any lookup source
    case notFound(callsign: String)
    /// Lookup failed with an error
    case error(callsign: String, error: CallsignLookupError)

    // MARK: Internal

    /// The callsign associated with this lookup state
    var callsign: String {
        switch self {
        case let .loading(callsign):
            callsign
        case let .found(info, _):
            info.callsign
        case let .notFound(callsign):
            callsign
        case let .error(callsign, _):
            callsign
        }
    }

    /// The lookup info if available
    var info: CallsignInfo? {
        if case let .found(info, _) = self {
            return info
        }
        return nil
    }

    /// The previous QSO count if available
    var previousQSOCount: Int {
        if case let .found(_, count) = self {
            return count
        }
        return 0
    }

    /// Whether the lookup is still in progress
    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }
}
