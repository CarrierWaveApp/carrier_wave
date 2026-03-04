import CarrierWaveData
import CoreLocation
import Foundation
import SwiftData

// MARK: - Detection Methods

extension ActivityDetector {
    /// Load historical data from existing QSOs (excluding the new batch)
    func loadHistoricalData(excluding newQSOs: [QSO]) -> HistoricalData {
        let newQSOIds = Set(newQSOs.map(\.id))

        // Fetch QSOs with a limit to avoid full table scans that freeze the UI.
        // 10k is enough to cover bands/modes/DXCC for the vast majority of users.
        // Users with more QSOs may see rare false "new" detections — acceptable tradeoff.
        var descriptor = FetchDescriptor<QSO>(
            sortBy: [SortDescriptor(\QSO.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 10_000
        let allQSOs = (try? modelContext.fetch(descriptor)) ?? []

        // Filter out the new QSOs
        let historicalQSOs = allQSOs.filter { !newQSOIds.contains($0.id) }

        // Build historical data sets
        var knownDXCCCodes = Set<Int>()
        var knownBands = Set<String>()
        var knownModes = Set<String>()
        var qsoDates = Set<Date>()
        var potaDates = Set<Date>()
        var maxDistanceKm: Double = 0
        var qsosPerDay: [Date: Int] = [:]

        for qso in historicalQSOs {
            // Track DXCC codes
            if let dxcc = qso.dxcc {
                knownDXCCCodes.insert(dxcc)
            }

            // Track bands and modes
            knownBands.insert(qso.band.uppercased())
            knownModes.insert(qso.mode.uppercased())

            // Track QSO dates for streaks
            let dateOnly = qso.dateOnly
            qsoDates.insert(dateOnly)

            // Track POTA dates (UTC) for POTA streak
            if qso.parkReference != nil {
                potaDates.insert(qso.utcDateOnly)
            }

            // Track QSOs per day for personal best
            qsosPerDay[dateOnly, default: 0] += 1

            // Track max distance
            if let distance = calculateDistanceKm(from: qso.myGrid, to: qso.theirGrid) {
                maxDistanceKm = max(maxDistanceKm, distance)
            }
        }

        let maxQSOsInDay = qsosPerDay.values.max() ?? 0

        return HistoricalData(
            knownDXCCCodes: knownDXCCCodes,
            knownBands: knownBands,
            knownModes: knownModes,
            qsoDates: qsoDates,
            potaDates: potaDates,
            maxDistanceKm: maxDistanceKm,
            maxQSOsInDay: maxQSOsInDay
        )
    }

    /// Detect if QSO represents a new DXCC entity
    func detectNewDXCC(qso: QSO, historical: HistoricalData) -> DetectedActivity? {
        guard let dxcc = qso.dxcc, !historical.knownDXCCCodes.contains(dxcc) else {
            return nil
        }

        let entity = qso.dxccEntity
        return DetectedActivity(
            type: .newDXCCEntity,
            timestamp: qso.timestamp,
            entityName: entity?.name,
            entityCode: entity?.name,
            band: qso.band,
            mode: qso.mode
        )
    }

    /// Detect if QSO represents a new band
    func detectNewBand(qso: QSO, historical: HistoricalData) -> DetectedActivity? {
        let band = qso.band.uppercased()
        guard !historical.knownBands.contains(band) else {
            return nil
        }

        return DetectedActivity(
            type: .newBand,
            timestamp: qso.timestamp,
            band: qso.band,
            mode: qso.mode
        )
    }

    /// Detect if QSO represents a new mode
    func detectNewMode(qso: QSO, historical: HistoricalData) -> DetectedActivity? {
        let mode = qso.mode.uppercased()
        guard !historical.knownModes.contains(mode) else {
            return nil
        }

        return DetectedActivity(
            type: .newMode,
            timestamp: qso.timestamp,
            band: qso.band,
            mode: qso.mode
        )
    }

    /// Detect if QSO is a DX contact (>5000km)
    func detectDXContact(qso: QSO) -> DetectedActivity? {
        guard let distance = calculateDistanceKm(from: qso.myGrid, to: qso.theirGrid),
              distance >= dxDistanceThresholdKm
        else {
            return nil
        }

        return DetectedActivity(
            type: .dxContact,
            timestamp: qso.timestamp,
            band: qso.band,
            mode: qso.mode,
            workedCallsign: qso.callsign,
            distanceKm: distance
        )
    }

    /// Detect POTA activations from QSOs (10+ QSOs at a park)
    func detectPOTAActivations(qsos: [QSO]) -> [DetectedActivity] {
        // Group QSOs by park reference (ignoring nil)
        var parkQSOs: [String: [QSO]] = [:]
        for qso in qsos where qso.parkReference != nil && !qso.parkReference!.isEmpty {
            parkQSOs[qso.parkReference!, default: []].append(qso)
        }

        // Create activity for each park with enough QSOs
        return parkQSOs.compactMap { parkRef, parkQSOList -> DetectedActivity? in
            guard parkQSOList.count >= potaActivationThreshold else {
                return nil
            }

            let timestamp = parkQSOList.map(\.timestamp).min() ?? Date()
            return DetectedActivity(
                type: .potaActivation,
                timestamp: timestamp,
                parkReference: parkRef,
                parkName: nil,
                qsoCount: parkQSOList.count
            )
        }
    }

    /// Detect SOTA activations from QSOs (4+ QSOs at a summit)
    func detectSOTAActivations(qsos: [QSO]) -> [DetectedActivity] {
        // Group QSOs by SOTA reference (ignoring nil)
        var sotaQSOs: [String: [QSO]] = [:]
        for qso in qsos where qso.sotaRef != nil && !qso.sotaRef!.isEmpty {
            sotaQSOs[qso.sotaRef!, default: []].append(qso)
        }

        // Create activity for each summit with enough QSOs
        return sotaQSOs.compactMap { sotaRef, sotaQSOList -> DetectedActivity? in
            guard sotaQSOList.count >= sotaActivationThreshold else {
                return nil
            }

            let timestamp = sotaQSOList.map(\.timestamp).min() ?? Date()
            return DetectedActivity(
                type: .sotaActivation,
                timestamp: timestamp,
                parkReference: sotaRef,
                parkName: nil,
                qsoCount: sotaQSOList.count
            )
        }
    }

    /// Detect if new QSOs create a daily streak milestone
    func detectDailyStreakMilestone(newQSOs: [QSO], historical: HistoricalData) -> DetectedActivity? {
        // Add new QSO dates to historical dates
        var allDates = historical.qsoDates
        for qso in newQSOs {
            allDates.insert(qso.dateOnly)
        }

        // Calculate streak with all dates
        let newStreak = StreakCalculator.calculateStreak(from: allDates)
        let oldStreak = StreakCalculator.calculateStreak(from: historical.qsoDates)

        // Check if we crossed a milestone
        guard
            let milestone = findCrossedMilestone(
                oldValue: oldStreak.current, newValue: newStreak.current
            )
        else {
            return nil
        }

        let timestamp = newQSOs.map(\.timestamp).max() ?? Date()
        return DetectedActivity(type: .dailyStreak, timestamp: timestamp, streakDays: milestone)
    }

    /// Detect if new QSOs create a POTA streak milestone
    func detectPOTAStreakMilestone(newQSOs: [QSO], historical: HistoricalData) -> DetectedActivity? {
        // Add new POTA dates (UTC) to historical dates
        var allPOTADates = historical.potaDates
        for qso in newQSOs where qso.parkReference != nil {
            allPOTADates.insert(qso.utcDateOnly)
        }

        // No new POTA QSOs, no possible milestone
        guard allPOTADates.count > historical.potaDates.count else {
            return nil
        }

        // Calculate streak with all dates (using UTC)
        let newStreak = StreakCalculator.calculateStreak(from: allPOTADates, useUTC: true)
        let oldStreak = StreakCalculator.calculateStreak(from: historical.potaDates, useUTC: true)

        // Check if we crossed a milestone
        guard
            let milestone = findCrossedMilestone(
                oldValue: oldStreak.current, newValue: newStreak.current
            )
        else {
            return nil
        }

        let timestamp = newQSOs.filter { $0.parkReference != nil }.map(\.timestamp).max() ?? Date()
        return DetectedActivity(type: .potaDailyStreak, timestamp: timestamp, streakDays: milestone)
    }

    /// Detect personal bests (new distance record, new QSOs-in-day record)
    func detectPersonalBests(qsos: [QSO], historical: HistoricalData) -> [DetectedActivity] {
        var activities: [DetectedActivity] = []

        // Check for new distance record
        if let distanceActivity = detectDistanceRecord(qsos: qsos, historical: historical) {
            activities.append(distanceActivity)
        }

        // Check for new QSOs-in-day record
        if let qsoCountActivity = detectQSOCountRecord(qsos: qsos, historical: historical) {
            activities.append(qsoCountActivity)
        }

        return activities
    }

    // MARK: - Private Helpers

    /// Calculate distance in kilometers between two grid squares
    func calculateDistanceKm(from myGrid: String?, to theirGrid: String?) -> Double? {
        guard let myGrid, let theirGrid,
              let myCoord = MaidenheadConverter.coordinate(from: myGrid),
              let theirCoord = MaidenheadConverter.coordinate(from: theirGrid)
        else {
            return nil
        }

        let myLocation = CLLocation(latitude: myCoord.latitude, longitude: myCoord.longitude)
        let theirLocation = CLLocation(
            latitude: theirCoord.latitude, longitude: theirCoord.longitude
        )

        return myLocation.distance(from: theirLocation) / 1_000.0
    }

    /// Find if a milestone was crossed going from old to new value
    func findCrossedMilestone(oldValue: Int, newValue: Int) -> Int? {
        for milestone in streakMilestones where newValue >= milestone && oldValue < milestone {
            return milestone
        }
        return nil
    }

    private func detectDistanceRecord(qsos: [QSO], historical: HistoricalData) -> DetectedActivity? {
        var maxNewDistance: Double = 0
        var maxDistanceQSO: QSO?

        for qso in qsos {
            if let distance = calculateDistanceKm(from: qso.myGrid, to: qso.theirGrid),
               distance > maxNewDistance
            {
                maxNewDistance = distance
                maxDistanceQSO = qso
            }
        }

        guard maxNewDistance > historical.maxDistanceKm, let qso = maxDistanceQSO else {
            return nil
        }

        return DetectedActivity(
            type: .personalBest,
            timestamp: qso.timestamp,
            workedCallsign: qso.callsign,
            distanceKm: maxNewDistance,
            recordType: "distance",
            recordValue: String(format: "%.0f km", maxNewDistance)
        )
    }

    private func detectQSOCountRecord(qsos: [QSO], historical: HistoricalData) -> DetectedActivity? {
        // Group new QSOs by date
        var qsosPerDay: [Date: Int] = [:]
        for qso in qsos {
            qsosPerDay[qso.dateOnly, default: 0] += 1
        }

        // Find if any day's total exceeds historical max
        for (date, newCount) in qsosPerDay where newCount > historical.maxQSOsInDay {
            let dayQSOs = qsos.filter { $0.dateOnly == date }
            let timestamp = dayQSOs.map(\.timestamp).max() ?? Date()

            return DetectedActivity(
                type: .personalBest,
                timestamp: timestamp,
                recordType: "qsos_in_day",
                recordValue: "\(newCount) QSOs"
            )
        }

        return nil
    }

    /// Detect QSOs with accepted friends
    func detectWorkedFriends(qsos: [QSO]) -> [DetectedActivity] {
        // Load accepted friends
        let acceptedStatus = "accepted"
        let descriptor = FetchDescriptor<Friendship>(
            predicate: #Predicate { $0.statusRawValue == acceptedStatus }
        )
        let friends = (try? modelContext.fetch(descriptor)) ?? []

        guard !friends.isEmpty else {
            return []
        }

        let friendCallsigns = Set(friends.map { $0.friendCallsign.uppercased() })
        let ownCallsign = userCallsign.uppercased()

        var activities: [DetectedActivity] = []

        for qso in qsos {
            let callsign = qso.callsign.uppercased()

            // Skip self-QSOs
            guard callsign != ownCallsign else {
                continue
            }

            guard friendCallsigns.contains(callsign) else {
                continue
            }

            activities.append(
                DetectedActivity(
                    type: .workedFriend,
                    timestamp: qso.timestamp,
                    band: qso.band,
                    mode: qso.mode,
                    workedCallsign: qso.callsign
                )
            )
        }

        return activities
    }
}
