import CarrierWaveData
import Foundation
import SwiftData

/// One-time backfill: compute average WPM from spot comments stored on past
/// LoggingSessions and write into ActivationMetadata.averageWPM.
/// Only sessions with a parkReference and spotCommentsData are processed.
actor WPMBackfillService {
    // MARK: Lifecycle

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Internal

    struct BackfillResult {
        let sessionsProcessed: Int
        let metadataUpdated: Int
    }

    let container: ModelContainer

    /// Run the backfill. Returns count of sessions processed and metadata records updated.
    func backfill() throws -> BackfillResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let allSessions = try context.fetch(FetchDescriptor<LoggingSession>())
        var metaByKey = try buildMetadataLookup(context: context)

        var sessionsProcessed = 0
        var updatedMetadata: [ActivationMetadata] = []

        for session in allSessions {
            if let metadata = processSession(session, metaByKey: &metaByKey, context: context) {
                sessionsProcessed += 1
                updatedMetadata.append(metadata)
            }
        }

        if !updatedMetadata.isEmpty {
            // Route the off-main save through the seam: cw-store first in `.on`,
            // then one per-context-suppressed save (ActivationMetadata-only).
            try OffMainStoreSeam.commitActivationMetadata(updatedMetadata, in: context)
        }

        return BackfillResult(
            sessionsProcessed: sessionsProcessed, metadataUpdated: updatedMetadata.count
        )
    }

    // MARK: Private

    private static let utcCalendar: Calendar = {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// The backfill needs every metadata row, so page through the table in
    /// bounded batches rather than one unbounded fetch.
    private func buildMetadataLookup(
        context: ModelContext
    ) throws -> [String: ActivationMetadata] {
        let batchSize = BoundedDescriptor<ActivationMetadata>.maxLimit
        var offset = 0
        var dict: [String: ActivationMetadata] = [:]

        while true {
            let descriptor = BoundedDescriptor<ActivationMetadata>(
                sortBy: [SortDescriptor(\.date), SortDescriptor(\.parkReference)],
                limit: batchSize,
                offset: offset
            )
            let batch = try context.boundedFetch(descriptor)
            for meta in batch {
                let dateStr = Self.dateFormatter.string(from: meta.date)
                dict["\(meta.parkReference)|\(dateStr)"] = meta
            }
            if batch.count < batchSize {
                break
            }
            offset += batch.count
        }
        return dict
    }

    /// Process a single session. Returns the touched `ActivationMetadata` if updated,
    /// or `nil` when nothing changed — the caller routes it through the seam.
    private func processSession(
        _ session: LoggingSession,
        metaByKey: inout [String: ActivationMetadata],
        context: ModelContext
    ) -> ActivationMetadata? {
        guard let parkRef = session.parkReference, !parkRef.isEmpty,
              session.spotCommentsData != nil
        else {
            return nil
        }

        let wpms = session.spotComments.compactMap(\.wpm)
        guard !wpms.isEmpty else {
            return nil
        }

        let avgWPM = wpms.reduce(0, +) / wpms.count
        let date = Self.utcCalendar.startOfDay(for: session.startedAt)
        let key = "\(parkRef)|\(Self.dateFormatter.string(from: date))"

        if let existing = metaByKey[key] {
            guard existing.averageWPM == nil else {
                return nil
            }
            existing.averageWPM = avgWPM
            return existing
        }
        let metadata = ActivationMetadata(
            parkReference: parkRef, date: date, averageWPM: avgWPM
        )
        context.insert(metadata)
        metaByKey[key] = metadata
        return metadata
    }
}
