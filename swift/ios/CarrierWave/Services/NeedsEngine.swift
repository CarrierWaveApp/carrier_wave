// Needs Engine
//
// Background actor that computes what the operator still needs for awards
// and goals. Produces a frozen NeedsSnapshot consumed by SpotNeedsMatcher.
// Recomputes on sync completion, manual refresh, or app foreground after 1 hour.

import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData

// MARK: - NeedsEngine

actor NeedsEngine {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = NeedsEngine()

    /// Most recent computed snapshot.
    func snapshot() -> NeedsSnapshot {
        cachedSnapshot ?? .empty
    }

    /// Recompute all needs from QSO data.
    /// Uses a single batched pass over QSOs to avoid loading the entire table
    /// into memory — critical for 100k+ QSO databases on 4 GB devices.
    func recompute(container: ModelContainer) async -> NeedsSnapshot {
        let profiler = StartupProfiler.shared
        let context = ModelContext(container)
        context.autosaveEnabled = false

        profiler.record("needs.ctyLoad.start")
        let ctyDB = await CTYService.shared.database()
        profiler.record("needs.ctyLoad.done")

        // Single-pass batched accumulation of all QSO-derived needs
        profiler.record("needs.accumulate.start")
        let accum = accumulateFromQSOs(container: container, ctyDB: ctyDB)
        profiler.record("needs.accumulate.done")

        // Finalize each need type from accumulated data
        let dxcc = finalizeDXCC(accum, ctyDB: ctyDB)
        let was = finalizeWAS(accum)
        let potaHunter = finalizePOTAHunter(accum)
        let potaActivator = finalizePOTAActivator(accum)
        let wwffHunter = finalizeWWFF(accum)

        // These don't touch QSOs — small bounded fetches
        let customPatterns = loadCustomPatterns(context: context)

        let snap = NeedsSnapshot(
            dxcc: dxcc,
            was: was,
            potaHunter: potaHunter,
            potaActivator: potaActivator,
            wwffHunter: wwffHunter,
            customPatterns: customPatterns,
            modeFamiliesWorked: accum.modeFamiliesWorked,
            generatedAt: Date()
        )

        cachedSnapshot = snap
        return snap
    }

    /// Invalidate cached snapshot (forces recompute on next access).
    func invalidate() {
        cachedSnapshot = nil
    }

    // MARK: Private

    private var cachedSnapshot: NeedsSnapshot?
}

// MARK: - PerGridDXCC

/// DXCC data accumulated per grid square.  At finalization we select
/// the primary grid's data, discarding the rest.  This avoids storing
/// a CallsignBandEntry per QSO (~10 MB for 100k QSOs).
private struct PerGridDXCC {
    var allTimeWorked = Set<String>()
    var bandSlots = Set<BandSlotKey>()
}

// MARK: - NeedsAccumulator

/// Intermediate state accumulated during single-pass QSO iteration.
/// Avoids holding any QSO objects in memory — only lightweight sets/dicts.
private struct NeedsAccumulator {
    /// Grid counting (for DXCC primary grid selection)
    var gridCounts: [String: Int] = [:]

    /// DXCC data keyed by grid prefix — typically 1-3 entries.
    var dxccByGrid: [String: PerGridDXCC] = [:]

    /// DXCC data for QSOs with no grid (counted regardless of primary grid)
    var dxccNoGrid = PerGridDXCC()

    // WAS
    var statesWorked = Set<String>()
    var perModeWorked: [String: Set<String>] = [:]

    /// POTA Hunter
    var hunterParksWorked = Set<String>()

    // POTA Activator
    var activationQSOCounts: [String: Int] = [:]
    var activationStates: [String: Set<String>] = [:]
    var activationEntities: [String: String] = [:]

    /// WWFF Hunter
    var wwffRefsWorked = Set<String>()

    /// Mode families the operator has actually worked (for filtering)
    var modeFamiliesWorked = Set<String>()
}

// MARK: - Single-Pass Accumulation

private extension NeedsEngine {
    /// Iterate all non-hidden QSOs in batches, accumulating data for every
    /// need type simultaneously.  A fresh ModelContext per batch keeps
    /// peak memory to ~5 MB regardless of total QSO count.
    func accumulateFromQSOs(
        container: ModelContainer,
        ctyDB: CTYDatabase?
    ) -> NeedsAccumulator {
        var accum = NeedsAccumulator()
        let batchSize = 500
        var offset = 0
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        while true {
            let batchCount: Int = autoreleasepool {
                let context = ModelContext(container)
                context.autosaveEnabled = false
                let descriptor = BoundedDescriptor<QSO>(
                    predicate: #Predicate { !$0.isHidden },
                    limit: batchSize,
                    offset: offset
                )

                guard let batch = try? context.boundedFetch(descriptor),
                      !batch.isEmpty
                else {
                    return 0
                }

                for qso in batch {
                    guard !QSOMode.isMetadata(qso.mode) else {
                        continue
                    }
                    processQSO(
                        qso, into: &accum,
                        ctyDB: ctyDB, dateFormatter: dateFormatter
                    )
                }

                return batch.count
            }

            guard batchCount > 0 else {
                break
            }
            offset += batchCount
            if batchCount < batchSize {
                break
            }
        }

        return accum
    }

    func processQSO(
        _ qso: QSO,
        into accum: inout NeedsAccumulator,
        ctyDB: CTYDatabase?,
        dateFormatter: DateFormatter
    ) {
        // --- Mode family tracking (computed once, reused for WAS) ---
        let modeFamily = String(
            describing: ModeEquivalence.family(for: qso.mode)
        )
        accum.modeFamiliesWorked.insert(modeFamily)

        // --- Grid counting (for DXCC) ---
        let gridPrefix: String?
        if let grid = qso.myGrid, grid.count >= 4 {
            let gp = String(grid.prefix(4)).uppercased()
            accum.gridCounts[gp, default: 0] += 1
            gridPrefix = gp
        } else {
            gridPrefix = nil
        }

        accumulateDXCC(qso, gridPrefix: gridPrefix, ctyDB: ctyDB, into: &accum)
        accumulateWAS(qso, modeFamily: modeFamily, into: &accum)
        accumulateParksAndWWFF(qso, into: &accum, dateFormatter: dateFormatter)
    }

    private func accumulateDXCC(
        _ qso: QSO,
        gridPrefix: String?,
        ctyDB: CTYDatabase?,
        into accum: inout NeedsAccumulator
    ) {
        guard let db = ctyDB, let entity = db.lookup(qso.callsign) else {
            return
        }
        let prefix = entity.primaryPrefix
        if let gp = gridPrefix {
            accum.dxccByGrid[gp, default: PerGridDXCC()]
                .allTimeWorked.insert(prefix)
            if !qso.band.isEmpty {
                accum.dxccByGrid[gp, default: PerGridDXCC()]
                    .bandSlots.insert(BandSlotKey(
                        entity: prefix, band: qso.band
                    ))
            }
        } else {
            accum.dxccNoGrid.allTimeWorked.insert(prefix)
            if !qso.band.isEmpty {
                accum.dxccNoGrid.bandSlots.insert(BandSlotKey(
                    entity: prefix, band: qso.band
                ))
            }
        }
    }

    private func accumulateWAS(
        _ qso: QSO,
        modeFamily: String,
        into accum: inout NeedsAccumulator
    ) {
        guard let raw = qso.state else {
            return
        }
        let state = USStates.normalizeAbbreviation(raw)
        guard USStatesReference.allStates.contains(state) else {
            return
        }
        accum.statesWorked.insert(state)
        accum.perModeWorked[modeFamily, default: []].insert(state)
    }

    func accumulateParksAndWWFF(
        _ qso: QSO,
        into accum: inout NeedsAccumulator,
        dateFormatter: DateFormatter
    ) {
        // --- POTA Hunter ---
        if let park = qso.theirParkReference, !park.isEmpty {
            let refs = park.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            for ref in refs where !ref.isEmpty {
                accum.hunterParksWorked.insert(ref.uppercased())
            }
        }

        // --- POTA Activator ---
        // Split 2-fers so each park is counted independently
        if let parkRef = qso.parkReference, !parkRef.isEmpty {
            let utcDate = dateFormatter.string(from: qso.timestamp)
            let parks = ParkReference.split(parkRef)
            for park in parks {
                let key = "\(park)|\(utcDate)"
                accum.activationQSOCounts[key, default: 0] += 1

                if let state = qso.state?.uppercased(),
                   USStatesReference.allStates.contains(state)
                {
                    accum.activationStates[park, default: []]
                        .insert(state)
                }
                if let country = qso.country?.uppercased() {
                    accum.activationEntities[park] = country
                }
            }
        }

        // --- WWFF Hunter ---
        if let wwff = qso.wwffRef, !wwff.isEmpty {
            accum.wwffRefsWorked.insert(wwff.uppercased())
        }
        if let park = qso.theirParkReference,
           park.uppercased().contains("FF-")
        {
            accum.wwffRefsWorked.insert(park.uppercased())
        }
    }
}

// MARK: - Finalization

private extension NeedsEngine {
    func finalizeDXCC(
        _ accum: NeedsAccumulator, ctyDB: CTYDatabase?
    ) -> DXCCNeeds {
        guard let db = ctyDB else {
            return .empty
        }

        let primaryGrid = accum.gridCounts
            .max(by: { $0.value < $1.value })?.key

        // Select the primary grid's DXCC data, merged with no-grid QSOs
        var allTimeWorked = accum.dxccNoGrid.allTimeWorked
        var bandSlotsWorked = accum.dxccNoGrid.bandSlots

        if let primaryGrid, let gridData = accum.dxccByGrid[primaryGrid] {
            allTimeWorked.formUnion(gridData.allTimeWorked)
            bandSlotsWorked.formUnion(gridData.bandSlots)
        } else if accum.dxccByGrid.count == 1,
                  let onlyGrid = accum.dxccByGrid.values.first
        {
            // Single grid — use it regardless
            allTimeWorked.formUnion(onlyGrid.allTimeWorked)
            bandSlotsWorked.formUnion(onlyGrid.bandSlots)
        }

        return DXCCNeeds(
            allTimeWorked: allTimeWorked,
            bandSlotsWorked: bandSlotsWorked,
            totalKnownEntities: db.entities.count,
            gridSquare: primaryGrid
        )
    }

    func finalizeWAS(_ accum: NeedsAccumulator) -> WASNeeds {
        let missing = USStatesReference.allStates
            .subtracting(accum.statesWorked)
        return WASNeeds(
            country: "USA",
            subdivisionTerm: "states",
            statesWorked: accum.statesWorked,
            statesMissing: missing,
            perModeWorked: accum.perModeWorked
        )
    }

    func finalizePOTAHunter(_ accum: NeedsAccumulator) -> POTAHunterNeeds {
        let (threshold, tierName) = nextPOTAHunterTier(
            currentCount: accum.hunterParksWorked.count
        )
        return POTAHunterNeeds(
            parksWorked: accum.hunterParksWorked,
            nextTierThreshold: threshold,
            nextTierName: tierName
        )
    }

    func finalizePOTAActivator(
        _ accum: NeedsAccumulator
    ) -> POTAActivatorNeeds {
        // Only count valid activations (10+ QSOs)
        let validParks = Set(
            accum.activationQSOCounts.filter { $0.value >= 10 }.keys
                .compactMap { $0.components(separatedBy: "|").first }
        )

        var statesActivated = Set<String>()
        for park in validParks {
            if let states = accum.activationStates[park] {
                statesActivated.formUnion(states)
            }
        }

        let statesMissing = USStatesReference.allStates
            .subtracting(statesActivated)
        let entityCount = Set(
            validParks.compactMap { accum.activationEntities[$0] }
        ).count

        let nextEntityTier = ((entityCount / 5) + 1) * 5

        return POTAActivatorNeeds(
            statesMissing: statesMissing,
            entitiesWorked: entityCount,
            nextEntityTierThreshold: nextEntityTier
        )
    }

    func finalizeWWFF(_ accum: NeedsAccumulator) -> WWFFHunterNeeds {
        let (threshold, tierName) = nextWWFFHunterTier(
            currentCount: accum.wwffRefsWorked.count
        )
        return WWFFHunterNeeds(
            referencesWorked: accum.wwffRefsWorked,
            nextTierThreshold: threshold,
            nextTierName: tierName
        )
    }
}

// MARK: - Tier Helpers

private extension NeedsEngine {
    func nextPOTAHunterTier(currentCount: Int) -> (Int, String?) {
        // POTA hunter tiers: 10, 25, 50, 100, 250, 500, 750, 1000, ...
        let tiers: [(Int, String)] = [
            (10, "Bronze"), (25, "Silver"), (50, "Gold"),
            (100, "Platinum"), (250, "Ruby"), (500, "Sapphire"),
            (750, "Emerald"), (1_000, "Diamond"),
            (2_500, "Obsidian"), (5_000, "Sasquatch"),
            (7_500, "Chupacabra"), (10_000, "Unicorn"),
        ]
        for (count, name) in tiers where count > currentCount {
            return (count, name)
        }
        // Beyond all tiers
        let next = ((currentCount / 2_500) + 1) * 2_500
        return (next, nil)
    }

    func nextWWFFHunterTier(currentCount: Int) -> (Int, String?) {
        // WWFF hunter tiers: 10, 44, 88, 176, 264, 352, 396, 444, 544, ...
        let tiers: [(Int, String)] = [
            (10, "Novice"), (44, "Hunter"), (88, "Bronze"),
            (176, "Silver"), (264, "Gold"), (352, "Platinum"),
            (396, "Diamond"), (444, "Ruby"),
        ]
        for (count, name) in tiers where count > currentCount {
            return (count, name)
        }
        // Beyond Ruby: 544, 644, 744, ...
        let next = 444 + (((currentCount - 444) / 100) + 1) * 100
        return (max(next, currentCount + 1), nil)
    }
}

// MARK: - Custom Needs

private extension NeedsEngine {
    func loadCustomPatterns(context: ModelContext) -> [CustomNeedPattern] {
        var descriptor = FetchDescriptor<CustomNeed>(
            predicate: #Predicate { $0.isActive && $0.fulfilledAt == nil }
        )
        descriptor.fetchLimit = 100

        guard let needs = try? context.fetch(descriptor) else {
            return []
        }

        return needs.map { need in
            CustomNeedPattern(
                id: need.id,
                pattern: need.pattern,
                patternType: CustomNeedPattern.PatternType(
                    rawValue: need.patternTypeRaw
                ) ?? .callsign,
                label: need.label
            )
        }
    }
}
