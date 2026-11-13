import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - Data Loading

extension CallsignHistoryView {
    func loadData() async {
        let target = callsign.uppercased()

        loadOwnProfileIfNeeded()
        await loadClubs(targets: initialClubTargets(for: target))
        await loadQSOs(target: target)
        await loadFriendship(target: target)
        await loadRecordings(target: target)
        await loadRecordingClips(target: target)
        await loadActivityItems(target: target)
        await lookupCallsign(target: target)

        // After QRZ/HamDB lookup, re-fetch clubs including any previous
        // callsign returned by the lookup so club memberships stored
        // under an old call still surface here.
        await loadClubs(targets: postLookupClubTargets(for: target))
    }

    /// Initial fetch — only knows the displayed callsign and (for own
    /// profile) any previous callsigns the user has recorded locally.
    func initialClubTargets(for target: String) -> [String] {
        var targets = [target]
        if isOwnProfile {
            let previous = CallsignAliasService.shared.getPreviousCallsigns()
                .map { $0.uppercased() }
                .filter { $0 != target }
            targets.append(contentsOf: previous)
        }
        return targets
    }

    /// Post-lookup fetch — adds the QRZ-reported previous callsign on
    /// top of whatever the initial fetch knew about.
    func postLookupClubTargets(for target: String) -> [String] {
        var targets = initialClubTargets(for: target)
        let prev = callsignInfo?.previousCallsign?.uppercased() ?? ""
        if !prev.isEmpty, !targets.contains(prev) {
            targets.append(prev)
        }
        return targets
    }

    func loadOwnProfileIfNeeded() {
        guard isOwnProfile else {
            ownProfile = nil
            return
        }
        ownProfile = UserProfileService.shared.getProfile()
    }

    func loadClubs(targets: [String]) async {
        var seen = Set<String>()
        var names: [String] = []
        for target in targets {
            for clubName in ClubsSyncService.shared.clubs(for: target)
                where seen.insert(clubName).inserted
            {
                names.append(clubName)
            }
        }
        clubs = names.sorted()
    }

    // MARK: - Individual Loaders

    func loadQSOs(target: String) async {
        let descriptor = BoundedDescriptor<QSO>(
            predicate: #Predicate { qso in
                qso.callsign == target && !qso.isHidden
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)],
            limit: 200
        )
        let fetched = (try? modelContext.boundedFetch(descriptor)) ?? []
        qsos = fetched.filter {
            !QSOMode.isMetadata($0.mode)
        }
    }

    func loadFriendship(target: String) async {
        friendship = FriendsSyncService.shared.allFriendships
            .first { $0.friendCallsign.uppercased() == target.uppercased() }
    }

    func loadRecordings(target: String) async {
        var tuneInDescriptor = FetchDescriptor<WebSDRRecording>(
            predicate: #Predicate { recording in
                recording.spotCallsign == target && recording.isComplete
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        tuneInDescriptor.fetchLimit = 50
        let tuneIns = (try? modelContext.fetch(tuneInDescriptor)) ?? []
        var knownIds = Set(tuneIns.map(\.id))

        var items = tuneIns.map { recording in
            let ranges = callsignRanges(
                target: target, sessionId: recording.loggingSessionId
            )
            return RecordingWithRanges(
                recording: recording, callsignRanges: ranges
            )
        }

        items += findSessionMatchedRecordings(
            target: target, excluding: knownIds
        )
        knownIds.formUnion(items.map(\.recording.id))

        items += findTranscriptMatchedRecordings(
            target: target, excluding: knownIds
        )

        recordingItems = items.sorted {
            $0.recording.startedAt > $1.recording.startedAt
        }
    }

    func loadRecordingClips(target: String) async {
        clipsByQSOId = QSORecordingClipLoader.loadClips(
            for: target,
            qsos: qsos,
            modelContext: modelContext
        )
    }

    func loadActivityItems(target: String) async {
        var descriptor = FetchDescriptor<ActivityItem>(
            predicate: #Predicate { $0.callsign == target }
        )
        descriptor.fetchLimit = 50
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]
        activityItems = (try? modelContext.fetch(descriptor)) ?? []
    }

    func lookupCallsign(target: String) async {
        isLookingUp = true
        defer { isLookingUp = false }
        let service = CallsignLookupService(modelContext: modelContext)
        // Streamed lookup: cached row first (instant from disk), enriched
        // row once QRZ/HamDB resolves.
        for await result in service.lookupStream(target) {
            guard !Task.isCancelled else {
                return
            }
            callsignInfo = result.info
            isLookingUp = false
        }
    }

    // MARK: - Recording Search Helpers

    func findSessionMatchedRecordings(
        target: String, excluding knownIds: Set<UUID>
    ) -> [RecordingWithRanges] {
        let qsoDescriptor = BoundedDescriptor<QSO>(
            predicate: #Predicate { qso in
                qso.callsign == target
                    && !qso.isHidden
                    && qso.loggingSessionId != nil
            },
            limit: 200
        )
        let matchingQSOs = (try? modelContext.boundedFetch(qsoDescriptor)) ?? []
        let qsosBySession = Dictionary(
            grouping: matchingQSOs,
            by: { $0.loggingSessionId! } // swiftlint:disable:this force_unwrapping
        )

        guard !qsosBySession.isEmpty else {
            return []
        }

        var recDescriptor = FetchDescriptor<WebSDRRecording>(
            predicate: #Predicate { $0.isComplete }
        )
        recDescriptor.fetchLimit = 500
        let allRecs = (try? modelContext.fetch(recDescriptor)) ?? []

        return allRecs
            .filter {
                qsosBySession[$0.loggingSessionId] != nil
                    && !knownIds.contains($0.id)
            }
            .map { recording in
                // Use transcript ranges if available, otherwise
                // synthesize from QSO timestamps
                var ranges = callsignRanges(
                    target: target,
                    sessionId: recording.loggingSessionId
                )
                if ranges.isEmpty {
                    let sessionQSOs = qsosBySession[recording.loggingSessionId] ?? []
                    ranges = syntheticRanges(
                        from: sessionQSOs, recording: recording
                    )
                }
                return RecordingWithRanges(
                    recording: recording, callsignRanges: ranges
                )
            }
    }

    /// Create approximate ranges from QSO timestamps relative to recording start.
    func syntheticRanges(
        from qsos: [QSO], recording: WebSDRRecording
    ) -> [DetectedQSORange] {
        let leadIn: TimeInterval = 90
        let trailOut: TimeInterval = 15
        let duration = recording.durationSeconds

        return qsos.compactMap { qso in
            let offset = qso.timestamp.timeIntervalSince(recording.startedAt)
            let start = max(0, offset - leadIn)
            let end = min(duration, offset + trailOut)
            guard start < duration, end > 0 else {
                return nil
            }
            return DetectedQSORange(
                callsign: qso.callsign,
                startOffset: start,
                endOffset: end,
                loggedQSOId: qso.id
            )
        }
    }

    func findTranscriptMatchedRecordings(
        target: String, excluding knownIds: Set<UUID>
    ) -> [RecordingWithRanges] {
        var descriptor = FetchDescriptor<WebSDRRecording>(
            predicate: #Predicate { $0.isComplete }
        )
        descriptor.fetchLimit = 500
        guard let allRecordings = try? modelContext.fetch(descriptor)
        else {
            return []
        }

        return allRecordings
            .filter { !knownIds.contains($0.id) }
            .compactMap { recording in
                let ranges = callsignRanges(
                    target: target,
                    sessionId: recording.loggingSessionId
                )
                guard !ranges.isEmpty else {
                    return nil
                }
                return RecordingWithRanges(
                    recording: recording, callsignRanges: ranges
                )
            }
    }

    func callsignRanges(
        target: String, sessionId: UUID
    ) -> [DetectedQSORange] {
        guard let transcript = SDRRecordingTranscript.load(
            sessionId: sessionId
        ) else {
            return []
        }
        return transcript.detectedQSORanges.filter {
            $0.callsign.uppercased() == target
        }
    }

    // MARK: - Enriched Timeline Builder

    func buildEnrichedTimeline() -> [EnrichedTimelineItem] {
        // Index recordings by loggingSessionId for fast lookup
        let recBySession = Dictionary(
            grouping: recordingItems,
            by: { $0.recording.loggingSessionId }
        )

        var usedRecordingIds = Set<UUID>()
        var items: [EnrichedTimelineItem] = []

        // 1. Pair each QSO with its recording (if any)
        for qso in qsos {
            let recItem = qso.loggingSessionId
                .flatMap { recBySession[$0]?.first }
            let ranges = recItem?.callsignRanges.filter {
                $0.loggedQSOId == qso.id
            } ?? []

            if let recId = recItem?.recording.id {
                usedRecordingIds.insert(recId)
            }

            items.append(EnrichedTimelineItem(
                qso: qso,
                recording: recItem?.recording,
                callsignRanges: ranges,
                clip: clipsByQSOId[qso.id]
            ))
        }

        // 2. Add tune-in recordings that weren't matched to any QSO
        for recItem in recordingItems
            where !usedRecordingIds.contains(recItem.recording.id)
        {
            items.append(EnrichedTimelineItem(
                qso: nil,
                recording: recItem.recording,
                callsignRanges: recItem.callsignRanges,
                clip: nil
            ))
        }

        return items.sorted { $0.date > $1.date }
    }
}
