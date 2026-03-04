import CarrierWaveData
import Foundation

// MARK: - GoertzelThreshold

/// Adaptive threshold for Goertzel magnitude-based key detection
struct GoertzelThreshold: Sendable {
    // MARK: Lifecycle

    nonisolated init() {}

    // MARK: Internal

    /// Current key state
    nonisolated var currentKeyState: Bool {
        isKeyDown
    }

    /// Whether still in calibration period
    nonisolated var isCalibrating: Bool {
        blockCount < calibrationBlocks
    }

    /// Current noise floor level
    nonisolated var currentNoiseFloor: Float {
        noiseFloor
    }

    /// Current signal peak level
    nonisolated var currentSignalPeak: Float {
        signalPeak
    }

    /// Signal-to-noise ratio
    nonisolated var signalToNoiseRatio: Float {
        guard noiseFloor > 0.0001 else {
            return 0
        }
        return signalPeak / noiseFloor
    }

    /// Process a magnitude value and detect key state changes
    nonisolated mutating func process(
        magnitude: Float,
        blockDuration: Double,
        blockStartTime: TimeInterval
    ) -> (isDown: Bool, timestamp: TimeInterval)? {
        blockCount += 1

        // Apply smoothing to reduce block-to-block variance from noise
        smoothedMagnitude =
            smoothedMagnitude * magnitudeSmoothing
                + magnitude * (1.0 - magnitudeSmoothing)
        let effectiveMagnitude = smoothedMagnitude

        // Update signal estimates (pass current transmission state)
        updateSignalEstimates(magnitude: effectiveMagnitude, blockStartTime: blockStartTime)

        // Don't detect during calibration
        guard !isCalibrating else {
            return nil
        }

        // Calculate threshold dynamically
        // Use the locked noise floor during active transmission for stability
        let effectiveNoiseFloor = isInTransmission ? lockedNoiseFloor : noiseFloor
        let ratio = effectiveMagnitude / max(effectiveNoiseFloor, 0.0001)

        // Adaptive threshold based on signal quality
        let effectiveOnThreshold = calculateEffectiveOnThreshold()
        let effectiveOffThreshold = effectiveOnThreshold * offThresholdRatio

        // Update confirmation counters
        updateConfirmationCounters(
            ratio: ratio, onThreshold: effectiveOnThreshold, offThreshold: effectiveOffThreshold
        )

        let wasKeyDown = isKeyDown
        let timeSinceChange = blockStartTime - lastStateChangeTime

        // Process state transitions
        processStateTransitions(
            effectiveMagnitude: effectiveMagnitude,
            timeSinceChange: timeSinceChange,
            blockStartTime: blockStartTime
        )

        // Check if transmission has ended (extended silence)
        checkTransmissionEnd(blockStartTime: blockStartTime)

        // Return event if state changed
        if isKeyDown != wasKeyDown {
            lastStateChangeTime = blockStartTime
            let eventTime = blockStartTime + blockDuration / 2 // Mid-block timing
            return (isDown: isKeyDown, timestamp: eventTime)
        }

        return nil
    }

    /// Reset threshold state
    nonisolated mutating func reset() {
        signalPeak = 0
        noiseFloor = 0.01
        smoothedMagnitude = 0
        isKeyDown = false
        blockCount = 0
        activeSignalLevel = 0
        lastStateChangeTime = 0
        blocksAboveThreshold = 0
        blocksBelowThreshold = 0
        isInTransmission = false
        lockedNoiseFloor = 0.01
        transmissionStartTime = 0
        lastKeyEventTime = 0
    }

    // MARK: Private

    private var signalPeak: Float = 0
    private var noiseFloor: Float = 0.01
    private var smoothedMagnitude: Float = 0
    private var isKeyDown = false
    private var blockCount: Int = 0
    private var activeSignalLevel: Float = 0
    private var lastStateChangeTime: TimeInterval = 0

    // Transmission tracking
    private var isInTransmission = false
    private var lockedNoiseFloor: Float = 0.01
    private var transmissionStartTime: TimeInterval = 0
    private var lastKeyEventTime: TimeInterval = 0
    private let transmissionEndTimeout: TimeInterval = 2.0

    // Confirmation counters
    private var blocksAboveThreshold: Int = 0
    private var blocksBelowThreshold: Int = 0

    // Configuration constants
    private let calibrationBlocks: Int = 30
    private let confirmationBlocksOn: Int = 3
    private let confirmationBlocksOff: Int = 3
    private let confirmationBlocksOffInTransmission: Int = 3
    private let minimumStateDuration: TimeInterval = 0.012
    private let magnitudeSmoothing: Float = 0.5
    private let baseOnThreshold: Float = 8.0
    private let minOnThreshold: Float = 6.0
    private let offThresholdRatio: Float = 0.5
    private let dropThreshold: Float = 0.6
    private let peakDecay: Float = 0.995
    private let noiseDecay: Float = 0.99
    private let activeDecay: Float = 0.95

    nonisolated private func calculateEffectiveOnThreshold() -> Float {
        let snr = signalToNoiseRatio
        if snr > 10 {
            return baseOnThreshold
        } else if snr > 3 {
            let interpFactor = (snr - 3) / 7.0
            return minOnThreshold + (baseOnThreshold - minOnThreshold) * interpFactor
        } else {
            return minOnThreshold
        }
    }

    nonisolated private mutating func updateConfirmationCounters(
        ratio: Float, onThreshold: Float, offThreshold: Float
    ) {
        if ratio > onThreshold {
            blocksAboveThreshold += 1
            blocksBelowThreshold = 0
        } else if ratio < offThreshold {
            blocksBelowThreshold += 1
            blocksAboveThreshold = 0
        } else {
            blocksAboveThreshold = max(0, blocksAboveThreshold - 1)
            blocksBelowThreshold = max(0, blocksBelowThreshold - 1)
        }
    }

    nonisolated private mutating func processStateTransitions(
        effectiveMagnitude: Float,
        timeSinceChange: TimeInterval,
        blockStartTime: TimeInterval
    ) {
        let onConfirmation = confirmationBlocksOn
        let offConfirmation =
            isInTransmission ? confirmationBlocksOffInTransmission : confirmationBlocksOff

        if !isKeyDown {
            if blocksAboveThreshold >= onConfirmation, timeSinceChange >= minimumStateDuration {
                isKeyDown = true
                activeSignalLevel = effectiveMagnitude
                blocksAboveThreshold = 0

                if !isInTransmission {
                    isInTransmission = true
                    lockedNoiseFloor = noiseFloor
                    transmissionStartTime = blockStartTime
                }
                lastKeyEventTime = blockStartTime
            }
        } else {
            if effectiveMagnitude > activeSignalLevel {
                activeSignalLevel = effectiveMagnitude
            } else {
                activeSignalLevel *= activeDecay
            }

            let relativeDrop = effectiveMagnitude / max(activeSignalLevel, 0.0001)
            if timeSinceChange >= minimumStateDuration {
                let belowThresholdConfirmed = blocksBelowThreshold >= offConfirmation
                let significantDrop = relativeDrop < dropThreshold && blocksBelowThreshold >= 2

                if belowThresholdConfirmed || significantDrop {
                    isKeyDown = false
                    blocksBelowThreshold = 0
                    lastKeyEventTime = blockStartTime
                }
            }
        }
    }

    nonisolated private mutating func checkTransmissionEnd(blockStartTime: TimeInterval) {
        if isInTransmission, !isKeyDown {
            let silenceDuration = blockStartTime - lastKeyEventTime
            if silenceDuration > transmissionEndTimeout {
                isInTransmission = false
            }
        }
    }

    nonisolated private mutating func updateSignalEstimates(
        magnitude: Float, blockStartTime: TimeInterval
    ) {
        if magnitude > signalPeak {
            signalPeak = magnitude
        } else {
            signalPeak *= peakDecay
        }

        let inActiveTransmission = isInTransmission && (blockStartTime - lastKeyEventTime < 1.0)

        if magnitude < noiseFloor {
            let dropRate: Float = inActiveTransmission ? 0.02 : 0.1
            noiseFloor = noiseFloor * (1.0 - dropRate) + magnitude * dropRate
        } else if !inActiveTransmission, magnitude < noiseFloor * baseOnThreshold {
            let adaptRate: Float = blockCount < calibrationBlocks ? 0.1 : 0.02
            noiseFloor = noiseFloor * (1.0 - adaptRate) + magnitude * adaptRate
        }
        noiseFloor = max(noiseFloor, 0.0001)
    }
}
