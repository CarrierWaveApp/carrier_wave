import CarrierWaveData
import Foundation

// MARK: - GoertzelFilter

/// Goertzel algorithm implementation for efficient single-frequency detection
/// More computationally efficient than FFT when detecting only one frequency
struct GoertzelFilter: Sendable {
    // MARK: Lifecycle

    /// Create a Goertzel filter for a specific frequency
    /// - Parameters:
    ///   - targetFrequency: The frequency to detect (Hz)
    ///   - sampleRate: Audio sample rate (Hz)
    ///   - blockSize: Number of samples per block (affects frequency resolution)
    nonisolated init(targetFrequency: Double, sampleRate: Double, blockSize: Int) {
        self.targetFrequency = targetFrequency
        self.sampleRate = sampleRate
        self.blockSize = blockSize

        // Calculate the Goertzel coefficient: 2 * cos(2 * pi * k / N)
        // where k = targetFrequency * N / sampleRate
        let k = targetFrequency * Double(blockSize) / sampleRate
        let omega = 2.0 * Double.pi * k / Double(blockSize)
        coefficient = 2.0 * cos(omega)

        // Pre-calculate for power computation
        cosOmega = cos(omega)
        sinOmega = sin(omega)
    }

    // MARK: Internal

    let targetFrequency: Double
    let sampleRate: Double
    let blockSize: Int
    let coefficient: Double

    /// Process a block of samples and return the magnitude at the target frequency
    /// - Parameter samples: Audio samples (should be exactly blockSize samples)
    /// - Returns: Magnitude at the target frequency (normalized by block size)
    nonisolated func processSamples(_ samples: [Float]) -> Float {
        var s1 = 0.0
        var s2 = 0.0

        // Main Goertzel recursion
        for sample in samples {
            let s0 = Double(sample) + coefficient * s1 - s2
            s2 = s1
            s1 = s0
        }

        // Compute power: |X[k]|² = s1² + s2² - coeff * s1 * s2
        let power = s1 * s1 + s2 * s2 - coefficient * s1 * s2

        // Return magnitude normalized by block size
        let magnitude = sqrt(max(0, power)) / Double(blockSize)
        return Float(magnitude)
    }

    /// Process samples and return both real and imaginary components
    /// - Parameter samples: Audio samples
    /// - Returns: Tuple of (real, imaginary) components
    nonisolated func processComplex(_ samples: [Float]) -> (real: Double, imag: Double) {
        var s1 = 0.0
        var s2 = 0.0

        for sample in samples {
            let s0 = Double(sample) + coefficient * s1 - s2
            s2 = s1
            s1 = s0
        }

        // Real = s1 - s2 * cos(omega)
        // Imag = s2 * sin(omega)
        let real = s1 - s2 * cosOmega
        let imag = s2 * sinOmega

        return (real, imag)
    }

    // MARK: Private

    private let cosOmega: Double
    private let sinOmega: Double
}
