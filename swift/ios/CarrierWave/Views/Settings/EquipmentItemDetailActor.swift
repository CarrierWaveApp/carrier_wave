import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData

// MARK: - EquipmentSessionSummary

nonisolated struct EquipmentSessionSummary: Identifiable {
    let id: UUID
    let startedAt: Date
    let qsoCount: Int
    let activationType: String
    let parkReference: String?
    let myCallsign: String
    let mode: String?
}

// MARK: - EquipmentQSOSnapshot

nonisolated private struct EquipmentQSOSnapshot {
    let band: String
    let mode: String
    let myGrid: String?
    let theirGrid: String?
    let dxcc: Int?

    var distanceKm: Double? {
        // Great-circle (haversine) via MaidenheadConverter — the SAME math as the
        // cw-store `cw_grid_distance_km` UDF used by the `.on` path, so both modes (and
        // the parity oracle) agree. Returns nil for grids shorter than 4 chars / invalid.
        guard let myGrid, let theirGrid else {
            return nil
        }
        return MaidenheadConverter.distanceKm(from: myGrid, to: theirGrid)
    }
}

// MARK: - EquipmentPairedItem

nonisolated struct EquipmentPairedItem: Identifiable {
    let name: String
    let category: EquipmentStatsCategory
    let sessionCount: Int

    var id: String {
        "\(category.rawValue):\(name)"
    }
}

// MARK: - ComputedEquipmentItemDetail

nonisolated struct ComputedEquipmentItemDetail {
    let sessions: [EquipmentSessionSummary]
    let totalQSOs: Int
    let pairedItems: [EquipmentPairedItem]
    let farthestQSOKm: Double?
    let averageQSOKm: Double?
    let shortestQSOKm: Double?
    let bandBreakdown: [(band: String, count: Int)]
    let modeBreakdown: [(mode: String, count: Int)]
    let uniqueEntities: Int
    let firstUsed: Date?
    let lastUsed: Date?
}

// MARK: - EquipmentItemDetailActor

actor EquipmentItemDetailActor {
    // MARK: Internal

    func computeDetail(
        displayName: String,
        container: ModelContainer
    ) async throws -> ComputedEquipmentItemDetail {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let sessions = try fetchMatchingSessions(
            name: displayName, context: context
        )
        try Task.checkCancellation()

        let paired = buildPairedItems(
            sessions: sessions, excludingName: displayName
        )

        let summaries = sessions.map { session in
            EquipmentSessionSummary(
                id: session.id,
                startedAt: session.startedAt,
                qsoCount: session.qsoCount,
                activationType: session.activationTypeRawValue,
                parkReference: session.parkReference,
                myCallsign: session.myCallsign,
                mode: session.mode
            )
        }.sorted { $0.startedAt > $1.startedAt }

        let stats = try await computeStats(
            displayName: displayName,
            sessionIds: sessions.map(\.id),
            context: context
        )
        try Task.checkCancellation()

        return ComputedEquipmentItemDetail(
            sessions: summaries,
            totalQSOs: stats.totalQSOs,
            pairedItems: paired,
            farthestQSOKm: stats.farthestKm,
            averageQSOKm: stats.averageKm,
            shortestQSOKm: stats.shortestKm,
            bandBreakdown: stats.bandBreakdown,
            modeBreakdown: stats.modeBreakdown,
            uniqueEntities: stats.uniqueEntities,
            firstUsed: summaries.last?.startedAt,
            lastUsed: summaries.first?.startedAt
        )
    }

    // MARK: Private

    private struct QSOStatsResult {
        let totalQSOs: Int
        let farthestKm: Double?
        let averageKm: Double?
        let shortestKm: Double?
        let bandBreakdown: [(band: String, count: Int)]
        let modeBreakdown: [(mode: String, count: Int)]
        let uniqueEntities: Int
    }

    // MARK: - QSO Stats

    /// Compute the QSO-derived stats for `displayName`. In `.on`, serve them from cw-store's
    /// `session_item_detail` (no SwiftData QSO scan); otherwise fall back to the batched
    /// SwiftData snapshot scan. Parity is gated by `AnalyticsSessionItemDetailParityTests`.
    private func computeStats(
        displayName: String,
        sessionIds: [UUID],
        context: ModelContext
    ) async throws -> QSOStatsResult {
        if CwStoreQSOMode.current == .on,
           let store = try? await CwStoreProvider.shared.store()
        {
            let detail = try await RustAnalyticsReadSource(store: store)
                .sessionItemDetail(name: displayName)
            return QSOStatsResult(
                totalQSOs: detail.totalQSOs,
                farthestKm: detail.farthestKm,
                averageKm: detail.averageKm,
                shortestKm: detail.shortestKm,
                bandBreakdown: detail.bandBreakdown.map { (band: $0.name, count: $0.count) },
                modeBreakdown: detail.modeBreakdown.map { (mode: $0.name, count: $0.count) },
                uniqueEntities: detail.uniqueEntities
            )
        }

        let snapshots = try await fetchQSOSnapshots(sessionIds: sessionIds, context: context)
        try Task.checkCancellation()
        return computeQSOStats(snapshots)
    }

    // MARK: - Session Fetch

    private func fetchMatchingSessions(
        name: String,
        context: ModelContext
    ) throws -> [LoggingSession] {
        let descriptor = BoundedDescriptor<LoggingSession>(
            predicate: #Predicate<LoggingSession> { session in
                session.qsoCount > 0
                    && (session.myRig == name
                        || session.myAntenna == name
                        || session.myKey == name
                        || session.myMic == name)
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)],
            limit: 1_000
        )
        return try context.boundedFetch(descriptor)
    }

    // MARK: - QSO Fetch

    private func fetchQSOSnapshots(
        sessionIds: [UUID],
        context: ModelContext
    ) async throws -> [EquipmentQSOSnapshot] {
        guard !sessionIds.isEmpty else {
            return []
        }
        let idSet = Set(sessionIds)
        var snapshots: [EquipmentQSOSnapshot] = []
        var offset = 0
        let batchSize = BoundedDescriptor<QSO>.maxLimit

        while true {
            try Task.checkCancellation()
            let descriptor = BoundedDescriptor<QSO>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)],
                limit: batchSize,
                offset: offset
            )
            let batch = try context.boundedFetch(descriptor)
            if batch.isEmpty {
                break
            }

            for qso in batch {
                guard let sid = qso.loggingSessionId,
                      idSet.contains(sid),
                      !QSOMode.isMetadata(qso.mode)
                else {
                    continue
                }
                snapshots.append(EquipmentQSOSnapshot(
                    band: qso.band,
                    mode: qso.mode,
                    myGrid: qso.myGrid,
                    theirGrid: qso.theirGrid,
                    dxcc: qso.dxcc
                ))
            }

            if batch.count < batchSize {
                break
            }
            offset += batchSize
        }
        return snapshots
    }

    // MARK: - Paired Equipment

    private func buildPairedItems(
        sessions: [LoggingSession],
        excludingName name: String
    ) -> [EquipmentPairedItem] {
        var counts: [String: (EquipmentStatsCategory, Int)] = [:]

        for session in sessions {
            accumulatePair(
                session.myRig, category: .radio,
                exclude: name, into: &counts
            )
            accumulatePair(
                session.myAntenna, category: .antenna,
                exclude: name, into: &counts
            )
            accumulatePair(
                session.myKey, category: .key,
                exclude: name, into: &counts
            )
            accumulatePair(
                session.myMic, category: .mic,
                exclude: name, into: &counts
            )
        }

        return counts.map { key, val in
            EquipmentPairedItem(
                name: key, category: val.0, sessionCount: val.1
            )
        }.sorted { $0.sessionCount > $1.sessionCount }
    }

    private func accumulatePair(
        _ value: String?,
        category: EquipmentStatsCategory,
        exclude: String,
        into counts: inout [String: (EquipmentStatsCategory, Int)]
    ) {
        guard let value, !value.isEmpty, value != exclude else {
            return
        }
        let existing = counts[value] ?? (category, 0)
        counts[value] = (existing.0, existing.1 + 1)
    }

    private func computeQSOStats(
        _ snapshots: [EquipmentQSOSnapshot]
    ) -> QSOStatsResult {
        var bandCounts: [String: Int] = [:]
        var modeCounts: [String: Int] = [:]
        var entities = Set<Int>()
        var distances: [Double] = []

        for qso in snapshots {
            bandCounts[qso.band, default: 0] += 1
            modeCounts[qso.mode, default: 0] += 1
            if let dxcc = qso.dxcc, dxcc > 0 {
                entities.insert(dxcc)
            }
            if let km = qso.distanceKm, km > 0 {
                distances.append(km)
            }
        }

        return QSOStatsResult(
            totalQSOs: snapshots.count,
            farthestKm: distances.max(),
            averageKm: distances.isEmpty
                ? nil
                : distances.reduce(0, +) / Double(distances.count),
            shortestKm: distances.min(),
            bandBreakdown: bandCounts
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .map { (band: $0.key, count: $0.value) },
            modeBreakdown: modeCounts
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .map { (mode: $0.key, count: $0.value) },
            uniqueEntities: entities.count
        )
    }
}
