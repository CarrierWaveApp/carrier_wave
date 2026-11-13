import CarrierWaveData
import Foundation

// MARK: - SinglePassAccumulator

/// Collects basic counts, favorites, and WAS data in a single pass over all snapshots.
/// Replaces ~12 separate filter/map/count iterations with one loop.
nonisolated struct SinglePassAccumulator {
    // MARK: Internal

    /// Process one snapshot, accumulating all relevant stats.
    mutating func process(_ qso: StatsQSOSnapshot) {
        accumulateServiceCounts(qso)

        guard !QSOMode.isMetadata(qso.mode) else {
            metadataCount += 1
            return
        }
        totalReal += 1
        accumulateBasicCounts(qso)
        accumulateFavorites(qso)
        accumulateWAS(qso)
    }

    /// Finalize accumulated data into a ComputedStats struct.
    func finalize() -> ComputedStats {
        var stats = ComputedStats()

        stats.totalQSOs = totalReal
        stats.uniqueBands = bands.count
        stats.uniqueGrids = grids.count
        stats.uniqueEntities = entities.count
        stats.confirmedQSLs = confirmedCount
        stats.uniqueMyCallsigns = myCallsigns
        stats.qrzConfirmedCount = qrzCount
        stats.lotwConfirmedCount = lotwCount
        stats.icloudImportedCount = icloudCount
        stats.metadataExcludedCount = metadataCount

        // Intermediate counts for filter pipeline explanations
        stats.qsosWithDXCC = withDXCCCount
        stats.qsosWithGrid = withGridCount
        stats.qsosWithFrequency = withFrequencyCount
        stats.qsosWithParkRef = withParkRefCount
        stats.uniqueCallsignCount = uniqueCallsigns.count
        stats.uniqueHunterCallsignCount = uniqueHunterCallsigns.count
        stats.uniqueFrequencyGroupCount = uniqueFrequencyKeys.count

        applyFavorites(to: &stats)
        applyWAS(to: &stats)

        return stats
    }

    // MARK: Private

    /// US state abbreviations for WAS filtering
    private static let usStates: Set<String> = [
        "AK", "AL", "AR", "AZ", "CA", "CO", "CT", "DE", "FL", "GA",
        "HI", "IA", "ID", "IL", "IN", "KS", "KY", "LA", "MA", "MD",
        "ME", "MI", "MN", "MO", "MS", "MT", "NC", "ND", "NE", "NH",
        "NJ", "NM", "NV", "NY", "OH", "OK", "OR", "PA", "RI", "SC",
        "SD", "TN", "TX", "UT", "VA", "VT", "WA", "WI", "WV", "WY",
    ]

    // Basic counts
    private var metadataCount = 0
    private var bands: Set<String> = []
    private var grids: Set<String> = []
    private var entities: Set<Int> = []
    private var confirmedCount = 0
    private var totalReal = 0
    private var myCallsigns: Set<String> = []

    // Service counts
    private var qrzCount = 0
    private var lotwCount = 0
    private var icloudCount = 0

    // Intermediate counts for filter pipeline explanations
    private var withDXCCCount = 0
    private var withGridCount = 0
    private var withFrequencyCount = 0
    private var withParkRefCount = 0
    private var uniqueCallsigns: Set<String> = []
    private var uniqueHunterCallsigns: Set<String> = []
    private var uniqueFrequencyKeys: Set<Int> = []

    // Favorites — kHz as Int key avoids Double hashing overhead
    private var frequencyCounts: [Int: Int] = [:]
    private var friendCounts: [String: Int] = [:]
    private var hunterCounts: [String: Int] = [:]

    // WAS accumulators
    private var wasAllData = WASStateData()
    private var wasAllModeMap: [String: WASStateData] = [:]
    private var wasQTHData = WASStateData()
    private var wasQTHModeMap: [String: WASStateData] = [:]
    private var modesWithStates: Set<String> = []

    // MARK: - Accumulation Helpers

    private mutating func accumulateServiceCounts(_ qso: StatsQSOSnapshot) {
        if qso.qrzConfirmed {
            qrzCount += 1
        }
        if qso.lotwConfirmed {
            lotwCount += 1
        }
        if qso.importSource == .icloud {
            icloudCount += 1
        }
        let base = StatsComputationActor.extractBaseCallsign(
            qso.myCallsign.uppercased()
        )
        if !base.isEmpty {
            myCallsigns.insert(base)
        }
    }

    private mutating func accumulateBasicCounts(_ qso: StatsQSOSnapshot) {
        bands.insert(qso.band.lowercased())
        if let grid = qso.theirGrid, !grid.isEmpty {
            grids.insert(grid)
            withGridCount += 1
        }
        if let dxcc = qso.dxcc {
            entities.insert(dxcc)
            withDXCCCount += 1
        }
        if qso.lotwConfirmed || qso.qrzConfirmed {
            confirmedCount += 1
        }
        if let park = qso.parkReference, !park.isEmpty {
            withParkRefCount += 1
        }
    }

    private mutating func accumulateFavorites(_ qso: StatsQSOSnapshot) {
        if let freqMHz = qso.frequency, freqMHz > 0 {
            let kHz = Int((freqMHz * 1_000).rounded())
            frequencyCounts[kHz, default: 0] += 1
            withFrequencyCount += 1
            uniqueFrequencyKeys.insert(kHz)
        }
        let call = qso.callsign.uppercased()
        guard !call.isEmpty else {
            return
        }
        friendCounts[call, default: 0] += 1
        uniqueCallsigns.insert(call)
        if let park = qso.parkReference, !park.isEmpty {
            hunterCounts[call, default: 0] += 1
            uniqueHunterCallsigns.insert(call)
        }
    }

    private mutating func accumulateWAS(_ qso: StatsQSOSnapshot) {
        guard let raw = qso.state, !raw.isEmpty else {
            return
        }
        let state = USStates.normalizeAbbreviation(raw)
        guard Self.usStates.contains(state) else {
            return
        }
        let call = qso.callsign.uppercased()
        let mode = qso.mode.uppercased()

        wasAllData.stateCounts[state, default: 0] += 1
        wasAllData.stateCallsigns[state, default: []].append(call)
        wasAllModeMap[mode, default: WASStateData()]
            .stateCounts[state, default: 0] += 1
        wasAllModeMap[mode, default: WASStateData()]
            .stateCallsigns[state, default: []].append(call)
        modesWithStates.insert(mode)

        let isQTH = qso.parkReference == nil || qso.parkReference!.isEmpty
        guard isQTH else {
            return
        }
        wasQTHData.stateCounts[state, default: 0] += 1
        wasQTHData.stateCallsigns[state, default: []].append(call)
        wasQTHModeMap[mode, default: WASStateData()]
            .stateCounts[state, default: 0] += 1
        wasQTHModeMap[mode, default: WASStateData()]
            .stateCallsigns[state, default: []].append(call)
    }

    // MARK: - Finalization Helpers

    private func applyFavorites(to stats: inout ComputedStats) {
        if let (kHz, count) = frequencyCounts.max(by: { $0.value < $1.value }) {
            stats.topFrequency = String(format: "%.3f", Double(kHz) / 1_000)
            stats.topFrequencyCount = count
        }
        if let (call, count) = friendCounts.max(by: { $0.value < $1.value }) {
            stats.topFriend = call
            stats.topFriendCount = count
        }
        if let (call, count) = hunterCounts.max(by: { $0.value < $1.value }) {
            stats.topHunter = call
            stats.topHunterCount = count
        }
    }

    private func applyWAS(to stats: inout ComputedStats) {
        var wasData: [WASFilterKey: WASStateData] = [:]
        wasData[WASFilterKey(source: .all, mode: nil)] = wasAllData
        for (mode, modeData) in wasAllModeMap {
            wasData[WASFilterKey(source: .all, mode: mode)] = modeData
        }
        wasData[WASFilterKey(source: .qthOnly, mode: nil)] = wasQTHData
        for (mode, modeData) in wasQTHModeMap {
            wasData[WASFilterKey(source: .qthOnly, mode: mode)] = modeData
        }
        stats.wasData = wasData
        stats.wasAvailableModes = modesWithStates.sorted()
    }
}
