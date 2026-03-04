// Frequency Activity Service
//
// Aggregates nearby frequency activity from RBN and POTA spots.

import CarrierWaveData
import Foundation
import SwiftUI

// MARK: - NearbyActivity

/// Activity near the operating frequency
struct NearbyActivity: Identifiable, Sendable {
    let id: String
    let callsign: String
    let frequencyMHz: Double
    let mode: String
    let source: ActivitySource
    let timestamp: Date
    let signalReport: Int?
    let notes: String?

    /// Distance from the target frequency in kHz
    var offsetKHz: Double = 0

    /// Formatted frequency
    var formattedFrequency: String {
        String(format: "%.1f kHz", frequencyMHz * 1_000)
    }

    /// Formatted offset
    var formattedOffset: String {
        let sign = offsetKHz >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", offsetKHz)) kHz"
    }

    /// Time ago
    var timeAgo: String {
        let seconds = Date().timeIntervalSince(timestamp)
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3_600 {
            return "\(Int(seconds / 60))m"
        } else {
            return "\(Int(seconds / 3_600))h"
        }
    }
}

// MARK: - ActivitySource

enum ActivitySource: String, Sendable {
    case rbn = "RBN"
    case pota = "POTA"
    case sota = "SOTA"
    case manual = "Manual"

    // MARK: Internal

    var icon: String {
        switch self {
        case .rbn: "antenna.radiowaves.left.and.right"
        case .pota: "tree.fill"
        case .sota: "mountain.2.fill"
        case .manual: "person.fill"
        }
    }

    var color: Color {
        switch self {
        case .rbn: .blue
        case .pota: .green
        case .sota: .orange
        case .manual: .purple
        }
    }
}

// MARK: - QRMLevel

/// QRM (interference) assessment
enum QRMLevel: Sendable {
    case clear
    case light
    case moderate
    case heavy

    // MARK: Internal

    var description: String {
        switch self {
        case .clear: "Clear"
        case .light: "Light QRM"
        case .moderate: "Moderate QRM"
        case .heavy: "Heavy QRM"
        }
    }

    var color: Color {
        switch self {
        case .clear: .green
        case .light: .blue
        case .moderate: .orange
        case .heavy: .red
        }
    }

    var icon: String {
        switch self {
        case .clear: "checkmark.circle.fill"
        case .light: "exclamationmark.circle"
        case .moderate: "exclamationmark.triangle"
        case .heavy: "xmark.octagon.fill"
        }
    }
}

// MARK: - FrequencyActivityService

/// Service for aggregating nearby frequency activity
@MainActor
@Observable
final class FrequencyActivityService {
    // MARK: Internal

    // MARK: - Published Properties

    private(set) var nearbyActivity: [NearbyActivity] = []
    private(set) var qrmLevel: QRMLevel = .clear
    private(set) var isLoading = false
    private(set) var lastUpdate: Date?

    // MARK: - Configuration

    /// Bandwidth to search (kHz from center)
    var bandwidthKHz: Double = 2.0

    /// Auto-refresh interval (seconds, 0 to disable)
    var refreshInterval: TimeInterval = 30

    // MARK: - Public Methods

    /// Start monitoring activity near a frequency
    func startMonitoring(frequencyMHz: Double, mode: String?) {
        stopMonitoring()

        refreshTask = Task {
            while !Task.isCancelled {
                await refresh(frequencyMHz: frequencyMHz, mode: mode)

                if refreshInterval > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(refreshInterval * 1_000_000_000))
                } else {
                    break
                }
            }
        }
    }

    /// Stop monitoring
    func stopMonitoring() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Manual refresh
    func refresh(frequencyMHz: Double, mode: String?) async {
        isLoading = true

        var allActivity: [NearbyActivity] = []

        // Fetch RBN spots
        do {
            let spots = try await rbnClient.spotsNearFrequency(
                frequencyMHz,
                bandwidthKHz: bandwidthKHz,
                mode: mode,
                limit: 50
            )

            let rbnActivity = spots.map { spot in
                var activity = NearbyActivity(
                    id: "rbn-\(spot.id)",
                    callsign: spot.callsign,
                    frequencyMHz: spot.frequency / 1_000.0,
                    mode: spot.mode,
                    source: .rbn,
                    timestamp: spot.timestamp,
                    signalReport: spot.snr,
                    notes: spot.wpm.map { "\($0) WPM" }
                )
                activity.offsetKHz = (spot.frequency / 1_000.0 - frequencyMHz) * 1_000
                return activity
            }

            allActivity.append(contentsOf: rbnActivity)
        } catch {
            // Silently handle RBN errors
        }

        // Sort by distance from center frequency
        nearbyActivity = allActivity.sorted { abs($0.offsetKHz) < abs($1.offsetKHz) }

        // Assess QRM level
        qrmLevel = assessQRM(activity: nearbyActivity, frequencyMHz: frequencyMHz)

        lastUpdate = Date()
        isLoading = false
    }

    /// Get activity within a specific range
    func activity(within kHz: Double) -> [NearbyActivity] {
        nearbyActivity.filter { abs($0.offsetKHz) <= kHz }
    }

    /// Check if there's a station very close to the frequency
    func hasCloseActivity(within kHz: Double = 0.5) -> Bool {
        nearbyActivity.contains { abs($0.offsetKHz) <= kHz }
    }

    // MARK: Private

    private let rbnClient = RBNClient()
    private var refreshTask: Task<Void, Never>?

    // MARK: - Private Methods

    private func assessQRM(activity: [NearbyActivity], frequencyMHz: Double) -> QRMLevel {
        let veryClose = activity.filter { abs($0.offsetKHz) <= 0.5 }
        let close = activity.filter { abs($0.offsetKHz) <= 1.0 }
        let nearby = activity.filter { abs($0.offsetKHz) <= 2.0 }

        if !veryClose.isEmpty {
            return .heavy
        } else if close.count >= 3 {
            return .moderate
        } else if nearby.count >= 5 {
            return .moderate
        } else if !close.isEmpty {
            return .light
        } else if !nearby.isEmpty {
            return .light
        } else {
            return .clear
        }
    }
}
