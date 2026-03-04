import CarrierWaveData
import Foundation
import SwiftData

/// One-time repair: clear corrupted K-index data from before the HamQSL XML
/// whitespace parsing fix (commit 661310d, Feb 14 2026). Before that fix,
/// XML whitespace caused K-index to always parse as 0. Records with kIndex=0
/// before the cutoff date have their kIndex and propagationRating cleared
/// so they don't pollute charts, while preserving valid SFI/sunspot data.
actor KIndexRepairService {
    // MARK: Lifecycle

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Internal

    struct RepairResult: Sendable {
        let sessionsRepaired: Int
        let metadataRepaired: Int
    }

    let container: ModelContainer

    /// Run the repair. Returns counts of sessions and metadata records repaired.
    func repair() throws -> RepairResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        var sessionsRepaired = 0
        var metadataRepaired = 0

        // Feb 15 2026 00:00:00 UTC — first day after the fix
        let cutoffDate = Self.cutoffDate

        // Repair LoggingSession records
        var sessionDescriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate<LoggingSession> {
                $0.solarKIndex == 0 && $0.startedAt < cutoffDate
            }
        )
        sessionDescriptor.fetchLimit = 1_000

        let sessions = (try? context.fetch(sessionDescriptor)) ?? []
        for session in sessions {
            session.solarKIndex = nil
            session.solarPropagationRating = nil
            sessionsRepaired += 1
        }

        // Repair ActivationMetadata records
        var metaDescriptor = FetchDescriptor<ActivationMetadata>(
            predicate: #Predicate<ActivationMetadata> {
                $0.solarKIndex == 0 && $0.date < cutoffDate
            }
        )
        metaDescriptor.fetchLimit = 1_000

        let metadata = (try? context.fetch(metaDescriptor)) ?? []
        for meta in metadata {
            meta.solarKIndex = nil
            meta.solarPropagationRating = nil
            metadataRepaired += 1
        }

        if sessionsRepaired > 0 || metadataRepaired > 0 {
            try context.save()
        }

        return RepairResult(
            sessionsRepaired: sessionsRepaired,
            metadataRepaired: metadataRepaired
        )
    }

    // MARK: Private

    /// Feb 15 2026 00:00:00 UTC — first day after the K-index parsing fix
    private static let cutoffDate: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2_026, month: 2, day: 15))!
    }()
}
