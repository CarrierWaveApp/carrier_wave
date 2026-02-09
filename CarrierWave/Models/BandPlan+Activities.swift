// Band Plan Activities Extension
//
// Common amateur radio activity frequencies (QRP, SSTV, FT8, CWT, nets).

import Foundation

// MARK: - BandPlan+Activities

extension BandPlan {
    // MARK: - CWT Time Windows

    /// CWOps CWT occurs Wed 1300Z, 1900Z and Thu 0300Z, 0700Z (60 min each, 15 min buffer)
    static let cwtTimeWindows: [TimeWindow] = [
        // Wednesday (weekday 4) 1300Z
        TimeWindow(
            dayOfWeek: 4, startHourUTC: 13, startMinuteUTC: 0,
            durationMinutes: 60, bufferMinutes: 15
        ),
        // Wednesday (weekday 4) 1900Z
        TimeWindow(
            dayOfWeek: 4, startHourUTC: 19, startMinuteUTC: 0,
            durationMinutes: 60, bufferMinutes: 15
        ),
        // Thursday (weekday 5) 0300Z
        TimeWindow(
            dayOfWeek: 5, startHourUTC: 3, startMinuteUTC: 0,
            durationMinutes: 60, bufferMinutes: 15
        ),
        // Thursday (weekday 5) 0700Z
        TimeWindow(
            dayOfWeek: 5, startHourUTC: 7, startMinuteUTC: 0,
            durationMinutes: 60, bufferMinutes: 15
        ),
    ]

    // MARK: - CWT Frequency Ranges

    /// CWOps CWT uses 28-45 kHz from band edge on each band
    static let cwtRanges: [CWTRange] = [
        CWTRange(band: "160m", bandEdgeMHz: 1.800, startOffsetKHz: 28, endOffsetKHz: 45),
        CWTRange(band: "80m", bandEdgeMHz: 3.500, startOffsetKHz: 28, endOffsetKHz: 45),
        CWTRange(band: "40m", bandEdgeMHz: 7.000, startOffsetKHz: 28, endOffsetKHz: 45),
        CWTRange(band: "20m", bandEdgeMHz: 14.000, startOffsetKHz: 28, endOffsetKHz: 45),
        CWTRange(band: "15m", bandEdgeMHz: 21.000, startOffsetKHz: 28, endOffsetKHz: 45),
        CWTRange(band: "10m", bandEdgeMHz: 28.000, startOffsetKHz: 28, endOffsetKHz: 45),
    ]

    // MARK: - Frequency Activities

    static let activities: [FrequencyActivity] = buildActivities()

    // swiftlint:disable:next function_body_length
    private static func buildActivities() -> [FrequencyActivity] {
        var list: [FrequencyActivity] = []

        // MARK: QRP CW Calling Frequencies (±2 kHz)

        let qrpCWFreqs: [(String, Double)] = [
            ("160m", 1.810), ("80m", 3.560), ("40m", 7.030), ("30m", 10.106),
            ("20m", 14.060), ("17m", 18.080), ("15m", 21.060), ("12m", 24.906),
            ("10m", 28.060), ("6m", 50.060), ("2m", 144.060),
        ]
        for (band, freq) in qrpCWFreqs {
            list.append(
                FrequencyActivity(
                    type: .qrpCW, band: band, centerMHz: freq, toleranceKHz: 2,
                    modes: ["CW"], description: "QRP CW calling frequency", timeWindows: nil
                )
            )
        }

        // MARK: QRP SSB Calling Frequencies (±2 kHz)

        let qrpSSBFreqs: [(String, Double)] = [
            ("160m", 1.910), ("80m", 3.985), ("40m", 7.285), ("20m", 14.285),
            ("17m", 18.130), ("15m", 21.385), ("12m", 24.950), ("10m", 28.385),
            ("6m", 50.885), ("2m", 144.285),
        ]
        for (band, freq) in qrpSSBFreqs {
            list.append(
                FrequencyActivity(
                    type: .qrpSSB, band: band, centerMHz: freq, toleranceKHz: 2,
                    modes: ["SSB", "USB", "LSB"], description: "QRP SSB calling frequency",
                    timeWindows: nil
                )
            )
        }

        // MARK: SSTV Frequencies (±3 kHz)

        let sstvFreqs: [(String, Double)] = [
            ("80m", 3.845), ("40m", 7.171), ("20m", 14.230), ("20m", 14.233),
            ("20m", 14.236), ("15m", 21.340), ("10m", 28.680),
        ]
        for (band, freq) in sstvFreqs {
            list.append(
                FrequencyActivity(
                    type: .sstv, band: band, centerMHz: freq, toleranceKHz: 3,
                    modes: ["USB", "SSB"], description: "SSTV calling frequency", timeWindows: nil
                )
            )
        }

        // MARK: FT8/FT4 Frequencies (±3 kHz)

        let ft8Freqs: [(String, Double)] = [
            ("160m", 1.840), ("80m", 3.573), ("40m", 7.074), ("30m", 10.136),
            ("20m", 14.074), ("17m", 18.100), ("15m", 21.074), ("12m", 24.915),
            ("10m", 28.074), ("6m", 50.313),
        ]
        for (band, freq) in ft8Freqs {
            list.append(
                FrequencyActivity(
                    type: .digitalFT, band: band, centerMHz: freq, toleranceKHz: 3,
                    modes: ["DATA", "FT8", "FT4", "USB"],
                    description: "FT8/FT4 frequency", timeWindows: nil
                )
            )
        }

        // MARK: PSK31 Frequencies (±3 kHz)

        let pskFreqs: [(String, Double)] = [
            ("160m", 1.838), ("80m", 3.580), ("40m", 7.035), ("30m", 10.142),
            ("20m", 14.070), ("17m", 18.100), ("15m", 21.080), ("12m", 24.920),
            ("10m", 28.120),
        ]
        for (band, freq) in pskFreqs {
            list.append(
                FrequencyActivity(
                    type: .digitalPSK, band: band, centerMHz: freq, toleranceKHz: 3,
                    modes: ["DATA", "PSK31", "PSK", "USB"],
                    description: "PSK31 frequency", timeWindows: nil
                )
            )
        }

        // MARK: RTTY Frequencies (±3 kHz)

        let rttyFreqs: [(String, Double)] = [
            ("80m", 3.580), ("40m", 7.080), ("20m", 14.080),
            ("15m", 21.080), ("10m", 28.080),
        ]
        for (band, freq) in rttyFreqs {
            list.append(
                FrequencyActivity(
                    type: .rtty, band: band, centerMHz: freq, toleranceKHz: 3,
                    modes: ["DATA", "RTTY", "USB"],
                    description: "RTTY frequency", timeWindows: nil
                )
            )
        }

        // MARK: AM Calling Frequencies (±2 kHz)

        let amFreqs: [(String, Double)] = [
            ("80m", 3.885), ("40m", 7.290), ("20m", 14.286),
        ]
        for (band, freq) in amFreqs {
            list.append(
                FrequencyActivity(
                    type: .amCalling, band: band, centerMHz: freq, toleranceKHz: 2,
                    modes: ["AM"], description: "AM calling frequency", timeWindows: nil
                )
            )
        }

        // MARK: FM Simplex Frequencies (±2 kHz)

        let fmFreqs: [(String, Double)] = [
            ("10m", 29.600), ("6m", 52.525), ("2m", 146.520), ("70cm", 446.000),
        ]
        for (band, freq) in fmFreqs {
            list.append(
                FrequencyActivity(
                    type: .fmSimplex, band: band, centerMHz: freq, toleranceKHz: 2,
                    modes: ["FM"], description: "FM simplex calling frequency", timeWindows: nil
                )
            )
        }

        // MARK: Net Frequencies (±5 kHz)

        list.append(
            FrequencyActivity(
                type: .net, band: "20m", centerMHz: 14.336, toleranceKHz: 5,
                modes: ["SSB", "USB", "LSB"], description: "County Hunters Net", timeWindows: nil
            )
        )
        list.append(
            FrequencyActivity(
                type: .net, band: "40m", centerMHz: 7.188, toleranceKHz: 5,
                modes: ["SSB", "USB", "LSB"], description: "County Hunters Net", timeWindows: nil
            )
        )

        return list
    }

    /// Check if a frequency falls within a CWT range during active CWT time
    static func isInCWTRange(frequencyMHz: Double, at date: Date = Date()) -> CWTRange? {
        // First check if we're in a CWT time window
        guard cwtTimeWindows.contains(where: { $0.contains(date: date) }) else {
            return nil
        }
        // Then check if frequency is in a CWT range
        return cwtRanges.first { $0.contains(frequencyMHz: frequencyMHz) }
    }

    /// Find all activities that match a given frequency
    static func activitiesMatching(frequencyMHz: Double) -> [FrequencyActivity] {
        activities.filter { $0.matches(frequencyMHz: frequencyMHz) }
    }

    // MARK: - ARRL Band Plan Usage Zones

    /// Conventional usage zones per the ARRL band plan.
    /// These are voluntary conventions, not regulatory — but the recommendation
    /// algorithm should respect them to suggest appropriate frequencies.
    static let usageZones: [UsageZone] = [
        // 160m
        UsageZone(band: "160m", startMHz: 1.800, endMHz: 1.810, usage: .cw),
        UsageZone(band: "160m", startMHz: 1.810, endMHz: 1.843, usage: .cwAndDigital),
        UsageZone(band: "160m", startMHz: 1.843, endMHz: 2.000, usage: .phone),

        // 80m
        UsageZone(band: "80m", startMHz: 3.500, endMHz: 3.570, usage: .cw),
        UsageZone(band: "80m", startMHz: 3.570, endMHz: 3.600, usage: .digital),
        UsageZone(band: "80m", startMHz: 3.600, endMHz: 3.700, usage: .cwAndDigital),
        UsageZone(band: "80m", startMHz: 3.700, endMHz: 4.000, usage: .phone),

        // 40m
        UsageZone(band: "40m", startMHz: 7.000, endMHz: 7.040, usage: .cw),
        UsageZone(band: "40m", startMHz: 7.040, endMHz: 7.125, usage: .cwAndDigital),
        UsageZone(band: "40m", startMHz: 7.125, endMHz: 7.300, usage: .phone),

        // 30m (CW and Data only band)
        UsageZone(band: "30m", startMHz: 10.100, endMHz: 10.130, usage: .cw),
        UsageZone(band: "30m", startMHz: 10.130, endMHz: 10.150, usage: .digital),

        // 20m
        UsageZone(band: "20m", startMHz: 14.000, endMHz: 14.070, usage: .cw),
        UsageZone(band: "20m", startMHz: 14.070, endMHz: 14.100, usage: .digital),
        UsageZone(band: "20m", startMHz: 14.100, endMHz: 14.150, usage: .cwAndDigital),
        UsageZone(band: "20m", startMHz: 14.150, endMHz: 14.350, usage: .phone),

        // 17m
        UsageZone(band: "17m", startMHz: 18.068, endMHz: 18.100, usage: .cw),
        UsageZone(band: "17m", startMHz: 18.100, endMHz: 18.110, usage: .digital),
        UsageZone(band: "17m", startMHz: 18.110, endMHz: 18.168, usage: .phone),

        // 15m
        UsageZone(band: "15m", startMHz: 21.000, endMHz: 21.070, usage: .cw),
        UsageZone(band: "15m", startMHz: 21.070, endMHz: 21.110, usage: .digital),
        UsageZone(band: "15m", startMHz: 21.110, endMHz: 21.200, usage: .cwAndDigital),
        UsageZone(band: "15m", startMHz: 21.200, endMHz: 21.450, usage: .phone),

        // 12m
        UsageZone(band: "12m", startMHz: 24.890, endMHz: 24.920, usage: .cw),
        UsageZone(band: "12m", startMHz: 24.920, endMHz: 24.930, usage: .digital),
        UsageZone(band: "12m", startMHz: 24.930, endMHz: 24.990, usage: .phone),

        // 10m
        UsageZone(band: "10m", startMHz: 28.000, endMHz: 28.070, usage: .cw),
        UsageZone(band: "10m", startMHz: 28.070, endMHz: 28.150, usage: .digital),
        UsageZone(band: "10m", startMHz: 28.150, endMHz: 28.300, usage: .cwAndDigital),
        UsageZone(band: "10m", startMHz: 28.300, endMHz: 29.000, usage: .phone),
        UsageZone(band: "10m", startMHz: 29.000, endMHz: 29.200, usage: .am),
        UsageZone(band: "10m", startMHz: 29.500, endMHz: 29.700, usage: .fm),

        // VHF/UHF — broad zones
        UsageZone(band: "6m", startMHz: 50.000, endMHz: 50.100, usage: .cw),
        UsageZone(band: "6m", startMHz: 50.100, endMHz: 50.300, usage: .phone),
        UsageZone(band: "6m", startMHz: 50.300, endMHz: 50.600, usage: .digital),
        UsageZone(band: "6m", startMHz: 52.000, endMHz: 54.000, usage: .fm),
        UsageZone(band: "2m", startMHz: 144.000, endMHz: 144.100, usage: .cw),
        UsageZone(band: "2m", startMHz: 144.100, endMHz: 144.275, usage: .phone),
        UsageZone(band: "2m", startMHz: 144.275, endMHz: 144.500, usage: .digital),
        UsageZone(band: "2m", startMHz: 146.000, endMHz: 148.000, usage: .fm),
        UsageZone(band: "70cm", startMHz: 420.000, endMHz: 432.000, usage: .fm),
        UsageZone(band: "70cm", startMHz: 432.000, endMHz: 433.000, usage: .cw),
        UsageZone(band: "70cm", startMHz: 440.000, endMHz: 450.000, usage: .fm),
    ]

    /// Find usage zones for a band that match a given mode
    static func usageZones(forBand band: String, mode: String) -> [UsageZone] {
        usageZones.filter { $0.band == band && $0.matchesMode(mode) }
    }
}

// MARK: - UsageZone

/// A frequency range with its conventional usage per the ARRL band plan
struct UsageZone: Sendable {
    enum Usage: String, Sendable {
        case cw
        case digital // FT8, FT4, RTTY, PSK, etc.
        case cwAndDigital // Mixed CW/data zones
        case phone // SSB
        case am
        case fm
    }

    let band: String
    let startMHz: Double
    let endMHz: Double
    let usage: Usage

    func contains(frequencyMHz: Double) -> Bool {
        frequencyMHz >= startMHz && frequencyMHz < endMHz
    }

    /// Check if a mode conventionally belongs in this usage zone
    func matchesMode(_ mode: String) -> Bool {
        switch mode.uppercased() {
        case "CW":
            usage == .cw || usage == .cwAndDigital
        case "SSB",
             "USB",
             "LSB":
            usage == .phone
        case "FT8",
             "FT4",
             "RTTY",
             "PSK31",
             "PSK":
            usage == .digital || usage == .cwAndDigital
        case "AM":
            usage == .am || usage == .phone
        case "FM":
            usage == .fm
        default:
            usage == .cw || usage == .cwAndDigital
        }
    }

    /// Whether this zone is the primary (preferred) zone for a mode,
    /// vs a secondary zone where the mode is allowed but not ideal.
    /// E.g., CW's primary zone is `.cw`; `.cwAndDigital` is secondary.
    func isPrimaryZone(for mode: String) -> Bool {
        switch mode.uppercased() {
        case "CW":
            usage == .cw
        case "SSB",
             "USB",
             "LSB":
            usage == .phone
        case "FT8",
             "FT4",
             "RTTY",
             "PSK31",
             "PSK":
            usage == .digital
        case "AM":
            usage == .am
        case "FM":
            usage == .fm
        default:
            usage == .cw
        }
    }
}
