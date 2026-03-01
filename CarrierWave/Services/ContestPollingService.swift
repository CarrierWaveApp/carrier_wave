import Foundation

/// Background service that polls the WA7BNM Contest Calendar every 6 hours.
/// In-memory only — no SwiftData persistence needed.
///
/// Mirrors the `SolarPollingService` pattern: `@MainActor @Observable` singleton
/// with a Task-based poll loop.
@MainActor
@Observable
final class ContestPollingService {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = ContestPollingService()

    static let settingsKey = "contestPollingEnabled"

    /// Currently-running contests
    private(set) var activeContests: [Contest] = []

    /// Contests that haven't started yet
    private(set) var upcomingContests: [Contest] = []

    /// When the last successful fetch occurred
    private(set) var lastFetchDate: Date?

    /// Error message from the most recent fetch attempt
    private(set) var fetchError: String?

    /// Whether polling is currently active
    private(set) var isPolling = false

    /// Configure the service. Call once at startup.
    func configure() {
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

    /// Polling interval: 6 hours
    private let pollingInterval: TimeInterval = 21_600

    private var pollingTask: Task<Void, Never>?
    private let client = ContestCalendarClient()

    private func start() {
        guard !isPolling else {
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
        await fetchContests()

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

            await fetchContests()
        }
    }

    private func fetchContests() async {
        do {
            let contests = try await client.fetchContests()
            updateContests(contests)
            lastFetchDate = Date()
            fetchError = nil
        } catch is CancellationError {
            // Task cancelled — don't update state
        } catch let error as ContestCalendarError {
            switch error {
            case .notModified:
                // Server says content unchanged — keep existing data
                lastFetchDate = Date()
                fetchError = nil
            case .rateLimited:
                // Silently wait for next interval
                break
            default:
                fetchError = error.localizedDescription
            }
        } catch {
            fetchError = error.localizedDescription
        }
    }

    private func updateContests(_ contests: [Contest]) {
        activeContests = contests
            .filter(\.isActive)
            .sorted { $0.endDate < $1.endDate }

        upcomingContests = contests
            .filter(\.isUpcoming)
            .sorted { $0.startDate < $1.startDate }
    }
}
