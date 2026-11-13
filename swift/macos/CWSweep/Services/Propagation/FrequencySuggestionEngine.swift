import CarrierWaveCore
import Foundation

// MARK: - FrequencySuggestion

struct FrequencySuggestion {
    let frequencyMHz: Double
    let reason: String
}

// MARK: - FrequencySuggestionEngine

enum FrequencySuggestionEngine {
    // MARK: Internal

    /// Suggest a clear frequency for activating on the given band/mode.
    /// Always uses General+ segments to maximize hunter reach.
    /// For CW/SSB, searches near the calling frequency first (±10 kHz),
    /// then falls back to the full General+ sub-band.
    static func suggest(
        band: String,
        mode: String,
        recentSpotFrequencies: [Double],
        clearanceHz: Double = 500
    ) -> FrequencySuggestion? {
        if let fixed = fixedDialFrequency(band: band, mode: mode) {
            return fixed
        }

        guard let range = generalPlusRange(band: band, mode: mode) else {
            return nil
        }

        let callingFreq = callingFrequency(mode: mode, band: band)
        let clearanceMHz = clearanceHz / 1_000_000

        // Search near calling frequency first (±10 kHz) — where POTA activators cluster
        if let anchor = callingFreq {
            let narrowMin = max(anchor - 0.010, range.min)
            let narrowMax = min(anchor + 0.010, range.max)
            if let result = suggestInRange(
                minFreq: narrowMin, maxFreq: narrowMax,
                spots: recentSpotFrequencies, clearanceMHz: clearanceMHz,
                reason: "Near \(mode) calling frequency, clear within ±\(Int(clearanceHz)) Hz"
            ) {
                return result
            }
        }

        // Fall back to full General+ sub-band
        if let result = suggestInRange(
            minFreq: range.min, maxFreq: range.max,
            spots: recentSpotFrequencies, clearanceMHz: clearanceMHz,
            reason: "Clear \(mode) window, no activity within ±\(Int(clearanceHz)) Hz"
        ) {
            return result
        }

        if let freq = callingFreq {
            return FrequencySuggestion(frequencyMHz: freq, reason: "Busy band — standard POTA frequency")
        }
        return nil
    }

    // MARK: Private

    private struct FrequencyGap {
        let start: Double
        let end: Double

        var size: Double {
            end - start
        }

        var center: Double {
            FrequencySuggestionEngine.roundToNearest100Hz((start + end) / 2)
        }
    }

    /// Round a frequency in MHz to the nearest 100 Hz (0.0001 MHz).
    /// Produces clean values like 14.0560, 14.0565 — never 14.05575.
    private static func roundToNearest100Hz(_ freqMHz: Double) -> Double {
        (freqMHz * 10_000).rounded() / 10_000
    }

    private static func fixedDialFrequency(band: String, mode: String) -> FrequencySuggestion? {
        if mode == "FT8", let freq = BandPlan.ft8Frequencies[band] {
            return FrequencySuggestion(frequencyMHz: freq, reason: "Standard FT8 dial frequency")
        }
        if mode == "FT4", let freq = BandPlan.ft4Frequencies[band] {
            return FrequencySuggestion(frequencyMHz: freq, reason: "Standard FT4 dial frequency")
        }
        return nil
    }

    private static func generalPlusRange(band: String, mode: String) -> (min: Double, max: Double)? {
        let segments = BandPlan.segments.filter { segment in
            segment.band == band
                && segment.minimumLicense != .extra
                && segment.allowsMode(mode)
        }
        guard let minFreq = segments.map(\.startMHz).min(),
              let maxFreq = segments.map(\.endMHz).max()
        else {
            return nil
        }
        return (minFreq, maxFreq)
    }

    private static func callingFrequency(mode: String, band: String) -> Double? {
        switch mode {
        case "CW": BandPlan.cwCallingFrequencies[band]
        case "SSB": BandPlan.ssbCallingFrequencies[band]
        default: nil
        }
    }

    /// Find the best clear frequency within a given range.
    private static func suggestInRange(
        minFreq: Double,
        maxFreq: Double,
        spots: [Double],
        clearanceMHz: Double,
        reason: String
    ) -> FrequencySuggestion? {
        let relevantSpots = spots.filter { $0 >= minFreq && $0 <= maxFreq }.sorted()

        if relevantSpots.isEmpty {
            let mid = roundToNearest100Hz((minFreq + maxFreq) / 2)
            return FrequencySuggestion(frequencyMHz: mid, reason: reason)
        }

        if let best = findLargestGap(
            spots: relevantSpots, minFreq: minFreq, maxFreq: maxFreq, clearanceMHz: clearanceMHz
        ) {
            return FrequencySuggestion(frequencyMHz: best.center, reason: reason)
        }

        return nil
    }

    private static func findLargestGap(
        spots: [Double],
        minFreq: Double,
        maxFreq: Double,
        clearanceMHz: Double
    ) -> FrequencyGap? {
        var gaps: [FrequencyGap] = []

        let firstGapEnd = spots[0] - clearanceMHz
        if firstGapEnd > minFreq {
            gaps.append(FrequencyGap(start: minFreq, end: firstGapEnd))
        }

        for idx in 0 ..< spots.count - 1 {
            let gapStart = spots[idx] + clearanceMHz
            let gapEnd = spots[idx + 1] - clearanceMHz
            if gapEnd > gapStart {
                gaps.append(FrequencyGap(start: gapStart, end: gapEnd))
            }
        }

        let lastGapStart = spots[spots.count - 1] + clearanceMHz
        if maxFreq > lastGapStart {
            gaps.append(FrequencyGap(start: lastGapStart, end: maxFreq))
        }

        return gaps.max(by: { $0.size < $1.size })
    }
}
