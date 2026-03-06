import CarrierWaveData
import Foundation

/// Pure-logic scoring and dupe-checking engine for contests.
/// No SwiftUI or SwiftData dependency — operates on Sendable value types.
actor ContestEngine {
    // MARK: Lifecycle

    init(definition: ContestDefinition, startingSerial: Int = 0) {
        self.definition = definition
        serialCounter = startingSerial
    }

    // MARK: Internal

    let definition: ContestDefinition
    private(set) var serialCounter: Int = 0

    // MARK: - Public API

    /// Check if a callsign on a band is a dupe — O(1)
    func dupeStatus(callsign: String, band: String) -> DupeStatus {
        let key = dupeKey(callsign: callsign, band: band)
        let bandKey = definition.dupeRules.perBand ? band : "ALL"

        if dupeTable[bandKey]?.contains(key) == true {
            return .dupe
        }
        return .newStation
    }

    /// Get next auto-increment serial number
    func nextSerial() -> Int {
        serialCounter += 1
        return serialCounter
    }

    /// Peek at current serial without incrementing
    func currentSerial() -> Int {
        serialCounter + 1
    }

    /// Suggest exchange from a previous QSO with this callsign on another band
    func suggestedExchange(for callsign: String) -> String? {
        knownExchanges[callsign.uppercased()]
    }

    /// Register a completed QSO — updates dupe table, multipliers, score
    func registerQSO(_ snapshot: QSOContestSnapshot) -> DupeStatus {
        let callUpper = snapshot.callsign.uppercased()
        let bandKey = definition.dupeRules.perBand ? snapshot.band : "ALL"
        let key = dupeKey(callsign: callUpper, band: snapshot.band)

        // Check dupe
        if dupeTable[bandKey]?.contains(key) == true {
            dupeCount += 1
            return .dupe
        }

        // Record in dupe table
        dupeTable[bandKey, default: []].insert(key)

        // Record exchange for future suggestions
        if !snapshot.exchangeReceived.isEmpty {
            knownExchanges[callUpper] = snapshot.exchangeReceived
        }

        // Calculate points
        let points = calculatePoints(for: snapshot)
        totalPoints += points
        pointsByBand[snapshot.band, default: 0] += points
        qsosByBand[snapshot.band, default: 0] += 1
        qsoLog.append((timestamp: snapshot.timestamp, points: points))

        // Check for new multipliers
        let newMult = checkMultipliers(snapshot: snapshot)
        return newMult ?? .newStation
    }

    /// Get current score snapshot
    func scoreSnapshot() -> ContestScoreSnapshot {
        let multCount = countTotalMultipliers()
        let total = totalQSOs()
        return ContestScoreSnapshot(
            totalQSOs: total,
            totalPoints: totalPoints,
            multiplierCount: multCount,
            finalScore: totalPoints * max(1, multCount),
            qsosByBand: qsosByBand,
            pointsByBand: pointsByBand,
            multsByBand: countMultipliersByBand(),
            dupeCount: dupeCount
        )
    }

    /// QSO rate over the last N minutes
    func rate(overMinutes minutes: Int = 60) -> Double {
        guard !qsoLog.isEmpty else {
            return 0
        }
        let cutoff = Date().addingTimeInterval(-Double(minutes) * 60)
        let recent = qsoLog.filter { $0.timestamp > cutoff }
        let fraction = Double(minutes) / 60.0
        return Double(recent.count) / fraction
    }

    /// Time series for rate graph (QSOs per bucket)
    func rateTimeSeries(bucketMinutes: Int = 60) -> [(date: Date, count: Int)] {
        guard let first = qsoLog.first?.timestamp else {
            return []
        }
        let bucketSeconds = Double(bucketMinutes * 60)
        var result: [(date: Date, count: Int)] = []
        var bucketStart = first
        let now = Date()

        while bucketStart < now {
            let bucketEnd = bucketStart.addingTimeInterval(bucketSeconds)
            let count = qsoLog.filter { $0.timestamp >= bucketStart && $0.timestamp < bucketEnd }.count
            result.append((date: bucketStart, count: count))
            bucketStart = bucketEnd
        }
        return result
    }

    /// Bulk-load existing QSOs at session start
    func loadExistingQSOs(_ qsos: [QSOContestSnapshot]) {
        for qso in qsos.sorted(by: { $0.timestamp < $1.timestamp }) {
            _ = registerQSO(qso)
        }
    }

    /// Get all multiplier values for a given type and band
    func multiplierValues(for type: MultiplierType, band: String?) -> Set<String> {
        let bandKey = definition.multipliers.perBand ? (band ?? "ALL") : "ALL"
        return multiplierTable[bandKey]?[type.rawValue] ?? []
    }

    // MARK: Private

    /// band → set of callsigns worked on that band
    private var dupeTable: [String: Set<String>] = [:]

    /// band → multiplierType → set of values
    private var multiplierTable: [String: [String: Set<String>]] = [:]

    /// Timestamps and points for rate calculation
    private var qsoLog: [(timestamp: Date, points: Int)] = []

    /// Callsign → exchange (for suggesting on other bands)
    private var knownExchanges: [String: String] = [:]

    /// Running totals
    private var totalPoints: Int = 0
    private var dupeCount: Int = 0
    private var qsosByBand: [String: Int] = [:]
    private var pointsByBand: [String: Int] = [:]

    private func dupeKey(callsign: String, band: String) -> String {
        if definition.dupeRules.perMode {
            return callsign.uppercased()
        }
        return callsign.uppercased()
    }

    private func totalQSOs() -> Int {
        qsosByBand.values.reduce(0, +)
    }

    private func calculatePoints(for snapshot: QSOContestSnapshot) -> Int {
        for rule in definition.scoring.rules {
            switch rule.condition {
            case .any:
                return rule.points
            case .sameCountry:
                if snapshot.dxcc != nil {
                    // Assume same country = US for now (simplified)
                    // Full implementation would compare with operator's DXCC
                    continue
                }
            case .sameContinent:
                continue
            case .differentContinent:
                continue
            case .sameDXCC:
                continue
            }
        }
        // If no specific rule matched, use the last rule or default to 1
        return definition.scoring.rules.last?.points ?? 1
    }

    private func checkMultipliers(snapshot: QSOContestSnapshot) -> DupeStatus? {
        let bandKey = definition.multipliers.perBand ? snapshot.band : "ALL"
        var firstNewMult: DupeStatus?

        for multType in definition.multipliers.types {
            guard let value = multiplierValue(for: multType, from: snapshot) else {
                continue
            }
            let existing = multiplierTable[bandKey]?[multType.rawValue] ?? []
            if !existing.contains(value) {
                multiplierTable[bandKey, default: [:]][multType.rawValue, default: []].insert(value)
                if firstNewMult == nil {
                    firstNewMult = .newMultiplier(value: value, multType)
                }
            }
        }

        return firstNewMult
    }

    private func multiplierValue(for type: MultiplierType, from snapshot: QSOContestSnapshot) -> String? {
        switch type {
        case .dxcc:
            if let dxcc = snapshot.dxcc {
                return String(dxcc)
            }
            // Fall back to country name
            return snapshot.country
        case .cqZone:
            if let zone = snapshot.cqZone {
                return String(zone)
            }
            return nil
        case .ituZone:
            if let zone = snapshot.ituZone {
                return String(zone)
            }
            return nil
        case .state:
            return snapshot.state?.uppercased()
        case .arrlSection:
            return snapshot.arrlSection?.uppercased()
        case .county:
            return snapshot.county?.uppercased()
        case .wpxPrefix:
            return snapshot.wpxPrefix?.uppercased()
        }
    }

    private func countTotalMultipliers() -> Int {
        var total = 0
        for (_, typeDict) in multiplierTable {
            for (_, values) in typeDict {
                total += values.count
            }
        }
        return total
    }

    private func countMultipliersByBand() -> [String: Int] {
        var result: [String: Int] = [:]
        for (band, typeDict) in multiplierTable {
            var count = 0
            for (_, values) in typeDict {
                count += values.count
            }
            result[band] = count
        }
        return result
    }
}
