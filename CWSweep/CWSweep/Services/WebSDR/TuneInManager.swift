import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import Foundation
import SwiftData

// MARK: - TuneInStrategy

/// How the user wants to select a KiwiSDR receiver for Tune In.
enum TuneInStrategy: String, CaseIterable, Sendable {
    /// Find an SDR near the strongest RBN spotter (best signal quality).
    case nearStrongRBN

    /// Find an SDR near the activator's location (hear what they hear).
    case nearActivator

    /// Find an SDR near the user's own QTH.
    case nearMyQTH

    // MARK: Internal

    var title: String {
        switch self {
        case .nearStrongRBN: "Best signal"
        case .nearActivator: "Near the activator"
        case .nearMyQTH: "Near my location"
        }
    }

    var description: String {
        switch self {
        case .nearStrongRBN: "Listen near the strongest RBN spot"
        case .nearActivator: "Listen near the activator's location"
        case .nearMyQTH: "Listen near your QTH"
        }
    }

    var systemImage: String {
        switch self {
        case .nearStrongRBN: "antenna.radiowaves.left.and.right"
        case .nearActivator: "mappin.and.ellipse"
        case .nearMyQTH: "location.fill"
        }
    }
}

// MARK: - TuneInSpotMetadata

/// Spot metadata to attach to WebSDR recordings created from Tune In.
struct TuneInSpotMetadata: Sendable {
    let callsign: String
    let parkRef: String?
    let parkName: String?
    let summitCode: String?
    let band: String
}

// MARK: - TuneInSpot

/// Lightweight snapshot of a spot being tuned into.
struct TuneInSpot: Sendable {
    let callsign: String
    let frequencyMHz: Double
    let mode: String
    let band: String
    let parkRef: String?
    let parkName: String?
    let summitCode: String?
    let summitName: String?
    let latitude: Double?
    let longitude: Double?
    let grid: String?
}

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
    let frequencyMHz: Double?
    let mode: String?

    var id: String {
        callsign
    }
}

// MARK: - TuneInManager

/// Coordinates standalone "Tune In" sessions from spot rows.
/// Owns a WebSDRSession and adds: spot metadata, smart receiver selection,
/// and observable state for the player UI.
@MainActor
@Observable
final class TuneInManager {
    // MARK: Internal

    /// Current spot being listened to
    var spot: TuneInSpot?

    /// Whether the expanded player sheet is shown
    var showExpandedPlayer = false

    /// Whether the strategy picker needs to be shown
    var showStrategyPicker = false

    /// Pending tune-in waiting for strategy selection
    private(set) var pendingStrategySpot: TuneInSpot?

    /// The underlying WebSDR session (exposes state, peakLevel, sMeter, etc.)
    let session = WebSDRSession()

    /// WebSDR directory for receiver lookups
    let directory = WebSDRDirectory()

    // MARK: - Smart Features State

    /// QSY alert when activator re-spotted at different frequency
    var qsyAlert: TuneInQSYAlert?

    /// Receiver switch suggestion when a better receiver is found
    var receiverSuggestion: ReceiverSuggestion?

    /// QSY monitoring task
    var qsyMonitorTask: Task<Void, Never>?

    /// Receiver quality monitoring task
    var receiverMonitorTask: Task<Void, Never>?

    // MARK: - Observable State

    /// Whether a tune-in session is active
    var isActive: Bool {
        session.state.isActive || session.state == .connecting
    }

    /// Whether audio is currently streaming
    var isStreaming: Bool {
        session.state.isStreaming
    }

    /// Whether CW transcription is available (mode is CW)
    var isCWMode: Bool {
        spot?.mode.uppercased() == "CW"
    }

    // MARK: - Tune In

    /// Present the strategy picker before tuning in.
    func requestTuneIn(to spot: TuneInSpot) {
        pendingStrategySpot = spot
        showStrategyPicker = true
    }

    /// Dismiss the strategy picker without tuning in.
    func dismissStrategyPicker() {
        showStrategyPicker = false
        pendingStrategySpot = nil
    }

    /// Start listening to a spot with a chosen strategy.
    func tuneIn(
        to spot: TuneInSpot,
        modelContext: ModelContext,
        strategy: TuneInStrategy = .nearStrongRBN
    ) async {
        await performTuneIn(
            spot: spot, modelContext: modelContext, strategy: strategy
        )
    }

    /// Stop listening and tear down the session
    func stop() async {
        stopQSYMonitor()
        stopReceiverMonitor()
        session.onReconnectsExhausted = nil
        await session.finalize()
        spot = nil
        showExpandedPlayer = false
    }

    /// Toggle mute
    func toggleMute() {
        session.toggleMute()
    }

    /// Add a clip bookmark at the current recording position
    func addClipBookmark(label: String? = nil) {
        let offset = session.recordingDuration
        guard offset > 0 else {
            return
        }

        let bookmark = ClipBookmark(
            offsetSeconds: offset,
            label: label
        )
        session.addClipBookmark(bookmark)
    }

    // MARK: Private

    private func performTuneIn(
        spot: TuneInSpot,
        modelContext: ModelContext,
        strategy: TuneInStrategy = .nearStrongRBN
    ) async {
        // Stop any existing session
        if isActive {
            await session.finalize()
        }

        self.spot = spot

        guard let receiver = await selectReceiver(
            for: spot, strategy: strategy
        ) else {
            session.state = .error("No receivers available")
            return
        }

        // Wire up receiver failover when reconnects are exhausted
        session.onReconnectsExhausted = { [weak self] in
            await self?.switchToAlternateReceiver()
        }

        // Attach spot metadata for recording enrichment
        session.tuneInSpotMetadata = TuneInSpotMetadata(
            callsign: spot.callsign,
            parkRef: spot.parkRef,
            parkName: spot.parkName,
            summitCode: spot.summitCode,
            band: spot.band
        )

        // Use a standalone session ID (not tied to a logging session)
        let standaloneId = UUID()

        await session.start(
            receiver: receiver,
            frequencyMHz: spot.frequencyMHz,
            mode: spot.mode,
            loggingSessionId: standaloneId,
            modelContext: modelContext
        )

        // Start smart feature monitors
        startQSYMonitor()
        startReceiverMonitor()
    }
}

// MARK: - Receiver Selection

extension TuneInManager {
    /// Select a receiver using the chosen listening strategy.
    func selectReceiver(
        for spot: TuneInSpot,
        strategy: TuneInStrategy
    ) async -> KiwiSDRReceiver? {
        switch strategy {
        case .nearStrongRBN:
            await selectReceiverNearRBN(for: spot)
        case .nearActivator:
            await selectReceiverNearActivator(for: spot)
        case .nearMyQTH:
            await selectReceiverNearMyQTH(for: spot)
        }
    }

    // MARK: - Near Strong RBN

    private func selectReceiverNearRBN(
        for spot: TuneInSpot
    ) async -> KiwiSDRReceiver? {
        let rbn = RBNClient()
        do {
            let spots = try await rbn.spots(
                for: spot.callsign, hours: 1, limit: 20
            )
            let sorted = spots.sorted { $0.snr > $1.snr }

            for rbnSpot in sorted {
                guard let grid = rbnSpot.spotterGrid,
                      let coord = MaidenheadConverter.coordinate(from: grid)
                else {
                    continue
                }
                if let receiver = await findNearbyAvailable(
                    latitude: coord.latitude,
                    longitude: coord.longitude
                ) {
                    return receiver
                }
            }
        } catch {
            // RBN lookup failed — fall through to fallback
        }

        return await selectReceiverFallback(for: spot)
    }

    // MARK: - Near Activator

    private func selectReceiverNearActivator(
        for spot: TuneInSpot
    ) async -> KiwiSDRReceiver? {
        // Try spot-provided coordinates
        if let lat = spot.latitude, let lon = spot.longitude {
            if let receiver = await findNearbyAvailable(
                latitude: lat, longitude: lon
            ) {
                return receiver
            }
        }

        // Try grid square if available
        if let grid = spot.grid,
           let coord = MaidenheadConverter.coordinate(from: grid)
        {
            if let receiver = await findNearbyAvailable(
                latitude: coord.latitude,
                longitude: coord.longitude
            ) {
                return receiver
            }
        }

        // Try HamDB callsign lookup for grid
        let hamDB = HamDBClient()
        do {
            if let license = try await hamDB.lookup(callsign: spot.callsign),
               let grid = license.grid,
               let coord = MaidenheadConverter.coordinate(from: grid)
            {
                if let receiver = await findNearbyAvailable(
                    latitude: coord.latitude,
                    longitude: coord.longitude
                ) {
                    return receiver
                }
            }
        } catch {
            // HamDB lookup failed — fall through
        }

        // Fall back to nearRBN strategy
        return await selectReceiverNearRBN(for: spot)
    }

    // MARK: - Near My QTH

    private func selectReceiverNearMyQTH(
        for spot: TuneInSpot
    ) async -> KiwiSDRReceiver? {
        if let grid = UserDefaults.standard.string(
            forKey: "loggerDefaultGrid"
        ),
            let coord = MaidenheadConverter.coordinate(from: grid)
        {
            if let receiver = await findNearbyAvailable(
                latitude: coord.latitude,
                longitude: coord.longitude
            ) {
                return receiver
            }
        }

        return await selectReceiverNearRBN(for: spot)
    }

    // MARK: - Receiver Failover

    func switchToAlternateReceiver() async {
        guard let spot, let failedReceiver = session.receiver else {
            return
        }

        let candidates = await directory.findNearby(
            grid: spot.grid,
            latitude: spot.latitude,
            longitude: spot.longitude,
            limit: 20
        )
        let alternate = candidates.first {
            $0.isAvailable && $0.id != failedReceiver.id
        }

        guard let alternate else {
            return
        }

        await session.resumeFromDormant(
            receiver: alternate,
            frequencyMHz: spot.frequencyMHz,
            mode: spot.mode
        )
    }

    // MARK: - Helpers

    private func findNearbyAvailable(
        latitude: Double,
        longitude: Double
    ) async -> KiwiSDRReceiver? {
        let receivers = await directory.findNearby(
            grid: nil,
            latitude: latitude,
            longitude: longitude,
            limit: 20
        )
        return receivers.first(where: \.isAvailable)
    }

    func selectReceiverFallback(
        for spot: TuneInSpot
    ) async -> KiwiSDRReceiver? {
        let receivers = await directory.findNearby(
            grid: spot.grid,
            latitude: spot.latitude,
            longitude: spot.longitude,
            limit: 20
        )
        return receivers.first(where: \.isAvailable)
    }
}

// MARK: - TuneInSpot Convenience Initializers

extension TuneInSpot {
    /// Create from a UnifiedSpot (spot list)
    init(from unified: UnifiedSpot) {
        callsign = unified.callsign
        frequencyMHz = unified.frequencyMHz
        mode = unified.mode
        band = unified.band
        parkRef = unified.parkRef
        parkName = unified.parkName
        summitCode = unified.summitCode
        summitName = unified.summitName
        if let grid = unified.spotterGrid,
           let coord = MaidenheadConverter.coordinate(from: grid)
        {
            latitude = coord.latitude
            longitude = coord.longitude
            self.grid = grid
        } else {
            latitude = nil
            longitude = nil
            grid = nil
        }
    }

    /// Create from an EnrichedSpot (enriched spot list)
    init(from enriched: EnrichedSpot) {
        self.init(from: enriched.spot)
    }
}
