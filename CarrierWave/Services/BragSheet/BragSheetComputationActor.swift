import CarrierWaveData
import Foundation
import SwiftData

// MARK: - BragSheetComputedResult

/// All computed brag sheet stats for a single period.
nonisolated struct BragSheetComputedResult: Sendable {
    // MARK: Lifecycle

    init(
        period: BragSheetPeriod,
        stats: [BragSheetStatType: BragSheetStatValue] = [:],
        qsoCount: Int = 0,
        dateRange: (start: Date, end: Date) = (.distantPast, Date())
    ) {
        self.period = period
        self.stats = stats
        self.qsoCount = qsoCount
        self.dateRange = dateRange
    }

    // MARK: Internal

    let period: BragSheetPeriod
    let stats: [BragSheetStatType: BragSheetStatValue]
    let qsoCount: Int
    let dateRange: (start: Date, end: Date)

    /// Get the value for a stat, or .noData if not computed.
    func value(for stat: BragSheetStatType) -> BragSheetStatValue {
        stats[stat] ?? .noData
    }
}

// MARK: - BragSheetComputationActor

/// Background actor for computing brag sheet statistics.
/// Fetches QSOs within the time window and computes only the requested stats.
actor BragSheetComputationActor {
    // MARK: Internal

    /// Compute stats for a given period and configuration.
    func computeStats(
        container: ModelContainer,
        period: BragSheetPeriod,
        config: BragSheetPeriodConfig,
        allTimeSnapshots: [BragSheetQSOSnapshot]? = nil
    ) async throws -> BragSheetComputedResult {
        let dateRange = period.dateRange()
        let snapshots: [BragSheetQSOSnapshot] = if let allTimeSnapshots, period == .allTime {
            allTimeSnapshots
        } else if let allTimeSnapshots {
            allTimeSnapshots.filter {
                $0.timestamp >= dateRange.start && $0.timestamp <= dateRange.end
            }
        } else {
            try await fetchSnapshots(
                container: container, dateRange: dateRange
            )
        }

        try Task.checkCancellation()

        guard !snapshots.isEmpty else {
            return BragSheetComputedResult(
                period: period, qsoCount: 0, dateRange: dateRange
            )
        }

        let enabledSet = Set(config.enabledStats)
        var results: [BragSheetStatType: BragSheetStatValue] = [:]
        results.reserveCapacity(enabledSet.count)

        // Compute each enabled stat
        for stat in config.enabledStats {
            try Task.checkCancellation()
            results[stat] = computeStat(stat, from: snapshots, allSnapshots: allTimeSnapshots)
        }

        return BragSheetComputedResult(
            period: period,
            stats: results,
            qsoCount: snapshots.count,
            dateRange: dateRange
        )
    }

    /// Fetch all QSOs as snapshots (for allTime, shared across periods).
    func fetchAllSnapshots(container: ModelContainer) async throws -> [BragSheetQSOSnapshot] {
        try await fetchSnapshots(container: container, dateRange: (.distantPast, Date()))
    }

    // MARK: - Stat Dispatch

    /// Compute a single stat from the snapshot data.
    func computeStat(
        _ stat: BragSheetStatType,
        from snapshots: [BragSheetQSOSnapshot],
        allSnapshots: [BragSheetQSOSnapshot]?
    ) -> BragSheetStatValue {
        switch stat.category {
        case .totals: computeTotalsStat(stat, snapshots)
        case .speedAndRate: computeSpeedStat(stat, snapshots)
        case .distance: computeDistanceStat(stat, snapshots)
        case .powerAndEfficiency: computePowerStat(stat, snapshots)
        case .geographicReach: computeGeoStat(stat, snapshots, allSnapshots: allSnapshots)
        case .volumeRecords: computeVolumeStat(stat, snapshots)
        case .streaks: computeStreakStat(stat, snapshots)
        case .pota: computePOTAStat(stat, snapshots, allSnapshots: allSnapshots)
        case .cw: computeCWStat(stat, snapshots)
        case .signalQuality: computeSignalStat(stat, snapshots)
        case .funAndUnique: computeFunStat(stat, snapshots)
        }
    }

    // MARK: Private

    /// Modes that represent metadata rather than actual contacts.
    private static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

    // MARK: - Category Dispatch

    private func computeTotalsStat(
        _ stat: BragSheetStatType,
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        switch stat {
        case .totalQSOs: computeTotalQSOs(snapshots)
        case .totalCWQSOs: computeModeCount(snapshots, family: .cw)
        case .totalPhoneQSOs: computeModeCount(snapshots, family: .phone)
        case .totalDigitalQSOs: computeModeCount(snapshots, family: .digital)
        case .totalDistance: computeTotalDistance(snapshots)
        case .operatingDays: computeOperatingDays(snapshots)
        case .operatingHours: computeOperatingHours(snapshots)
        case .activeBands: computeActiveBands(snapshots)
        case .activeModes: computeActiveModes(snapshots)
        case .uniqueCallsigns: computeUniqueCallsigns(snapshots)
        case .qrpQSOCount: computeQRPCount(snapshots)
        case .milliwattQSOCount: computeMilliwattCount(snapshots)
        default: .noData
        }
    }

    private func computeSpeedStat(
        _ stat: BragSheetStatType,
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        switch stat {
        case .fastest10QSOs: computeFastest10(snapshots)
        case .peak15MinRate: computePeak15MinRate(snapshots)
        case .bestSessionRate: computeBestSessionRate(snapshots)
        case .fastestActivation: computeFastestActivation(snapshots)
        default: .noData
        }
    }

    private func computeDistanceStat(
        _ stat: BragSheetStatType,
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        switch stat {
        case .furthestContact: computeFurthestContact(snapshots)
        case .furthestContactPerBand: computeFurthestPerBand(snapshots)
        case .furthestQRPContact: computeFurthestQRP(snapshots)
        case .averageContactDistance: computeAverageDistance(snapshots)
        default: .noData
        }
    }

    private func computePowerStat(
        _ stat: BragSheetStatType,
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        switch stat {
        case .lowestPowerContact: computeLowestPower(snapshots)
        case .bestWattsPerMile: computeBestWattsPerMile(snapshots)
        default: .noData
        }
    }

    private func computeGeoStat(
        _ stat: BragSheetStatType,
        _ snapshots: [BragSheetQSOSnapshot],
        allSnapshots: [BragSheetQSOSnapshot]?
    ) -> BragSheetStatValue {
        switch stat {
        case .dxccEntities: computeDXCCEntities(snapshots)
        case .newDXCCEntities: computeNewDXCC(snapshots, allSnapshots: allSnapshots)
        case .statesAndProvinces: computeStatesProvinces(snapshots)
        case .gridSquares: computeGridSquares(snapshots)
        case .continents: computeContinents(snapshots)
        case .mostContinentsInADay: computeMostContinentsDay(snapshots)
        case .workedAllStatesProgress: computeWASProgress(snapshots)
        default: .noData
        }
    }

    private func computeVolumeStat(
        _ stat: BragSheetStatType,
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        switch stat {
        case .mostQSOsInADay: computeMostQSOsDay(snapshots)
        case .mostQSOsInASession: computeMostQSOsSession(snapshots)
        case .mostCountriesInADay: computeMostCountriesDay(snapshots)
        case .mostBandsInADay: computeMostBandsDay(snapshots)
        default: .noData
        }
    }

    private func computeStreakStat(
        _ stat: BragSheetStatType,
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        switch stat {
        case .currentOnAirStreak: computeCurrentStreak(snapshots)
        case .bestOnAirStreak: computeBestStreak(snapshots)
        case .currentActivationStreak: computeActivationStreak(snapshots)
        case .modeStreaks: computeModeStreaks(snapshots)
        default: .noData
        }
    }

    private func computePOTAStat(
        _ stat: BragSheetStatType,
        _ snapshots: [BragSheetQSOSnapshot],
        allSnapshots: [BragSheetQSOSnapshot]?
    ) -> BragSheetStatValue {
        switch stat {
        case .parksActivated: computeParksActivated(snapshots)
        case .parksHunted: computeParksHunted(snapshots)
        case .parkToParkContacts: computeP2P(snapshots)
        case .largestNfer: computeLargestNfer(snapshots)
        case .bestActivation: computeBestActivation(snapshots)
        case .newParks: computeNewParks(snapshots, allSnapshots: allSnapshots)
        default: .noData
        }
    }

    private func computeCWStat(
        _ stat: BragSheetStatType,
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        switch stat {
        case .fastestCWSpeed: .noData
        case .cwDistanceRecord: computeCWDistanceRecord(snapshots)
        case .cwQRPRecord: computeCWQRPRecord(snapshots)
        default: .noData
        }
    }

    private func computeSignalStat(
        _ stat: BragSheetStatType,
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        switch stat {
        case .perfectReports: computePerfectReports(snapshots)
        case .averageRSTReceived: computeAverageRST(snapshots)
        case .bestRSTAtDistance: computeBestRSTAtDistance(snapshots)
        default: .noData
        }
    }

    private func computeFunStat(
        _ stat: BragSheetStatType,
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        switch stat {
        case .earliestQSOOfTheDay: computeEarliestQSO(snapshots)
        case .latestQSOOfTheDay: computeLatestQSO(snapshots)
        case .longestSession: computeLongestSession(snapshots)
        case .mostActiveDayOfWeek: computeMostActiveDay(snapshots)
        case .busiestBand: computeBusiestBand(snapshots)
        case .busiestMode: computeBusiestMode(snapshots)
        case .repeatCustomers: computeRepeatCustomers(snapshots)
        default: .noData
        }
    }

    // MARK: - Fetching

    private func fetchSnapshots(
        container: ModelContainer,
        dateRange: (start: Date, end: Date)
    ) async throws -> [BragSheetQSOSnapshot] {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let start = dateRange.start
        let end = dateRange.end

        var descriptor = FetchDescriptor<QSO>(predicate: #Predicate {
            !$0.isHidden && $0.timestamp >= start && $0.timestamp <= end
        })
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]

        guard let qsos = try? context.fetch(descriptor) else {
            return []
        }

        // Convert to snapshots, filter metadata, deduplicate
        var seenIds = Set<UUID>()
        seenIds.reserveCapacity(qsos.count)
        var snapshots: [BragSheetQSOSnapshot] = []
        snapshots.reserveCapacity(qsos.count)

        for qso in qsos {
            guard seenIds.insert(qso.id).inserted else {
                continue
            }
            guard !Self.metadataModes.contains(qso.mode.uppercased()) else {
                continue
            }
            snapshots.append(BragSheetQSOSnapshot(from: qso))
        }

        return snapshots
    }
}
