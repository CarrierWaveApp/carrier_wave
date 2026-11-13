// DONKI Polling Service
//
// Polls NASA DONKI space weather API every 30 minutes.
// Tracks active events and notifies SpaceWeatherNotifier of new ones.

import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - DONKIPollingService

@MainActor
@Observable
final class DONKIPollingService {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = DONKIPollingService()

    static let settingsKey = "spaceWeatherAlertsEnabled"

    /// Currently active space weather events
    private(set) var activeEvents: [DONKIEvent] = []

    /// Worst impact level among active events
    var worstActiveImpact: RadioImpactLevel {
        activeEvents.map(\.radioImpact).max() ?? .none
    }

    /// Configure the service. Call once at startup.
    func configure(container: ModelContainer) {
        self.container = container
        startIfEnabled()
    }

    /// Start polling if the user setting is enabled, otherwise stop.
    func startIfEnabled() {
        let enabled = UserDefaults.standard.object(
            forKey: Self.settingsKey
        ) == nil
            || UserDefaults.standard.bool(forKey: Self.settingsKey)

        if enabled {
            start()
        } else {
            stop()
        }
    }

    // MARK: Private

    /// Polling interval: 30 minutes
    private let pollingInterval: TimeInterval = 1_800

    private var container: ModelContainer?
    private var pollingTask: Task<Void, Never>?
    private var isPolling = false
    private let client = DONKIClient()

    /// Previously seen event IDs for diffing
    private var previousEventIDs: Set<String> = []
    private var hasPolledOnce = false

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
        await fetchAndNotify()

        while !Task.isCancelled, isPolling {
            try? await Task.sleep(for: .seconds(pollingInterval))

            guard !Task.isCancelled, isPolling else {
                break
            }

            // Re-check setting each iteration
            let enabled = UserDefaults.standard.object(
                forKey: Self.settingsKey
            ) == nil
                || UserDefaults.standard.bool(forKey: Self.settingsKey)
            guard enabled else {
                stop()
                break
            }

            await fetchAndNotify()
        }
    }

    private func fetchAndNotify() async {
        let events = await client.fetchActiveEvents(lookbackDays: 3)
        let currentIDs = Set(events.map(\.eventID))
        let isFirstPoll = previousEventIDs.isEmpty && !hasPolledOnce

        // Find newly appeared events
        let newIDs = currentIDs.subtracting(previousEventIDs)
        let newEvents = events.filter { newIDs.contains($0.eventID) }

        // Update state
        activeEvents = events
        previousEventIDs = currentIDs
        hasPolledOnce = true

        WidgetDataWriter.writeSpaceWeather(buildWidgetSnapshot(events: events))

        // Skip notifications on first poll to avoid flooding
        // with existing events. Only notify for events that
        // appear after the initial fetch.
        guard !isFirstPoll else {
            return
        }

        for event in newEvents {
            SpaceWeatherNotifier.shared.notify(event: event)
        }
    }

    private func buildWidgetSnapshot(
        events: [DONKIEvent]
    ) -> WidgetSpaceWeatherSnapshot {
        let worst = events.max { $0.radioImpact < $1.radioImpact }
        let impact = worst?.radioImpact ?? .none
        let headline = if let worst {
            "\(worst.typeName): \(impact.label)"
        } else {
            "All quiet"
        }
        return WidgetSpaceWeatherSnapshot(
            worstImpactRaw: impact.rawValue,
            eventCount: events.count,
            headline: headline,
            icon: worst?.typeIcon ?? "checkmark.shield.fill",
            updatedAt: Date()
        )
    }
}
