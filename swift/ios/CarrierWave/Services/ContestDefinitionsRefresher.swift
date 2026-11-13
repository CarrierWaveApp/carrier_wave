import CarrierWaveData
import OSLog
import UIKit

// MARK: - ContestDefinitions

/// Shared access to the Rust contest-definition cache (`ContestApi` over the
/// encrypted FieldStore). Replaces the old `ContestDefinitionsStore` disk
/// cache — fetch, parse, and storage all live in the core now.
enum ContestDefinitions {
    // MARK: Internal

    /// The shared `ContestApi` over the app's FieldStore + activities base URL.
    static func api() async throws -> ContestApi {
        if let api = await Holder.shared.api {
            return api
        }
        let store = try await CwStoreProvider.shared.store()
        let baseURL = ActivitiesClient.normalizeBase(ActivitiesClient.resolvedBaseURL)
        let api = try ContestApi(store: store, baseUrl: baseURL)
        await Holder.shared.set(api)
        return api
    }

    /// Cached summaries, name-sorted. Empty when the cache is cold.
    static func allSummaries() async -> [ContestDefinitionSummary] {
        await (try? api().summaries()) ?? []
    }

    /// All cached full definitions, name-sorted.
    static func allDefinitions() async -> [ContestDefinition] {
        await allSummaries().asyncCompactMap { summary in
            await definition(id: summary.id)
        }
    }

    /// A cached definition by contest id.
    static func definition(id: String) async -> ContestDefinition? {
        guard let api = try? await api() else {
            return nil
        }
        return try? api.definition(id: id)
    }

    // MARK: Private

    private actor Holder {
        static let shared = Holder()

        private(set) var api: ContestApi?

        func set(_ api: ContestApi) {
            self.api = api
        }
    }
}

private extension Array {
    func asyncCompactMap<T>(_ transform: (Element) async -> T?) async -> [T] {
        var result: [T] = []
        result.reserveCapacity(count)
        for element in self {
            if let value = await transform(element) {
                result.append(value)
            }
        }
        return result
    }
}

// MARK: - ContestDefinitionsRefresher

/// Observable wrapper that coordinates refreshing contest definitions from
/// the activities server into the Rust cache. Exposes the cached summaries
/// and state to SwiftUI views.
@MainActor
@Observable
final class ContestDefinitionsRefresher {
    // MARK: Lifecycle

    init() {}

    // MARK: Internal

    /// Minimum interval between automatic refreshes (24h).
    static let automaticRefreshInterval: TimeInterval = 24 * 60 * 60

    private(set) var summaries: [ContestDefinitionSummary] = []
    private(set) var definitions: [ContestDefinition] = []
    private(set) var isRefreshing: Bool = false
    private(set) var lastRefreshed: Date?
    private(set) var lastError: String?

    /// Load currently cached summaries and full definitions.
    func loadFromCache() async {
        summaries = await ContestDefinitions.allSummaries()
        definitions = await ContestDefinitions.allDefinitions()
        lastRefreshed = summaries
            .map(\.lastSyncedAt)
            .min()
            .map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    /// Kick off a refresh if the cache is empty or older than
    /// `automaticRefreshInterval`. Call this on app foreground or whenever
    /// the user opens the contest picker.
    func refreshIfStale() async {
        await loadFromCache()
        if summaries.isEmpty {
            await refresh()
            return
        }
        guard let last = lastRefreshed else {
            await refresh()
            return
        }
        if Date().timeIntervalSince(last) > Self.automaticRefreshInterval {
            await refresh()
        }
    }

    /// Force a refresh from the server.
    func refresh() async {
        if isRefreshing {
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let api = try await ContestDefinitions.api()
            let result = try await api.refresh()
            await loadFromCache()
            lastRefreshed = Date()
            lastError = nil
            let missing = Int(result.total - result.fetched)
            if missing > 0 {
                Self.logger.warning(
                    "\(missing) contest(s) failed to fetch; displaying cached copies"
                )
            }
            Self.logger.info("Refreshed \(result.fetched) contest definitions")
        } catch {
            lastError = error.localizedDescription
            Self.logger.error("Contest refresh failed: \(error.localizedDescription)")
        }
    }

    /// Look up a full definition by id. Falls through to a live refresh when
    /// the cache doesn't have it yet.
    func definition(id: String) async -> ContestDefinition? {
        if let cached = await ContestDefinitions.definition(id: id) {
            return cached
        }
        await refresh()
        return await ContestDefinitions.definition(id: id)
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CarrierWave",
        category: "ContestDefinitions"
    )
}
