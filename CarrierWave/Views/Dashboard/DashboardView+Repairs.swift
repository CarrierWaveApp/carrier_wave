import CarrierWaveData
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

    private static let commentParkRefBackfillKey = "commentParkRefBackfillV2Completed"

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

    // MARK: - Duplicate QSO & ServicePresence Repair

    private static let duplicateQSORepairKey = "duplicateQSORepairV1Completed"
    private static let presenceDeduplicationRepairKey = "presenceDeduplicationRepairCompleted"

    /// One-time repair: merge duplicate QSOs created by iCloud sync delivering
    /// records with different UUIDs that match on dedup key.
    func repairDuplicateQSOsIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: Self.duplicateQSORepairKey) else {
            return
        }

        let service = DeduplicationService(modelContext: modelContext)
        do {
            let result = try service.findAndMergeDuplicates()
            if result.qsosRemoved > 0 {
                print("QSO dedup repair: \(result.duplicateGroupsFound) groups,"
                    + " \(result.qsosRemoved) removed")
                asyncStats.recompute(from: modelContext)
                presenceCounts.recompute(from: modelContext)
                NotificationCenter.default.post(name: .didSyncQSOs, object: nil)
            }
            UserDefaults.standard.set(true, forKey: Self.duplicateQSORepairKey)
        } catch {
            print("QSO dedup repair failed: \(error)")
        }
    }

    /// One-time repair: remove duplicate ServicePresence records created by iCloud sync.
    func repairDuplicatePresenceIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: Self.presenceDeduplicationRepairKey) else {
            return
        }

        let service = ServicePresenceDeduplicationRepairService(
            container: modelContext.container
        )
        do {
            let result = try await service.repair()
            if result.deleted > 0 {
                print("Presence dedup repair: deleted \(result.deleted) of \(result.scanned)")
            }
            UserDefaults.standard.set(true, forKey: Self.presenceDeduplicationRepairKey)
        } catch {
            print("Presence dedup repair failed: \(error)")
        }
    }

    // MARK: - Duplicate Spot Note Repair

    private static let duplicateSpotNoteRepairKey = "duplicateSpotNoteRepairCompleted"

    /// One-time repair: deduplicate spot comments appended multiple times to QSO notes.
    func repairDuplicateSpotNotesIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: Self.duplicateSpotNoteRepairKey) else {
            return
        }

        let service = DuplicateSpotNoteRepairService(container: modelContext.container)
        do {
            let result = try await service.repair()
            if result.repaired > 0 {
                print("Spot note dedup repair: fixed \(result.repaired) of \(result.scanned) QSOs")
            }
            UserDefaults.standard.set(true, forKey: Self.duplicateSpotNoteRepairKey)
        } catch {
            print("Spot note dedup repair failed: \(error)")
        }
    }

    // MARK: - Hunting Park Reference Repair

    private static let huntingParkRefRepairKey = "huntingParkRefRepairCompleted"

    /// One-time repair: move comment-extracted park refs from parkReference to theirParkReference.
    /// Fixes QSOs where hunting contacts were misidentified as activations.
    func repairHuntingParkRefsIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: Self.huntingParkRefRepairKey) else {
            return
        }

        let service = HuntingParkRefRepairService(container: modelContext.container)
        do {
            let result = try await service.repair()
            if result.repaired > 0 {
                let msg = "Hunting park ref repair: fixed \(result.repaired)"
                    + " of \(result.scanned) QSOs"
                print(msg)
            }
            UserDefaults.standard.set(true, forKey: Self.huntingParkRefRepairKey)
        } catch {
            print("Hunting park ref repair failed: \(error)")
        }
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
