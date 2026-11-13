import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - DashboardView Backfill & Repair Jobs

extension DashboardView {
    // MARK: - Repair Chain Entry Point

    /// CAR-244: Once-per-day gate so cold-start repair scans don't run on
    /// every launch. Stored in `UserDefaults.standard` (not App Group) — this
    /// is per-device cadence and shouldn't be shared with the widget.
    private static let lastRepairChainRunKey = "lastRepairChainRunDate"
    private static let repairChainCooldown: TimeInterval = 24 * 60 * 60

    /// Runs all one-time repair and backfill jobs sequentially.
    /// Called AFTER the stats pipeline completes to avoid main actor contention.
    /// Interactive checks (callsign aliases, POTA repair, duplicates) run on
    /// main actor since they may show alerts. Pure background repairs run on a
    /// detached task to keep the main thread free for UI events.
    func runRepairChainIfNeeded(profiler: StartupProfiler) async {
        guard !hasCheckedCallsignAliases else {
            return
        }
        hasCheckedCallsignAliases = true

        // CAR-244: skip the entire chain if we ran it within the past 24 h.
        // Individual backfills are idempotent and self-skip via UserDefaults
        // flags, but the interactive checks (callsign aliases, POTA presence,
        // two-fer duplicates) re-scan on every cold start without this gate.
        let defaults = UserDefaults.standard
        let last = defaults.object(forKey: Self.lastRepairChainRunKey) as? Date
        let elapsed = last.map { Date().timeIntervalSince($0) } ?? .infinity
        if elapsed < Self.repairChainCooldown {
            profiler.record("dashboard.repairs.skipped24h")
            return
        }
        defaults.set(Date(), forKey: Self.lastRepairChainRunKey)

        // Brief delay to let SwiftUI settle after stats updates
        try? await Task.sleep(for: .milliseconds(200))
        profiler.record("dashboard.repairs.start")

        // Interactive checks that may show alerts — must stay on main actor
        await checkForUnconfiguredCallsigns()
        profiler.record("repair.callsignAliases.done")
        await checkForMismarkedPOTAPresence()
        profiler.record("repair.potaPresence.done")
        await checkForTwoferDuplicates()
        profiler.record("repair.twofer.done")

        // Background repairs — fire-and-forget. These all use their own
        // background ModelContexts and record profiler milestones on completion.
        Task.detached(priority: .utility) { [self] in
            await backfillWPMIfNeeded()
            profiler.record("repair.wpmBackfill.done")
            await backfillConditionsIfNeeded()
            profiler.record("repair.conditionsBackfill.done")
            await backfillCommentParkRefsIfNeeded()
            profiler.record("repair.commentParkRefs.done")
            await repairHuntingParkRefsIfNeeded()
            profiler.record("repair.huntingParkRefs.done")
            await repairPOTAMidnightSplitIfNeeded()
            profiler.record("repair.potaSplit.done")
            await repairKIndexIfNeeded()
            profiler.record("repair.kIndex.done")
            await repairActivityLogQSOsIfNeeded()
            profiler.record("repair.activityLogQSOs.done")
            await repairDuplicateQSOsIfNeeded()
            profiler.record("repair.duplicateQSOs.done")
            await repairDuplicatePresenceIfNeeded()
            profiler.record("repair.duplicatePresence.done")
            await repairDuplicateSpotNotesIfNeeded()
            profiler.record("repair.spotNotes.done")
            await backfillOPPrefixIfNeeded()
            profiler.record("repair.opPrefix.done")
            await repairPhoneSSBDuplicatesIfNeeded()
            profiler.record("repair.phoneSSB.done")
            await backfillSessionClubMembersIfNeeded()
            profiler.record("dashboard.repairs.done")
        }
    }

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

    private static let phoneSSBDuplicateRepairKey = "phoneSSBDuplicateRepairV2Completed"

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
    /// Runs synchronous ModelContext work on a detached task to avoid blocking the main actor.
    func repairPOTAMidnightSplitIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: Self.potaSplitRepairKey) else {
            return
        }

        let container = modelContext.container
        let debugResult: String = await Task.detached(priority: .utility) {
            do {
                let count = try POTASplitRepairService.repair(container: container)
                return "ran: split \(count)"
            } catch {
                return "error: \(error)"
            }
        }.value
        UserDefaults.standard.set(debugResult, forKey: "potaSplitRepairDebug")
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

        let service = DeduplicationService(container: modelContext.container)
        do {
            let result = try await service.findAndMergeDuplicates()
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

    // MARK: - OP: Prefix Backfill (CAR-258)

    private static let opPrefixBackfillKey = "opPrefixBackfillCompleted"

    /// One-time backfill: strip legacy `OP: <nickname>` segments from QSO
    /// notes where `notesUserAuthored == false`. CAR-258 follow-up to the
    /// CAR-243 fix that stopped emitting the prefix going forward.
    func backfillOPPrefixIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: Self.opPrefixBackfillKey) else {
            return
        }

        let service = OPPrefixBackfillService(container: modelContext.container)
        do {
            let result = try await service.backfill()
            if result.repaired > 0 {
                print("OP prefix backfill: cleaned \(result.repaired) of \(result.scanned) QSOs")
            }
            UserDefaults.standard.set(true, forKey: Self.opPrefixBackfillKey)
        } catch {
            print("OP prefix backfill failed: \(error)")
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

    // MARK: - Session Club Members Backfill

    /// Roster revision (`ClubsSyncService.membershipRevision`) the session
    /// club-member snapshots were last computed against. -1 = never.
    private static let sessionClubMembersRevisionKey = "sessionClubMembersBackfillRevision"

    /// Recompute `sessionClubMembers` on the user's session activity items
    /// whenever the club roster cache has changed since the last pass.
    ///
    /// The brag sheet renders a snapshot stored in the activity item at
    /// session end, so a roster that grows later (the BKG roster went from
    /// ~30 to 550+ members server-side) never reached existing sessions.
    /// Runs from the startup repair chain and on `.clubMembershipDidChange`.
    /// Uses a background ModelContext to avoid blocking the main thread.
    func backfillSessionClubMembersIfNeeded() async {
        let service = ClubsSyncService.shared
        guard !service.clubMemberCallsigns.isEmpty else {
            return // Roster not loaded yet — retry when the sync notifies
        }
        let revision = service.membershipRevision
        let done = UserDefaults.standard.object(forKey: Self.sessionClubMembersRevisionKey) as? Int ?? -1
        guard revision != done else {
            return
        }

        let container = modelContext.container
        let result = await Task.detached {
            await Self.runClubMembersBackfill(container: container)
        }.value

        if let count = result {
            if count > 0 {
                print("Session club members recompute: updated \(count) activity items")
            }
            UserDefaults.standard.set(revision, forKey: Self.sessionClubMembersRevisionKey)
        }
    }

    /// Run club members recompute on a background context. Returns updated count, or nil on failure.
    private static func runClubMembersBackfill(container: ModelContainer) async -> Int? {
        let bgContext = ModelContext(container)
        bgContext.autosaveEnabled = false

        let typeRaw = ActivityType.sessionCompleted.rawValue
        var descriptor = FetchDescriptor<ActivityItem>(
            predicate: #Predicate { $0.isOwn && $0.activityTypeRawValue == typeRaw }
        )
        descriptor.fetchLimit = 200

        guard let items = try? bgContext.fetch(descriptor) else {
            return nil
        }

        var updated = 0
        for item in items {
            if await backfillClubMembers(for: item, context: bgContext) {
                updated += 1
            }
        }

        if updated > 0 {
            try? bgContext.save()
        }
        return updated
    }

    /// Recompute sessionClubMembers for a single activity item from the current
    /// roster cache. Returns true if the stored snapshot changed.
    private static func backfillClubMembers(
        for item: ActivityItem,
        context: ModelContext
    ) async -> Bool {
        guard var details = item.details else {
            return false
        }

        let start = item.timestamp.addingTimeInterval(
            -Double((details.sessionDurationMinutes ?? 60) + 5) * 60
        )
        let end = item.timestamp
        let callsign = item.callsign
        let qsoDesc = BoundedDescriptor<QSO>(
            predicate: #Predicate {
                !$0.isHidden
                    && $0.myCallsign == callsign
                    && $0.timestamp >= start
                    && $0.timestamp <= end
            },
            limit: 500
        )
        guard let qsos = try? context.boundedFetch(qsoDesc) else {
            return false
        }

        let qsoCallsigns = qsos.map(\.callsign)
        // Roster lookups live on the main actor; one hop per item, not per QSO.
        let members = await MainActor.run {
            var seen = Set<String>()
            var members: [ClubMemberEntry] = []
            for qsoCallsign in qsoCallsigns {
                let key = qsoCallsign.uppercased()
                guard seen.insert(key).inserted else {
                    continue
                }
                let clubs = ClubsSyncService.shared.clubs(for: qsoCallsign)
                guard !clubs.isEmpty else {
                    continue
                }
                members.append(ClubMemberEntry(callsign: qsoCallsign, clubs: clubs))
            }
            return members
        }

        let newValue: [ClubMemberEntry]? = members.isEmpty ? nil : members
        guard newValue != details.sessionClubMembers else {
            return false
        }
        details.sessionClubMembers = newValue
        item.details = details
        return true
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
