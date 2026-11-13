import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - Group Selected QSOs Into Session

extension LogsListContentView {
    /// Live QSOs for the currently-selected rows, bridged from snapshot ids.
    var selectedQSOs: [QSO] {
        LogbookIDBridge.fetchQSOs(ids: selectedQSOIDs, in: modelContext)
    }

    /// Build the pre-flight summary used by `GroupIntoSessionSheet`.
    ///
    /// A QSO is only counted as "already in a session" when `loggingSessionId`
    /// points to a session that actually exists. QSOs referencing a deleted
    /// session are treated as orphans and remain eligible. Both the real
    /// blocking sessions and the orphan count are surfaced so the user can
    /// see exactly why any selected QSO is ineligible.
    func buildGroupingSummary() -> GroupIntoSessionSheet.Summary {
        let selected = selectedQSOs
        let referencedIds = Set(selected.compactMap(\.loggingSessionId))
        let existingSessions = fetchSessions(ids: referencedIds)
        let validIds = Set(existingSessions.map(\.id))

        let (eligible, blocked) = selected.partitioned { qso in
            guard let sessionId = qso.loggingSessionId else {
                return true
            }
            return !validIds.contains(sessionId)
        }

        let orphanedRefs = selected.reduce(into: 0) { acc, qso in
            if let sessionId = qso.loggingSessionId, !validIds.contains(sessionId) {
                acc += 1
            }
        }

        let existingEntries = existingSessionEntries(
            sessions: existingSessions,
            blockedQSOs: blocked
        )

        let timestamps = eligible.map(\.timestamp).sorted()
        let dateRange: ClosedRange<Date>? = timestamps.isEmpty
            ? nil
            : (timestamps.first! ... timestamps.last!)
        let uniqueStations = Set(eligible.map { $0.callsign.uppercased() }).count

        return GroupIntoSessionSheet.Summary(
            totalSelected: selected.count,
            eligibleCount: eligible.count,
            skippedAlreadyInSession: blocked.count,
            existingSessions: existingEntries,
            orphanedSessionRefs: orphanedRefs,
            dateRange: dateRange,
            uniqueStations: uniqueStations,
            suggestedCallsign: suggestedCallsign(from: eligible),
            suggestedActivationType: suggestedActivationType(from: eligible),
            suggestedParkReference: suggestedParkReference(from: eligible),
            suggestedSOTAReference: nil,
            suggestedWWFFReference: nil
        )
    }

    // MARK: - Fetch helpers

    func fetchSessions(ids: Set<UUID>) -> [LoggingSession] {
        guard !ids.isEmpty else {
            return []
        }
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { ids.contains($0.id) }
        )
        descriptor.fetchLimit = ids.count
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func existingSessionEntries(
        sessions: [LoggingSession],
        blockedQSOs: [QSO]
    ) -> [GroupIntoSessionSheet.ExistingSession] {
        let counts = blockedQSOs.reduce(into: [UUID: Int]()) { acc, qso in
            if let sessionId = qso.loggingSessionId {
                acc[sessionId, default: 0] += 1
            }
        }
        return sessions
            .map { session in
                GroupIntoSessionSheet.ExistingSession(
                    id: session.id,
                    title: sessionDisplayTitle(session),
                    qsoCount: counts[session.id] ?? 0
                )
            }
            .sorted { $0.title < $1.title }
    }

    func sessionDisplayTitle(_ session: LoggingSession) -> String {
        if let custom = session.customTitle?.nonEmpty {
            return custom
        }
        if let park = session.parkReference?.nonEmpty {
            return park
        }
        if let sota = session.sotaReference?.nonEmpty {
            return sota
        }
        if let wwff = session.wwffReference?.nonEmpty {
            return wwff
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return session.activationType.displayName
            + " · " + formatter.string(from: session.startedAt)
    }

    // MARK: - Suggestions

    func suggestedCallsign(from qsos: [QSO]) -> String {
        let counts = qsos.reduce(into: [String: Int]()) { acc, qso in
            acc[qso.myCallsign.uppercased(), default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? ""
    }

    func suggestedActivationType(from qsos: [QSO]) -> ActivationType {
        let parks = Set(qsos.compactMap { $0.parkReference?.uppercased() })
        return parks.isEmpty ? .casual : .pota
    }

    func suggestedParkReference(from qsos: [QSO]) -> String? {
        let parks = Set(qsos.compactMap { $0.parkReference?.uppercased() })
        return parks.count == 1 ? parks.first : nil
    }

    // MARK: - Session creation

    /// Create a completed `LoggingSession` that groups selected QSOs. QSOs
    /// whose `loggingSessionId` points to an existing session are skipped
    /// unless `unlinkFromExistingSessions` is set — in which case they are
    /// moved into the new session.
    func createSessionFromSelection(_ result: GroupIntoSessionResult) {
        let selected = selectedQSOs
        let referencedIds = Set(selected.compactMap(\.loggingSessionId))
        let validIds = Set(fetchSessions(ids: referencedIds).map(\.id))

        let targeted = selected.filter { qso in
            guard let sessionId = qso.loggingSessionId else {
                return true
            }
            if result.unlinkFromExistingSessions {
                return true
            }
            return !validIds.contains(sessionId)
        }

        guard !targeted.isEmpty else {
            return
        }

        let sorted = targeted.sorted { $0.timestamp < $1.timestamp }
        let session = makeSession(result: result, qsos: sorted)
        modelContext.insert(session)

        let sessionId = session.id
        for qso in targeted {
            qso.loggingSessionId = sessionId
            qso.cloudDirtyFlag = true
            qso.modifiedAt = Date()
        }

        do {
            try QSOWriteSink.commitUpsertBatch(targeted, in: modelContext)
        } catch {
            modelContext.rollback()
            CwStoreWriteLog.shared.record("Group into session failed: \(error.localizedDescription)")
            return
        }
        selectedQSOIDs.removeAll()
        isSelectMode = false
        NotificationCenter.default.post(name: .didLogQSO, object: nil)
    }

    func makeSession(result: GroupIntoSessionResult, qsos sorted: [QSO]) -> LoggingSession {
        let first = sorted[0]
        let last = sorted[sorted.count - 1]
        let modeCounts = sorted.reduce(into: [String: Int]()) { acc, qso in
            acc[qso.mode.uppercased(), default: 0] += 1
        }
        let primaryMode = modeCounts
            .max(by: { $0.value < $1.value })?.key ?? first.mode
        let lastFrequency = sorted.last(where: { $0.frequency != nil })?.frequency

        let session = LoggingSession(
            myCallsign: result.myCallsign,
            startedAt: first.timestamp,
            frequency: lastFrequency,
            mode: primaryMode,
            activationType: result.activationType,
            parkReference: result.parkReference,
            sotaReference: result.sotaReference,
            wwffReference: result.wwffReference,
            notes: result.notes
        )
        session.status = .completed
        session.endedAt = last.timestamp
        session.qsoCount = sorted.count
        session.customTitle = result.title
        session.cloudDirtyFlag = true
        return session
    }
}

// MARK: - Array.partitioned

private extension Array {
    /// Splits the array into (matching, non-matching) groups.
    func partitioned(by predicate: (Element) -> Bool) -> ([Element], [Element]) {
        var matching: [Element] = []
        var other: [Element] = []
        for element in self {
            if predicate(element) {
                matching.append(element)
            } else {
                other.append(element)
            }
        }
        return (matching, other)
    }
}
