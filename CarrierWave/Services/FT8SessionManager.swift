//
//  FT8SessionManager.swift
//  CarrierWave
//

import CarrierWaveData
import Foundation
import os
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
        loggingSessionManager: LoggingSessionManager
    ) {
        qsoStateMachine = FT8QSOStateMachine(myCallsign: myCallsign, myGrid: myGrid)
        decodeEnricher = FT8DecodeEnricher(
            myCallsign: myCallsign,
            myGrid: myGrid,
            currentBand: "20m"
        )
        self.modelContext = modelContext
        self.loggingSessionManager = loggingSessionManager
    }

    // MARK: Internal

    // MARK: - Published State

    private(set) var decodeResults: [FT8DecodeResult] = []
    private(set) var currentCycleDecodes: [FT8DecodeResult] = []
    private(set) var isTransmitting = false
    private(set) var isReceiving = false
    private(set) var cycleTimeRemaining: Double = 15.0
    private(set) var qsoStateMachine: FT8QSOStateMachine
    private(set) var operatingMode: FT8OperatingMode = .listen
    private(set) var qsoCount = 0
    private(set) var audioLevel: Float = 0
    private(set) var waterfallData = FT8WaterfallData()
    private(set) var availableAudioInputs: [AudioInputInfo] = []
    private(set) var enrichedDecodes: [FT8EnrichedDecode] = []
    private(set) var currentCycleEnriched: [FT8EnrichedDecode] = []
    private(set) var cyclesSinceLastDecode = 0
    private(set) var rxAudioFrequency: Double = 1_500
    private(set) var txAudioFrequency: Double = 1_500
    private(set) var txEvents: [FT8TXEvent] = []
    private(set) var txState: FT8TXState = .idle
    private(set) var isTXHalted = false
    var isFocusMode = false

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

    // MARK: - Start/Stop

    func start() async throws {
        guard !isReceiving else {
            return
        }

        try await audioEngine.configure()
        try await audioEngine.start(onSlotReady: { _ in
            // Slot collection is now timer-driven via onSlotBoundary()
        })

        await audioEngine.setAudioLevelCallback { [weak self] level in
            Task { @MainActor in
                self?.audioLevel = level
            }
        }

        await audioEngine.setWaterfallCallback { [weak self] samples in
            Task { @MainActor in
                self?.waterfallData.processAudio(samples)
            }
        }

        await refreshAudioInputs()
        startCycleTimer()
        isReceiving = true
    }

    func stop() async {
        slotTimer?.invalidate()
        cycleTimer?.invalidate()
        slotTimer = nil
        cycleTimer = nil
        await audioEngine.stop()
        isReceiving = false
        isTransmitting = false
        waterfallData.clear()
    }

    // MARK: - Mode Control

    func setMode(_ mode: FT8OperatingMode) {
        operatingMode = mode
        switch mode {
        case .listen:
            qsoStateMachine.setListenMode()
            txState = .idle
            isTXHalted = false
        case let .callCQ(modifier):
            qsoStateMachine.setCQMode(modifier: modifier)
        case .searchAndPounce:
            qsoStateMachine.setListenMode()
        }
    }

    func refreshAudioInputs() async {
        availableAudioInputs = await audioEngine.availableInputs()
    }

    func selectAudioInput(uid: String) {
        Task {
            try? await audioEngine.selectInput(uid: uid)
            await refreshAudioInputs()
        }
    }

    /// Set the TX audio frequency explicitly (for channel picker / waterfall tap).
    func setTXChannel(_ hz: Double) {
        let snapped = (hz / 50).rounded() * 50
        let clamped = max(100, min(snapped, 2_950))
        txAudioFrequency = clamped
    }

    func callStation(_ result: FT8DecodeResult) {
        guard case let .cq(call, grid, _) = result.message else {
            Self.log.debug("callStation called with non-CQ message")
            return
        }
        setMode(.searchAndPounce)
        txAudioFrequency = result.frequency
        // TX on OPPOSITE parity from when we heard them
        transmitOnEven = !isEvenSlot
        qsoStateMachine.initiateCall(to: call, theirGrid: grid.isEmpty ? nil : grid)
        txState = .armed(callsign: call)
    }

    // MARK: Private

    private static let log = Logger(
        subsystem: "com.jsvana.CarrierWave",
        category: "FT8SessionManager"
    )

    /// Maximum number of decode results to retain (~4 minutes of decodes).
    private static let maxDecodeResults = 500

    private var decodeEnricher: FT8DecodeEnricher

    private let audioEngine = FT8AudioEngine()
    private var slotTimer: Timer?
    private var cycleTimer: Timer?
    private var isEvenSlot = true
    private var transmitOnEven = true
    private var currentSlotStartTime = Date()
    private let modelContext: ModelContext
    private let loggingSessionManager: LoggingSessionManager

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

            // Auto-set TX frequency when CQ response starts a QSO
            if prevState == .idle, qsoStateMachine.state == .reportSent {
                txAudioFrequency = result.frequency
            }

            if qsoStateMachine.state == .completing,
               let completed = qsoStateMachine.completedQSO
            {
                logCompletedQSO(completed)
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

        do {
            let samples = try FT8Encoder.encode(
                message: message,
                frequency: txAudioFrequency
            )
            isTransmitting = true
            txState = .transmitting(message: message)
            txEvents.append(FT8TXEvent(
                message: message,
                timestamp: Date(),
                audioFrequency: txAudioFrequency
            ))
            Task { @MainActor [weak self] in
                await self?.audioEngine.playTones(samples)
                self?.isTransmitting = false
                if let call = self?.qsoStateMachine.theirCallsign {
                    self?.txState = .armed(callsign: call)
                } else {
                    self?.txState = .idle
                }
            }
        } catch {
            Self.log.error("FT8 encode failed: \(error)")
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
    }

    private func onSlotBoundary() {
        isEvenSlot.toggle()
        currentSlotStartTime = Date()
        cycleTimeRemaining = FT8Constants.slotDuration

        // Age existing enriched decodes
        for i in enrichedDecodes.indices {
            enrichedDecodes[i].cycleAge += 1
        }
        decodeEnricher.advanceCycle()

        let wasCompleting = qsoStateMachine.state == .completing
        qsoStateMachine.advanceCycle()

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

    // MARK: - QSO Logging

    private func logCompletedQSO(_ completed: FT8QSOStateMachine.CompletedQSO) {
        let rstSent = formatReport(completed.myReport)
        let rstReceived = formatReport(completed.theirReport)

        _ = loggingSessionManager.logQSO(
            callsign: completed.theirCallsign,
            rstSent: rstSent,
            rstReceived: rstReceived,
            theirGrid: completed.theirGrid
        )

        qsoCount += 1
        decodeEnricher.markWorkedThisSession(completed.theirCallsign)
        Self.log.info("FT8 QSO logged: \(completed.theirCallsign)")

        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // POTA milestone: extra haptic when reaching 10 valid QSOs
        if qsoCount == 10 {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    private func formatReport(_ report: Int?) -> String {
        guard let report else {
            return "+00" // Neutral fallback for unknown FT8 dB report
        }
        let sign = report >= 0 ? "+" : "-"
        return "\(sign)\(String(format: "%02d", abs(report)))"
    }
}

// MARK: - TX Control & Channel Recommendation

extension FT8SessionManager {
    func haltTX() {
        isTXHalted = true
        if let call = qsoStateMachine.theirCallsign {
            txState = .halted(callsign: call)
        }
    }

    func resumeTX() {
        isTXHalted = false
        if let call = qsoStateMachine.theirCallsign {
            txState = .armed(callsign: call)
        }
    }

    /// Analyze recent decodes to recommend the least-occupied channels.
    func recommendedChannels() -> [ChannelRecommendation] {
        let binWidth = 50.0
        let minHz = 200.0
        let maxHz = 2_800.0
        let binCount = Int((maxHz - minHz) / binWidth)

        // Count decodes per bin across all retained results
        var bins = [Int](repeating: 0, count: binCount)
        for result in decodeResults {
            let freq = result.frequency
            guard freq >= minHz, freq < maxHz else {
                continue
            }
            let idx = Int((freq - minHz) / binWidth)
            if idx >= 0, idx < binCount {
                bins[idx] += 1
                // Penalise adjacent bins (guard band)
                if idx > 0 {
                    bins[idx - 1] += 1
                }
                if idx < binCount - 1 {
                    bins[idx + 1] += 1
                }
            }
        }

        let maxCount = bins.max() ?? 0
        var recommendations: [ChannelRecommendation] = []
        for i in 0 ..< binCount {
            let freq = minHz + Double(i) * binWidth + binWidth / 2
            let count = bins[i]
            let occupancy: ChannelRecommendation.OccupancyLevel = if count == 0 {
                .clear
            } else if maxCount > 0, Double(count) / Double(maxCount) < 0.25 {
                .quiet
            } else if maxCount > 0, Double(count) / Double(maxCount) < 0.6 {
                .fair
            } else {
                .busy
            }
            recommendations.append(ChannelRecommendation(
                frequency: freq,
                activityCount: count,
                occupancy: occupancy
            ))
        }

        return recommendations.sorted { $0.activityCount < $1.activityCount }
    }
}
