import CarrierWaveData
import Foundation

// MARK: - CWSignalResult

/// Result of processing an audio buffer through the CW signal pipeline
struct CWSignalResult {
    /// Key state changes detected in this buffer: (isKeyDown, timestamp)
    let keyEvents: [(isDown: Bool, timestamp: TimeInterval)]

    /// Peak amplitude of the filtered signal (0.0-1.0)
    let peakAmplitude: Float

    /// Current key state at end of buffer
    let isKeyDown: Bool

    /// Recent envelope samples for visualization
    let envelopeSamples: [Float]

    /// Whether still in calibration period
    let isCalibrating: Bool

    /// Current noise floor level (0.0-1.0, normalized)
    let noiseFloor: Float

    /// Current signal-to-noise ratio (higher = cleaner signal)
    let signalToNoiseRatio: Float

    /// Detected tone frequency when using adaptive frequency mode (nil if fixed)
    let detectedFrequency: Double?
}

// MARK: - CWSignalProcessorProtocol

/// Protocol defining the interface for CW signal processors
protocol CWSignalProcessorProtocol: Actor {
    /// Current tone frequency being detected
    var currentToneFrequency: Double { get }

    /// Process an audio buffer and return signal analysis results
    /// - Parameters:
    ///   - samples: Raw audio samples from microphone
    ///   - timestamp: Timestamp of buffer start
    /// - Returns: Signal processing result with key events and visualization data
    func process(samples: [Float], timestamp: TimeInterval) -> CWSignalResult

    /// Update the tone frequency for detection
    /// - Parameter frequency: New tone frequency in Hz
    func setToneFrequency(_ frequency: Double)

    /// Reset all processor state (call when starting new capture)
    func reset()
}

// MARK: - GoertzelSignalProcessor + CWSignalProcessorProtocol

extension GoertzelSignalProcessor: CWSignalProcessorProtocol {}
