import CarrierWaveCore
import Foundation

// MARK: - POTA Stats

extension BragSheetComputationActor {
    func computeParksActivated(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        let groups = activationGroups(from: snapshots)
        let successful = groups.values.filter { $0.count >= 10 }
        let parks = Set(successful.compactMap { $0.first?.parkReference })
        return .count(parks.count)
    }

    func computeParksHunted(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        let hunted = Set(
            snapshots.compactMap(\.theirParkReference).filter { !$0.isEmpty }
        )
        return .count(hunted.count)
    }

    func computeP2P(_ snapshots: [BragSheetQSOSnapshot]) -> BragSheetStatValue {
        let p2p = snapshots.filter {
            ($0.parkReference != nil && !$0.parkReference!.isEmpty)
                && ($0.theirParkReference != nil && !$0.theirParkReference!.isEmpty)
        }
        return .count(p2p.count)
    }

    func computeLargestNfer(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        // N-fer = multiple parks activated simultaneously (same session)
        // Group by session, find session with most distinct park references
        let bySession = Dictionary(grouping: snapshots.filter {
            $0.parkReference != nil && !$0.parkReference!.isEmpty
        }) { $0.loggingSessionId ?? $0.id }

        var bestNfer = 0
        for (_, sessionQSOs) in bySession {
            let parks = Set(sessionQSOs.compactMap(\.parkReference))
            bestNfer = max(bestNfer, parks.count)
        }

        guard bestNfer > 1 else { return .noData }
        return .count(bestNfer)
    }

    func computeBestActivation(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        let groups = activationGroups(from: snapshots)
        guard let best = groups.max(by: { $0.value.count < $1.value.count }) else {
            return .noData
        }
        let qsos = best.value
        guard let first = qsos.first else { return .noData }
        return .parkDetail(
            park: first.parkReference ?? "Unknown",
            date: first.utcDateOnly,
            count: qsos.count
        )
    }

    func computeNewParks(
        _ snapshots: [BragSheetQSOSnapshot],
        allSnapshots: [BragSheetQSOSnapshot]?
    ) -> BragSheetStatValue {
        guard let allSnapshots else { return .noData }

        let periodStart = snapshots.map(\.timestamp).min() ?? Date()

        // Parks activated in this period
        let periodParks = Set(
            snapshots.compactMap(\.parkReference).filter { !$0.isEmpty }
        )
        // Parks hunted in this period
        let periodHunted = Set(
            snapshots.compactMap(\.theirParkReference).filter { !$0.isEmpty }
        )
        let periodAll = periodParks.union(periodHunted)

        // Find parks where the earliest contact is within this period
        var newCount = 0
        for park in periodAll {
            let allForPark = allSnapshots.filter {
                $0.parkReference == park || $0.theirParkReference == park
            }
            let earliest = allForPark.min(by: { $0.timestamp < $1.timestamp })
            if let earliest, earliest.timestamp >= periodStart {
                newCount += 1
            }
        }
        return .count(newCount)
    }

    // MARK: - Helpers

    private func activationGroups(
        from snapshots: [BragSheetQSOSnapshot]
    ) -> [String: [BragSheetQSOSnapshot]] {
        let parksOnly = snapshots.filter { $0.parkReference != nil && !$0.parkReference!.isEmpty }
        return Dictionary(grouping: parksOnly) { qso in
            "\(qso.parkReference!)|\(qso.utcDateOnly.timeIntervalSince1970)"
        }
    }
}

// MARK: - Fun & Unique Stats

extension BragSheetComputationActor {
    func computeEarliestQSO(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // Find QSO closest to midnight UTC
        guard let earliest = snapshots.min(by: { qso1, qso2 in
            let time1 = timeOfDaySeconds(qso1.timestamp, calendar: calendar)
            let time2 = timeOfDaySeconds(qso2.timestamp, calendar: calendar)
            return time1 < time2
        }) else { return .noData }
        return .timeOfDay(earliest.timestamp)
    }

    func computeLatestQSO(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let latest = snapshots.max(by: { qso1, qso2 in
            let time1 = timeOfDaySeconds(qso1.timestamp, calendar: calendar)
            let time2 = timeOfDaySeconds(qso2.timestamp, calendar: calendar)
            return time1 < time2
        }) else { return .noData }
        return .timeOfDay(latest.timestamp)
    }

    func computeLongestSession(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        let bySession = Dictionary(grouping: snapshots) { $0.loggingSessionId ?? $0.id }
        var longest: TimeInterval = 0

        for (_, sessionQSOs) in bySession {
            let sorted = sessionQSOs.sorted { $0.timestamp < $1.timestamp }
            guard let first = sorted.first, let last = sorted.last else { continue }
            let duration = last.timestamp.timeIntervalSince(first.timestamp)
            longest = max(longest, duration)
        }

        guard longest > 0 else { return .noData }
        return .duration(seconds: longest)
    }

    func computeMostActiveDay(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var dayCounts: [Int: Int] = [:] // weekday number -> count
        for qso in snapshots {
            let weekday = calendar.component(.weekday, from: qso.timestamp)
            dayCounts[weekday, default: 0] += 1
        }
        guard let best = dayCounts.max(by: { $0.value < $1.value }) else {
            return .noData
        }
        let dayNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let dayName = best.key < dayNames.count ? dayNames[best.key] : "?"
        return .dayOfWeek(day: dayName, count: best.value)
    }

    func computeBusiestBand(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        var counts: [String: Int] = [:]
        for qso in snapshots {
            counts[qso.band.lowercased(), default: 0] += 1
        }
        guard let best = counts.max(by: { $0.value < $1.value }) else {
            return .noData
        }
        return .callsignCount(callsign: best.key, count: best.value)
    }

    func computeBusiestMode(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        var counts: [String: Int] = [:]
        for qso in snapshots {
            let canonical = ModeEquivalence.canonicalName(qso.mode)
            counts[canonical, default: 0] += 1
        }
        guard let best = counts.max(by: { $0.value < $1.value }) else {
            return .noData
        }
        return .callsignCount(callsign: best.key, count: best.value)
    }

    func computeRepeatCustomers(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        var counts: [String: Int] = [:]
        for qso in snapshots {
            counts[qso.callsign.uppercased(), default: 0] += 1
        }
        guard let best = counts.filter({ $0.value > 1 })
            .max(by: { $0.value < $1.value })
        else {
            return .noData
        }
        return .callsignCount(callsign: best.key, count: best.value)
    }

    // MARK: - Helpers

    private func timeOfDaySeconds(_ date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (components.hour ?? 0) * 3600
            + (components.minute ?? 0) * 60
            + (components.second ?? 0)
    }
}
