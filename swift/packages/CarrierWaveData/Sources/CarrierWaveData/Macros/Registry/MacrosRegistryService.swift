import Foundation
import OSLog
import SwiftData

// MARK: - MacrosRegistrySnapshot

/// Lightweight, Sendable snapshot of the last successful poll. UI surfaces
/// (Updates tab, Mine tab badges) read from this rather than touching the
/// SwiftData store from the actor.
public struct MacrosRegistrySnapshot: Sendable, Equatable {
    public static let empty = MacrosRegistrySnapshot(pendingUpdates: [:], lastSeen: nil, polledAt: nil)

    /// Server's latest known version per installed slug. Only contains
    /// entries where the server version > the local registry version.
    public let pendingUpdates: [String: RegistryVersionInfo]
    /// Tombstones applied during the last poll (cumulative across runs).
    public let lastSeen: Date?
    /// Wall clock for the most recent successful poll.
    public let polledAt: Date?
}

// MARK: - MacrosRegistryService

/// Foreground-debounced polling service that keeps locally installed
/// macros in sync with the registry — surfacing updates and propagating
/// tombstones. The actor never mutates UI state directly; views read the
/// `snapshot` value to decide what badges/diffs to show.
public actor MacrosRegistryService {
    // MARK: Lifecycle

    public init(
        client: MacrosRegistryClient,
        container: ModelContainer,
        tombstoneStore: TombstoneStore = UserDefaultsTombstoneStore(),
        pollInterval: TimeInterval = 30 * 60
    ) {
        self.client = client
        self.container = container
        self.tombstoneStore = tombstoneStore
        self.pollInterval = pollInterval
    }

    // MARK: Public

    public private(set) var snapshot: MacrosRegistrySnapshot = .empty

    /// Force the next call to `pollIfStale` to run, ignoring the debounce.
    /// The "Pull-to-refresh" action and the Updates tab onAppear use this.
    public func invalidateDebounce() {
        lastPoll = nil
    }

    /// Hits both registry endpoints if enough time has passed since the
    /// last successful poll. Returns the produced snapshot.
    @discardableResult
    public func pollIfStale(now: Date = Date()) async throws -> MacrosRegistrySnapshot {
        if let last = lastPoll, now.timeIntervalSince(last) < pollInterval {
            return snapshot
        }

        let installed = try fetchInstalledSlugs()
        let slugs = installed.map(\.slug)
        guard !slugs.isEmpty else {
            // No installed registry macros — still bump lastPoll so we don't
            // hammer on every foreground when the user has nothing to sync.
            lastPoll = now
            snapshot = MacrosRegistrySnapshot(
                pendingUpdates: [:],
                lastSeen: tombstoneStore.lastSeen,
                polledAt: now
            )
            return snapshot
        }

        async let versionsTask = client.versions(slugs: slugs)
        async let tombstoneTask = client.tombstones(since: tombstoneStore.lastSeen)
        let serverVersions: [String: RegistryVersionInfo]
        let tombstoneResponse: RegistryTombstonesResponse
        do {
            (serverVersions, tombstoneResponse) = try await (versionsTask, tombstoneTask)
        } catch {
            Self.logger.error("registry poll failed: \(String(describing: error), privacy: .public)")
            throw error
        }

        let pendingUpdates = installed.reduce(into: [String: RegistryVersionInfo]()) { acc, row in
            if let info = serverVersions[row.slug], info.version > row.localVersion {
                acc[row.slug] = info
            }
        }

        try applyTombstones(tombstoneResponse.entries)
        if let newest = tombstoneResponse.entries.map(\.tombstonedAt).max() {
            tombstoneStore.setLastSeen(newest)
        }

        lastPoll = now
        snapshot = MacrosRegistrySnapshot(
            pendingUpdates: pendingUpdates,
            lastSeen: tombstoneStore.lastSeen,
            polledAt: now
        )
        return snapshot
    }

    // MARK: Private

    private struct InstalledRow {
        let slug: String
        let localVersion: Int
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CarrierWave",
        category: "MacrosRegistryService"
    )

    private let client: MacrosRegistryClient
    private let container: ModelContainer
    private let tombstoneStore: TombstoneStore
    private let pollInterval: TimeInterval

    private var lastPoll: Date?
    private var modelContext: ModelContext?

    private func ensureModelContext() -> ModelContext {
        if let modelContext {
            return modelContext
        }
        let context = ModelContext(container)
        modelContext = context
        return context
    }

    private func fetchInstalledSlugs() throws -> [InstalledRow] {
        let context = ensureModelContext()
        let descriptor = FetchDescriptor<RadioMacro>()
        let macros = try context.fetch(descriptor)
        return macros.compactMap { macro in
            guard let registry = macro.registry else {
                return nil
            }
            return InstalledRow(slug: registry.slug, localVersion: registry.registryVersion)
        }
    }

    private func applyTombstones(_ entries: [RegistryTombstoneEntry]) throws {
        guard !entries.isEmpty else {
            return
        }
        let context = ensureModelContext()
        let macros = try context.fetch(FetchDescriptor<RadioMacro>())
        var changed = false
        for entry in entries {
            guard let macro = macros.first(where: { $0.registry?.slug == entry.slug }) else {
                continue
            }
            if !macro.tombstoned || macro.tombstoneReason != entry.reason {
                macro.tombstoned = true
                macro.tombstoneReason = entry.reason
                macro.updatedAt = Date()
                changed = true
            }
        }
        if changed {
            try context.save()
        }
    }
}
