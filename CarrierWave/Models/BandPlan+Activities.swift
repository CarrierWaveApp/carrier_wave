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
}
