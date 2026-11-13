//
//  FT8AudioBandpassFilter.swift
//  CarrierWave
//

import Accelerate
import Foundation

// MARK: - FT8AudioBandpassFilter

/// Cascaded 2nd-order Butterworth biquads forming a band-pass over the FT8
/// audio passband (200–2900 Hz at the engine's target rate). The level meter
/// and overload detector measure RMS/peak on the filtered output — wide-band
/// peak detection mis-fires on adjacent-channel signals (broadcast splatter,
/// out-of-passband carriers) that don't affect FT8 decoding but trivially
/// peg an unfiltered meter.
///
/// State (z1, z2 per section) is retained across `process` calls so the
/// filter is continuous across tap buffers; call `reset()` on route change
/// or interruption resume to clear the delay lines.
nonisolated final class FT8AudioBandpassFilter {
    // MARK: Lifecycle

    init(sampleRate: Double, lowCutHz: Double = 200, highCutHz: Double = 2_900) {
        highpass = Biquad.butterworthHighpass(cutoffHz: lowCutHz, sampleRateHz: sampleRate)
        lowpass = Biquad.butterworthLowpass(cutoffHz: highCutHz, sampleRateHz: sampleRate)
    }

    // MARK: Internal

    /// Apply the bandpass to `samples` in place and return RMS + peak of the
    /// filtered signal. Avoids a second allocation for the filtered buffer
    /// when only the level stats are needed.
    func levelOfFiltered(_ samples: [Float]) -> (rms: Float, peak: Float) {
        guard !samples.isEmpty else {
            return (0, 0)
        }
        var filtered = samples
        highpass.processInPlace(&filtered)
        lowpass.processInPlace(&filtered)

        var rms: Float = 0
        var peak: Float = 0
        filtered.withUnsafeBufferPointer { buf in
            guard let ptr = buf.baseAddress else {
                return
            }
            vDSP_rmsqv(ptr, 1, &rms, vDSP_Length(filtered.count))
            vDSP_maxmgv(ptr, 1, &peak, vDSP_Length(filtered.count))
        }
        return (rms, peak)
    }

    func reset() {
        highpass.reset()
        lowpass.reset()
    }

    // MARK: Private

    private let highpass: Biquad
    private let lowpass: Biquad
}

// MARK: - Biquad

/// Direct-form II transposed 2nd-order biquad. Stateful — `z1`/`z2` carry
/// across `processInPlace` calls so the filter is continuous across buffer
/// boundaries (no transient at every tap).
nonisolated private final class Biquad {
    // MARK: Lifecycle

    init(b0: Float, b1: Float, b2: Float, a1: Float, a2: Float) {
        self.b0 = b0
        self.b1 = b1
        self.b2 = b2
        self.a1 = a1
        self.a2 = a2
    }

    // MARK: Internal

    /// 2nd-order Butterworth high-pass, bilinear-transformed from analog
    /// prototype. Pre-warps the cutoff so the discrete-time -3 dB point
    /// matches `cutoffHz` exactly.
    static func butterworthHighpass(cutoffHz: Double, sampleRateHz: Double) -> Biquad {
        let kk = tan(.pi * cutoffHz / sampleRateHz)
        let sqrt2 = 2.0.squareRoot()
        let norm = 1.0 / (1.0 + kk * sqrt2 + kk * kk)
        return Biquad(
            b0: Float(norm),
            b1: Float(-2.0 * norm),
            b2: Float(norm),
            a1: Float(2.0 * (kk * kk - 1.0) * norm),
            a2: Float((1.0 - kk * sqrt2 + kk * kk) * norm)
        )
    }

    static func butterworthLowpass(cutoffHz: Double, sampleRateHz: Double) -> Biquad {
        let kk = tan(.pi * cutoffHz / sampleRateHz)
        let sqrt2 = 2.0.squareRoot()
        let norm = 1.0 / (1.0 + kk * sqrt2 + kk * kk)
        return Biquad(
            b0: Float(kk * kk * norm),
            b1: Float(2.0 * kk * kk * norm),
            b2: Float(kk * kk * norm),
            a1: Float(2.0 * (kk * kk - 1.0) * norm),
            a2: Float((1.0 - kk * sqrt2 + kk * kk) * norm)
        )
    }

    func processInPlace(_ samples: inout [Float]) {
        let b0 = b0, b1 = b1, b2 = b2, a1 = a1, a2 = a2
        var z1 = z1
        var z2 = z2
        for idx in samples.indices {
            let input = samples[idx]
            let output = b0 * input + z1
            z1 = b1 * input - a1 * output + z2
            z2 = b2 * input - a2 * output
            samples[idx] = output
        }
        self.z1 = z1
        self.z2 = z2
    }

    func reset() {
        z1 = 0
        z2 = 0
    }

    // MARK: Private

    private let b0, b1, b2, a1, a2: Float
    private var z1: Float = 0
    private var z2: Float = 0
}
