import SwiftData
import SwiftUI

// MARK: - DashboardView Backfill & Repair Jobs

extension DashboardView {
    // MARK: - WPM Backfill

    private static let wpmBackfillKey = "wpmBackfillCompleted"

    /// One-time backfill of average WPM from stored spot comments into ActivationMetadata.
    /// Runs silently on background thread, only once.
    func backfillWPMIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: Self.wpmBackfillKey) else {
            return
        }

        let service = WPMBackfillService(container: modelContext.container)
        do {
            let result = try await service.backfill()
            if result.metadataUpdated > 0 {
                print("WPM backfill: updated \(result.metadataUpdated) activation metadata records")
            }
            UserDefaults.standard.set(true, forKey: Self.wpmBackfillKey)
        } catch {
            print("WPM backfill failed: \(error)")
        }
    }

    // MARK: - Conditions Backfill

    private static let conditionsBackfillKey = "conditionsBackfillCompleted"

    /// One-time backfill: parse text-based solar/weather into structured fields.
    /// Runs silently on background thread, only once.
    func backfillConditionsIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: Self.conditionsBackfillKey) else {
            return
        }

        let service = ConditionsBackfillService(container: modelContext.container)
        do {
            let result = try await service.backfill()
            if result.solarUpdated > 0 || result.weatherUpdated > 0 {
                let msg = "Conditions backfill: solar=\(result.solarUpdated)"
                    + ", weather=\(result.weatherUpdated)"
                print(msg)
            }
            UserDefaults.standard.set(true, forKey: Self.conditionsBackfillKey)
        } catch {
            print("Conditions backfill failed: \(error)")
        }
    }

    // MARK: - Comment Park Reference Backfill

    private static let commentParkRefBackfillKey = "commentParkRefBackfillCompleted"

    /// One-time backfill: extract park references from ADIF comment fields.
    /// Runs silently on background thread, only once.
    func backfillCommentParkRefsIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: Self.commentParkRefBackfillKey) else {
            return
        }

        let service = CommentParkRefRepairService(container: modelContext.container)
        do {
            let result = try await service.backfill()
            if result.updated > 0 {
                print("Comment park ref backfill: updated \(result.updated) of \(result.scanned) QSOs")
            }
            UserDefaults.standard.set(true, forKey: Self.commentParkRefBackfillKey)
        } catch {
            print("Comment park ref backfill failed: \(error)")
        }
    }

    // MARK: - Activity Log QSO Repair

    private static let activityLogQSORepairKey = "activityLogQSORepairCompleted"

    /// One-time repair: flag activity log QSOs and fix misplaced parkReference fields.
    /// Runs silently on background thread, only once.
    func repairActivityLogQSOsIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: Self.activityLogQSORepairKey) else {
            return
        }

        let service = ActivityLogQSORepairService(container: modelContext.container)
        do {
            let result = try await service.repair()
            if result.flagged > 0 || result.parkRefsMoved > 0 {
                let msg = "Activity log QSO repair: flagged=\(result.flagged)"
                    + ", parkRefsMoved=\(result.parkRefsMoved)"
                print(msg)
            }
            UserDefaults.standard.set(true, forKey: Self.activityLogQSORepairKey)
        } catch {
            print("Activity log QSO repair failed: \(error)")
        }
    }

    // MARK: - PHONE/SSB Duplicate Repair

    private static let phoneSSBDuplicateRepairKey = "phoneSSBDuplicateRepairCompleted"

    /// One-time repair: merge duplicate QSOs caused by PHONE vs SSB mode mismatch
    /// between POTA and QRZ imports. Runs silently on background thread, only once.
    func repairPhoneSSBDuplicatesIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: Self.phoneSSBDuplicateRepairKey) else {
            return
        }

        let service = PhoneSSBDuplicateRepairService(container: modelContext.container)
        do {
            let count = try await service.countDuplicates()
            if count > 0 {
                phoneSSBDuplicateCount = count
                showingPhoneSSBRepairAlert = true
            } else {
                UserDefaults.standard.set(true, forKey: Self.phoneSSBDuplicateRepairKey)
            }
        } catch {
            print("PHONE/SSB duplicate check failed: \(error)")
        }
    }

    /// Perform the actual PHONE/SSB duplicate repair
    func performPhoneSSBDuplicateRepair() async {
        let service = PhoneSSBDuplicateRepairService(container: modelContext.container)
        do {
            let result = try await service.repairDuplicates()
            print("PHONE/SSB repair: merged \(result.qsosMerged) duplicate pairs")
            phoneSSBDuplicateCount = 0
            UserDefaults.standard.set(true, forKey: Self.phoneSSBDuplicateRepairKey)
            // Recompute stats after merge
            asyncStats.recompute(from: modelContext)
            presenceCounts.recompute(from: modelContext)
        } catch {
            print("PHONE/SSB duplicate repair failed: \(error)")
        }
    }

    // MARK: - POTA UTC Midnight Split Repair

    private static let potaSplitRepairKey = "potaUTCMidnightSplitRepairV4Completed"

    /// One-time repair: split existing POTA sessions that span UTC midnight.
    func repairPOTAMidnightSplitIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: Self.potaSplitRepairKey) else {
            return
        }

        do {
            let count = try POTASplitRepairService.repair(context: modelContext)
            UserDefaults.standard.set(
                "ran: split \(count)", forKey: "potaSplitRepairDebug"
            )
        } catch {
            UserDefaults.standard.set(
                "error: \(error)", forKey: "potaSplitRepairDebug"
            )
        }
        UserDefaults.standard.set(true, forKey: Self.potaSplitRepairKey)
    }

    // MARK: - K-Index Repair

    private static let kIndexRepairKey = "kIndexRepairCompleted"

    /// One-time repair: clear corrupted K-index data (always 0) from before
    /// the HamQSL XML whitespace parsing fix (Feb 14, 2026).
    func repairKIndexIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: Self.kIndexRepairKey) else {
            return
        }

        let service = KIndexRepairService(container: modelContext.container)
        do {
            let result = try await service.repair()
            if result.sessionsRepaired > 0 || result.metadataRepaired > 0 {
                let msg = "K-index repair: sessions=\(result.sessionsRepaired)"
                    + ", metadata=\(result.metadataRepaired)"
                print(msg)
            }
            UserDefaults.standard.set(true, forKey: Self.kIndexRepairKey)
        } catch {
            print("K-index repair failed: \(error)")
        }
    }
}
