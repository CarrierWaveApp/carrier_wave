//
//  TwoferMatcher.swift
//  CarrierWaveCore
//
//  Logic for detecting and matching two-fer duplicate QSOs.
//
//  When QSOs are imported from multiple sources (e.g., PoLo with full ref "US-1044, US-3791"
//  and POTA.app with single ref "US-1044"), duplicates can be created because the park
//  references don't match exactly. This module provides matching logic for these cases.
//

import Foundation

// MARK: - TwoferMatchConfig

/// Configuration for two-fer duplicate detection
public struct TwoferMatchConfig: Sendable {
    // MARK: Lifecycle

    public init(timeWindowSeconds: TimeInterval = 60) {
        self.timeWindowSeconds = timeWindowSeconds
    }

    // MARK: Public

    public static let standard = TwoferMatchConfig()

    /// Time window in seconds for considering QSOs as potential duplicates
    /// POTA timestamps are often rounded to the minute, so 60 seconds is typical
    public let timeWindowSeconds: TimeInterval
}

// MARK: - TwoferMatcher

/// Pure logic for two-fer duplicate detection and matching
public enum TwoferMatcher: Sendable {
    /// Find QSO snapshots that are duplicates of a multi-park QSO
    /// Returns IDs of QSOs that should be merged into the multi-park version
    public static func findDuplicatesFor(
        multiParkSnapshot: QSOSnapshot,
        in allSnapshots: [QSOSnapshot],
        config: TwoferMatchConfig = .standard
    ) -> [UUID] {
        guard let multiParkRef = multiParkSnapshot.normalizedParkReference,
              ParkReference.isMultiPark(multiParkRef)
        else {
            return []
        }

        let multiParks = ParkReference.split(multiParkRef)

        return allSnapshots.compactMap { candidate -> UUID? in
            // Not the same QSO
            guard candidate.id != multiParkSnapshot.id else {
                return nil
            }

            // Must have a park reference
            guard let candidateParkRef = candidate.normalizedParkReference else {
                return nil
            }

            // Candidate should NOT be a multi-park (we want to merge singles into multi)
            // OR it should be a truncated version (fewer parks or shorter string)
            let candidateParks = ParkReference.split(candidateParkRef)
            guard
                candidateParks.count < multiParks.count
                || candidateParkRef.count < multiParkRef.count
            else {
                return nil
            }

            // Check if candidate's park(s) are a subset of multi-park's parks
            guard ParkReference.isSubset(candidateParkRef, of: multiParkRef) else {
                return nil
            }

            // Same callsign
            guard multiParkSnapshot.normalizedCallsign == candidate.normalizedCallsign else {
                return nil
            }

            // Timestamps within window
            let timeDiff = abs(multiParkSnapshot.timestamp.timeIntervalSince(candidate.timestamp))
            guard timeDiff <= config.timeWindowSeconds else {
                return nil
            }

            // Same band (or one is empty)
            let band1 = multiParkSnapshot.normalizedBand
            let band2 = candidate.normalizedBand
            if !band1.isEmpty, !band2.isEmpty, band1 != band2 {
                return nil
            }

            // Same mode family
            guard ModeEquivalence.areEquivalent(multiParkSnapshot.mode, candidate.mode) else {
                return nil
            }

            return candidate.id
        }
    }

    /// Find all two-fer duplicate groups in a list of QSO snapshots
    /// Returns groups where the winner is the multi-park version
    public static func findTwoferDuplicateGroups(
        _ snapshots: [QSOSnapshot],
        config: TwoferMatchConfig = .standard
    ) -> [DuplicateGroup] {
        // Find QSOs with multi-park references
        let multiParkSnapshots = snapshots.filter { snapshot in
            guard let parkRef = snapshot.normalizedParkReference else {
                return false
            }
            return ParkReference.isMultiPark(parkRef)
        }

        var groups: [DuplicateGroup] = []
        var processedIds = Set<UUID>()

        for multiParkSnapshot in multiParkSnapshots {
            if processedIds.contains(multiParkSnapshot.id) {
                continue
            }

            let duplicateIds = findDuplicatesFor(
                multiParkSnapshot: multiParkSnapshot,
                in: snapshots,
                config: config
            )

            if !duplicateIds.isEmpty {
                // Winner is the multi-park QSO (most complete)
                groups.append(
                    DuplicateGroup(
                        winnerId: multiParkSnapshot.id,
                        loserIds: duplicateIds
                    )
                )

                processedIds.insert(multiParkSnapshot.id)
                for id in duplicateIds {
                    processedIds.insert(id)
                }
            }
        }

        return groups
    }
}
