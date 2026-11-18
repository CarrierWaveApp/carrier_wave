import Foundation

// MARK: - RadioManager + Band Step

/// Band Up / Band Down. Steps through the bands the focused radio can tune,
/// so an IC-9700 goes 2m → 70cm → 23cm instead of stalling on 1.25m / 33cm,
/// and HF rigs stop at 6m as before.
extension RadioManager {
    /// Landing frequency per band (MHz), low to high: HF CW segment starts,
    /// then the US weak-signal calling frequencies above 6m.
    static let bandStepFrequencies: [(band: String, mhz: Double)] = [
        ("160m", 1.840), ("80m", 3.530), ("60m", 5.332), ("40m", 7.030),
        ("30m", 10.110), ("20m", 14.030), ("17m", 18.080), ("15m", 21.030),
        ("12m", 24.900), ("10m", 28.030), ("6m", 50.030),
        ("2m", 144.200), ("1.25m", 222.100), ("70cm", 432.100),
        ("33cm", 903.100), ("23cm", 1_296.100),
    ]

    private static let hfAnd6m: Set = [
        "160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m",
    ]

    /// Bands the focused radio covers, by model; unknown radios get HF + 6m.
    var tunableBands: Set<String> {
        let modelId = slotStates[focusedSlot]?.profile.modelId ?? ""
        if modelId.hasPrefix("ic9700") {
            return ["2m", "70cm", "23cm"]
        }
        if modelId.hasPrefix("ic705") || modelId.hasPrefix("ft991") {
            return Self.hfAnd6m.union(["2m", "70cm"])
        }
        return Self.hfAnd6m
    }

    /// Next band's landing frequency above (or below) `currentMHz`, wrapping.
    func nextBandFrequency(from currentMHz: Double, up: Bool) -> Double {
        let bands = tunableBands
        let steps = Self.bandStepFrequencies.filter { bands.contains($0.band) }.map(\.mhz)
        guard let first = steps.first, let last = steps.last else {
            return currentMHz
        }
        if up {
            return steps.first { $0 > currentMHz + 0.5 } ?? first
        }
        return steps.last { $0 < currentMHz - 0.5 } ?? last
    }
}
