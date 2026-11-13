import CarrierWaveData
import Foundation
@testable import CarrierWave

/// Factory for generating synthetic QSO data for testing
///
/// Provides:
/// - Bulk generation for performance testing
/// - Duplicate QSO pairs for deduplication testing
/// - Metadata mode records (WEATHER, SOLAR, NOTE)
/// - POTA activation groups
/// - Edge case scenarios
@MainActor
enum QSOFactory {
    // MARK: Internal

    // MARK: - Configuration

    static let bands = ["160m", "80m", "40m", "20m", "15m", "10m", "6m", "2m"]
    static let modes = ["SSB", "CW", "FT8", "FT4", "RTTY"]
    static let metadataModes = ["WEATHER", "SOLAR", "NOTE"]

    // MARK: - Bulk Generation (Performance Testing)

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

    // MARK: - Duplicate Pair Generation (Deduplication Testing)

    /// Generate a pair of duplicate QSOs with configurable time offset
    /// - Parameters:
    ///   - callsign: Callsign for both QSOs
    ///   - band: Band for both QSOs
    ///   - mode: Mode for both QSOs
    ///   - timeOffsetSeconds: Time between the two QSOs
    ///   - baseTimestamp: Timestamp for the first QSO
    /// - Returns: Tuple of (first QSO, second QSO)
    static func duplicatePair(
        callsign: String = "W1AW",
        band: String = "20m",
        mode: String = "CW",
        timeOffsetSeconds: TimeInterval = 60,
        baseTimestamp: Date = Date()
    ) -> (QSO, QSO) {
        let qso1 = QSO(
            callsign: callsign,
            band: band,
            mode: mode,
            frequency: frequencyForBand(band),
            timestamp: baseTimestamp,
            myCallsign: "N0TEST",
            importSource: .adifFile
        )

        let qso2 = QSO(
            callsign: callsign,
            band: band,
            mode: mode,
            frequency: frequencyForBand(band),
            timestamp: baseTimestamp.addingTimeInterval(timeOffsetSeconds),
            myCallsign: "N0TEST",
            importSource: .adifFile
        )

        return (qso1, qso2)
    }

    /// Generate duplicates with different richness levels
    /// - Parameters:
    ///   - sparse: If true, first QSO has minimal fields; if false, second has minimal
    /// - Returns: Tuple of (sparse QSO, rich QSO)
    static func duplicatesWithDifferentRichness(
        callsign: String = "W1AW",
        sparseFirst: Bool = true
    ) -> (sparse: QSO, rich: QSO) {
        let baseTime = Date()

        let sparse = QSO(
            callsign: callsign,
            band: "20m",
            mode: "CW",
            timestamp: sparseFirst ? baseTime : baseTime.addingTimeInterval(60),
            myCallsign: "N0TEST",
            importSource: .adifFile
        )

        let rich = QSO(
            callsign: callsign,
            band: "20m",
            mode: "CW",
            frequency: 14.060,
            timestamp: sparseFirst ? baseTime.addingTimeInterval(60) : baseTime,
            rstSent: "599",
            rstReceived: "579",
            myCallsign: "N0TEST",
            myGrid: "FN31",
            theirGrid: "FN42",
            notes: "Great signal",
            importSource: .adifFile,
            name: "John",
            qth: "Connecticut",
            state: "CT",
            country: "USA"
        )

        return (sparse, rich)
    }

    /// Generate duplicates where one has sync status
    static func duplicatesWithSyncStatus(
        callsign: String = "W1AW"
    ) -> (unsynced: QSO, synced: QSO) {
        let baseTime = Date()

        let unsynced = QSO(
            callsign: callsign,
            band: "20m",
            mode: "CW",
            timestamp: baseTime,
            myCallsign: "N0TEST",
            importSource: .adifFile
        )

        let synced = QSO(
            callsign: callsign,
            band: "20m",
            mode: "CW",
            timestamp: baseTime.addingTimeInterval(60),
            myCallsign: "N0TEST",
            importSource: .adifFile,
            qrzLogId: "12345",
            qrzConfirmed: true
        )

        return (unsynced, synced)
    }

    // MARK: - Metadata Mode Generation

    /// Generate a metadata record (WEATHER, SOLAR, or NOTE)
    /// These should never be synced to external services
    static func metadataRecord(
        mode: String,
        parkReference: String = "US-0001",
        notes: String? = nil
    ) -> QSO {
        let defaultNotes = switch mode.uppercased() {
        case "WEATHER":
            "Temp: 72F, Wind: 5mph NW, Clear skies"
        case "SOLAR":
            "SFI: 150, K: 2, A: 5"
        case "NOTE":
            "Activation note"
        default:
            ""
        }

        return QSO(
            callsign: "METADATA",
            band: "",
            mode: mode.uppercased(),
            timestamp: Date(),
            myCallsign: "N0TEST",
            parkReference: parkReference,
            notes: notes ?? defaultNotes,
            importSource: .lofi
        )
    }

    /// Generate a set of metadata records for a POTA activation
    static func activationMetadata(
        parkReference: String = "US-0001"
    ) -> [QSO] {
        [
            metadataRecord(mode: "WEATHER", parkReference: parkReference),
            metadataRecord(mode: "SOLAR", parkReference: parkReference),
            metadataRecord(mode: "NOTE", parkReference: parkReference, notes: "Starting activation"),
        ]
    }

    // MARK: - POTA Activation Generation

    /// Generate a complete POTA activation with QSOs
    /// - Parameters:
    ///   - parkReference: Park reference
    ///   - qsoCount: Number of QSOs (not including metadata)
    ///   - includeMetadata: Whether to include WEATHER/SOLAR/NOTE records
    ///   - twoFerPark: Optional second park for two-fer activation
    /// - Returns: Array of QSOs for the activation
    static func potaActivation(
        parkReference: String = "US-0001",
        qsoCount: Int = 10,
        includeMetadata: Bool = true,
        twoFerPark: String? = nil
    ) -> [QSO] {
        var qsos: [QSO] = []
        let baseTime = Date()

        // Add metadata records first
        if includeMetadata {
            qsos.append(contentsOf: activationMetadata(parkReference: parkReference))
        }

        // Generate QSOs
        for i in 0 ..< qsoCount {
            let callsign = randomCallsign()
            let mode = ["CW", "SSB"].randomElement()!
            let band = ["20m", "40m"].randomElement()!

            let qso = QSO(
                callsign: callsign,
                band: band,
                mode: mode,
                frequency: frequencyForBand(band),
                timestamp: baseTime.addingTimeInterval(Double(i * 120)), // 2 min between QSOs
                rstSent: "599",
                rstReceived: "599",
                myCallsign: "N0TEST",
                myGrid: "FN31",
                parkReference: parkReference,
                importSource: .logger
            )
            qsos.append(qso)
        }

        return qsos
    }

    // MARK: - Edge Case Scenarios

    /// QSO with missing band (common from POTA imports)
    static func qsoWithoutBand(
        callsign: String = "W1AW",
        mode: String = "SSB"
    ) -> QSO {
        QSO(
            callsign: callsign,
            band: "",
            mode: mode,
            timestamp: Date(),
            myCallsign: "N0TEST",
            parkReference: "US-0001",
            importSource: .pota
        )
    }

    /// QSO with case variations (for testing case-insensitive matching)
    static func caseVariationPair() -> (lowercase: QSO, uppercase: QSO) {
        let baseTime = Date()

        let lower = QSO(
            callsign: "w1aw",
            band: "20m",
            mode: "cw",
            timestamp: baseTime,
            myCallsign: "n0test",
            importSource: .adifFile
        )

        let upper = QSO(
            callsign: "W1AW",
            band: "20M",
            mode: "CW",
            timestamp: baseTime.addingTimeInterval(60),
            myCallsign: "N0TEST",
            importSource: .adifFile
        )

        return (lower, upper)
    }

    /// Hidden QSO (soft deleted)
    static func hiddenQSO(callsign: String = "W1AW") -> QSO {
        let qso = QSO(
            callsign: callsign,
            band: "20m",
            mode: "CW",
            timestamp: Date(),
            myCallsign: "N0TEST",
            importSource: .logger
        )
        qso.isHidden = true
        return qso
    }

    // MARK: - Helpers

    /// Get frequency for a band
    static func frequencyForBand(_ band: String) -> Double {
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

    /// Generate a random callsign
    static func randomCallsign() -> String {
        let prefix = prefixes.randomElement()!
        let suffix = Int.random(in: 1 ... 9)
        let callsuffix = suffixes.randomElement()!
        return "\(prefix)\(suffix)\(callsuffix)"
    }

    /// Generate a random grid square
    static func randomGrid() -> String {
        grids.randomElement()!
    }

    // MARK: Private

    private static let prefixes = [
        "W", "K", "N", "AA", "AB", "WA", "KB", "KD", "VE", "G", "DL", "JA", "VK",
    ]
    private static let suffixes = ["AW", "LR", "ZZ", "AB", "CD", "EF", "GH", "IJ", "KL", "MN"]
    private static let grids = [
        "FN31", "FN42", "EM73", "DM79", "CN87", "IO91", "JN58", "PM95", "EM48", "DN70",
    ]
}
