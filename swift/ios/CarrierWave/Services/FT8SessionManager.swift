//
//  FT8SessionManager.swift
//  CarrierWave
//

import CarrierWaveData
import Foundation
import OSLog
import SwiftData
import UIKit

// MARK: - FT8SessionManager

/// Manages an active FT8 session — decoding, auto-sequencing, and QSO logging.
@MainActor @Observable
final class FT8SessionManager {
    // MARK: Lifecycle

    init(
        myCallsign: String,
        myGrid: String,
        modelContext: ModelContext,
        qsoLogger: any FT8QSOLogger,
        initialBand: String? = nil
    ) {
        qsoStateMachine = FT8QSOStateMachine(myCallsign: myCallsign, myGrid: myGrid)
        let band = FT8Constants.resolveBand(initialBand) ?? "20m"
        selectedBand = band
        decodeEnricher = FT8DecodeEnricher(
            myCallsign: myCallsign,
            myGrid: myGrid,
            currentBand: band
        )
        self.modelContext = modelContext
        self.qsoLogger = qsoLogger
        let data = FT8WaterfallData()
        waterfallData = data
        waterfallProcessor = FT8WaterfallProcessor(target: data)
    }

    // MARK: Internal

    static let log = Logger(
        subsystem: "com.jsvana.CarrierWave",
        category: "FT8SessionManager"
    )

    // MARK: - Published State

    private(set) var decodeResults: [FT8DecodeResult] = []
    private(set) var currentCycleDecodes: [FT8DecodeResult] = []
    private(set) var isTransmitting = false
    private(set) var isReceiving = false
    private(set) var cycleTimeRemaining: Double = 15.0
    private(set) var qsoStateMachine: FT8QSOStateMachine
    private(set) var operatingMode: FT8OperatingMode = .listen
    var qsoCount = 0
    private(set) var audioLevel: FT8AudioLevel = .zero
    private(set) var waterfallData: FT8WaterfallData
    private(set) var availableAudioInputs: [AudioInputInfo] = []
    private(set) var enrichedDecodes: [FT8EnrichedDecode] = []
    private(set) var currentCycleEnriched: [FT8EnrichedDecode] = []
    private(set) var cyclesSinceLastDecode = 0
    private(set) var rxAudioFrequency: Double = 1_500
    private(set) var txAudioFrequency: Double = 1_500
    private(set) var txEvents: [FT8TXEvent] = []
    var txState: FT8TXState = .idle
    var isTXHalted = false
    /// Tracks sustained digital clipping; surfaces an actionable banner.
    let audioOverload = FT8AudioOverloadTracker()
    var isFocusMode = false
    /// Last error from `start()`. Surfaced in-view so the user sees that FT8
    /// failed to initialise instead of a silent black waterfall. Cleared on
    /// the next successful start.
    private(set) var startupError: String?

    var decodeEnricher: FT8DecodeEnricher

    let qsoLogger: any FT8QSOLogger

    var selectedBand: String = "20m" {
        didSet {
            decodeEnricher = FT8DecodeEnricher(
                myCallsign: qsoStateMachine.myCallsign,
                myGrid: qsoStateMachine.myGrid,
                currentBand: selectedBand
            )
        }
    }

    var selectedFrequency: Double {
        FT8Constants.dialFrequency(forBand: selectedBand) ?? 14.074
    }

    // MARK: - Mode Control

    func setMode(_ mode: FT8OperatingMode) {
        operatingMode = mode
        switch mode {
        case .listen:
            qsoStateMachine.setListenMode()
            txState = .idle
            isTXHalted = false
            didLogCurrentQSO = false
        case let .callCQ(modifier):
            qsoStateMachine.setCQMode(modifier: modifier)
            isTXHalted = false
            didLogCurrentQSO = false
        case .searchAndPounce:
            qsoStateMachine.setListenMode()
            didLogCurrentQSO = false
        }
    }

    func refreshAudioInputs() async {
        availableAudioInputs = await audioEngine.availableInputs()
    }

    func selectAudioInput(uid: String) {
        // Drop the previous device's clipped-peak history before any samples
        // from the new device arrive — otherwise the overload banner stays
        // latched against a quieter input until the rolling window naturally
        // expires (and re-arms on any transient in the meantime).
        audioOverload.reset()
        Task {
            try? await audioEngine.selectInput(uid: uid)
            await audioEngine.resetLevelMetering()
            await refreshAudioInputs()
        }
    }

    /// Set the TX audio frequency explicitly (for channel picker / waterfall tap).
    /// Snap step is 25 Hz so recommended bin-center channels (225/275/325/...)
    /// are preserved exactly. A coarser 50 Hz snap collided with banker's
    /// rounding and pushed every selection onto multiples of 100, defeating the
    /// channel picker's selection indicator.
    func setTXChannel(_ hz: Double) {
        let snapped = (hz / 25).rounded() * 25
        let clamped = max(100, min(snapped, 2_950))
        txAudioFrequency = clamped
    }

    func callStation(_ result: FT8DecodeResult) {
        guard let call = result.message.callerCallsign else {
            Self.log.debug("callStation called with messageless caller")
            return
        }
        setMode(.searchAndPounce)
        txAudioFrequency = result.frequency
        transmitOnEven = !isEvenSlot
        didLogCurrentQSO = false
        qsoStateMachine.initiateCall(to: call, theirGrid: result.message.grid)
        txState = .armed(callsign: call)
    }

    // MARK: Fileprivate

    /// Maximum number of decode results to retain (~4 minutes of decodes).
    fileprivate static let maxDecodeResults = 500

    // MARK: Private

    private let waterfallProcessor: FT8WaterfallProcessor

    private let audioEngine = FT8AudioEngine()
    private var slotTimer: Timer?
    private var cycleTimer: Timer?
    private var isEvenSlot = true
    private var transmitOnEven = true
    private var currentSlotStartTime = Date()
    private let modelContext: ModelContext

    /// Guards against double-logging the same QSO from multiple decode messages
    /// in one cycle, or from both the completing-state path and the timeout-salvage path.
    /// Reset whenever a new QSO begins.
    private var didLogCurrentQSO = false

    // MARK: - Decoding

    private func handleDecodedResults(_ results: [FT8DecodeResult]) {
        print("[FT8Decode] Result: \(results.count) messages decoded")
        for result in results {
            print("[FT8Decode]   \(result.rawText) @ \(Int(result.frequency)) Hz, SNR \(result.snr)")
        }
        currentCycleDecodes = results
        decodeResults.append(contentsOf: results)

        // Trim old decodes
        if decodeResults.count > Self.maxDecodeResults {
            decodeResults.removeFirst(decodeResults.count - Self.maxDecodeResults)
        }

        // Enrich decodes
        currentCycleEnriched = decodeEnricher.enrich(results)
        enrichedDecodes.append(contentsOf: currentCycleEnriched)

        // Trim enriched decodes in sync with raw decodes
        if enrichedDecodes.count > Self.maxDecodeResults {
            enrichedDecodes.removeFirst(enrichedDecodes.count - Self.maxDecodeResults)
        }

        // Track cycles since last decode (for status pill)
        if results.isEmpty {
            cyclesSinceLastDecode += 1
        } else {
            cyclesSinceLastDecode = 0
        }

        // Process each decode and check for completion after each message
        for result in results {
            let prevState = qsoStateMachine.state
            qsoStateMachine.processMessage(result.message)

            // New QSO starting (e.g., CQ originator: handleCQResponse takes us idle → reportSent).
            // Clear the dedup flag so the next QSO can be logged.
            if prevState == .idle, qsoStateMachine.state != .idle {
                didLogCurrentQSO = false
            }

            // When entering reportSent, set myReport from the decode's SNR
            // so nextTXMessage can generate the signal report.
            if qsoStateMachine.state == .reportSent, qsoStateMachine.myReport == nil {
                qsoStateMachine.myReport = result.snr
            }

            // Auto-set TX frequency when CQ response starts a QSO
            if prevState == .idle, qsoStateMachine.state == .reportSent {
                txAudioFrequency = result.frequency
            }

            if qsoStateMachine.state == .completing,
               !didLogCurrentQSO,
               let completed = qsoStateMachine.completedQSO
            {
                logCompletedQSO(completed)
                didLogCurrentQSO = true
                // Don't reset yet — completing state sends grace 73/RR73
                // and auto-resets to idle after one cycle via advanceCycle()
            }
        }
    }

    // MARK: - Transmitting

    private func transmitIfNeeded() {
        guard !isTXHalted else {
            return
        }
        if case .listen = operatingMode {
            return
        }
        guard let message = qsoStateMachine.nextTXMessage else {
            return
        }

        isTransmitting = true
        txState = .transmitting(message: message)
        txEvents.append(FT8TXEvent(
            message: message,
            timestamp: Date(),
            audioFrequency: txAudioFrequency
        ))

        // Encode off-main-thread to avoid blocking the UI during tone synthesis.
        let frequency = txAudioFrequency
        let engine = audioEngine
        let logger = Self.log
        Task.detached {
            do {
                let samples = try FT8Encoder.encode(
                    message: message,
                    frequency: frequency
                )
                logger.info("FT8 TX: \(samples.count) samples at \(Int(frequency)) Hz")
                await engine.playTones(samples)
            } catch {
                logger.error("FT8 encode failed: \(error)")
            }
            // Keep isTransmitting true for the full TX slot (~12.6s).
            // The slot boundary handler resets it when the next slot begins.
        }
    }

    // MARK: - Timing

    private func startCycleTimer() {
        // Synchronize to UTC 15-second boundaries
        let now = Date()
        let seconds = now.timeIntervalSince1970
        let slotSeconds = seconds.truncatingRemainder(dividingBy: FT8Constants.slotDuration)
        let nextSlotStart = FT8Constants.slotDuration - slotSeconds

        // Initialize to the NEXT slot's parity (onSlotBoundary will toggle)
        isEvenSlot = !Int(seconds / FT8Constants.slotDuration).isMultiple(of: 2)
        currentSlotStartTime = now

        // Fire at next slot boundary, then repeating every 15 seconds.
        // Use MainActor.assumeIsolated to avoid async Task hop for timing-critical code.
        slotTimer = Timer.scheduledTimer(
            withTimeInterval: nextSlotStart,
            repeats: false
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }
                self.onSlotBoundary()
                self.slotTimer = Timer.scheduledTimer(
                    withTimeInterval: FT8Constants.slotDuration,
                    repeats: true
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.onSlotBoundary()
                    }
                }
                self.slotTimer?.tolerance = 1.5 // 10% of 15s slot duration
            }
        }

        // Countdown timer — compute from wall clock to avoid drift
        cycleTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateCountdown()
            }
        }
        cycleTimer?.tolerance = 0.1 // 10% of 1s interval
    }

    private func onSlotBoundary() {
        isEvenSlot.toggle()
        currentSlotStartTime = Date()
        cycleTimeRemaining = FT8Constants.slotDuration

        // Clear TX state from previous slot
        if isTransmitting {
            isTransmitting = false
            if let call = qsoStateMachine.theirCallsign {
                txState = .armed(callsign: call)
            } else {
                txState = .idle
            }
        }

        // Age existing enriched decodes
        for i in enrichedDecodes.indices {
            enrichedDecodes[i].cycleAge += 1
        }
        decodeEnricher.advanceCycle()

        let wasCompleting = qsoStateMachine.state == .completing
        // Snapshot loggable partial-QSO data before advanceCycle wipes it on timeout.
        let salvageOnTimeout = qsoStateMachine.partialQSO
        qsoStateMachine.advanceCycle()

        // Salvage path: we had enough info to log (both reports exchanged) but timed
        // out before the closing handshake. Log once instead of dropping the contact.
        if !didLogCurrentQSO,
           qsoStateMachine.state == .idle,
           let partial = salvageOnTimeout
        {
            logCompletedQSO(partial)
            didLogCurrentQSO = true
        }

        // Reset TX state when completing state auto-resets to idle
        if wasCompleting, qsoStateMachine.state == .idle {
            txState = .idle
            isTXHalted = false
            txEvents.removeAll()
        }

        // Collect and decode audio from the completed slot.
        // Decode runs off the main actor to avoid blocking the UI.
        let engine = audioEngine
        Task.detached { [weak self] in
            guard let slot = await engine.collectSlot() else {
                return
            }
            let results = FT8Decoder.decode(samples: slot)
            await self?.handleDecodedResults(results)
        }

        // Transmit on our designated slot (even or odd)
        if isEvenSlot == transmitOnEven {
            transmitIfNeeded()
        }
    }

    private func updateCountdown() {
        let elapsed = Date().timeIntervalSince(currentSlotStartTime)
        cycleTimeRemaining = max(0, FT8Constants.slotDuration - elapsed)
    }
}

// QSO logging and TX control extensions moved to:
// - FT8SessionManager+Logging.swift
// - FT8SessionManager+TXControl.swift

// MARK: - Start / Stop / Retry

//
// Kept in a same-file extension so the class body stays under SwiftLint's
// 300-line type_body_length cap. Same-file extensions can still write
// `private(set)` properties because Swift's `private` access scope includes
// extensions of the type that live in the same source file.

extension FT8SessionManager {
    func start() async throws {
        guard !isReceiving else {
            return
        }

        do {
            try await audioEngine.configure()
            try await audioEngine.start(onSlotReady: { _ in
                // Slot collection is now timer-driven via onSlotBoundary()
            })
        } catch {
            startupError = (error as? LocalizedError)?.errorDescription
                ?? "FT8 audio engine failed to start: \(error.localizedDescription)"
            FT8SessionManager.log.error("FT8 start failed: \(error)")
            throw error
        }

        await audioEngine.setAudioLevelCallback { [weak self] level in
            Task { @MainActor in
                self?.audioLevel = level
                self?.audioOverload.record(level)
            }
        }

        await audioEngine.setOnRouteChange { [weak self] in
            // Route just swapped — drop the previous device's history so
            // residue from a hot dongle doesn't latch the banner against
            // a quieter built-in mic.
            Task { @MainActor in
                self?.audioOverload.reset()
            }
        }

        let processor = waterfallProcessor
        await audioEngine.setWaterfallCallback { samples in
            // Compute on the processor actor — keeps FFT, vDSP, and per-bin
            // percentile sorts off the main actor where they used to land
            // alongside SwiftUI rebuilds and TX state transitions.
            Task { await processor.process(samples) }
        }

        await refreshAudioInputs()
        startCycleTimer()
        isReceiving = true
        startupError = nil
    }

    /// Tear down and start fresh after a failed initial start. Used by the
    /// in-view error banner's Retry button.
    func retryStart() async {
        await audioEngine.stop()
        isReceiving = false
        do {
            try await start()
        } catch {
            // start() already populated startupError.
        }
    }

    func stop() async {
        slotTimer?.invalidate()
        cycleTimer?.invalidate()
        slotTimer = nil
        cycleTimer = nil
        await audioEngine.stop()
        isReceiving = false
        isTransmitting = false
        await waterfallProcessor.reset()
        audioOverload.reset()
    }
}
