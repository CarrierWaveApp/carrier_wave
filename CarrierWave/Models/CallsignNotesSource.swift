// Callsign Notes Source Model
//
// SwiftData model for user-configured callsign notes file sources.
// These are URLs to Polo-style notes files that get fetched and cached.
// Synced between devices via iCloud KVS (SettingsSyncService).

import CarrierWaveData
import Foundation
import SwiftData

// MARK: - CallsignNotesSource

@Model
nonisolated final class CallsignNotesSource {
    // MARK: Lifecycle

    init(title: String, url: String) {
        id = UUID()
        self.title = title
        self.url = url
        isEnabled = true
        lastFetched = nil
        entryCount = 0
        lastError = nil
    }

    // MARK: Internal

    /// Unique identifier
    var id = UUID()

    /// Display name for this source (e.g., "POTA Activators")
    var title = ""

    /// URL to the notes file
    var url = ""

    /// Whether this source is enabled for lookups
    var isEnabled: Bool = true

    /// When this source was last successfully fetched
    var lastFetched: Date?

    /// Number of callsign entries parsed from this source
    var entryCount: Int = 0

    /// Last error message (if fetch failed)
    var lastError: String?

    /// Whether the source needs refresh (older than 1 day)
    var needsRefresh: Bool {
        guard let lastFetched else {
            return true
        }
        let oneDayAgo = Date().addingTimeInterval(-24 * 60 * 60)
        return lastFetched < oneDayAgo
    }

    /// Formatted last fetched string
    var lastFetchedDescription: String? {
        guard let lastFetched else {
            return nil
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastFetched, relativeTo: Date())
    }
}

// MARK: - CallsignNotesSourceConfig

/// Codable subset of CallsignNotesSource for iCloud KVS sync.
/// Only syncs configuration (id, title, url, isEnabled), not transient
/// device-local state (lastFetched, entryCount, lastError).
struct CallsignNotesSourceConfig: Codable, Equatable {
    var id: UUID
    var title: String
    var url: String
    var isEnabled: Bool
}

// MARK: - CallsignNotesSourceSync

/// Bridges CallsignNotesSource (SwiftData) with UserDefaults for iCloud KVS sync.
@MainActor
enum CallsignNotesSourceSync {
    static let defaultsKey = "callsignNotesSources"

    /// Serialize current SwiftData sources to UserDefaults.
    static func mirrorToDefaults(modelContext: ModelContext) {
        do {
            let descriptor = FetchDescriptor<CallsignNotesSource>(
                sortBy: [SortDescriptor(\.title)]
            )
            let sources = try modelContext.fetch(descriptor)
            let configs = sources.map {
                CallsignNotesSourceConfig(
                    id: $0.id,
                    title: $0.title,
                    url: $0.url,
                    isEnabled: $0.isEnabled
                )
            }
            if let data = try? JSONEncoder().encode(configs) {
                UserDefaults.standard.set(data, forKey: defaultsKey)
            }
        } catch {
            // Sync is best-effort
        }
    }

    /// Read UserDefaults and reconcile with SwiftData.
    /// Adds new sources, updates changed ones, removes deleted ones.
    static func reconcileFromDefaults(modelContext: ModelContext) {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let configs = try? JSONDecoder().decode(
                  [CallsignNotesSourceConfig].self,
                  from: data
              )
        else {
            return
        }

        do {
            let descriptor = FetchDescriptor<CallsignNotesSource>()
            let existing = try modelContext.fetch(descriptor)
            let existingById = Dictionary(
                uniqueKeysWithValues: existing.map { ($0.id, $0) }
            )
            let configIds = Set(configs.map(\.id))

            for config in configs {
                if let source = existingById[config.id] {
                    if source.title != config.title {
                        source.title = config.title
                    }
                    if source.url != config.url {
                        source.url = config.url
                    }
                    if source.isEnabled != config.isEnabled {
                        source.isEnabled = config.isEnabled
                    }
                } else {
                    let newSource = CallsignNotesSource(
                        title: config.title,
                        url: config.url
                    )
                    newSource.id = config.id
                    newSource.isEnabled = config.isEnabled
                    modelContext.insert(newSource)
                }
            }

            for source in existing where !configIds.contains(source.id) {
                modelContext.delete(source)
            }

            try modelContext.save()
        } catch {
            // Sync is best-effort
        }
    }
}
