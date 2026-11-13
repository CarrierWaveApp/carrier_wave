import Foundation

// MARK: - SatelliteWaterfallSynth

/// Synthesizes waterfall lines for the satellite view when no SDR is feeding
/// `WaterfallStore`: a noise floor plus one signal whose center follows the
/// Doppler-shifted downlink, whose width matches the transponder mode, and
/// whose brightness scales with slant range. Deterministic for a given seed
/// so the renderer and tests agree.
///
/// Two presentations share the math:
/// - **uncorrected** — the passband is centered on the *nominal* downlink,
///   so the signal drifts across the display as Doppler changes (teaching
///   view).
/// - **corrected** — the passband is centered on the *corrected* downlink,
///   so the signal stays put while the scale slides (what Gpredict and
///   SatPC32 show).
enum SatelliteWaterfallSynth {
    // MARK: Internal

    struct Line: Equatable {
        /// Normalized 0…1 magnitudes, lowest frequency first.
        var magnitudes: [Float]
        /// Frequency at bin 0.
        var startHz: Double
        /// Hz per bin.
        var binHz: Double
    }

    static let defaultBins = 512
    /// Half-span of the display (downlink ±25 kHz).
    static let halfSpanHz = 25_000.0

    /// Occupied bandwidth per transponder mode.
    static func signalWidthHz(mode: SatelliteModeKind) -> Double {
        switch mode {
        case .fm: 10_000
        case .ssb: 2_400
        case .cw: 300
        case .digital: 2_000
        }
    }

    /// Signal strength 0…1 from slant range: ~1 at 500 km, fading toward 0
    /// around 3 500 km (horizon for a 400 km LEO is ≈ 2 300 km).
    static func strength(rangeKm: Double?) -> Double {
        guard let rangeKm, rangeKm > 0 else {
            return 0
        }
        let value = 1 - (rangeKm - 500) / 3_000
        return min(max(value, 0), 1)
    }

    /// Build one line.
    /// - Parameters:
    ///   - centerHz: passband center (nominal or corrected downlink).
    ///   - signalHz: where the signal actually is (corrected downlink); pass
    ///     `nil` for "satellite below horizon" (noise only).
    static func line(
        centerHz: Double,
        signalHz: Double?,
        widthHz: Double,
        strength: Double,
        bins: Int = defaultBins,
        seed: UInt64
    ) -> Line {
        let spanHz = halfSpanHz * 2
        let binHz = spanHz / Double(bins)
        let startHz = centerHz - halfSpanHz
        var rng = SplitMix64(seed: seed)
        var magnitudes = [Float](repeating: 0, count: bins)
        for index in 0 ..< bins {
            // Noise floor around 0.10 with ±0.06 jitter.
            let noise = 0.10 + (rng.nextUnit() - 0.5) * 0.12
            var value = noise
            if let signalHz, strength > 0 {
                let frequency = startHz + (Double(index) + 0.5) * binHz
                let offset = frequency - signalHz
                let halfWidth = widthHz / 2
                // Flat-topped passband with soft shoulders (≈ 1.5 bins).
                let edge = max(abs(offset) - halfWidth, 0)
                let shoulder = exp(-(edge * edge) / (2 * pow(binHz * 1.5, 2)))
                let flicker = 0.85 + rng.nextUnit() * 0.15
                value += strength * shoulder * flicker * 0.9
            }
            magnitudes[index] = Float(min(max(value, 0), 1))
        }
        return Line(magnitudes: magnitudes, startHz: startHz, binHz: binHz)
    }

    /// Bin index (fractional) for a frequency on this line, or nil if it is
    /// outside the display.
    static func bin(for frequencyHz: Double, in line: Line) -> Double? {
        let position = (frequencyHz - line.startHz) / line.binHz
        guard position >= 0, position <= Double(line.magnitudes.count) else {
            return nil
        }
        return position
    }

    // MARK: Private

    /// Tiny deterministic PRNG so rendering is reproducible frame to frame.
    private struct SplitMix64 {
        // MARK: Lifecycle

        init(seed: UInt64) {
            state = seed
        }

        // MARK: Internal

        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func nextUnit() -> Double {
            Double(next() >> 11) / Double(1 << 53)
        }
    }
}
