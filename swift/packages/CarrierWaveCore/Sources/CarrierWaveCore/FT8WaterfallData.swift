//
//  FT8WaterfallData.swift
//  CarrierWaveCore
//

import Accelerate
import Foundation

// MARK: - FT8WaterfallData

/// Published @MainActor state for the FT8 waterfall: the rolling magnitude
/// rows and the bin count. The expensive work (FFT, dB conversion, per-bin
/// percentile reference, vDSP) lives in `FT8WaterfallProcessor` and runs on a
/// background actor so it never blocks the main thread during TX cycles or
/// view rebuilds. The processor pushes new rows here via `append(rows:)`.
@MainActor @Observable
public final class FT8WaterfallData {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    /// Maximum number of time rows to keep (~2.5 slots ≈ 38 seconds).
    public static let maxRows = 240

    /// 2D array of magnitude values [time][frequency], normalized 0-1.
    public private(set) var magnitudes: [[Float]] = []

    /// Number of frequency bins.
    public private(set) var frequencyBins: Int = 0

    /// Frequency range in Hz.
    public let minFrequency: Float = 100
    public let maxFrequency: Float = 3_000

    /// Append new spectrum rows produced by `FT8WaterfallProcessor`.
    public func append(rows: [[Float]]) {
        guard !rows.isEmpty else {
            return
        }
        magnitudes.append(contentsOf: rows)
        if magnitudes.count > Self.maxRows {
            magnitudes.removeFirst(magnitudes.count - Self.maxRows)
        }
        if frequencyBins == 0, let first = magnitudes.first {
            frequencyBins = first.count
        }
    }

    public func clear() {
        magnitudes.removeAll()
        frequencyBins = 0
    }
}

// MARK: - FT8WaterfallProcessor

/// Background actor that owns the FFT machinery and per-bin reference
/// computation for the FT8 waterfall. Audio buffers from `FT8AudioEngine`
/// flow into `process(_:)`; new spectrum rows are pushed to the supplied
/// `FT8WaterfallData` on the main actor.
///
/// Splitting compute (here) from published state (`FT8WaterfallData`) keeps
/// the per-buffer FFT and the 496×~61-element percentile sort off the main
/// thread, where they used to land alongside SwiftUI rebuilds and TX state
/// transitions.
public actor FT8WaterfallProcessor {
    // MARK: Lifecycle

    public init(target: FT8WaterfallData) {
        self.target = target
        let size = Self.fftSize
        let log2n = vDSP_Length(log2(Float(size)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))

        var window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        hannWindow = window
    }

    // FFTSetup is a small one-shot allocation that lives for the lifetime of
    // the FT8 session. Matches the previous behaviour on the deprecated
    // @MainActor FT8WaterfallData where the setup was also never destroyed —
    // a per-session leak of a few hundred bytes, recovered when the FT8
    // session manager is released. An isolated deinit would be cleaner but
    // is unavailable on actors in current Swift.

    // MARK: Public

    /// Process a chunk of audio samples. Accumulates partial buffers until
    /// there are enough samples for a full FFT window, then publishes one or
    /// more spectrum rows to the bound `FT8WaterfallData` on the main actor.
    public func process(_ samples: [Float]) async {
        guard let setup = fftSetup else {
            return
        }

        pendingSamples.append(contentsOf: samples)

        var newRows: [[Float]] = []
        while pendingSamples.count >= Self.fftSize {
            let chunk = Array(pendingSamples.prefix(Self.fftSize))
            pendingSamples.removeFirst(Self.fftSize)
            let spectrum = computeSpectrum(chunk, setup: setup)
            newRows.append(spectrum)
        }

        // Cap pending buffer to prevent unbounded growth if processing falls
        // behind (e.g. main actor is briefly busy and the publish hop queues).
        if pendingSamples.count > Self.fftSize * 2 {
            pendingSamples.removeFirst(pendingSamples.count - Self.fftSize * 2)
        }

        if !newRows.isEmpty {
            await publish(rows: newRows)
        }
    }

    public func reset() async {
        pendingSamples.removeAll()
        await target.clear()
    }

    // MARK: Private

    /// FFT size — must be power of two for vDSP_fft_zrip (5.86 Hz bins at 12 kHz).
    private static let fftSize = 2_048

    /// dB span above the per-bin reference that maps to full-scale on the
    /// inferno palette. WSJT-X uses ~30 dB.
    private static let displayDBSpan: Float = 30

    /// Lower percentile of bin magnitudes used as the per-bin reference.
    private static let referencePercentile: Float = 0.25

    /// Half-width (in FFT bins) of the sliding window used to compute the
    /// per-bin reference level. ±30 bins ≈ ±175 Hz at 5.86 Hz/bin — wider
    /// than an FT8 signal (~9 bins / 50 Hz) so a real signal can never
    /// dominate its own local reference.
    private static let referenceWindowBins = 30

    private let target: FT8WaterfallData

    private let fftSetup: FFTSetup?
    private let hannWindow: [Float]
    private var pendingSamples: [Float] = []

    nonisolated private func publish(rows: [[Float]]) async {
        await target.append(rows: rows)
    }

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

        var windowed = [Float](repeating: 0, count: n)
        vDSP_vmul(samples, 1, hannWindow, 1, &windowed, 1, vDSP_Length(n))

        var realPart = [Float](repeating: 0, count: halfN)
        var imagPart = [Float](repeating: 0, count: halfN)
        var mags = [Float](repeating: 0, count: halfN)

        realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                guard let realPtr = realBuf.baseAddress,
                      let imagPtr = imagBuf.baseAddress
                else {
                    return
                }
                var split = DSPSplitComplex(realp: realPtr, imagp: imagPtr)

                windowed.withUnsafeBufferPointer { windowedBuf in
                    guard let base = windowedBuf.baseAddress else {
                        return
                    }
                    base.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(halfN))
                    }
                }

                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(halfN))
            }
        }

        return mags
    }

    /// Convert raw magnitudes to dB, extract the useful frequency range, and
    /// map (binDB − localReferenceDB) onto [0, 1] across `displayDBSpan` dB.
    private func normalizeSpectrum(_ mags: [Float], n: Int, halfN: Int) -> [Float] {
        var dbMags = mags
        var epsilon: Float = 1e-10
        vDSP_vsadd(dbMags, 1, &epsilon, &dbMags, 1, vDSP_Length(halfN))

        var logMags = [Float](repeating: 0, count: halfN)
        var count = Int32(halfN)
        vvlog10f(&logMags, dbMags, &count)

        var scale: Float = 10.0
        vDSP_vsmul(logMags, 1, &scale, &logMags, 1, vDSP_Length(halfN))

        let binSpacing = Float(FT8Constants.sampleRate) / Float(n)
        let minBin = Int(100 / binSpacing)
        let maxBin = min(Int(3_000 / binSpacing), halfN - 1)
        let usefulBins = Array(logMags[minBin ... maxBin])

        let references = localReferenceDB(usefulBins)
        var normalized = [Float](repeating: 0, count: usefulBins.count)
        vDSP_vsub(references, 1, usefulBins, 1, &normalized, 1, vDSP_Length(usefulBins.count))

        var divisor: Float = Self.displayDBSpan
        vDSP_vsdiv(normalized, 1, &divisor, &normalized, 1, vDSP_Length(normalized.count))

        var low: Float = 0
        var high: Float = 1
        vDSP_vclip(normalized, 1, &low, &high, &normalized, 1, vDSP_Length(normalized.count))

        return normalized
    }

    /// Per-bin 25th percentile over a ±`referenceWindowBins` window of dB
    /// values. O(N · W log W) per row.
    private func localReferenceDB(_ binsDB: [Float]) -> [Float] {
        let count = binsDB.count
        guard count > 0 else {
            return []
        }
        let halfWindow = Self.referenceWindowBins
        var refs = [Float](repeating: 0, count: count)
        var window: [Float] = []
        window.reserveCapacity(2 * halfWindow + 1)
        for idx in 0 ..< count {
            let lo = max(0, idx - halfWindow)
            let hi = min(count - 1, idx + halfWindow)
            window.removeAll(keepingCapacity: true)
            window.append(contentsOf: binsDB[lo ... hi])
            window.sort()
            let pctIdx = Int(Float(window.count) * Self.referencePercentile)
            refs[idx] = window[max(0, min(window.count - 1, pctIdx))]
        }
        return refs
    }
}
