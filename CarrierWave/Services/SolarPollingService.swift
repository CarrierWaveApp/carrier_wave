import Foundation
import SwiftData

/// Background service that polls solar conditions every hour and persists
/// snapshots as `SolarSnapshot` records. Runs while the app is in the foreground.
///
/// Follows the `SpotMonitoringService` pattern: `@MainActor @Observable` singleton
/// with a Task-based poll loop.
@MainActor
@Observable
final class SolarPollingService {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = SolarPollingService()

    static let settingsKey = "solarPollingEnabled"

    /// Whether polling is currently active
    private(set) var isPolling = false

    /// Configure the service with the app's model container. Call once at startup.
    func configure(container: ModelContainer) {
        self.container = container
        startIfEnabled()
    }

    /// Start polling if the user setting is enabled, otherwise stop.
    func startIfEnabled() {
        let enabled = UserDefaults.standard.object(forKey: Self.settingsKey) == nil
            || UserDefaults.standard.bool(forKey: Self.settingsKey)

        if enabled {
            start()
        } else {
            stop()
        }
    }

    // MARK: Private

    /// Polling interval: 1 hour
    private let pollingInterval: TimeInterval = 3_600

    /// Dedup window: skip insert if a snapshot exists within last 30 minutes
    private let dedupWindow: TimeInterval = 1_800

    private var container: ModelContainer?
    private var pollingTask: Task<Void, Never>?

    private func start() {
        guard !isPolling, container != nil else {
            return
        }
        isPolling = true
        pollingTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    private func stop() {
        isPolling = false
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func pollLoop() async {
        // Initial fetch
        await fetchAndStore()

        while !Task.isCancelled, isPolling {
            try? await Task.sleep(for: .seconds(pollingInterval))

            guard !Task.isCancelled, isPolling else {
                break
            }

            // Re-check setting each iteration
            let enabled = UserDefaults.standard.object(forKey: Self.settingsKey) == nil
                || UserDefaults.standard.bool(forKey: Self.settingsKey)
            guard enabled else {
                stop()
                break
            }

            await fetchAndStore()
        }
    }

    private func fetchAndStore() async {
        guard let container else {
            return
        }

        do {
            let solar = try await NOAAClient().fetchSolarConditions()

            // Persist on a background context
            let context = ModelContext(container)
            context.autosaveEnabled = false

            // Dedup: skip if a snapshot exists within the last 30 minutes
            let cutoff = Date().addingTimeInterval(-dedupWindow)
            var descriptor = FetchDescriptor<SolarSnapshot>(
                predicate: #Predicate<SolarSnapshot> { $0.timestamp >= cutoff }
            )
            descriptor.fetchLimit = 1

            let recentCount = (try? context.fetchCount(descriptor)) ?? 0
            guard recentCount == 0 else {
                return
            }

            let snapshot = SolarSnapshot(
                timestamp: solar.timestamp,
                kIndex: solar.kIndex,
                aIndex: solar.aIndex,
                solarFlux: solar.solarFlux,
                sunspots: solar.sunspots,
                propagationRating: solar.propagationRating,
                bandConditions: solar.bandConditions
            )
            context.insert(snapshot)
            try context.save()

            // Write to App Group for Watch/widget consumption
            WidgetDataWriter.writeSolar(WidgetSolarSnapshot(
                kIndex: solar.kIndex,
                aIndex: solar.aIndex,
                solarFlux: solar.solarFlux,
                sunspots: solar.sunspots,
                propagationRating: solar.propagationRating,
                updatedAt: Date()
            ))
        } catch {
            // Network or save failed — retry next interval
        }
    }
}
