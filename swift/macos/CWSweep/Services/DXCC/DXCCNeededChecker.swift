// DXCC Needed Checker
//
// Loads worked/confirmed DXCC band-slots from SwiftData and determines
// whether a callsign+band+mode combination represents a new entity,
// new band-slot, or already-worked station. Indexes by both numeric
// DXCC code (from LoTW) and country name (from CTY.dat) to ensure
// matching across data sources.

import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData

// MARK: - DXCCScanResult

/// Sendable snapshot of DXCC scan results from background thread.
private struct DXCCScanResult {
    let entityNames: Set<String>
    let workedByName: Set<String>
    let confirmedByName: Set<String>
}

// MARK: - NeededStatus

/// Award status for a spot relative to the user's log.
enum NeededStatus: Equatable, Comparable {
    /// New DXCC entity never worked on any band/mode
    case newEntity
    /// Entity worked, but not on this band
    case newBandSlot
    /// Entity worked on this band, but not confirmed
    case workedNotConfirmed
    /// Entity worked and confirmed on this band
    case confirmed
    /// Cannot determine (no DXCC entity resolved)
    case unknown

    // MARK: Internal

    /// Display label
    var label: String {
        switch self {
        case .newEntity: "NEW DXCC"
        case .newBandSlot: "NEW BAND"
        case .workedNotConfirmed: "DXCC NOT CFMD"
        case .confirmed: "DXCC CFMD"
        case .unknown: ""
        }
    }
}

// MARK: - DXCCNeededChecker

/// Checks spots against the user's QSO log for DXCC needed status.
@MainActor
@Observable
final class DXCCNeededChecker {
    // MARK: Internal

    private(set) var isLoaded = false
    private(set) var workedEntityCount = 0

    /// Load worked/confirmed data from SwiftData on a background thread.
    func loadWorkedEntities(container: ModelContainer) async {
        let result = await Self.scanWorkedEntities(container: container)

        if let result {
            workedEntityNames = result.entityNames
            workedBandSlotsByName = result.workedByName
            confirmedBandSlotsByName = result.confirmedByName
            workedEntityCount = result.entityNames.count
            isLoaded = true
        } else {
            isLoaded = false
        }
    }

    /// Check the needed status for a DXCC entity on a given band.
    func check(entityName: String, band: String) -> NeededStatus {
        guard isLoaded, !entityName.isEmpty else {
            return .unknown
        }

        let normalized = entityName.uppercased()
        let bandKey = "\(normalized)|\(band)"

        if !workedEntityNames.contains(normalized) {
            return .newEntity
        }
        if !workedBandSlotsByName.contains(bandKey) {
            return .newBandSlot
        }
        if confirmedBandSlotsByName.contains(bandKey) {
            return .confirmed
        }
        return .workedNotConfirmed
    }

    // MARK: Private

    /// Set of uppercased country names for all worked entities
    private var workedEntityNames = Set<String>()

    /// Set of "COUNTRY|band" keys for all worked QSOs
    private var workedBandSlotsByName = Set<String>()

    /// Set of "COUNTRY|band" keys for LoTW-confirmed QSOs
    private var confirmedBandSlotsByName = Set<String>()

    /// Scan all QSOs for DXCC entity data off the main thread.
    private static func scanWorkedEntities(
        container: ModelContainer
    ) async -> DXCCScanResult? {
        await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let predicate = #Predicate<QSO> { !$0.isHidden }
            var seenUUIDs = Set<UUID>()
            var entityNames = Set<String>()
            var workedByName = Set<String>()
            var confirmedByName = Set<String>()
            var offset = 0

            do {
                while true {
                    let descriptor = BoundedDescriptor<QSO>(
                        predicate: predicate,
                        limit: BoundedDescriptor<QSO>.maxLimit,
                        offset: offset
                    )
                    let batch = try context.boundedFetch(descriptor)
                    if batch.isEmpty {
                        break
                    }

                    for qso in batch {
                        guard seenUUIDs.insert(qso.id).inserted else {
                            continue
                        }
                        if let country = qso.country, !country.isEmpty {
                            let normalized = country.uppercased()
                            entityNames.insert(normalized)
                            workedByName.insert("\(normalized)|\(qso.band)")
                            if qso.lotwConfirmed {
                                confirmedByName.insert("\(normalized)|\(qso.band)")
                            }
                        }
                    }
                    offset += batch.count
                }
                return DXCCScanResult(
                    entityNames: entityNames,
                    workedByName: workedByName,
                    confirmedByName: confirmedByName
                )
            } catch {
                return nil
            }
        }.value
    }
}
