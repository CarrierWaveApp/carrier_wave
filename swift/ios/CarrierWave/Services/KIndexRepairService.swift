import CarrierWaveData
import Foundation
import SwiftData

/// One-time repair: clear corrupted K-index data from before the HamQSL XML
/// whitespace parsing fix (commit 661310d, Feb 14 2026). Before that fix,
/// XML whitespace caused K-index to always parse as 0. Records with kIndex=0
/// before the cutoff date have their kIndex and propagationRating cleared
/// so they don't pollute charts, while preserving valid SFI/sunspot data.
///
/// Implementation note: this is a thin façade over `BatchedRewrite` — the
/// per-table counts in `RepairResult` are what the UI renders.
actor KIndexRepairService {
    // MARK: Lifecycle

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Internal

    struct RepairResult {
        let sessionsRepaired: Int
        let metadataRepaired: Int
    }

    let container: ModelContainer

    /// Run the repair. Returns counts of sessions and metadata records repaired.
    func repair() async throws -> RepairResult {
        let cutoffDate = Self.cutoffDate

        let sessions = try await BatchedRewrite<LoggingSession>(
            label: "kindex.session",
            container: container,
            predicate: #Predicate<LoggingSession> {
                $0.solarKIndex == 0 && $0.startedAt < cutoffDate
            }
        ) { session, _ in
            session.solarKIndex = nil
            session.solarPropagationRating = nil
            return true
        }.run()

        let metadata = try await BatchedRewrite<ActivationMetadata>(
            label: "kindex.metadata",
            container: container,
            predicate: #Predicate<ActivationMetadata> {
                $0.solarKIndex == 0 && $0.date < cutoffDate
            }
        ) { meta, _ in
            meta.solarKIndex = nil
            meta.solarPropagationRating = nil
            return true
        }.run()

        return RepairResult(
            sessionsRepaired: sessions.mutated,
            metadataRepaired: metadata.mutated
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
