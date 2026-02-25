//
//  FT8SessionManager.swift
//  CarrierWave
//

import CarrierWaveCore
import Foundation
import os
import SwiftData

// MARK: - FT8OperatingMode

/// Operating mode for FT8.
enum FT8OperatingMode: Sendable {
    case listen
    case callCQ(modifier: String?)
    case searchAndPounce
}

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

    var selectedFrequency: Double = 14.074

    var selectedBand: String = "20m" {
        didSet {
            selectedFrequency = FT8Constants.dialFrequency(forBand: selectedBand) ?? 14.074
        }
    }

    // MARK: - Start/Stop

    func start() async throws {
        guard !isReceiving else {
            return
        }

        try await audioEngine.configure()
        try await audioEngine.start { [weak self] samples in
            Task { @MainActor in
                self?.handleDecodedSlot(samples)
            }
        }

        await audioEngine.setAudioLevelCallback { [weak self] level in
            Task { @MainActor in
                self?.audioLevel = level
            }
        }

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
    }

    // MARK: - Mode Control

    func setMode(_ mode: FT8OperatingMode) {
        operatingMode = mode
        switch mode {
        case .listen:
            qsoStateMachine.setListenMode()
        case let .callCQ(modifier):
            qsoStateMachine.setCQMode(modifier: modifier)
        case .searchAndPounce:
            qsoStateMachine.setListenMode()
        }
    }

    func callStation(_ result: FT8DecodeResult) {
        guard case let .cq(call, grid, _) = result.message else {
            Self.log.debug("callStation called with non-CQ message")
            return
        }
        setMode(.searchAndPounce)
        // TX on the same parity as the CQ was heard (CQ station's TX slot)
        transmitOnEven = isEvenSlot
        qsoStateMachine.initiateCall(to: call, theirGrid: grid.isEmpty ? nil : grid)
    }

    // MARK: Private

    private static let log = Logger(
        subsystem: "com.jsvana.CarrierWave",
        category: "FT8SessionManager"
    )

    /// Maximum number of decode results to retain (~4 minutes of decodes).
    private static let maxDecodeResults = 500

    private let audioEngine = FT8AudioEngine()
    private var slotTimer: Timer?
    private var cycleTimer: Timer?
    private var isEvenSlot = true
    private var transmitOnEven = true
    private var currentSlotStartTime = Date()
    private let modelContext: ModelContext
    private let loggingSessionManager: LoggingSessionManager

    // MARK: - Decoding

    private func handleDecodedSlot(_ samples: [Float]) {
        let results = FT8Decoder.decode(samples: samples)
        currentCycleDecodes = results
        decodeResults.append(contentsOf: results)

        // Trim old decodes
        if decodeResults.count > Self.maxDecodeResults {
            decodeResults.removeFirst(decodeResults.count - Self.maxDecodeResults)
        }

        // Process each decode and check for completion after each message
        for result in results {
            qsoStateMachine.processMessage(result.message)

            if qsoStateMachine.state == .complete,
               let completed = qsoStateMachine.completedQSO
            {
                logCompletedQSO(completed)
                qsoStateMachine.resetForNextQSO()
            }
        }
    }

    // MARK: - Transmitting

    private func transmitIfNeeded() {
        if case .listen = operatingMode {
            return
        }
        guard let message = qsoStateMachine.nextTXMessage else {
            return
        }

        do {
            let samples = try FT8Encoder.encode(
                message: message,
                frequency: 1_500 // Default audio offset
            )
            isTransmitting = true
            Task { @MainActor [weak self] in
                await self?.audioEngine.playTones(samples)
                self?.isTransmitting = false
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
        qsoStateMachine.advanceCycle()

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
        Self.log.info("FT8 QSO logged: \(completed.theirCallsign)")
    }

    private func formatReport(_ report: Int?) -> String {
        guard let report else {
            return "+00" // Neutral fallback for unknown FT8 dB report
        }
        let sign = report >= 0 ? "+" : "-"
        return "\(sign)\(String(format: "%02d", abs(report)))"
    }
}
