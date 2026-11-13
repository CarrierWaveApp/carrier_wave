// Polling Coordinator
//
// Centralizes all periodic network polling behind a single timer tick.
// Services register closures with a tick multiplier; the coordinator fires
// all due work in one burst so the CPU/radio can sleep between ticks.

import UIKit

// MARK: - PollingCoordinator

@MainActor
@Observable
final class PollingCoordinator {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = PollingCoordinator()

    /// Base tick interval in seconds
    static let tickInterval: TimeInterval = 60

    /// Whether the coordinator is actively ticking
    private(set) var isRunning = false

    /// Number of active registrations
    var registrationCount: Int {
        registrations.count
    }

    /// Register a polling closure.
    /// - Parameters:
    ///   - id: Unique identifier for this registration
    ///   - interval: Number of ticks between invocations (1 = every 60s, 2 = every 120s)
    ///   - fireImmediately: Fire the closure as soon as it's registered (default true). When false,
    ///     the closure first runs at the next tick that aligns with `interval`.
    ///   - action: Async closure to execute
    func register(
        id: String,
        every interval: Int,
        fireImmediately: Bool = true,
        action: @escaping () async -> Void
    ) {
        let registration = Registration(
            id: id,
            interval: max(1, interval),
            fireImmediately: false,
            action: action
        )
        registrations[id] = registration

        SyncDebugLog.shared.info(
            "PollingCoordinator: registered '\(id)' every \(interval) ticks (\(interval * 60)s)"
        )

        // Fire right away rather than waiting up to a full tick interval (60s) for the
        // next coordinator tick. Without this, view-driven registrations (e.g. opening
        // the hunter log) appear "stuck loading" until the polling loop next wakes.
        if fireImmediately {
            let taskId = id
            runningTasks[id] = Task {
                await action()
                self.runningTasks[taskId] = nil
            }
        }
    }

    /// Remove a registration
    func unregister(id: String) {
        registrations.removeValue(forKey: id)
        runningTasks.removeValue(forKey: id)

        SyncDebugLog.shared.info(
            "PollingCoordinator: unregistered '\(id)'"
        )
    }

    /// Start the coordinator (call at app launch)
    func start() {
        guard !isRunning else {
            return
        }
        isRunning = true
        tickCount = 0
        startTickLoop()
    }

    /// Pause the coordinator (scene goes background)
    func pause() {
        isRunning = false
        tickTask?.cancel()
        tickTask = nil
    }

    /// Resume the coordinator (scene goes foreground).
    /// Fires all due registrations immediately, then resumes the tick loop.
    func resume() {
        guard !isRunning else {
            return
        }
        isRunning = true

        // Mark all registrations as fireImmediately so the next tick runs them
        for id in registrations.keys {
            registrations[id]?.fireImmediately = true
        }

        startTickLoop()
    }

    // MARK: Private

    private var tickCount: Int = 0
    private var tickTask: Task<Void, Never>?
    private var registrations: [String: Registration] = [:]

    /// Tracks in-flight tasks per registration (skip-if-busy)
    private var runningTasks: [String: Task<Void, Never>] = [:]

    private func startTickLoop() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            guard let self else {
                return
            }
            while !Task.isCancelled, isRunning {
                fireDueRegistrations()
                tickCount += 1

                try? await Task.sleep(for: .seconds(Self.tickInterval))
            }
        }
    }

    private func fireDueRegistrations() {
        for (id, registration) in registrations {
            let shouldFire: Bool
            if registration.fireImmediately {
                shouldFire = true
                registrations[id]?.fireImmediately = false
            } else {
                shouldFire = tickCount > 0 && tickCount.isMultiple(of: registration.interval)
            }

            guard shouldFire else {
                continue
            }

            // Skip if previous invocation is still running
            if let existing = runningTasks[id], !existing.isCancelled {
                continue
            }

            let action = registration.action
            let taskId = id
            runningTasks[id] = Task {
                await action()
                self.runningTasks[taskId] = nil
            }
        }
    }
}

// MARK: PollingCoordinator.Registration

extension PollingCoordinator {
    struct Registration {
        let id: String
        let interval: Int
        var fireImmediately: Bool
        let action: () async -> Void
    }
}
