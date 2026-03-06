// Network Health Monitor
//
// Tracks network connectivity and detects degraded states where the device
// appears connected but web requests consistently fail. Reports a unified
// health status that the UI can use to warn users.

import Network
import os
import SwiftUI

// MARK: - NetworkHealth

/// Describes the current network health from the app's perspective.
enum NetworkHealth: Equatable, Sendable {
    /// Network is working normally
    case healthy
    /// Device reports no network connectivity
    case disconnected
    /// Device reports connectivity but requests are failing
    case degraded(consecutiveFailures: Int)

    // MARK: Internal

    var isUsable: Bool {
        if case .healthy = self {
            return true
        }
        return false
    }

    var isDegraded: Bool {
        if case .degraded = self {
            return true
        }
        return false
    }
}

// MARK: - NetworkHealthMonitor

/// Monitors network health by combining NWPathMonitor connectivity status
/// with actual request success/failure signals from services.
///
/// Services call `reportSuccess()` and `reportFailure()` after network requests.
/// When failures accumulate without intervening successes, the monitor transitions
/// to `.degraded` state, allowing the UI to warn the user.
@MainActor @Observable
final class NetworkHealthMonitor {
    // MARK: Lifecycle

    private init() {
        startPathMonitor()
    }

    // MARK: Internal

    static let shared = NetworkHealthMonitor()

    /// Current network health assessment
    private(set) var health: NetworkHealth = .healthy

    /// Number of consecutive failures across all services
    private(set) var consecutiveFailures: Int = 0

    /// Timestamp of the last successful network request
    private(set) var lastSuccessDate: Date?

    /// Timestamp of the first failure in the current streak
    private(set) var failureStreakStart: Date?

    /// Whether the OS-level path monitor reports connectivity
    private(set) var pathSatisfied: Bool = true

    /// Duration of the current failure streak, if any
    var failureStreakDuration: TimeInterval? {
        guard let start = failureStreakStart else {
            return nil
        }
        return Date().timeIntervalSince(start)
    }

    /// Call after a successful network request from any service
    func reportSuccess() {
        consecutiveFailures = 0
        lastSuccessDate = Date()
        failureStreakStart = nil
        updateHealth()
    }

    /// Call after a failed network request from any service
    func reportFailure(_ error: Error? = nil) {
        consecutiveFailures += 1
        if failureStreakStart == nil {
            failureStreakStart = Date()
        }
        if let error {
            logger.debug("Network failure #\(consecutiveFailures): \(error.localizedDescription)")
        }
        updateHealth()
    }

    /// Reset failure tracking (e.g., when user manually retries)
    func reset() {
        consecutiveFailures = 0
        failureStreakStart = nil
        updateHealth()
    }

    // MARK: Private

    /// Threshold of consecutive failures before reporting degraded
    private let degradedThreshold = 3

    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "networkHealthMonitor")
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CarrierWave",
        category: "NetworkHealth"
    )

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                let wasSatisfied = pathSatisfied
                pathSatisfied = path.status == .satisfied
                if pathSatisfied, !wasSatisfied {
                    // Network came back — reset failure tracking
                    logger.info("Network path restored")
                    reset()
                } else if !pathSatisfied {
                    logger.info("Network path lost")
                }
                updateHealth()
            }
        }
        monitor.start(queue: monitorQueue)
        pathMonitor = monitor
    }

    private func updateHealth() {
        if !pathSatisfied {
            health = .disconnected
        } else if consecutiveFailures >= degradedThreshold {
            health = .degraded(consecutiveFailures: consecutiveFailures)
        } else {
            health = .healthy
        }
    }
}
