import Accelerate
import CarrierWaveData
import Foundation

// MARK: - FrequencyBin

/// A single frequency bin in the adaptive filter bank
private struct FrequencyBin {
    let frequency: Double
    let filter: GoertzelFilter
    var recentMagnitude: Float = 0
}

// MARK: - GoertzelSignalProcessor

/// Signal processor using the Goertzel algorithm for CW tone detection
/// Alternative to bandpass filter approach - more computationally efficient
/// for single-frequency detection
///
/// Supports adaptive frequency detection: when initialized with a frequency range,
/// uses a bank of Goertzel filters to find the strongest tone automatically.
actor GoertzelSignalProcessor {
    // MARK: Lifecycle

    /// Create a Goertzel-based signal processor with fixed frequency
    /// - Parameters:
    ///   - sampleRate: Audio sample rate (typically 44100)
    ///   - toneFrequency: CW sidetone frequency (default 600 Hz)
    ///   - blockSize: Samples per Goertzel block (default 128, ~3ms at 44.1kHz)
    init(sampleRate: Double, toneFrequency: Double = 600, blockSize: Int = 128) {
        self.sampleRate = sampleRate
        self.toneFrequency = toneFrequency
        self.blockSize = blockSize
        adaptiveMode = false
        minFrequency = toneFrequency
        maxFrequency = toneFrequency
        frequencyStep = 50

        goertzelFilter = GoertzelFilter(
            targetFrequency: toneFrequency,
            sampleRate: sampleRate,
            blockSize: blockSize
        )
        threshold = GoertzelThreshold()
        filterBank = []

        blockDuration = Double(blockSize) / sampleRate
    }

    /// Create a Goertzel-based signal processor with adaptive frequency detection
    /// - Parameters:
    ///   - sampleRate: Audio sample rate (typically 44100)
    ///   - minFrequency: Minimum frequency to scan (Hz)
    ///   - maxFrequency: Maximum frequency to scan (Hz)
    ///   - frequencyStep: Step size between frequency bins (Hz, default 50)
    ///   - blockSize: Samples per Goertzel block (default 128, ~3ms at 44.1kHz)
    init(
        sampleRate: Double,
        minFrequency: Double = 400,
        maxFrequency: Double = 900,
        frequencyStep: Double = 50,
        blockSize: Int = 128
    ) {
        self.sampleRate = sampleRate
        self.blockSize = blockSize
        adaptiveMode = true
        self.minFrequency = minFrequency
        self.maxFrequency = maxFrequency
        self.frequencyStep = frequencyStep

        // Start with center frequency
        let centerFrequency = (minFrequency + maxFrequency) / 2
        toneFrequency = centerFrequency

        goertzelFilter = GoertzelFilter(
            targetFrequency: centerFrequency,
            sampleRate: sampleRate,
            blockSize: blockSize
        )
        threshold = GoertzelThreshold()

        // Build filter bank
        var bins: [FrequencyBin] = []
        var freq = minFrequency
        while freq <= maxFrequency {
            let filter = GoertzelFilter(
                targetFrequency: freq,
                sampleRate: sampleRate,
                blockSize: blockSize
            )
            bins.append(FrequencyBin(frequency: freq, filter: filter))
            freq += frequencyStep
        }
        filterBank = bins

        blockDuration = Double(blockSize) / sampleRate
    }

    // MARK: Internal

    /// Get current tone frequency
    var currentToneFrequency: Double {
        toneFrequency
    }

    /// Process an audio buffer through the Goertzel pipeline
    func process(samples: [Float], timestamp: TimeInterval) -> CWSignalResult {
        let (keyEvents, magnitudes) = processBlocks(samples: samples, timestamp: timestamp)
        let peakMagnitude = magnitudes.max() ?? 0

        updateRunningMax(peakMagnitude: peakMagnitude)
        updateVisualizationBuffer(magnitudes)

        let normalizedPeak = min(1.0, peakMagnitude / max(runningMax, 0.0001))
        let normalizedNoiseFloor = min(1.0, threshold.currentNoiseFloor / max(runningMax, 0.0001))

        return CWSignalResult(
            keyEvents: keyEvents,
            peakAmplitude: normalizedPeak,
            isKeyDown: threshold.currentKeyState,
            envelopeSamples: recentMagnitudes,
            isCalibrating: threshold.isCalibrating,
            noiseFloor: normalizedNoiseFloor,
            signalToNoiseRatio: threshold.signalToNoiseRatio,
            detectedFrequency: adaptiveMode ? toneFrequency : nil
        )
    }

    /// Update the tone frequency
    /// - Parameter frequency: New tone frequency in Hz
    func setToneFrequency(_ frequency: Double) {
        toneFrequency = frequency
        goertzelFilter = GoertzelFilter(
            targetFrequency: frequency,
            sampleRate: sampleRate,
            blockSize: blockSize
        )
    }

    /// Reset all processor state
    func reset() {
        threshold.reset()
        leftoverSamples = []
        recentMagnitudes = []
        runningMax = 0.01 // Match initial noise floor

        // Reset adaptive frequency state
        frequencyLockCounter = 0
        candidateFrequency = 0
        isFrequencyLocked = false

        // Reset bin magnitudes
        for i in 0 ..< filterBank.count {
            filterBank[i].recentMagnitude = 0
        }

        // Reset to center frequency in adaptive mode
        if adaptiveMode {
            let centerFrequency = (minFrequency + maxFrequency) / 2
            toneFrequency = centerFrequency
            goertzelFilter = GoertzelFilter(
                targetFrequency: centerFrequency,
                sampleRate: sampleRate,
                blockSize: blockSize
            )
        }
    }

    // MARK: Private

    private var goertzelFilter: GoertzelFilter
    private var threshold: GoertzelThreshold

    private let sampleRate: Double
    private var toneFrequency: Double
    private let blockSize: Int
    private let blockDuration: Double

    // Adaptive frequency detection
    private let adaptiveMode: Bool
    private let minFrequency: Double
    private let maxFrequency: Double
    private let frequencyStep: Double
    private var filterBank: [FrequencyBin]

    /// Number of consecutive blocks a frequency must be strongest to lock
    private let frequencyLockThreshold: Int = 15
    /// Counter for frequency lock confirmation
    private var frequencyLockCounter: Int = 0
    /// Candidate frequency being evaluated
    private var candidateFrequency: Double = 0
    /// Whether frequency is currently locked (stable signal detected)
    private var isFrequencyLocked: Bool = false
    /// Minimum magnitude ratio vs noise to consider a frequency active
    private let frequencyDetectionRatio: Float = 5.0
    /// Smoothing factor for bin magnitudes (0-1, higher = more smoothing)
    private let binMagnitudeSmoothing: Float = 0.85
    /// Minimum absolute magnitude to consider (ignore very weak signals)
    private let minimumDetectionMagnitude: Float = 0.0005

    /// Buffer for samples that don't fill a complete block
    private var leftoverSamples: [Float] = []

    // Visualization
    private let visualizationSampleCount = 128
    private var recentMagnitudes: [Float] = []

    // Normalization
    private var runningMax: Float = 0.01 // Match initial noise floor
    private let maxDecay: Float = 0.9995

    /// Pre-computed Hamming window
    private lazy var hammingWindow: [Float] = {
        var window = [Float](repeating: 0, count: blockSize)
        for i in 0 ..< blockSize {
            window[i] = Float(
                0.54 - 0.46 * cos(2.0 * Double.pi * Double(i) / Double(blockSize - 1))
            )
        }
        return window
    }()

    private func processBlocks(
        samples: [Float],
        timestamp: TimeInterval
    ) -> (keyEvents: [(isDown: Bool, timestamp: TimeInterval)], magnitudes: [Float]) {
        var keyEvents: [(isDown: Bool, timestamp: TimeInterval)] = []
        var magnitudes: [Float] = []
        var sampleIndex = 0
        var blockStartTime = timestamp

        let workingSamples = leftoverSamples + samples
        leftoverSamples = []

        while sampleIndex + blockSize <= workingSamples.count {
            let block = Array(workingSamples[sampleIndex ..< sampleIndex + blockSize])
            let windowedBlock = applyHammingWindow(block)

            if adaptiveMode {
                updateFrequencyTracking(
                    windowedBlock: windowedBlock, currentNoiseFloor: threshold.currentNoiseFloor
                )
            }

            let magnitude = goertzelFilter.processSamples(windowedBlock)
            magnitudes.append(magnitude)

            if let event = threshold.process(
                magnitude: magnitude,
                blockDuration: blockDuration,
                blockStartTime: blockStartTime
            ) {
                keyEvents.append(event)
            }

            sampleIndex += blockSize
            blockStartTime += blockDuration
        }

        if sampleIndex < workingSamples.count {
            leftoverSamples = Array(workingSamples[sampleIndex...])
        }

        return (keyEvents, magnitudes)
    }

    private func updateRunningMax(peakMagnitude: Float) {
        if peakMagnitude > runningMax {
            runningMax = peakMagnitude
        } else {
            runningMax *= maxDecay
        }
    }

    private func applyHammingWindow(_ samples: [Float]) -> [Float] {
        var result = [Float](repeating: 0, count: samples.count)
        vDSP_vmul(samples, 1, hammingWindow, 1, &result, 1, vDSP_Length(samples.count))
        return result
    }

    private func updateVisualizationBuffer(_ magnitudes: [Float]) {
        recentMagnitudes.append(contentsOf: magnitudes)

        // Keep only recent samples
        if recentMagnitudes.count > visualizationSampleCount {
            recentMagnitudes.removeFirst(recentMagnitudes.count - visualizationSampleCount)
        }
    }

    /// Update frequency tracking by scanning all bins in the filter bank
    private func updateFrequencyTracking(windowedBlock: [Float], currentNoiseFloor: Float) {
        guard !filterBank.isEmpty else {
            return
        }

        let currentFreqMagnitude = goertzelFilter.processSamples(windowedBlock)

        // If locked with no signal, decay bins and skip scanning
        if isFrequencyLocked,
           !hasActiveSignal(magnitude: currentFreqMagnitude, noiseFloor: currentNoiseFloor)
        {
            decayBinMagnitudes()
            return
        }

        let (strongestFrequency, strongestMagnitude) = findStrongestBin(
            windowedBlock: windowedBlock
        )

        guard hasStrongSignal(magnitude: strongestMagnitude, noiseFloor: currentNoiseFloor) else {
            if frequencyLockCounter > 0, !isFrequencyLocked {
                frequencyLockCounter -= 1
            }
            return
        }

        updateFrequencyCandidate(
            strongestFrequency: strongestFrequency,
            strongestMagnitude: strongestMagnitude,
            currentFreqMagnitude: currentFreqMagnitude
        )
        checkForFrequencySwitch()
    }

    private func hasActiveSignal(magnitude: Float, noiseFloor: Float) -> Bool {
        let ratio = magnitude / max(noiseFloor, 0.0001)
        return ratio > frequencyDetectionRatio && magnitude > minimumDetectionMagnitude
    }

    private func hasStrongSignal(magnitude: Float, noiseFloor: Float) -> Bool {
        let ratio = magnitude / max(noiseFloor, 0.0001)
        return ratio > frequencyDetectionRatio && magnitude > minimumDetectionMagnitude
    }

    private func decayBinMagnitudes() {
        for i in 0 ..< filterBank.count {
            filterBank[i].recentMagnitude *= 0.9
        }
    }

    private func findStrongestBin(windowedBlock: [Float]) -> (frequency: Double, magnitude: Float) {
        var strongestBinIndex = 0
        var strongestMagnitude: Float = 0

        for i in 0 ..< filterBank.count {
            let rawMagnitude = filterBank[i].filter.processSamples(windowedBlock)
            let smoothed =
                filterBank[i].recentMagnitude * binMagnitudeSmoothing
                    + rawMagnitude * (1.0 - binMagnitudeSmoothing)
            filterBank[i].recentMagnitude = smoothed

            if smoothed > strongestMagnitude {
                strongestMagnitude = smoothed
                strongestBinIndex = i
            }
        }

        return (filterBank[strongestBinIndex].frequency, strongestMagnitude)
    }

    private func updateFrequencyCandidate(
        strongestFrequency: Double,
        strongestMagnitude: Float,
        currentFreqMagnitude: Float
    ) {
        if abs(strongestFrequency - candidateFrequency) < frequencyStep / 2 {
            frequencyLockCounter += 1
            if frequencyLockCounter >= frequencyLockThreshold, !isFrequencyLocked {
                lockToFrequency(strongestFrequency)
            }
        } else if isFrequencyLocked {
            if strongestMagnitude > currentFreqMagnitude * 2.5 {
                candidateFrequency = strongestFrequency
                frequencyLockCounter = 1
            }
        } else {
            candidateFrequency = strongestFrequency
            frequencyLockCounter = 1
        }
    }

    private func checkForFrequencySwitch() {
        if isFrequencyLocked, frequencyLockCounter >= frequencyLockThreshold,
           abs(candidateFrequency - toneFrequency) > frequencyStep / 2
        {
            isFrequencyLocked = false
            lockToFrequency(candidateFrequency)
        }
    }

    /// Lock onto a frequency (confirmed stable signal)
    private func lockToFrequency(_ frequency: Double) {
        guard abs(frequency - toneFrequency) > 1.0 else {
            // Already at this frequency, just mark as locked
            isFrequencyLocked = true
            return
        }

        toneFrequency = frequency
        goertzelFilter = GoertzelFilter(
            targetFrequency: frequency,
            sampleRate: sampleRate,
            blockSize: blockSize
        )
        // Reset threshold to recalibrate for the new frequency
        threshold.reset()
        isFrequencyLocked = true
    }
}
