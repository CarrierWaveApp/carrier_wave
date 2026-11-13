import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - TuneInQSYAlert

/// Alert data when the tuned activator is re-spotted on a different frequency.
struct TuneInQSYAlert: Equatable {
    let callsign: String
    let newFrequencyMHz: Double
    let newMode: String
    let newBand: String
    let currentFrequencyMHz: Double
    let currentBand: String
}

// MARK: - ReceiverSuggestion

/// Suggestion to switch to a better receiver.
struct ReceiverSuggestion: Equatable {
    let currentName: String
    let suggestedName: String
    let suggestedReceiver: KiwiSDRReceiver
    let reason: String

    static func == (lhs: ReceiverSuggestion, rhs: ReceiverSuggestion) -> Bool {
        lhs.currentName == rhs.currentName && lhs.suggestedName == rhs.suggestedName
    }
}

// MARK: - FollowedActivator

/// An activator callsign the user is following.
struct FollowedActivator: Codable, Identifiable, Equatable {
    let callsign: String
    let followedAt: Date
    /// Last known frequency when followed
    let frequencyMHz: Double?
    let mode: String?

    var id: String {
        callsign
    }
}

// MARK: - Smart Features

/// QSY detection and receiver-quality monitoring run in the Rust core
/// (`SdrApi.startQsyMonitor` / `startReceiverMonitor` — 45 s / 120 s polls,
/// one alert per session). The listeners below hop back to the main actor to
/// publish the observable state. Followed-activator storage stays here (it
/// is plain UserDefaults persistence with no shared logic).
extension TuneInManager {
    // MARK: - QSY Detection

    /// Start monitoring for QSY (frequency change) of the tuned activator
    func startQSYMonitor() {
        guard let spot, let api = try? SdrApiProvider.shared() else {
            return
        }
        stopQSYMonitor()

        let listener = QSYListener(manager: self)
        Task {
            qsyMonitorHandle = await api.startQsyMonitor(
                callsign: spot.callsign,
                currentFrequencyMhz: spot.frequencyMHz,
                currentMode: spot.mode,
                currentBand: spot.band,
                listener: listener
            )
        }
    }

    /// Stop QSY monitoring
    func stopQSYMonitor() {
        qsyMonitorHandle?.stop()
        qsyMonitorHandle = nil
        qsyAlert = nil
    }

    /// Accept a QSY retune — switch to the new frequency
    func acceptQSYRetune() async {
        guard let alert = qsyAlert else {
            return
        }
        await session.retune(frequencyMHz: alert.newFrequencyMHz)
        // Update the spot metadata
        if let currentSpot = spot {
            spot = TuneInSpot(
                callsign: currentSpot.callsign,
                frequencyMHz: alert.newFrequencyMHz,
                mode: alert.newMode,
                band: alert.newBand,
                parkRef: currentSpot.parkRef,
                parkName: currentSpot.parkName,
                summitCode: currentSpot.summitCode,
                summitName: currentSpot.summitName,
                latitude: currentSpot.latitude,
                longitude: currentSpot.longitude,
                grid: currentSpot.grid
            )
        }
        qsyAlert = nil
        // Restart QSY monitor for the new frequency
        startQSYMonitor()
    }

    /// Dismiss a QSY alert without retuning
    func dismissQSYAlert() {
        qsyAlert = nil
    }

    // MARK: - Receiver Quality Monitoring

    /// Start monitoring receiver quality and suggest alternatives
    func startReceiverMonitor() {
        stopReceiverMonitor()
        guard let spot,
              let currentReceiver = session.receiver,
              let api = try? SdrApiProvider.shared()
        else {
            return
        }

        let listener = SuggestionListener(manager: self)
        Task {
            receiverMonitorHandle = await api.startReceiverMonitor(
                current: currentReceiver.ffiReceiver,
                spot: spot.ffiSpot,
                listener: listener
            )
        }
    }

    /// Stop receiver quality monitoring
    func stopReceiverMonitor() {
        receiverMonitorHandle?.stop()
        receiverMonitorHandle = nil
        receiverSuggestion = nil
    }

    /// Dismiss a receiver suggestion
    func dismissReceiverSuggestion() {
        receiverSuggestion = nil
    }

    // MARK: - Follow Activator

    /// Currently followed activators
    var followedActivators: [FollowedActivator] {
        get {
            guard let data = UserDefaults.standard.data(
                forKey: Self.followedActivatorsKey
            ) else {
                return []
            }
            return (try? JSONDecoder().decode(
                [FollowedActivator].self, from: data
            )) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: Self.followedActivatorsKey)
        }
    }

    /// Whether a callsign is currently followed
    func isFollowing(_ callsign: String) -> Bool {
        followedActivators.contains {
            $0.callsign.uppercased() == callsign.uppercased()
        }
    }

    /// Follow an activator callsign
    func followActivator(
        _ callsign: String,
        frequencyMHz: Double? = nil,
        mode: String? = nil
    ) {
        guard !isFollowing(callsign) else {
            return
        }
        var list = followedActivators
        list.append(FollowedActivator(
            callsign: callsign.uppercased(),
            followedAt: Date(),
            frequencyMHz: frequencyMHz,
            mode: mode
        ))
        followedActivators = list
    }

    /// Unfollow an activator callsign
    func unfollowActivator(_ callsign: String) {
        var list = followedActivators
        list.removeAll {
            $0.callsign.uppercased() == callsign.uppercased()
        }
        followedActivators = list
    }

    /// Toggle follow state for an activator
    func toggleFollow(_ callsign: String, frequencyMHz: Double?, mode: String?) {
        if isFollowing(callsign) {
            unfollowActivator(callsign)
        } else {
            followActivator(callsign, frequencyMHz: frequencyMHz, mode: mode)
        }
    }

    // MARK: - Private Storage

    private static let followedActivatorsKey = "tuneInFollowedActivators"
}

// MARK: - QSYListener

/// Bridges Rust QSY alerts back to the main-actor manager. Called from Rust
/// worker threads; only dispatches to the main actor.
private final class QSYListener: SdrQsyListener, @unchecked Sendable {
    // MARK: Lifecycle

    init(manager: TuneInManager) {
        self.manager = manager
    }

    // MARK: Internal

    func onQsy(alert: FfiQsyAlert) {
        Task { @MainActor [weak manager] in
            guard let manager, manager.isActive else {
                return
            }
            manager.qsyAlert = TuneInQSYAlert(
                callsign: alert.callsign,
                newFrequencyMHz: alert.newFrequencyMhz,
                newMode: alert.newMode,
                newBand: alert.newBand,
                currentFrequencyMHz: alert.currentFrequencyMhz,
                currentBand: alert.currentBand
            )
        }
    }

    // MARK: Private

    private weak var manager: TuneInManager?
}

// MARK: - SuggestionListener

/// Bridges Rust receiver suggestions back to the main-actor manager.
private final class SuggestionListener: SdrSuggestionListener, @unchecked Sendable {
    // MARK: Lifecycle

    init(manager: TuneInManager) {
        self.manager = manager
    }

    // MARK: Internal

    func onSuggestion(suggestion: FfiReceiverSuggestion) {
        Task { @MainActor [weak manager] in
            guard let manager, manager.isActive else {
                return
            }
            manager.receiverSuggestion = ReceiverSuggestion(
                currentName: suggestion.currentName,
                suggestedName: suggestion.suggestedName,
                suggestedReceiver: KiwiSDRReceiver(ffi: suggestion.suggested),
                reason: suggestion.reason
            )
        }
    }

    // MARK: Private

    private weak var manager: TuneInManager?
}
