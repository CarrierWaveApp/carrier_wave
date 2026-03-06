// Callsign Notes Source Config
//
// Codable configuration for callsign notes file sources.
// Synced between devices via iCloud KVS.
// Shared between Carrier Wave (iOS) and CW Sweep (macOS).

import Foundation

// MARK: - CallsignNotesSourceConfig

/// Codable subset of callsign notes source for iCloud KVS sync.
/// Only syncs configuration (id, title, url, isEnabled), not transient
/// device-local state (lastFetched, entryCount, lastError).
public struct CallsignNotesSourceConfig: Codable, Equatable, Sendable, Identifiable {
    // MARK: Lifecycle

    public init(id: UUID = UUID(), title: String, url: String, isEnabled: Bool = true) {
        self.id = id
        self.title = title
        self.url = url
        self.isEnabled = isEnabled
    }

    // MARK: Public

    public var id: UUID
    public var title: String
    public var url: String
    public var isEnabled: Bool
}
