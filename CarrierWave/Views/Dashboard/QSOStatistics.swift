import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - QSOStatistics

/// Statistics computed from QSO data with internal caching for performance.
/// Uses a class to enable lazy cached properties that are computed once on first access.
final class QSOStatistics {
    // MARK: Lifecycle

    init(qsos: [QSO]) {
        self.qsos = qsos
    }

    // MARK: Internal

    let qsos: [QSO]

    // Streak cache storage (set by extension)
    var cachedDailyStreak: StreakInfo?
    var cachedPotaActivationStreak: StreakInfo?
    var cachedModeStreaks: [StreakInfo]?
    var cachedBandStreaks: [StreakInfo]?

    var totalQSOs: Int {
        realQSOs.count
    }

    var uniqueEntities: Int {
        if let cached = _uniqueEntities {
            return cached
        }
        let result = Set(realQSOs.compactMap { $0.dxccEntity?.number }).count
        _uniqueEntities = result
        return result
    }

    var uniqueGrids: Int {
        if let cached = _uniqueGrids {
            return cached
        }
        let result = Set(realQSOs.compactMap(\.theirGrid).filter { !$0.isEmpty }).count
        _uniqueGrids = result
        return result
    }

    var uniqueBands: Int {
        if let cached = _uniqueBands {
            return cached
        }
        let result = Set(realQSOs.map { $0.band.lowercased() }).count
        _uniqueBands = result
        return result
    }

    var confirmedQSLs: Int {
        if let cached = _confirmedQSLs {
            return cached
        }
        // Count QSOs confirmed by either LoTW OR QRZ
        let result = realQSOs.filter { $0.lotwConfirmed || $0.qrzConfirmed }.count
        _confirmedQSLs = result
        return result
    }

    var uniqueParks: Int {
        if let cached = _uniqueParks {
            return cached
        }
        let result = Set(realQSOs.compactMap(\.parkReference).filter { !$0.isEmpty }).count
        _uniqueParks = result
        return result
    }

    /// Activations with 10+ QSOs (valid POTA activations)
    /// Each activation is a unique park+UTC date combination
    var successfulActivations: Int {
        activationGroups.values.filter { $0.count >= 10 }.count
    }

    /// Activations with <10 QSOs (activation attempts)
    /// Each activation is a unique park+UTC date combination
    var attemptedActivations: Int {
        activationGroups.values.filter { $0.count < 10 }.count
    }

    var activityByDate: [Date: Int] {
        if let cached = _activityByDate {
            return cached
        }
        var activity: [Date: Int] = [:]
        for qso in realQSOs {
            let date = qso.dateOnly
            activity[date, default: 0] += 1
        }
        _activityByDate = activity
        return activity
    }

    // MARK: - Internal Accessors for Extensions

    /// Internal accessor for cached realQSOs (for use by extensions)
    var cachedRealQSOs: [QSO] {
        realQSOs
    }

    /// Internal accessor for cached activation groups (for use by extensions)
    var cachedActivationGroups: [String: [QSO]] {
        activationGroups
    }

    // MARK: - Category Items

    func items(for category: StatCategoryType) -> [StatCategoryItem] {
        // Check cache first
        if let cached = _categoryItemsCache[category] {
            return cached
        }

        let result: [StatCategoryItem] =
            switch category {
            case .qsls:
                groupedByQSL()
            case .entities:
                groupedByEntity()
            case .grids:
                groupedByGrid()
            case .bands:
                groupedByBand()
            case .parks:
                groupedByPark()
            case .frequencies:
                groupedByFrequency()
            case .bestFriends:
                groupedByPartner()
            case .bestHunters:
                groupedByHunter()
            }

        _categoryItemsCache[category] = result
        return result
    }

    /// Top frequencies used, grouped to nearest 100kHz
    func topFrequencies(limit: Int = 5) -> [StatCategoryItem] {
        Array(items(for: .frequencies).sorted { $0.count > $1.count }.prefix(limit))
    }

    /// Top QSO partners (most frequent callsigns contacted)
    func topFriends(limit: Int = 5) -> [StatCategoryItem] {
        Array(items(for: .bestFriends).sorted { $0.count > $1.count }.prefix(limit))
    }

    /// Top hunters (most frequent callers during POTA activations)
    func topHunters(limit: Int = 5) -> [StatCategoryItem] {
        Array(items(for: .bestHunters).sorted { $0.count > $1.count }.prefix(limit))
    }

    // MARK: Private

    /// Modes that represent activation metadata, not actual QSOs (from Ham2K PoLo)
    /// These should never be counted as QSOs for any statistics
    private static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

    /// Static DateFormatter for park grouping (avoid creating on each call)
    private static let parkDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    // Cached computed values
    private var _realQSOs: [QSO]?
    private var _activationGroups: [String: [QSO]]?
    private var _activityByDate: [Date: Int]?
    private var _uniqueEntities: Int?
    private var _uniqueGrids: Int?
    private var _uniqueBands: Int?
    private var _confirmedQSLs: Int?
    private var _uniqueParks: Int?
    private var _categoryItemsCache: [StatCategoryType: [StatCategoryItem]] = [:]

    /// QSOs filtered to exclude metadata modes - use this for all stat calculations
    /// Cached after first computation
    private var realQSOs: [QSO] {
        if let cached = _realQSOs {
            return cached
        }
        let result = qsos.filter { !Self.metadataModes.contains($0.mode.uppercased()) }
        _realQSOs = result
        return result
    }

    /// Cached activation grouping (park + UTC date combinations)
    /// Used by both successfulActivations and attemptedActivations
    private var activationGroups: [String: [QSO]] {
        if let cached = _activationGroups {
            return cached
        }
        // Filter to QSOs with park references (realQSOs already excludes metadata)
        let parksOnly = realQSOs.filter {
            $0.parkReference != nil && !$0.parkReference!.isEmpty
        }
        // Group by park + UTC date (each UTC day at a park is a separate activation)
        let result = Dictionary(grouping: parksOnly) { qso in
            "\(qso.parkReference!)|\(qso.utcDateOnly.timeIntervalSince1970)"
        }
        _activationGroups = result
        return result
    }

    private func groupedByEntity() -> [StatCategoryItem] {
        // Group by DXCC entity number (realQSOs excludes metadata)
        let withEntity = realQSOs.filter { $0.dxccEntity != nil }
        let grouped = Dictionary(grouping: withEntity) { $0.dxccEntity!.number }
        return grouped.map { entityNumber, qsos in
            let entity = qsos.first?.dxccEntity
            return StatCategoryItem(
                identifier: entity?.name ?? "Unknown",
                description: "DXCC #\(entityNumber)",
                qsos: qsos
            )
        }
    }

    private func groupedByGrid() -> [StatCategoryItem] {
        let gridsOnly = realQSOs.filter { $0.theirGrid != nil && !$0.theirGrid!.isEmpty }
        let grouped = Dictionary(grouping: gridsOnly) { $0.theirGrid! }
        return grouped.map { grid, qsos in
            StatCategoryItem(
                identifier: grid,
                description: DescriptionLookup.gridDescription(for: grid),
                qsos: qsos
            )
        }
    }

    private func groupedByBand() -> [StatCategoryItem] {
        let grouped = Dictionary(grouping: realQSOs) { $0.band.lowercased() }
        return grouped.map { band, qsos in
            StatCategoryItem(
                identifier: band,
                description: DescriptionLookup.bandDescription(for: band),
                qsos: qsos
            )
        }
    }

    private func groupedByQSL() -> [StatCategoryItem] {
        // Include QSOs confirmed by either LoTW OR QRZ
        let confirmed = realQSOs.filter { $0.lotwConfirmed || $0.qrzConfirmed }
        // Group by DXCC entity for confirmed QSLs
        let withEntity = confirmed.filter { $0.dxccEntity != nil }
        let grouped = Dictionary(grouping: withEntity) { $0.dxccEntity!.number }
        return grouped.map { entityNumber, qsos in
            let entity = qsos.first?.dxccEntity
            return StatCategoryItem(
                identifier: entity?.name ?? "Unknown",
                description: "DXCC #\(entityNumber) - \(qsos.count) confirmed",
                qsos: qsos
            )
        }
    }

    private func groupedByPark() -> [StatCategoryItem] {
        // Reuse cached activation groups
        activationGroups.map { _, qsos in
            let park = qsos.first?.parkReference ?? "Unknown"
            let date = qsos.first?.utcDateOnly ?? Date()
            let status = qsos.count >= 10 ? "Valid" : "\(qsos.count)/10 QSOs"
            return StatCategoryItem(
                identifier: "\(park) - \(Self.parkDateFormatter.string(from: date))",
                description: status,
                qsos: qsos,
                date: date,
                parkReference: park
            )
        }
    }

    /// Group QSOs by frequency rounded to nearest 100Hz
    private func groupedByFrequency() -> [StatCategoryItem] {
        // Filter to QSOs with frequency data
        let withFrequency = realQSOs.filter { $0.frequency != nil && $0.frequency! > 0 }
        // Group by frequency rounded to nearest 100Hz (0.0001 MHz)
        let grouped = Dictionary(grouping: withFrequency) { qso in
            let freqMHz = qso.frequency! // Already in MHz
            return (freqMHz * 10_000).rounded() / 10_000 // Round to 0.0001 MHz = 100 Hz
        }
        return grouped.map { freqMHz, qsos in
            // Only show 100Hz digit if non-zero (e.g., 14.060 vs 14.0625)
            let has100Hz = (freqMHz * 10_000).truncatingRemainder(dividingBy: 10) != 0
            let freqString = String(format: has100Hz ? "%.4f MHz" : "%.3f MHz", freqMHz)
            let band = qsos.first?.band ?? "Unknown"
            return StatCategoryItem(
                identifier: freqString,
                description: band,
                qsos: qsos
            )
        }
    }

    /// Group QSOs by callsign (contact partner)
    private func groupedByPartner() -> [StatCategoryItem] {
        let grouped = Dictionary(grouping: realQSOs) { $0.callsign.uppercased() }
        return grouped.map { callsign, qsos in
            let entity = qsos.first?.dxccEntity?.name
            let description = entity ?? ""
            return StatCategoryItem(
                identifier: callsign,
                description: description,
                qsos: qsos
            )
        }
    }

    /// Group QSOs by callsign where I was activating (had a park reference)
    /// These are "hunters" who contacted me during POTA activations
    private func groupedByHunter() -> [StatCategoryItem] {
        // Filter to QSOs where I was activating (I have a park reference)
        let activationQSOs = realQSOs.filter {
            $0.parkReference != nil && !$0.parkReference!.isEmpty
        }
        let grouped = Dictionary(grouping: activationQSOs) { $0.callsign.uppercased() }
        return grouped.map { callsign, qsos in
            let entity = qsos.first?.dxccEntity?.name
            let description = entity ?? ""
            return StatCategoryItem(
                identifier: callsign,
                description: description,
                qsos: qsos
            )
        }
    }
}
