import CarrierWaveCore
import CoreLocation
import Foundation
import SwiftData

// MARK: - MapQSOSnapshot

/// Lightweight, Sendable snapshot of QSO data for map display.
/// Contains only the fields needed for map annotations and filtering.
struct MapQSOSnapshot: Sendable, Identifiable {
    let id: UUID
    let callsign: String
    let band: String
    let mode: String
    let timestamp: Date
    let myGrid: String?
    let theirGrid: String?
    let parkReference: String?
    let state: String?
    let dxccNumber: Int?
    let lotwConfirmed: Bool
    let qrzConfirmed: Bool
    let power: Int?
    let loggingSessionId: UUID?
    let myRig: String?
}

// MARK: - MapLoadingProgress

/// Progress information during map data loading
struct MapLoadingProgress: Sendable {
    let loaded: Int
    let total: Int
    let phase: String
}

// MARK: - MapActivationMetadata

/// Sendable snapshot of activation metadata for map display
struct MapActivationMetadata: Sendable {
    let weather: String?
    let solarConditions: String?
    let averageWPM: Int?
    let antenna: String?
    let key: String?
    let mic: String?
}

// MARK: - MapLoadedData

/// All data needed for the map view, computed on background thread
struct MapLoadedData: Sendable {
    let snapshots: [MapQSOSnapshot]
    let totalCount: Int
    let availableBands: [String]
    let availableModes: [String]
    let availableParks: [String]
    let earliestDate: Date?
    /// Activation metadata keyed by "parkReference|yyyy-MM-dd"
    let metadataByKey: [String: MapActivationMetadata]
}

// MARK: - MapDataLoadingActor

/// Background actor for fetching map QSO data without blocking the main thread.
/// Creates its own ModelContext from the container to perform all work off the main thread.
actor MapDataLoadingActor {
    // MARK: Internal

    /// Fetch QSOs and compute filter options on background thread.
    func loadMapData(
        container: ModelContainer,
        fetchLimit: Int?,
        onProgress: @escaping @Sendable (MapLoadingProgress) -> Void
    ) async throws -> MapLoadedData {
        // Create background context - this is the key to off-main-thread fetching
        let context = ModelContext(container)
        context.autosaveEnabled = false

        // Get total count
        let countDescriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
        let totalCount = (try? context.fetchCount(countDescriptor)) ?? 0

        onProgress(MapLoadingProgress(loaded: 0, total: totalCount, phase: "Loading QSOs..."))

        // Fetch activation metadata for map callouts
        let activationMetadata = fetchActivationMetadata(context: context)

        if totalCount == 0 {
            return MapLoadedData(
                snapshots: [],
                totalCount: 0,
                availableBands: [],
                availableModes: [],
                availableParks: [],
                earliestDate: nil,
                metadataByKey: activationMetadata
            )
        }

        // Fetch and process QSOs
        let targetCount = fetchLimit ?? totalCount
        let result = try await fetchQSOsInBatches(
            context: context,
            targetCount: targetCount,
            totalCount: totalCount,
            onProgress: onProgress
        )

        // Sort and return filter options
        return buildLoadedData(from: result, totalCount: totalCount, metadata: activationMetadata)
    }

    // MARK: Private

    /// Intermediate result from batch fetching
    private struct FetchResult {
        var snapshots: [MapQSOSnapshot]
        var bands: Set<String>
        var modes: Set<String>
        var parks: Set<String>
        var earliestDate: Date?
    }

    /// Modes that represent activation metadata, not actual QSOs
    private static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

    /// Bands to exclude from filter list (metadata or invalid values)
    private static let excludedBands: Set<String> = ["EVENT", "UNKNOWN"]

    /// Batch size for fetching
    private static let fetchBatchSize = 500

    /// Band sort order for consistent display
    private static let bandOrder = [
        "160M", "80M", "60M", "40M", "30M", "20M", "17M", "15M", "12M", "10M", "6M", "2M", "70CM",
    ]

    /// Fetch QSOs in batches and convert to snapshots
    private func fetchQSOsInBatches(
        context: ModelContext,
        targetCount: Int,
        totalCount: Int,
        onProgress: @escaping @Sendable (MapLoadingProgress) -> Void
    ) async throws -> FetchResult {
        var result = FetchResult(snapshots: [], bands: [], modes: [], parks: [], earliestDate: nil)
        let effectiveTarget = min(targetCount, totalCount)
        result.snapshots.reserveCapacity(effectiveTarget)

        var offset = 0

        while offset < targetCount {
            try Task.checkCancellation()

            let batch = try fetchBatch(context: context, offset: offset)
            if batch.isEmpty {
                break
            }

            processBatch(batch, into: &result)
            offset += Self.fetchBatchSize

            // Report progress against effective target, not total database count
            onProgress(
                MapLoadingProgress(
                    loaded: result.snapshots.count,
                    total: effectiveTarget,
                    phase: "Loading QSOs..."
                )
            )
        }

        return result
    }

    /// Fetch a single batch of QSOs
    private func fetchBatch(context: ModelContext, offset: Int) throws -> [QSO] {
        var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = Self.fetchBatchSize
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Process a batch of QSOs into snapshots and filter options
    private func processBatch(_ batch: [QSO], into result: inout FetchResult) {
        for qso in batch {
            let snapshot = MapQSOSnapshot(
                id: qso.id,
                callsign: qso.callsign,
                band: qso.band,
                mode: qso.mode,
                timestamp: qso.timestamp,
                myGrid: qso.myGrid,
                theirGrid: qso.theirGrid,
                parkReference: qso.parkReference,
                state: qso.state,
                dxccNumber: qso.dxccEntity?.number,
                lotwConfirmed: qso.lotwConfirmed,
                qrzConfirmed: qso.qrzConfirmed,
                power: qso.power,
                loggingSessionId: qso.loggingSessionId,
                myRig: qso.myRig
            )
            result.snapshots.append(snapshot)

            result.bands.insert(qso.band.uppercased())
            result.modes.insert(qso.mode.uppercased())
            if let park = qso.parkReference {
                result.parks.insert(park)
            }
            if result.earliestDate == nil || qso.timestamp < result.earliestDate! {
                result.earliestDate = qso.timestamp
            }
        }
    }

    /// Build final MapLoadedData from fetch result
    private func buildLoadedData(
        from result: FetchResult,
        totalCount: Int,
        metadata: [String: MapActivationMetadata]
    ) -> MapLoadedData {
        let sortedBands = Array(result.bands)
            .filter { !Self.excludedBands.contains($0.uppercased()) }
            .sorted { band1, band2 in
                let idx1 = Self.bandOrder.firstIndex(of: band1.uppercased()) ?? 999
                let idx2 = Self.bandOrder.firstIndex(of: band2.uppercased()) ?? 999
                return idx1 < idx2
            }

        let sortedModes = Array(result.modes)
            .filter { !Self.metadataModes.contains($0.uppercased()) }
            .sorted()

        return MapLoadedData(
            snapshots: result.snapshots,
            totalCount: totalCount,
            availableBands: sortedBands,
            availableModes: sortedModes,
            availableParks: Array(result.parks).sorted(),
            earliestDate: result.earliestDate,
            metadataByKey: metadata
        )
    }

    /// Fetch all ActivationMetadata and convert to Sendable snapshots,
    /// enriched with equipment from matching LoggingSessions.
    private func fetchActivationMetadata(
        context: ModelContext
    ) -> [String: MapActivationMetadata] {
        let descriptor = FetchDescriptor<ActivationMetadata>()
        let allMetadata = (try? context.fetch(descriptor)) ?? []

        // Fetch logging sessions with equipment to enrich metadata
        let sessionEquipment = fetchSessionEquipment(context: context)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")

        var dict: [String: MapActivationMetadata] = [:]
        for item in allMetadata {
            let dateStr = formatter.string(from: item.date)
            let key = "\(item.parkReference)|\(dateStr)"
            let equipment = sessionEquipment[key]
            let hasData =
                item.weather != nil || item.solarConditions != nil
                    || item.averageWPM != nil || equipment != nil
            guard hasData else {
                continue
            }
            dict[key] = MapActivationMetadata(
                weather: item.weather,
                solarConditions: item.solarConditions,
                averageWPM: item.averageWPM,
                antenna: equipment?.antenna,
                key: equipment?.key,
                mic: equipment?.mic
            )
        }
        return dict
    }

    /// Fetch equipment from LoggingSessions keyed by "parkRef|date"
    private func fetchSessionEquipment(
        context: ModelContext
    ) -> [String: SessionEquipment] {
        let predicate = #Predicate<LoggingSession> {
            $0.activationReference != nil
        }
        var descriptor = FetchDescriptor<LoggingSession>(predicate: predicate)
        descriptor.propertiesToFetch = []
        let sessions = (try? context.fetch(descriptor)) ?? []

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")

        var dict: [String: SessionEquipment] = [:]
        for session in sessions {
            guard let ref = session.activationReference else {
                continue
            }
            let hasEquipment =
                session.myAntenna != nil || session.myKey != nil
                    || session.myMic != nil
            guard hasEquipment else {
                continue
            }
            let dateStr = formatter.string(from: session.startedAt)
            let key = "\(ref)|\(dateStr)"
            dict[key] = SessionEquipment(
                antenna: session.myAntenna,
                key: session.myKey,
                mic: session.myMic
            )
        }
        return dict
    }
}

// MARK: - SessionEquipment

/// Lightweight equipment snapshot from a LoggingSession
private struct SessionEquipment {
    let antenna: String?
    let key: String?
    let mic: String?
}
