//
//  FT8Constants.swift
//  CarrierWaveCore
//

/// FT8 protocol constants: timing, tone parameters, and standard dial frequencies
public enum FT8Constants: Sendable {
    // MARK: Public

    // MARK: - Timing Constants

    /// Duration of one FT8 time slot in seconds
    public static let slotDuration: Double = 15.0

    /// Duration of one symbol period in seconds
    public static let symbolPeriod: Double = 0.160

    /// Frequency spacing between adjacent tones in Hz
    public static let toneSpacing: Double = 6.25

    /// Number of distinct tones used (8-FSK)
    public static let toneCount = 8

    /// Total number of symbols per FT8 transmission
    public static let totalSymbols = 79

    /// Actual transmission duration in seconds (79 symbols x 0.160s)
    public static let txDuration: Double = 12.64

    /// Audio sample rate in Hz
    public static let sampleRate = 12_000

    /// Number of audio samples in one 15-second slot
    public static let samplesPerSlot = 180_000

    /// Bands in ascending frequency order
    public static let supportedBands: [String] = [
        "160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m", "2m", "70cm",
    ]

    /// Returns the standard FT8 dial frequency in MHz for a given band
    /// - Parameter band: Band name (e.g. "20m")
    /// - Returns: Dial frequency in MHz, or nil if band is not recognized
    public static func dialFrequency(forBand band: String) -> Double? {
        dialFrequencies[band]
    }

    /// Returns the band name for a given dial frequency in MHz
    /// - Parameter frequency: Dial frequency in MHz
    /// - Returns: Band name (e.g. "20m"), or nil if frequency doesn't match a known FT8 dial frequency
    public static func band(forDialFrequency frequency: Double) -> String? {
        let tolerance = 0.001
        for band in supportedBands {
            if let dialFreq = dialFrequencies[band],
               abs(dialFreq - frequency) < tolerance
            {
                return band
            }
        }
        return nil
    }

    // MARK: Private

    // MARK: - Dial Frequencies

    /// Standard FT8 dial frequencies by band (MHz)
    private static let dialFrequencies: [String: Double] = [
        "160m": 1.840,
        "80m": 3.573,
        "60m": 5.357,
        "40m": 7.074,
        "30m": 10.136,
        "20m": 14.074,
        "17m": 18.100,
        "15m": 21.074,
        "12m": 24.915,
        "10m": 28.074,
        "6m": 50.313,
        "2m": 144.174,
        "70cm": 432.174,
    ]
}
