import Foundation
import Testing
@testable import CarrierWave

// MARK: - PropagationCheckTests

struct PropagationCheckTests {
    @Test("Blob round-trips through compress/decompress")
    func blobRoundTrip() throws {
        let now = Date()
        let original = PropagationCheckBlob(
            spots: [
                PropagationSpotEntry(
                    source: .rbn,
                    skimmerCall: "AK6RI",
                    skimmerGrid: "DM07",
                    skimmerLat: 33.7,
                    skimmerLon: -118.0,
                    freqHz: 14_055_000,
                    band: "20m",
                    mode: "CW",
                    snrDB: 18,
                    timestamp: now
                ),
                PropagationSpotEntry(
                    source: .pskr,
                    skimmerCall: "K1ABC",
                    skimmerGrid: "FN42",
                    skimmerLat: nil,
                    skimmerLon: nil,
                    freqHz: 14_074_500,
                    band: "20m",
                    mode: "FT8",
                    snrDB: -7,
                    timestamp: now.addingTimeInterval(60)
                ),
            ],
            connectivityGaps: [
                PropagationConnectivityGap(
                    source: .pskr,
                    startedAt: now,
                    endedAt: now.addingTimeInterval(120)
                ),
            ]
        )

        let encoded = original.encode()
        #expect(!encoded.isEmpty)

        let decoded = try #require(PropagationCheckBlob.decode(from: encoded))
        #expect(decoded.schemaVersion == PropagationCheckBlob.currentSchemaVersion)
        #expect(decoded.spots.count == 2)
        #expect(decoded.connectivityGaps.count == 1)
        #expect(decoded.spots[0].skimmerCall == "AK6RI")
        #expect(decoded.spots[1].source == .pskr)
        #expect(decoded.spots[1].snrDB == -7)
    }

    @Test("Decode handles empty data as empty blob")
    func decodeEmptyData() throws {
        let blob = try #require(PropagationCheckBlob.decode(from: Data()))
        #expect(blob.spots.isEmpty)
        #expect(blob.connectivityGaps.isEmpty)
        #expect(blob.schemaVersion == PropagationCheckBlob.currentSchemaVersion)
    }

    @Test("Decode tolerates uncompressed legacy JSON")
    func decodeUncompressed() throws {
        let original = PropagationCheckBlob(spots: [
            PropagationSpotEntry(
                source: .rbn,
                skimmerCall: "W3LPL",
                skimmerGrid: "FM19",
                skimmerLat: 39.0,
                skimmerLon: -77.0,
                freqHz: 7_025_000,
                band: "40m",
                mode: "CW",
                snrDB: 22,
                timestamp: Date()
            ),
        ])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let raw = try encoder.encode(original)

        let decoded = try #require(PropagationCheckBlob.decode(from: raw))
        #expect(decoded.spots.count == 1)
        #expect(decoded.spots[0].skimmerCall == "W3LPL")
    }

    @Test("Dedup key collapses identical spots within a 1-second bucket")
    func dedupKeyCollapsesIdentical() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000.4)
        let nearDuplicate = Date(timeIntervalSince1970: 1_700_000_000.9)

        let first = PropagationSpotEntry(
            source: .rbn,
            skimmerCall: "AK6RI",
            skimmerGrid: nil,
            skimmerLat: nil,
            skimmerLon: nil,
            freqHz: 14_055_000,
            band: "20m",
            mode: "CW",
            snrDB: 12,
            timestamp: timestamp
        )
        let second = PropagationSpotEntry(
            source: .rbn,
            skimmerCall: "ak6ri", // case-insensitive callsign
            skimmerGrid: nil,
            skimmerLat: nil,
            skimmerLon: nil,
            freqHz: 14_055_000,
            band: "20m",
            mode: "CW",
            snrDB: 14,
            timestamp: nearDuplicate
        )

        #expect(PropagationCheck.dedupKey(for: first) == PropagationCheck.dedupKey(for: second))
    }

    @Test("Dedup key separates different sources / freqs / skimmers")
    func dedupKeyDistinguishes() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        let base = PropagationSpotEntry(
            source: .rbn,
            skimmerCall: "AK6RI",
            skimmerGrid: nil,
            skimmerLat: nil,
            skimmerLon: nil,
            freqHz: 14_055_000,
            band: "20m",
            mode: "CW",
            snrDB: 10,
            timestamp: timestamp
        )

        var diffSource = base
        diffSource.source = .pskr

        var diffFreq = base
        diffFreq.freqHz = 14_055_500

        var diffSkimmer = base
        diffSkimmer.skimmerCall = "W3LPL"

        var diffTimestamp = base
        diffTimestamp.timestamp = timestamp.addingTimeInterval(2)

        let baseKey = PropagationCheck.dedupKey(for: base)
        #expect(baseKey != PropagationCheck.dedupKey(for: diffSource))
        #expect(baseKey != PropagationCheck.dedupKey(for: diffFreq))
        #expect(baseKey != PropagationCheck.dedupKey(for: diffSkimmer))
        #expect(baseKey != PropagationCheck.dedupKey(for: diffTimestamp))
    }

    @Test("Model defaults reflect transmit + stop reason kinds")
    func transmitAndStopKindDefaults() {
        let check = PropagationCheck(
            label: "test",
            startedAt: Date(),
            endedAt: Date(),
            callsignUsed: "W6JY",
            userGridUsed: "CM87",
            bandsRequested: ["20m"],
            transmitMode: PropagationTransmitMode.passive.rawValue,
            stopReason: PropagationStopReason.user.rawValue
        )
        #expect(check.transmitModeKind == .passive)
        #expect(check.stopReasonKind == .user)
        #expect(check.duration == 0)
    }

    @Test("Unknown raw values fall back to defaults")
    func unknownRawValues() {
        let check = PropagationCheck(
            label: "test",
            startedAt: Date(),
            endedAt: Date(),
            callsignUsed: "W6JY",
            userGridUsed: "CM87",
            bandsRequested: [],
            transmitMode: "garbage",
            stopReason: "nonsense"
        )
        #expect(check.transmitModeKind == .passive)
        #expect(check.stopReasonKind == .user)
    }

    @Test("Decoded blob accessor returns nil-safe default for empty model")
    func decodedBlobOnEmptyModel() {
        let check = PropagationCheck(
            label: "empty",
            startedAt: Date(),
            endedAt: Date(),
            callsignUsed: "W6JY",
            userGridUsed: "CM87",
            bandsRequested: ["20m"],
            transmitMode: PropagationTransmitMode.passive.rawValue,
            stopReason: PropagationStopReason.user.rawValue
        )
        let blob = check.decodedBlob
        #expect(blob != nil)
        #expect(blob?.spots.isEmpty == true)
    }

    @Test("hasSolarData is false when no solar fields are set")
    func hasSolarDataFalseByDefault() {
        let check = PropagationCheck(
            label: "no-solar",
            startedAt: Date(),
            endedAt: Date(),
            callsignUsed: "W6JY",
            userGridUsed: "CM87",
            bandsRequested: ["20m"],
            transmitMode: PropagationTransmitMode.passive.rawValue,
            stopReason: PropagationStopReason.user.rawValue
        )
        #expect(!check.hasSolarData)
        #expect(check.solarKIndex == nil)
        #expect(check.solarFlux == nil)
        #expect(check.solarSunspots == nil)
    }

    @Test("Solar fields round-trip through the initializer")
    func solarFieldsRoundTrip() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let check = PropagationCheck(
            label: "with-solar",
            startedAt: Date(),
            endedAt: Date(),
            callsignUsed: "W6JY",
            userGridUsed: "CM87",
            bandsRequested: ["20m"],
            transmitMode: PropagationTransmitMode.passive.rawValue,
            stopReason: PropagationStopReason.user.rawValue,
            solarKIndex: 2.3,
            solarAIndex: 11,
            solarFlux: 152,
            solarSunspots: 86,
            solarPropagationRating: "Good",
            solarBandConditions: "{\"20m\":\"Good\"}",
            solarTimestamp: timestamp
        )
        #expect(check.hasSolarData)
        #expect(check.solarKIndex == 2.3)
        #expect(check.solarAIndex == 11)
        #expect(check.solarFlux == 152)
        #expect(check.solarSunspots == 86)
        #expect(check.solarPropagationRating == "Good")
        #expect(check.solarBandConditions == "{\"20m\":\"Good\"}")
        #expect(check.solarTimestamp == timestamp)
    }

    @Test("hasSolarData reflects each individual headline metric")
    func hasSolarDataReflectsAnyField() {
        let base = {
            PropagationCheck(
                label: "x", startedAt: Date(), endedAt: Date(),
                callsignUsed: "W6JY", userGridUsed: "CM87",
                bandsRequested: [],
                transmitMode: PropagationTransmitMode.passive.rawValue,
                stopReason: PropagationStopReason.user.rawValue
            )
        }
        let onlyK = base(); onlyK.solarKIndex = 1.5
        let onlyFlux = base(); onlyFlux.solarFlux = 140
        let onlySpots = base(); onlySpots.solarSunspots = 50
        #expect(onlyK.hasSolarData)
        #expect(onlyFlux.hasSolarData)
        #expect(onlySpots.hasSolarData)
    }
}

// MARK: - PropagationConfigMatchTests

struct PropagationConfigMatchTests {
    // MARK: Internal

    @Test("Exact match works case-insensitively")
    func exactMatchCaseInsensitive() {
        let config = makeConfig(callsign: "W6JY")
        #expect(config.matches("W6JY"))
        #expect(config.matches("w6jy"))
        #expect(config.matches(" W6JY "))
    }

    @Test("Suffix variants match: /P /M /MM /QRP")
    func suffixVariantsMatch() {
        let config = makeConfig(callsign: "W6JY")
        #expect(config.matches("W6JY/P"))
        #expect(config.matches("W6JY/M"))
        #expect(config.matches("W6JY/MM"))
        #expect(config.matches("W6JY/QRP"))
        #expect(config.matches("w6jy/p"))
    }

    @Test("Different base callsigns do not match")
    func differentBaseDoesNotMatch() {
        let config = makeConfig(callsign: "W6JY")
        #expect(!config.matches("W6JX"))
        #expect(!config.matches("KH6/W6JY")) // prefix change is a different op
        #expect(!config.matches("AA6JY"))
    }

    @Test("Empty or invalid suffix forms do not match")
    func invalidSuffixDoesNotMatch() {
        let config = makeConfig(callsign: "W6JY")
        #expect(!config.matches("W6JY/")) // empty suffix
        #expect(!config.matches("W6JY/P/QRP")) // multiple slashes
    }

    // MARK: Private

    private func makeConfig(callsign: String) -> PropagationCheckConfig {
        PropagationCheckConfig(
            callsign: callsign,
            bands: ["20m"],
            transmitMode: .passive,
            userGrid: "CM87",
            startedAt: Date(),
            durationCap: nil
        )
    }
}

// MARK: - PropagationCheckStatisticsTests

struct PropagationCheckStatisticsTests {
    // MARK: Internal

    @Test("Headline computes total, unique, peak SNR")
    func headlineBasics() {
        let spots = [
            entry(skimmer: "AK6RI", snr: 18),
            entry(skimmer: "ak6ri", snr: 22), // dup callsign, different timestamp
            entry(skimmer: "K1ABC", snr: 8),
        ]
        let headline = PropagationCheckStatistics.compute(spots: spots, userGrid: "CM87")
        #expect(headline.totalSpots == 3)
        #expect(headline.uniqueSkimmers == 2)
        #expect(headline.peakSNRdB == 22)
    }

    @Test("Bands-with-activity returns sorted unique bands")
    func bandsWithActivity() {
        let spots = [
            entry(skimmer: "A", band: "20m"),
            entry(skimmer: "B", band: "40m"),
            entry(skimmer: "C", band: "20m"),
            entry(skimmer: "D", band: "10m"),
        ]
        let headline = PropagationCheckStatistics.compute(spots: spots, userGrid: "CM87")
        #expect(headline.bandsWithActivity == ["40m", "20m", "10m"])
    }

    @Test("Per-band breakdown groups + computes median SNR")
    func bandBreakdownMedian() {
        let spots = [
            entry(skimmer: "A", band: "20m", snr: 5),
            entry(skimmer: "B", band: "20m", snr: 15),
            entry(skimmer: "C", band: "20m", snr: 25),
            entry(skimmer: "D", band: "40m", snr: 10),
        ]
        let rows = PropagationCheckStatistics.bandBreakdown(spots: spots, userGrid: "CM87")
        let twenty = rows.first { $0.band == "20m" }
        #expect(twenty?.medianSNRdB == 15)
        #expect(twenty?.peakSNRdB == 25)
        #expect(twenty?.spotCount == 3)
    }

    @Test("Distance histogram sums to total spots with grids")
    func distanceHistogramSum() {
        let spots = [
            entry(skimmer: "A", grid: "CM87"), // ~0 km
            entry(skimmer: "B", grid: "FN42"), // ~4500 km
            entry(skimmer: "C", grid: "JO22"), // ~9000 km
        ]
        let buckets = PropagationCheckStatistics.distanceHistogram(spots: spots, userGrid: "CM87")
        let total = buckets.reduce(0) { $0 + $1.count }
        #expect(total == 3)
    }

    @Test("Continent breakdown returns at least one bucket for known grids")
    func continentBreakdownNonempty() {
        let spots = [
            entry(skimmer: "A", grid: "FN42"), // North America (Eastern US)
            entry(skimmer: "B", grid: "JO22"), // Europe
        ]
        let buckets = PropagationCheckStatistics.continentBreakdown(spots: spots)
        #expect(buckets.count >= 2)
        #expect(buckets.contains { $0.name == "North America" })
        #expect(buckets.contains { $0.name == "Europe" })
    }

    @Test("Timeline buckets cover the session window")
    func timelineCoversWindow() {
        let start = Date(timeIntervalSince1970: 1_700_000_000) // arbitrary
        let end = start.addingTimeInterval(180) // 3 minutes
        let spots = [
            entry(skimmer: "A", timestamp: start.addingTimeInterval(10)),
            entry(skimmer: "B", timestamp: start.addingTimeInterval(70)),
            entry(skimmer: "C", timestamp: start.addingTimeInterval(150)),
        ]
        let buckets = PropagationCheckStatistics.timeline(spots: spots, startedAt: start, endedAt: end)
        #expect(buckets.count >= 3)
        #expect(buckets.reduce(0) { $0 + $1.count } == 3)
    }

    // MARK: Private

    private func entry(
        source: PropagationSpotSource = .rbn,
        skimmer: String,
        grid: String? = "FN42",
        freqHz: Int = 14_055_000,
        band: String? = "20m",
        snr: Double? = 10,
        timestamp: Date = Date()
    ) -> PropagationSpotEntry {
        PropagationSpotEntry(
            source: source,
            skimmerCall: skimmer,
            skimmerGrid: grid,
            skimmerLat: nil,
            skimmerLon: nil,
            freqHz: freqHz,
            band: band,
            mode: "CW",
            snrDB: snr,
            timestamp: timestamp
        )
    }
}
