import Foundation
@testable import CarrierWave

/// Factory for generating synthetic QSO data for performance testing
@MainActor
enum QSOFactory {
    // MARK: Internal

    // MARK: - Public API

    /// Generate a batch of realistic QSOs for performance testing
    /// - Parameters:
    ///   - count: Number of QSOs to generate
    ///   - startDate: Earliest QSO date (defaults to 2 years ago)
    ///   - confirmedRatio: Fraction of QSOs that are QSL confirmed (0.0-1.0)
    ///   - potaRatio: Fraction of QSOs with park references (0.0-1.0)
    /// - Returns: Array of synthetic QSOs
    static func generate(
        count: Int,
        startDate: Date = Calendar.current.date(byAdding: .year, value: -2, to: Date())!,
        confirmedRatio: Double = 0.3,
        potaRatio: Double = 0.2
    ) -> [QSO] {
        let parks = (1 ... 500).map { String(format: "US-%04d", $0) }

        var qsos: [QSO] = []
        qsos.reserveCapacity(count)

        let dateRange = Date().timeIntervalSince(startDate)

        for _ in 0 ..< count {
            let randomInterval = Double.random(in: 0 ... dateRange)
            let timestamp = startDate.addingTimeInterval(randomInterval)

            let prefix = prefixes.randomElement()!
            let suffix = Int.random(in: 1 ... 9)
            let callsuffix = suffixes.randomElement()!
            let callsign = "\(prefix)\(suffix)\(callsuffix)"

            let band = bands.randomElement()!
            let mode = modes.randomElement()!

            let isConfirmed = Double.random(in: 0 ... 1) < confirmedRatio
            let isPota = Double.random(in: 0 ... 1) < potaRatio

            let qso = QSO(
                callsign: callsign,
                band: band,
                mode: mode,
                frequency: frequencyForBand(band),
                timestamp: timestamp,
                rstSent: "59",
                rstReceived: "59",
                myCallsign: "N0TEST",
                myGrid: "FN31",
                theirGrid: grids.randomElement(),
                parkReference: isPota ? parks.randomElement() : nil,
                importSource: .adifFile,
                qrzConfirmed: isConfirmed && Bool.random(),
                lotwConfirmed: isConfirmed && Bool.random(),
                dxcc: Int.random(in: 1 ... 340)
            )
            qsos.append(qso)
        }

        return qsos
    }

    // MARK: Private

    // MARK: - Configuration

    private static let bands = ["160m", "80m", "40m", "20m", "15m", "10m", "6m", "2m"]
    private static let modes = ["SSB", "CW", "FT8", "FT4", "RTTY"]
    private static let prefixes = [
        "W", "K", "N", "AA", "AB", "WA", "KB", "KD", "VE", "G", "DL", "JA", "VK",
    ]
    private static let suffixes = ["AW", "LR", "ZZ", "AB", "CD", "EF", "GH", "IJ", "KL", "MN"]
    private static let grids = [
        "FN31", "FN42", "EM73", "DM79", "CN87", "IO91", "JN58", "PM95", "EM48", "DN70",
    ]

    // MARK: - Private Helpers

    private static func frequencyForBand(_ band: String) -> Double {
        switch band {
        case "160m": 1.840
        case "80m": 3.573
        case "40m": 7.074
        case "20m": 14.074
        case "15m": 21.074
        case "10m": 28.074
        case "6m": 50.313
        case "2m": 144.174
        default: 14.074
        }
    }
}
