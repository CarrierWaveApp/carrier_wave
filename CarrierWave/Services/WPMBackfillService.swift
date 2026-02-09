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

    struct BackfillResult: Sendable {
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
        var metadataUpdated = 0

        for session in allSessions {
            let updated = processSession(session, metaByKey: &metaByKey, context: context)
            if updated {
                sessionsProcessed += 1
                metadataUpdated += 1
            }
        }

        if metadataUpdated > 0 {
            try context.save()
        }

        return BackfillResult(
            sessionsProcessed: sessionsProcessed, metadataUpdated: metadataUpdated
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

    private func buildMetadataLookup(
        context: ModelContext
    ) throws -> [String: ActivationMetadata] {
        let allMetadata = try context.fetch(FetchDescriptor<ActivationMetadata>())
        var dict: [String: ActivationMetadata] = [:]
        for meta in allMetadata {
            let dateStr = Self.dateFormatter.string(from: meta.date)
            dict["\(meta.parkReference)|\(dateStr)"] = meta
        }
        return dict
    }

    /// Process a single session. Returns true if metadata was updated.
    private func processSession(
        _ session: LoggingSession,
        metaByKey: inout [String: ActivationMetadata],
        context: ModelContext
    ) -> Bool {
        guard let parkRef = session.parkReference, !parkRef.isEmpty,
              session.spotCommentsData != nil
        else {
            return false
        }

        let wpms = session.spotComments.compactMap(\.wpm)
        guard !wpms.isEmpty else {
            return false
        }

        let avgWPM = wpms.reduce(0, +) / wpms.count
        let date = Self.utcCalendar.startOfDay(for: session.startedAt)
        let key = "\(parkRef)|\(Self.dateFormatter.string(from: date))"

        if let existing = metaByKey[key] {
            guard existing.averageWPM == nil else {
                return false
            }
            existing.averageWPM = avgWPM
        } else {
            let metadata = ActivationMetadata(
                parkReference: parkRef, date: date, averageWPM: avgWPM
            )
            context.insert(metadata)
            metaByKey[key] = metadata
        }
        return true
    }
}
