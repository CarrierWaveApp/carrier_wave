//
//  FT8WaterfallData.swift
//  CarrierWave
//

import Accelerate
import CarrierWaveCore
import Foundation

/// Computes and stores FFT spectrogram data for the FT8 waterfall display.
@MainActor @Observable
final class FT8WaterfallData {
    // MARK: Lifecycle

    init() {
        let size = Self.fftSize
        let log2n = vDSP_Length(log2(Float(size)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))

        var window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        hannWindow = window
    }

    // MARK: Internal

    /// 2D array of magnitude values [time][frequency], normalized 0-1.
    private(set) var magnitudes: [[Float]] = []

    /// Number of frequency bins.
    private(set) var frequencyBins: Int = 0

    /// Frequency range in Hz.
    let minFrequency: Float = 100
    let maxFrequency: Float = 3_000

    /// Process a chunk of audio samples and add rows to the waterfall.
    func processAudio(_ samples: [Float]) {
        guard samples.count >= Self.fftSize, let setup = fftSetup else {
            return
        }

        // Process in fftSize chunks
        var offset = 0
        while offset + Self.fftSize <= samples.count {
            let chunk = Array(samples[offset ..< offset + Self.fftSize])
            let spectrum = computeSpectrum(chunk, setup: setup)
            magnitudes.append(spectrum)
            offset += Self.fftSize
        }

        // Trim old rows
        if magnitudes.count > Self.maxRows {
            magnitudes.removeFirst(magnitudes.count - Self.maxRows)
        }

        if frequencyBins == 0, let first = magnitudes.first {
            frequencyBins = first.count
        }
    }

    func clear() {
        magnitudes.removeAll()
        frequencyBins = 0
    }

    // MARK: Private

    /// Maximum number of time rows to keep (~2.5 slots = ~38 seconds).
    private static let maxRows = 240

    /// FFT size — must be power of two for vDSP_fft_zrip (5.86 Hz bins at 12 kHz).
    private static let fftSize = 2_048

    /// Precomputed FFT setup (created once in init).
    @ObservationIgnored private var fftSetup: FFTSetup?

    /// Precomputed Hann window coefficients (created once in init).
    @ObservationIgnored private var hannWindow: [Float]

    private func computeSpectrum(_ samples: [Float], setup: FFTSetup) -> [Float] {
        let n = samples.count
        let halfN = n / 2

        let mags = computeFFTMagnitudes(samples, halfN: halfN, setup: setup)
        return normalizeSpectrum(mags, n: n, halfN: halfN)
    }

    /// Apply Hann window, run FFT, and return raw magnitude-squared values.
    private func computeFFTMagnitudes(
        _ samples: [Float],
        halfN: Int,
        setup: FFTSetup
    ) -> [Float] {
        let n = samples.count
        let log2n = vDSP_Length(log2(Float(n)))

        // Apply precomputed Hann window
        var windowed = [Float](repeating: 0, count: n)
        vDSP_vmul(samples, 1, hannWindow, 1, &windowed, 1, vDSP_Length(n))

        var realPart = [Float](repeating: 0, count: halfN)
        var imagPart = [Float](repeating: 0, count: halfN)
        var mags = [Float](repeating: 0, count: halfN)

        // All DSP operations within proper pointer scope
        realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                guard let realPtr = realBuf.baseAddress,
                      let imagPtr = imagBuf.baseAddress
                else {
                    return
                }
                var split = DSPSplitComplex(realp: realPtr, imagp: imagPtr)

                // Convert interleaved to split complex
                windowed.withUnsafeBufferPointer { windowedBuf in
                    guard let base = windowedBuf.baseAddress else {
                        return
                    }
                    base.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(halfN))
                    }
                }

                // Forward FFT and compute magnitudes
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(halfN))
            }
        }

        return mags
    }

    /// Convert raw magnitudes to dB, extract frequency range, and normalize to [0, 1].
    private func normalizeSpectrum(_ mags: [Float], n: Int, halfN: Int) -> [Float] {
        // Convert to dB: add epsilon, log10, scale by 10 (input is magnitude-squared)
        var dbMags = mags
        var epsilon: Float = 1e-10
        vDSP_vsadd(dbMags, 1, &epsilon, &dbMags, 1, vDSP_Length(halfN))

        var logMags = [Float](repeating: 0, count: halfN)
        var count = Int32(halfN)
        vvlog10f(&logMags, dbMags, &count)

        var scale: Float = 10.0
        vDSP_vsmul(logMags, 1, &scale, &logMags, 1, vDSP_Length(halfN))

        // Extract useful frequency range (100-3000 Hz)
        let binSpacing = Float(FT8Constants.sampleRate) / Float(n)
        let minBin = Int(minFrequency / binSpacing)
        let maxBin = min(Int(maxFrequency / binSpacing), halfN - 1)
        let usefulBins = Array(logMags[minBin ... maxBin])

        // Normalize: map [-80, 0] dB to [0, 1], clamped
        var normalized = [Float](repeating: 0, count: usefulBins.count)
        var offset: Float = 80
        vDSP_vsadd(usefulBins, 1, &offset, &normalized, 1, vDSP_Length(usefulBins.count))
        var divisor: Float = 80
        vDSP_vsdiv(normalized, 1, &divisor, &normalized, 1, vDSP_Length(normalized.count))

        var low: Float = 0
        var high: Float = 1
        vDSP_vclip(normalized, 1, &low, &high, &normalized, 1, vDSP_Length(normalized.count))

        return normalized
    }
}
