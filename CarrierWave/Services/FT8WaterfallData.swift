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
        guard samples.count >= fftSize else {
            return
        }

        // Process in fftSize chunks
        var offset = 0
        while offset + fftSize <= samples.count {
            let chunk = Array(samples[offset ..< offset + fftSize])
            let spectrum = computeSpectrum(chunk)
            magnitudes.append(spectrum)
            offset += fftSize
        }

        // Trim old rows
        if magnitudes.count > maxRows {
            magnitudes.removeFirst(magnitudes.count - maxRows)
        }

        if frequencyBins == 0, let first = magnitudes.first {
            frequencyBins = first.count
        }
    }

    func clear() {
        magnitudes.removeAll()
    }

    // MARK: Private

    /// Maximum number of time rows to keep (4 slots = ~60 seconds).
    private let maxRows = 240

    /// FFT size matching ft8_lib's resolution (6.25 Hz bins at 12 kHz).
    private let fftSize = 1_920

    @ObservationIgnored private lazy var fftSetup: FFTSetup? = {
        let log2n = vDSP_Length(log2(Float(fftSize)))
        return vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    }()

    private func computeSpectrum(_ samples: [Float]) -> [Float] {
        let n = samples.count
        let halfN = n / 2
        guard let setup = fftSetup else {
            return []
        }

        let mags = computeFFTMagnitudes(samples, n: n, halfN: halfN, setup: setup)
        return normalizeSpectrum(mags, n: n, halfN: halfN)
    }

    /// Apply Hann window, run FFT, and return raw magnitude-squared values.
    private func computeFFTMagnitudes(
        _ samples: [Float],
        n: Int,
        halfN: Int,
        setup: FFTSetup
    ) -> [Float] {
        let log2n = vDSP_Length(log2(Float(n)))

        // Apply Hann window
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        var windowed = [Float](repeating: 0, count: n)
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(n))

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
        // Convert to dB: add epsilon, log10, scale by 20
        var dbMags = mags
        var epsilon: Float = 1e-10
        vDSP_vsadd(dbMags, 1, &epsilon, &dbMags, 1, vDSP_Length(halfN))

        var logMags = [Float](repeating: 0, count: halfN)
        var count = Int32(halfN)
        vvlog10f(&logMags, dbMags, &count)

        var scale: Float = 20.0
        vDSP_vsmul(logMags, 1, &scale, &logMags, 1, vDSP_Length(halfN))

        // Extract useful frequency range (100-3000 Hz)
        let binSpacing = Float(FT8Constants.sampleRate) / Float(n) // 6.25 Hz
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
