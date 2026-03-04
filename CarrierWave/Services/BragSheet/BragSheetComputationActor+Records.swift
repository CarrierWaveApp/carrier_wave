import CarrierWaveData
import Foundation

// MARK: - Volume Records

extension BragSheetComputationActor {
    func computeMostQSOsDay(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let byDay = Dictionary(grouping: snapshots) { calendar.startOfDay(for: $0.timestamp) }
        guard let best = byDay.max(by: { $0.value.count < $1.value.count }) else {
            return .noData
        }
        return .count(best.value.count)
    }

    func computeMostQSOsSession(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        let bySession = Dictionary(grouping: snapshots) { $0.loggingSessionId ?? $0.id }
        guard let best = bySession.max(by: { $0.value.count < $1.value.count }) else {
            return .noData
        }
        return .count(best.value.count)
    }

    func computeMostCountriesDay(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let byDay = Dictionary(grouping: snapshots) { calendar.startOfDay(for: $0.timestamp) }
        var best = 0
        for (_, dayQSOs) in byDay {
            let countries = Set(dayQSOs.compactMap(\.dxcc))
            best = max(best, countries.count)
        }
        guard best > 0 else {
            return .noData
        }
        return .count(best)
    }

    func computeMostBandsDay(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let byDay = Dictionary(grouping: snapshots) { calendar.startOfDay(for: $0.timestamp) }
        var best = 0
        for (_, dayQSOs) in byDay {
            let bands = Set(dayQSOs.map { $0.band.lowercased() })
            best = max(best, bands.count)
        }
        guard best > 0 else {
            return .noData
        }
        return .count(best)
    }
}

// MARK: - Streaks

extension BragSheetComputationActor {
    func computeCurrentStreak(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        let result = computeStreakFromSnapshots(snapshots)
        return .streak(current: result.current, longest: result.longest)
    }

    func computeBestStreak(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        let result = computeStreakFromSnapshots(snapshots)
        return .streak(current: result.current, longest: result.longest)
    }

    func computeActivationStreak(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        let parksOnly = snapshots.filter { $0.parkReference != nil && !$0.parkReference!.isEmpty }
        let groups = Dictionary(grouping: parksOnly) { qso in
            "\(qso.parkReference!)|\(qso.utcDateOnly.timeIntervalSince1970)"
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let activationDates = groups.values
            .filter { $0.count >= 10 }
            .compactMap { $0.first?.utcDateOnly }
        let uniqueDates = Set(activationDates).sorted()
        guard !uniqueDates.isEmpty else {
            return .noData
        }
        let result = computeStreakFromDates(uniqueDates, using: calendar)
        return .streak(current: result.current, longest: result.longest)
    }

    func computeModeStreaks(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var entries: [ModeStreakEntry] = []

        for family in [ModeFamily.cw, .phone, .digital] {
            let filtered = snapshots.filter { $0.modeFamily == family }
            guard !filtered.isEmpty else {
                continue
            }
            let dates = Set(filtered.map { calendar.startOfDay(for: $0.timestamp) }).sorted()
            let result = computeStreakFromDates(dates, using: calendar)
            let name = switch family {
            case .cw: "CW"
            case .phone: "Phone"
            case .digital: "Digital"
            case .other: "Other"
            }
            entries.append(ModeStreakEntry(
                mode: name, current: result.current, longest: result.longest
            ))
        }

        guard !entries.isEmpty else {
            return .noData
        }
        return .modeStreakList(entries)
    }

    // MARK: - Streak Helpers

    private func computeStreakFromSnapshots(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> (current: Int, longest: Int) {
        let calendar = Calendar.current
        let dates = Set(snapshots.map { calendar.startOfDay(for: $0.timestamp) }).sorted()
        guard !dates.isEmpty else {
            return (0, 0)
        }
        let result = computeStreakFromDates(dates, using: calendar)
        return (result.current, result.longest)
    }

    private func computeStreakFromDates(
        _ uniqueDates: [Date], using calendar: Calendar
    ) -> (current: Int, longest: Int) {
        var currentStreak = 0
        var longestStreak = 0
        var previousDate: Date?

        for date in uniqueDates {
            if let prev = previousDate {
                let daysDiff = calendar.dateComponents([.day], from: prev, to: date).day ?? 0
                if daysDiff == 1 {
                    currentStreak += 1
                } else if daysDiff > 1 {
                    longestStreak = max(longestStreak, currentStreak)
                    currentStreak = 1
                }
            } else {
                currentStreak = 1
            }
            previousDate = date
        }
        longestStreak = max(longestStreak, currentStreak)

        // Check if current streak is active
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let isActive = previousDate.map {
            calendar.isDate($0, inSameDayAs: today)
                || calendar.isDate($0, inSameDayAs: yesterday)
        } ?? false

        return (current: isActive ? currentStreak : 0, longest: longestStreak)
    }
}

// MARK: - CW Stats

extension BragSheetComputationActor {
    func computeCWDistanceRecord(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        let cwWithDistance = snapshots
            .filter { $0.modeFamily == .cw }
            .compactMap { qso -> (BragSheetQSOSnapshot, Double)? in
                guard let km = qso.distanceKm else {
                    return nil
                }
                return (qso, km)
            }
        guard let best = cwWithDistance.max(by: { $0.1 < $1.1 }) else {
            return .noData
        }
        return .contact(
            callsign: best.0.callsign,
            distanceKm: best.1,
            band: best.0.band
        )
    }

    func computeCWQRPRecord(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        let cwQRP = snapshots
            .filter { $0.modeFamily == .cw && $0.isQRP }
            .compactMap { qso -> (BragSheetQSOSnapshot, Double)? in
                guard let km = qso.distanceKm else {
                    return nil
                }
                return (qso, km)
            }
        guard let best = cwQRP.max(by: { $0.1 < $1.1 }) else {
            return .noData
        }
        return .contact(
            callsign: best.0.callsign,
            distanceKm: best.1,
            band: best.0.band
        )
    }
}

// MARK: - Signal Quality Stats

extension BragSheetComputationActor {
    func computePerfectReports(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        let perfect = snapshots.filter { qso in
            guard let rst = qso.rstReceived else {
                return false
            }
            return rst == "599" || rst == "59"
        }
        return .count(perfect.count)
    }

    func computeAverageRST(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        let signals = snapshots.compactMap { qso -> Int? in
            guard let rst = qso.rstReceived, rst.count >= 2 else {
                return nil
            }
            return rst.compactMap(\.wholeNumberValue).dropFirst().first // S component
        }
        guard !signals.isEmpty else {
            return .noData
        }
        let avg = Double(signals.reduce(0, +)) / Double(signals.count)
        return .rst(value: String(format: "S%.1f", avg), detail: nil)
    }

    func computeBestRSTAtDistance(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        let perfectWithDistance = snapshots.compactMap { qso
            -> (BragSheetQSOSnapshot, Double)? in
            guard let rst = qso.rstReceived,
                  rst == "599" || rst == "59",
                  let km = qso.distanceKm
            else {
                return nil
            }
            return (qso, km)
        }
        guard let best = perfectWithDistance.max(by: { $0.1 < $1.1 }) else {
            return .noData
        }
        return .contact(
            callsign: best.0.callsign,
            distanceKm: best.1,
            band: best.0.band
        )
    }
}
