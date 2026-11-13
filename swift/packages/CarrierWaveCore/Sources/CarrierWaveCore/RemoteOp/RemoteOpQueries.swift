import Foundation

//
// Split out of RemoteOpProtocol.swift to keep that file under SwiftLint's
// 500-line cap. These messages let an iOS client see the saved queries
// Sweep knows about and switch the band-scope filter to widgets or to a
// specific query.

// MARK: - RemoteSavedQuery

/// Wire-format saved query. `drivesBandScope` is true when Sweep has
/// validated that the SQL emits a `spot_id` column — only those queries can
/// be picked as the band-scope filter.
public struct RemoteSavedQuery: Codable, Sendable, Equatable, Identifiable {
    // MARK: Lifecycle

    public init(id: UUID, name: String, summary: String, drivesBandScope: Bool) {
        self.id = id
        self.name = name
        self.summary = summary
        self.drivesBandScope = drivesBandScope
    }

    // MARK: Public

    public let id: UUID
    public let name: String
    public let summary: String
    public let drivesBandScope: Bool
}

// MARK: - RemoteFilterMode

/// Mirrors the macOS `BandScopeFilterMode`.
public enum RemoteFilterMode: Codable, Sendable, Equatable {
    case widgets
    case savedQuery(UUID)
}

// MARK: - QueriesListEvent

public struct QueriesListEvent: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(queries: [RemoteSavedQuery]) {
        self.queries = queries
    }

    // MARK: Public

    public let queries: [RemoteSavedQuery]
}

// MARK: - QuerySelectionEvent

public struct QuerySelectionEvent: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(mode: RemoteFilterMode) {
        self.mode = mode
    }

    // MARK: Public

    public let mode: RemoteFilterMode
}

// MARK: - SetQuerySelectionCommand

public struct SetQuerySelectionCommand: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(requestID: UUID = UUID(), mode: RemoteFilterMode) {
        self.requestID = requestID
        self.mode = mode
    }

    // MARK: Public

    public let requestID: UUID
    public let mode: RemoteFilterMode
}
