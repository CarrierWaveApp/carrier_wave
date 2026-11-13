import Foundation

extension Notification.Name {
    /// Broadcast by `QueryWorkbenchModel` after any CRUD on the saved
    /// query store. Band scope pickers listen for this so their
    /// "valid query" caches re-validate immediately after a user
    /// fixes a query in the workbench.
    static let savedQueriesChanged = Notification.Name("CWSweep.savedQueriesChanged")
}

// MARK: - BandScopeFilterMode

/// How the band scope decides which spots to render. Either the existing
/// widget-based filter (sources/region/status/age) or a user-selected
/// saved SQL query whose result set is treated as the allow-list of
/// `spot_id`s. Persisted via @AppStorage on `BandMapView`.
enum BandScopeFilterMode: Equatable, RawRepresentable {
    case widgets
    case savedQuery(UUID)

    // MARK: Lifecycle

    init?(rawValue: String) {
        if rawValue == "widgets" {
            self = .widgets
            return
        }
        if rawValue.hasPrefix("savedQuery:"),
           let uuid = UUID(uuidString: String(rawValue.dropFirst("savedQuery:".count)))
        {
            self = .savedQuery(uuid)
            return
        }
        return nil
    }

    // MARK: Internal

    var rawValue: String {
        switch self {
        case .widgets: "widgets"
        case let .savedQuery(uuid): "savedQuery:\(uuid.uuidString)"
        }
    }

    var savedQueryID: UUID? {
        if case let .savedQuery(uuid) = self {
            return uuid
        }
        return nil
    }
}

// MARK: - SpotStatusFilter

/// Filter spots by their worked/needed status
enum SpotStatusFilter: String, CaseIterable, Identifiable, Codable {
    case all
    case newOnly
    case neededOnly
    case newAndNeeded

    // MARK: Internal

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .all: "All"
        case .newOnly: "New"
        case .neededOnly: "Needed"
        case .newAndNeeded: "New + Needed"
        }
    }

    /// Whether a spot with the given needed status passes this filter
    func matches(status: NeededStatus, isWorkedToday: Bool) -> Bool {
        switch self {
        case .all:
            true
        case .newOnly:
            !isWorkedToday
        case .neededOnly:
            status == .newEntity || status == .newBandSlot
        case .newAndNeeded:
            !isWorkedToday || status == .newEntity || status == .newBandSlot
        }
    }
}

// MARK: - BandScopeFilterConfig

/// Persisted filter configuration for the band scope.
/// Each field maps to an @AppStorage key in BandMapView.
/// This struct provides defaults per operating role and
/// helper methods for applying filters to spots.
enum BandScopeFilterConfig {
    /// Default enabled sources for an operating role
    static func defaultSources(for role: OperatingRole) -> Set<SpotSource> {
        switch role {
        case .hunter:
            Set(SpotSource.allCases)
        case .activator:
            [.pota, .sota, .wwff, .cluster]
        }
    }

    /// Default max age in minutes for an operating role
    static func defaultMaxAge(for role: OperatingRole) -> Int {
        switch role {
        case .hunter: 30
        case .activator: 30
        }
    }

    /// Default status filter for an operating role
    static func defaultStatusFilter(for role: OperatingRole) -> SpotStatusFilter {
        switch role {
        case .hunter: .all
        case .activator: .all
        }
    }
}
