// Band Plan Frequencies Extension
//
// Common calling and activity frequencies by band.

// MARK: - BandPlan + Frequencies

public extension BandPlan {
    // MARK: - Common CW Frequencies

    static let cwCallingFrequencies: [String: Double] = [
        "160m": 1.810,
        "80m": 3.560,
        "40m": 7.030,
        "30m": 10.116,
        "20m": 14.060,
        "17m": 18.080,
        "15m": 21.060,
        "12m": 24.910,
        "10m": 28.060,
    ]

    // MARK: - Common SSB Frequencies

    static let ssbCallingFrequencies: [String: Double] = [
        "160m": 1.900,
        "80m": 3.885,
        "40m": 7.200,
        "20m": 14.250,
        "17m": 18.140,
        "15m": 21.300,
        "12m": 24.950,
        "10m": 28.400,
    ]

    // MARK: - Common FT8/FT4 Frequencies

    static let ft8Frequencies: [String: Double] = [
        "160m": 1.840,
        "80m": 3.573,
        "40m": 7.074,
        "30m": 10.136,
        "20m": 14.074,
        "17m": 18.100,
        "15m": 21.074,
        "12m": 24.915,
        "10m": 28.074,
        "6m": 50.313,
    ]

    // MARK: - Common FT4 Frequencies

    static let ft4Frequencies: [String: Double] = [
        "80m": 3.575,
        "40m": 7.0475,
        "30m": 10.140,
        "20m": 14.080,
        "17m": 18.104,
        "15m": 21.140,
        "12m": 24.919,
        "10m": 28.180,
        "6m": 50.318,
    ]

    // MARK: - Common RTTY Frequencies

    static let rttyFrequencies: [String: Double] = [
        "80m": 3.580,
        "40m": 7.080,
        "20m": 14.080,
        "15m": 21.080,
        "10m": 28.080,
    ]

    // MARK: - Common AM Calling Frequencies

    static let amFrequencies: [String: Double] = [
        "80m": 3.885,
        "40m": 7.290,
        "20m": 14.286,
    ]

    // MARK: - Common FM Simplex Frequencies

    static let fmFrequencies: [String: Double] = [
        "10m": 29.600,
        "6m": 52.525,
        "2m": 146.520,
        "70cm": 446.000,
    ]

    // MARK: - Region-Aware Calling Frequencies

    /// IARU Region 1 (Europe, Africa) CW calling frequencies. Values that
    /// are not listed fall through to the Region 2 table.
    static let cwCallingFrequenciesRegion1: [String: Double] = [
        "160m": 1.836,
        "80m": 3.555,
        "40m": 7.030,
        "20m": 14.055,
        "15m": 21.055,
        "10m": 28.055,
    ]

    /// IARU Region 3 (Asia-Pacific, Oceania) CW calling frequencies.
    static let cwCallingFrequenciesRegion3: [String: Double] = [
        "160m": 1.836,
        "80m": 3.525,
        "40m": 7.030,
        "20m": 14.060,
        "15m": 21.060,
        "10m": 28.060,
    ]

    /// IARU Region 1 SSB calling frequencies.
    static let ssbCallingFrequenciesRegion1: [String: Double] = [
        "160m": 1.843,
        "80m": 3.690,
        "40m": 7.090,
        "20m": 14.285,
        "15m": 21.205,
        "10m": 28.500,
    ]

    /// IARU Region 3 SSB calling frequencies.
    static let ssbCallingFrequenciesRegion3: [String: Double] = [
        "160m": 1.850,
        "80m": 3.825,
        "40m": 7.090,
        "20m": 14.250,
        "15m": 21.350,
        "10m": 28.500,
    ]

    /// CW calling frequency for the given band/region, falling back to
    /// the Region 2 table (the pre-existing US-centric default) when no
    /// regional override is known.
    static func cwCallingFrequency(
        band: String, region: IARURegion
    ) -> Double? {
        switch region {
        case .region1: cwCallingFrequenciesRegion1[band] ?? cwCallingFrequencies[band]
        case .region2: cwCallingFrequencies[band]
        case .region3: cwCallingFrequenciesRegion3[band] ?? cwCallingFrequencies[band]
        }
    }

    /// SSB calling frequency for the given band/region with fallback.
    static func ssbCallingFrequency(
        band: String, region: IARURegion
    ) -> Double? {
        switch region {
        case .region1: ssbCallingFrequenciesRegion1[band] ?? ssbCallingFrequencies[band]
        case .region2: ssbCallingFrequencies[band]
        case .region3: ssbCallingFrequenciesRegion3[band] ?? ssbCallingFrequencies[band]
        }
    }
}
