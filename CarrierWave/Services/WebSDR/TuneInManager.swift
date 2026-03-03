import CarrierWaveCore
import CoreLocation
import Foundation
import Network
import SwiftData
import UIKit

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
/// Works for both UnifiedSpot (hunter log) and POTASpot (logger spots).
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

// MARK: - TuneInManager

/// Coordinates standalone "Tune In" sessions from spot rows.
/// Owns a WebSDRSession and adds: spot metadata, smart receiver selection,
/// cellular data warning, and observable state for the mini player.
@MainActor
@Observable
final class TuneInManager {
    // MARK: - Singleton

    static let shared = TuneInManager()

    init() {
        // Stop tune-in when app backgrounds (design decision: no background audio)
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isActive else { return }
            Task { @MainActor in
                await self.stop()
            }
        }
    }

    // MARK: - Observable State

    /// Whether a tune-in session is active
    var isActive: Bool {
        session.state.isActive || session.state == .connecting
    }

    /// Whether audio is currently streaming
    var isStreaming: Bool {
        session.state.isStreaming
    }

    /// Current spot being listened to
    private(set) var spot: TuneInSpot?

    /// Whether the expanded player sheet is shown
    var showExpandedPlayer = false

    /// Whether a cellular data warning needs confirmation
    var showCellularWarning = false

    /// Pending tune-in waiting for cellular confirmation
    private(set) var pendingSpot: TuneInSpot?

    /// The underlying WebSDR session (exposes state, peakLevel, sMeter, etc.)
    let session = WebSDRSession()

    /// CW transcription service (active when tuned to a CW spot)
    let cwTranscription = CWTranscriptionService()

    /// Whether CW transcription is available (mode is CW)
    var isCWMode: Bool {
        spot?.mode.uppercased() == "CW"
    }

    // MARK: - Tune In

    /// Start listening to a spot. Auto-selects the best receiver.
    /// Shows a cellular warning on first cellular use.
    func tuneIn(to spot: TuneInSpot, modelContext: ModelContext) async {
        // Check cellular warning
        if shouldShowCellularWarning() {
            pendingSpot = spot
            showCellularWarning = true
            return
        }

        await performTuneIn(spot: spot, modelContext: modelContext)
    }

    /// Confirm cellular use and proceed with pending tune-in
    func confirmCellular(modelContext: ModelContext) async {
        UserDefaults.standard.set(true, forKey: Self.cellularWarningDismissedKey)
        showCellularWarning = false

        guard let spot = pendingSpot else {
            return
        }
        pendingSpot = nil
        await performTuneIn(spot: spot, modelContext: modelContext)
    }

    /// Dismiss cellular warning without tuning in
    func dismissCellularWarning() {
        showCellularWarning = false
        pendingSpot = nil
    }

    /// Stop listening and tear down the session
    func stop() async {
        await stopCWTranscription()
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
        guard offset > 0 else { return }

        let bookmark = ClipBookmark(
            offsetSeconds: offset,
            label: label
        )
        session.addClipBookmark(bookmark)
    }

    // MARK: - Smart Receiver Selection

    /// Find the best receiver for a spot based on activator proximity.
    /// Returns nil if no suitable receiver is found.
    func selectReceiver(for spot: TuneInSpot) async -> KiwiSDRReceiver? {
        let receivers = await WebSDRDirectory.shared.findNearby(
            grid: spot.grid,
            latitude: spot.latitude,
            longitude: spot.longitude,
            limit: 20
        )

        // Filter to available receivers, then score
        let candidates = receivers.filter { $0.isAvailable }

        // For now, closest available receiver wins.
        // Skip-zone scoring (penalize < 50mi, prefer 500-1500mi) is Phase 4.
        return candidates.first
    }

    // MARK: - Private

    private static let cellularWarningDismissedKey = "tuneInCellularWarningDismissed"

    private var cwFrameContinuation: AsyncStream<[Int16]>.Continuation?

    private func performTuneIn(
        spot: TuneInSpot,
        modelContext: ModelContext
    ) async {
        // Stop any existing session
        if isActive {
            await stopCWTranscription()
            await session.finalize()
        }

        self.spot = spot

        guard let receiver = await selectReceiver(for: spot) else {
            session.state = .error("No receivers available")
            return
        }

        // Wire up CW transcription for CW mode
        if spot.mode.uppercased() == "CW" {
            setupCWTranscription()
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
    }

    private func setupCWTranscription() {
        // Create an async stream that bridges audio frames to the CW decoder
        let (stream, continuation) = AsyncStream<[Int16]>.makeStream()
        cwFrameContinuation = continuation

        // Hook into the WebSDR session's audio frame callback
        session.onAudioFrame = { [weak self] samples in
            self?.cwFrameContinuation?.yield(samples)
        }

        // Start the CW decoder on the SDR audio stream
        Task {
            await cwTranscription.startListeningToSDR(
                frames: stream,
                sampleRate: session.lastSampleRate
            )
        }
    }

    private func stopCWTranscription() async {
        session.onAudioFrame = nil
        cwFrameContinuation?.finish()
        cwFrameContinuation = nil
        cwTranscription.stopListening()
        cwTranscription.clearTranscript()
    }

    private func shouldShowCellularWarning() -> Bool {
        guard !UserDefaults.standard.bool(
            forKey: Self.cellularWarningDismissedKey
        ) else {
            return false
        }

        let monitor = NWPathMonitor()
        let path = monitor.currentPath
        monitor.cancel()
        return path.usesInterfaceType(.cellular)
    }
}

// MARK: - TuneInSpot Convenience Initializers

extension TuneInSpot {
    /// Create from a UnifiedSpot (hunter log / activity tab)
    init(from unified: UnifiedSpot) {
        callsign = unified.callsign
        frequencyMHz = unified.frequencyMHz
        mode = unified.mode
        band = unified.band
        parkRef = unified.parkRef
        parkName = unified.parkName
        summitCode = unified.summitCode
        summitName = unified.summitName
        // Attempt to get coordinates from spotter grid (RBN) or park location
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

    /// Create from a POTASpot (logger spots panel)
    init(from pota: POTASpot) {
        callsign = pota.activator
        frequencyMHz = (pota.frequencyKHz ?? 14_060) / 1_000.0
        mode = pota.mode
        band = BandUtilities.deriveBand(from: pota.frequencyKHz) ?? ""
        parkRef = pota.reference
        parkName = pota.parkName
        summitCode = nil
        summitName = nil
        // POTASpot doesn't carry lat/lon — would need park database lookup
        latitude = nil
        longitude = nil
        grid = nil
    }
}
