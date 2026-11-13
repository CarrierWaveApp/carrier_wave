// POTA Awards Background Actor
//
// Moves all QSO fetching and awards computation off the main thread.
// Fetches park QSOs from a background ModelContext, converts to lightweight
// snapshots, and computes all award metrics without blocking the UI.

import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData

// MARK: - POTAAwardsActor

actor POTAAwardsActor {
    // MARK: Internal

    struct Result {
        let progress: POTAAwardsProgress
        let was250Progress: WAS250Progress
    }

    static let validStates: Set<String> = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE",
        "FL", "GA", "HI", "ID", "IL", "IN", "IA", "KS",
        "KY", "LA", "ME", "MD", "MA", "MI", "MN", "MS",
        "MO", "MT", "NE", "NV", "NH", "NJ", "NM", "NY",
        "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
        "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV",
        "WI", "WY",
    ]

    func compute(container: ModelContainer) async throws -> Result {
        // In `.on`, serve both halves from cw-store (`pota_awards` + `was250`),
        // mirroring this actor's math. Falls back to the SwiftData scan below.
        if CwStoreQSOMode.current == .on,
           let store = try? await CwStoreProvider.shared.store()
        {
            return try await computeFromStore(store: store)
        }

        let snapshots = try fetchParkQSOSnapshots(container: container)
        let activations = groupActivations(snapshots)
        let progress = computeAwardsProgress(
            activations: activations, allSnapshots: snapshots
        )
        let was250 = try computeWAS250(container: container)
        return Result(progress: progress, was250Progress: was250)
    }

    // MARK: Private

    private struct QSOSnapshot {
        let callsign: String
        let timestamp: Date
        let band: String
        let mode: String
        let myCallsign: String
        let myGrid: String?
        let parkReference: String
        let theirParkReference: String?
        let dxcc: Int?
    }

    private struct ActivationGroup {
        let parkReference: String
        let utcDateString: String
        let qsos: [QSOSnapshot]

        var qsoCount: Int {
            qsos.count
        }

        /// Unique QSOs (deduplicated by callsign + band + mode + park)
        var uniqueQSOCount: Int {
            var seen = Set<String>()
            let park = parkReference.uppercased()
            for qso in qsos {
                let key = "\(qso.callsign.uppercased())|\(qso.band)|\(qso.mode)|\(park)"
                seen.insert(key)
            }
            return seen.count
        }
    }

    private static let batchSize = 500
    private static let nearKiloThreshold = 100

    private static func makeDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }

    /// `.on`-mode path: map cw-store's `pota_awards` / `was250` aggregates into the
    /// view models. Parity with the SwiftData path is gated by
    /// `AnalyticsPOTAAwardsParityTests`.
    private func computeFromStore(store: FieldStore) async throws -> Result {
        let rust = RustAnalyticsReadSource(store: store)
        let awards = try await rust.potaAwards(query: "")
        let was = try await rust.was250(query: "")
        let progress = POTAAwardsProgress(
            uniqueParksCount: awards.uniqueParksCount,
            dxEntitiesCount: awards.dxEntitiesCount,
            statesActivated: Set(awards.statesActivated),
            roverMaxParks: awards.roverMaxParks,
            repeatOffenderMaxCount: awards.repeatOffenderMaxCount,
            parkToParkCount: awards.parkToParkCount,
            kiloParks: awards.kiloParks,
            nearKiloParks: awards.nearKiloParks.map {
                NearKiloPark(reference: $0.reference, qsoCount: $0.qsoCount)
            },
            laPortaEarned: awards.laPortaEarned,
            laPortaQualifyingParks: awards.laPortaQualifyingParks,
            sixPackEarned: awards.sixPackEarned,
            bestSingleParkTotal: awards.bestSingleParkTotal,
            totalParkQSOs: awards.totalParkQSOs,
            metadataExcluded: awards.metadataExcluded,
            totalActivationGroups: awards.totalActivationGroups,
            validActivationGroups: awards.validActivationGroups
        )
        let was250 = WAS250Progress(
            statesWorked: Set(was.statesWorked),
            cwStates: Set(was.cwStates),
            phoneStates: Set(was.phoneStates),
            digitalStates: Set(was.digitalStates),
            totalQSOs2026: was.totalQSOs,
            metadataExcluded: was.metadataExcluded,
            withStateField: was.withStateField,
            withValidState: was.withValidState
        )
        return Result(progress: progress, was250Progress: was250)
    }
}

// MARK: - Fetching & Grouping

extension POTAAwardsActor {
    private func fetchParkQSOSnapshots(
        container: ModelContainer
    ) throws -> [QSOSnapshot] {
        var snapshots: [QSOSnapshot] = []
        var offset = 0

        while true {
            try Task.checkCancellation()

            let context = ModelContext(container)
            context.autosaveEnabled = false
            let descriptor = BoundedDescriptor<QSO>(
                predicate: #Predicate {
                    $0.parkReference != nil && !$0.isHidden
                },
                sortBy: [
                    SortDescriptor(\QSO.timestamp, order: .reverse),
                ],
                limit: Self.batchSize,
                offset: offset
            )

            guard let batch = try? context.boundedFetch(descriptor),
                  !batch.isEmpty
            else {
                break
            }

            for qso in batch {
                guard let parkRef = qso.parkReference,
                      !parkRef.isEmpty
                else {
                    continue
                }
                snapshots.append(QSOSnapshot(
                    callsign: qso.callsign,
                    timestamp: qso.timestamp,
                    band: qso.band,
                    mode: qso.mode,
                    myCallsign: qso.myCallsign,
                    myGrid: qso.myGrid,
                    parkReference: parkRef,
                    theirParkReference: qso.theirParkReference,
                    dxcc: qso.dxcc
                ))
            }

            offset += batch.count
            if batch.count < Self.batchSize {
                break
            }
        }

        return snapshots
    }

    private func groupActivations(
        _ snapshots: [QSOSnapshot]
    ) -> [ActivationGroup] {
        let dateFormatter = Self.makeDateFormatter()
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!

        let filtered = snapshots.filter {
            !QSOMode.isMetadata($0.mode)
        }

        var groups: [String: [QSOSnapshot]] = [:]
        for snap in filtered {
            let utcDate = utcCalendar.startOfDay(for: snap.timestamp)
            let dateStr = dateFormatter.string(from: utcDate)
            let key = "\(snap.parkReference.uppercased())|\(snap.myCallsign.uppercased())|\(dateStr)"
            groups[key, default: []].append(snap)
        }

        return groups.compactMap { key, qsos in
            let parts = key.split(
                separator: "|", omittingEmptySubsequences: false
            )
            guard parts.count >= 3 else {
                return nil
            }
            return ActivationGroup(
                parkReference: String(parts[0]),
                utcDateString: String(parts[2]),
                qsos: qsos
            )
        }
    }
}

// MARK: - Awards Computation

extension POTAAwardsActor {
    private func computeAwardsProgress(
        activations: [ActivationGroup],
        allSnapshots: [QSOSnapshot]
    ) -> POTAAwardsProgress {
        let minQSOs = POTARules.activationMinQSOs
        let parkQSOCounts = computeParkQSOCounts(allSnapshots)
        let laPortaCount = computeLaPortaCount(
            activations, minQSOs: minQSOs
        )
        let metadataCount = allSnapshots.filter {
            QSOMode.isMetadata($0.mode)
        }.count
        let validCount = activations.filter {
            $0.uniqueQSOCount >= minQSOs
        }.count
        return POTAAwardsProgress(
            uniqueParksCount: computeUniqueParks(
                activations, minQSOs: minQSOs
            ),
            dxEntitiesCount: computeDXEntities(
                activations, minQSOs: minQSOs
            ),
            statesActivated: computeWorkedAllStates(
                activations, minQSOs: minQSOs
            ),
            roverMaxParks: computeRover(
                activations, minQSOs: minQSOs
            ),
            repeatOffenderMaxCount: computeRepeatOffender(
                activations, minQSOs: minQSOs
            ),
            parkToParkCount: computeParkToPark(allSnapshots),
            kiloParks: kiloParks(from: parkQSOCounts),
            nearKiloParks: nearKiloParks(from: parkQSOCounts),
            laPortaEarned: laPortaCount >= 10,
            laPortaQualifyingParks: laPortaCount,
            sixPackEarned: computeSixPack(
                activations, minQSOs: minQSOs
            ),
            bestSingleParkTotal: parkQSOCounts.values.max() ?? 0,
            totalParkQSOs: allSnapshots.count,
            metadataExcluded: metadataCount,
            totalActivationGroups: activations.count,
            validActivationGroups: validCount
        )
    }

    private func computeUniqueParks(
        _ activations: [ActivationGroup], minQSOs: Int
    ) -> Int {
        var parkSet = Set<String>()
        for activation in activations
            where activation.uniqueQSOCount >= minQSOs
        {
            for park in POTAClient.splitParkReferences(
                activation.parkReference
            ) {
                parkSet.insert(park.uppercased())
            }
        }
        return parkSet.count
    }

    private func computeDXEntities(
        _ activations: [ActivationGroup], minQSOs: Int
    ) -> Int {
        var entities = Set<Int>()
        for activation in activations
            where activation.uniqueQSOCount >= minQSOs
        {
            for qso in activation.qsos {
                if let dxcc = qso.dxcc, dxcc > 0 {
                    entities.insert(dxcc)
                    break
                }
            }
        }
        return entities.count
    }

    private func computeWorkedAllStates(
        _ activations: [ActivationGroup], minQSOs: Int
    ) -> Set<String> {
        let cache = POTAParksCache.shared
        var states = Set<String>()
        for activation in activations
            where activation.uniqueQSOCount >= minQSOs
        {
            let parks = POTAClient.splitParkReferences(
                activation.parkReference
            )
            for park in parks {
                for state in statesForPark(
                    park, activation: activation, cache: cache
                ) {
                    states.insert(state)
                }
            }
        }
        return states
    }

    private func statesForPark(
        _ parkRef: String,
        activation: ActivationGroup,
        cache: POTAParksCache
    ) -> [String] {
        if let park = cache.parkSync(for: parkRef),
           park.countryPrefix == "US" || park.countryPrefix == "K"
        {
            let parkStates = park.states.filter { !$0.isEmpty }
            if !parkStates.isEmpty {
                return parkStates
            }
        }
        let parkPrefix = String(
            parkRef.split(separator: "-").first ?? ""
        )
        guard parkPrefix == "US" || parkPrefix == "K" else {
            return []
        }
        if let grid = activation.qsos.first?.myGrid,
           let state = POTAClient.gridToUSState(grid)
        {
            return [state]
        }
        return []
    }

    private func computeRover(
        _ activations: [ActivationGroup], minQSOs: Int
    ) -> Int {
        var parksByDate: [String: Set<String>] = [:]
        for activation in activations
            where activation.uniqueQSOCount >= minQSOs
        {
            for park in POTAClient.splitParkReferences(
                activation.parkReference
            ) {
                parksByDate[
                    activation.utcDateString, default: []
                ].insert(park.uppercased())
            }
        }
        return parksByDate.values.map(\.count).max() ?? 0
    }

    private func computeRepeatOffender(
        _ activations: [ActivationGroup], minQSOs: Int
    ) -> Int {
        var countByPark: [String: Int] = [:]
        for activation in activations
            where activation.uniqueQSOCount >= minQSOs
        {
            for park in POTAClient.splitParkReferences(
                activation.parkReference
            ) {
                countByPark[park.uppercased(), default: 0] += 1
            }
        }
        return countByPark.values.max() ?? 0
    }

    private func computeParkToPark(
        _ snapshots: [QSOSnapshot]
    ) -> Int {
        snapshots.filter { snap in
            !snap.parkReference.isEmpty
                && snap.theirParkReference?.isEmpty == false
        }.count
    }

    private func computeParkQSOCounts(
        _ snapshots: [QSOSnapshot]
    ) -> [String: Int] {
        var countByPark: [String: Int] = [:]
        for snap in snapshots {
            guard !snap.parkReference.isEmpty else {
                continue
            }
            for park in POTAClient.splitParkReferences(
                snap.parkReference
            ) {
                countByPark[park.uppercased(), default: 0] += 1
            }
        }
        return countByPark
    }

    private func kiloParks(
        from counts: [String: Int]
    ) -> [String] {
        counts.filter { $0.value >= 1_000 }.keys.sorted()
    }

    private func nearKiloParks(
        from counts: [String: Int]
    ) -> [NearKiloPark] {
        let threshold = 1_000 - Self.nearKiloThreshold
        return counts
            .filter { $0.value >= threshold && $0.value < 1_000 }
            .map {
                NearKiloPark(reference: $0.key, qsoCount: $0.value)
            }
            .sorted { $0.qsoCount > $1.qsoCount }
    }

    private func computeLaPortaCount(
        _ activations: [ActivationGroup], minQSOs: Int
    ) -> Int {
        var bandsByPark: [String: Set<String>] = [:]
        for activation in activations
            where activation.uniqueQSOCount >= minQSOs
        {
            for park in POTAClient.splitParkReferences(
                activation.parkReference
            ) {
                let normalized = park.uppercased()
                for qso in activation.qsos {
                    bandsByPark[
                        normalized, default: []
                    ].insert(qso.band.uppercased())
                }
            }
        }
        return bandsByPark.values.filter { $0.count >= 10 }.count
    }

    private func computeSixPack(
        _ activations: [ActivationGroup], minQSOs: Int
    ) -> Bool {
        var parksWithTenOn6m = Set<String>()
        for activation in activations
            where activation.uniqueQSOCount >= minQSOs
        {
            let count = activation.qsos.filter {
                $0.band == "6m"
            }.count
            if count >= 10 {
                for park in POTAClient.splitParkReferences(
                    activation.parkReference
                ) {
                    parksWithTenOn6m.insert(park.uppercased())
                }
            }
        }
        return parksWithTenOn6m.count >= 6
    }
}

// WAS250 computation is in POTAAwardsActor+WAS250.swift
