import CarrierWaveData
import Foundation
import OSLog

// MARK: - ContestDefinitions

/// Shared access to the Rust contest-definition cache (`ContestApi` over the
/// encrypted FieldStore). Replaces the old `ContestDefinitionsStore` disk
/// cache + `ContestClient` — fetch, parse, and storage all live in the core.
enum ContestDefinitions {
    // MARK: Internal

    nonisolated static let defaultURL = "https://activities.carrierwave.app"

    /// Resolved base URL, respecting the developer override if set.
    nonisolated static var resolvedBaseURL: String {
        let override = UserDefaults.standard.string(forKey: "activitiesServerURLOverride") ?? ""
        let base = override.isEmpty ? defaultURL : override
        var result = base
        while result.hasSuffix("/") {
            result = String(result.dropLast())
        }
        return result
    }

    /// The shared `ContestApi` over the app's FieldStore + activities base URL.
    static func api() async throws -> ContestApi {
        if let api = await Holder.shared.api {
            return api
        }
        let store = try await CwStoreProvider.shared.store()
        let api = try ContestApi(store: store, baseUrl: resolvedBaseURL)
        await Holder.shared.set(api)
        return api
    }

    /// Cached summaries, name-sorted. Empty when the cache is cold.
    static func allSummaries() async -> [ContestDefinitionSummary] {
        await (try? api().summaries()) ?? []
    }

    /// All cached full definitions, name-sorted.
    static func allDefinitions() async -> [ContestDefinition] {
        var definitions: [ContestDefinition] = []
        for summary in await allSummaries() {
            if let definition = await definition(id: summary.id) {
                definitions.append(definition)
            }
        }
        return definitions
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
        subsystem: Bundle.main.bundleIdentifier ?? "CWSweep",
        category: "ContestDefinitions"
    )
}
