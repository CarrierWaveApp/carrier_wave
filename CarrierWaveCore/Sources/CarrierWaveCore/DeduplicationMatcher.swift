//
//  DeduplicationMatcher.swift
//  CarrierWaveCore
//
//  Pure logic for QSO deduplication matching.
//

import Foundation

// MARK: - DuplicateGroup

/// Result of finding duplicate groups
public struct DuplicateGroup: Sendable, Equatable {
    // MARK: Lifecycle

    public init(winnerId: UUID, loserIds: [UUID]) {
        self.winnerId = winnerId
        self.loserIds = loserIds
    }

    // MARK: Public

    /// The QSO that should be kept (most complete/synced)
    public let winnerId: UUID
    /// QSOs that should be merged into the winner and deleted
    public let loserIds: [UUID]
}

// MARK: - DeduplicationConfig

/// Configuration for deduplication matching
public struct DeduplicationConfig: Sendable {
    // MARK: Lifecycle

    public init(
        timeWindowSeconds: TimeInterval = 300, // 5 minutes default
        requireBandMatch: Bool = true,
        requireParkMatch: Bool = true
    ) {
        self.timeWindowSeconds = timeWindowSeconds
        self.requireBandMatch = requireBandMatch
        self.requireParkMatch = requireParkMatch
    }

    // MARK: Public

    /// Default config for standard deduplication (5 minute window)
    public static let standard = DeduplicationConfig()

    /// Config for two-fer repair (60 second window, looser park matching)
    public static let twoferRepair = DeduplicationConfig(
        timeWindowSeconds: 60,
        requireBandMatch: true,
        requireParkMatch: false // We handle park matching specially for two-fers
    )

    /// Time window in seconds for considering QSOs as potential duplicates
    public let timeWindowSeconds: TimeInterval

    /// Whether to require band match (if false, empty band matches anything)
    public let requireBandMatch: Bool

    /// Whether to require park reference match
    public let requireParkMatch: Bool
}

// MARK: - DeduplicationMatcher

/// Pure logic for QSO deduplication matching
public enum DeduplicationMatcher: Sendable {
    /// Check if two QSO snapshots are duplicates based on the given config
    public static func isDuplicate(
        _ qso1: QSOSnapshot,
        _ qso2: QSOSnapshot,
        config: DeduplicationConfig = .standard
    ) -> Bool {
        // Callsign must match
        guard qso1.normalizedCallsign == qso2.normalizedCallsign else {
            return false
        }

        // Mode must be equivalent
        guard ModeEquivalence.areEquivalent(qso1.mode, qso2.mode) else {
            return false
        }

        // Timestamp must be within window
        let timeDelta = abs(qso1.timestamp.timeIntervalSince(qso2.timestamp))
        guard timeDelta <= config.timeWindowSeconds else {
            return false
        }

        // Park reference check (if required)
        if config.requireParkMatch {
            let park1 = qso1.normalizedParkReference
            let park2 = qso2.normalizedParkReference

            // Both nil = match, both have value = must match, one nil one value = no match
            if park1 != park2 {
                return false
            }
        }

        // Band check
        let band1 = qso1.normalizedBand
        let band2 = qso2.normalizedBand

        if config.requireBandMatch {
            // If either band is empty, consider it a match (band-agnostic)
            if band1.isEmpty || band2.isEmpty {
                return true
            }
            // Both have bands - require match
            return band1 == band2
        }

        return true
    }

    /// Find duplicate groups in a list of QSO snapshots
    /// Returns groups where each group has a winner and losers to merge
    public static func findDuplicateGroups(
        _ snapshots: [QSOSnapshot],
        config: DeduplicationConfig = .standard
    ) -> [DuplicateGroup] {
        guard snapshots.count > 1 else {
            return []
        }

        // Sort by timestamp for efficient windowed comparison
        let sorted = snapshots.sorted { $0.timestamp < $1.timestamp }

        var groups: [DuplicateGroup] = []
        var processed = Set<UUID>()

        for i in 0 ..< sorted.count {
            let qso = sorted[i]
            if processed.contains(qso.id) {
                continue
            }

            var group = [qso]
            processed.insert(qso.id)

            // Check subsequent QSOs within time window
            for j in (i + 1) ..< sorted.count {
                let candidate = sorted[j]
                if processed.contains(candidate.id) {
                    continue
                }

                // Stop if beyond time window
                let timeDelta = candidate.timestamp.timeIntervalSince(qso.timestamp)
                if timeDelta > config.timeWindowSeconds {
                    break
                }

                // Check if duplicate
                if isDuplicate(qso, candidate, config: config) {
                    group.append(candidate)
                    processed.insert(candidate.id)
                }
            }

            if group.count > 1 {
                // Select winner based on sync count and field richness
                let winner = selectWinner(from: group)
                let loserIds = group.filter { $0.id != winner.id }.map(\.id)
                groups.append(DuplicateGroup(winnerId: winner.id, loserIds: loserIds))
            }
        }

        return groups
    }

    /// Select the winner from a group of duplicate QSOs
    /// Priority: 1) Most synced services, 2) Highest field richness
    public static func selectWinner(from group: [QSOSnapshot]) -> QSOSnapshot {
        group.max { first, second in
            if first.syncedServicesCount != second.syncedServicesCount {
                return first.syncedServicesCount < second.syncedServicesCount
            }
            return first.fieldRichnessScore < second.fieldRichnessScore
        }!
    }

    /// Merge field values, preferring non-nil values from the richer source
    /// Returns a new snapshot with merged fields
    public static func mergeFields(winner: QSOSnapshot, loser: QSOSnapshot) -> QSOSnapshot {
        QSOSnapshot(
            id: winner.id,
            callsign: winner.callsign,
            timestamp: winner.timestamp,
            band: winner.normalizedBand.isEmpty ? loser.band : winner.band,
            mode: ModeEquivalence.moreSpecific(winner.mode, loser.mode),
            parkReference: winner.parkReference ?? loser.parkReference,
            frequency: winner.frequency ?? loser.frequency,
            rstSent: winner.rstSent ?? loser.rstSent,
            rstReceived: winner.rstReceived ?? loser.rstReceived,
            myGrid: winner.myGrid ?? loser.myGrid,
            theirGrid: winner.theirGrid ?? loser.theirGrid,
            notes: winner.notes ?? loser.notes,
            rawADIF: winner.rawADIF ?? loser.rawADIF,
            name: winner.name ?? loser.name,
            qth: winner.qth ?? loser.qth,
            state: winner.state ?? loser.state,
            country: winner.country ?? loser.country,
            power: winner.power ?? loser.power,
            theirLicenseClass: winner.theirLicenseClass ?? loser.theirLicenseClass,
            syncedServicesCount: max(winner.syncedServicesCount, loser.syncedServicesCount)
        )
    }
}
