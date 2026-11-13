import CarrierWaveData
import Foundation
import SwiftData

// MARK: - LoggingSessionManager Spotting Extension

extension LoggingSessionManager {
    /// Whether auto-spotting is enabled (from settings)
    /// Controls recurring spots every 10 minutes AND initial spot on session start
    var potaAutoSpotEnabled: Bool {
        UserDefaults.standard.bool(forKey: "potaAutoSpotEnabled")
    }

    /// Whether QSY spot prompts are enabled (from settings)
    /// When true, prompts user to post a spot after frequency/mode changes
    /// Defaults to true if setting hasn't been explicitly set
    var potaQSYSpotEnabled: Bool {
        if UserDefaults.standard.object(forKey: "potaQSYSpotEnabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "potaQSYSpotEnabled")
    }

    /// The message to use for mid-rove QRT spots (from settings)
    var potaRoveQRTMessage: String {
        let message = UserDefaults.standard.string(forKey: "potaRoveQRTMessage")
            ?? "QRT moving to next park"
        return message.isEmpty ? "QRT moving to next park" : message
    }

    /// Whether QRT spotting is enabled (from settings)
    var potaQRTSpotEnabled: Bool {
        // Default to true if setting hasn't been explicitly set
        if UserDefaults.standard.object(forKey: "potaQRTSpotEnabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "potaQRTSpotEnabled")
    }

    /// Start the auto-spot timer for POTA activations
    func startAutoSpotTimer() {
        stopAutoSpotTimer()

        guard potaAutoSpotEnabled,
              let session = activeSession,
              session.isPOTA
        else {
            return
        }

        // Post an initial spot immediately
        Task {
            await postSpot(comment: customSpotMessage)
        }

        // Schedule recurring spots
        autoSpotTimer = Timer.scheduledTimer(
            withTimeInterval: autoSpotInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.postSpot(comment: self?.customSpotMessage)
            }
        }
        autoSpotTimer?.tolerance = autoSpotInterval * 0.1
    }

    /// Stop the auto-spot timer
    func stopAutoSpotTimer() {
        autoSpotTimer?.invalidate()
        autoSpotTimer = nil
    }

    /// Start a repeating spot with custom message and interval (from SPOT REPEAT command)
    func startRepeatSpot(comment: String?, intervalMinutes: Int) {
        stopAutoSpotTimer()
        customSpotMessage = comment
        autoSpotInterval = TimeInterval(intervalMinutes * 60)

        guard let session = activeSession,
              session.isPOTA || session.isSOTA
        else {
            return
        }

        // Post an initial spot immediately
        Task {
            await postSpot(comment: customSpotMessage)
        }

        // Schedule recurring spots at custom interval
        autoSpotTimer = Timer.scheduledTimer(
            withTimeInterval: autoSpotInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.postSpot(comment: self?.customSpotMessage)
            }
        }
        autoSpotTimer?.tolerance = autoSpotInterval * 0.1
    }

    /// Stop the repeating spot timer and reset to defaults
    func stopRepeatSpot() {
        stopAutoSpotTimer()
        customSpotMessage = nil
        autoSpotInterval = 10 * 60
    }

    /// Start spot comments polling for POTA activations
    /// Uses the first (primary) park reference for comments lookup
    func startSpotCommentsPolling() {
        guard let session = activeSession,
              session.isPOTA,
              let parkRef = session.parkReference
        else {
            return
        }

        let callsign = session.stationCallsign ?? session.myCallsign
        guard !callsign.isEmpty else {
            return
        }

        // Use the first park for spot comments polling
        let primaryPark = ParkReference.split(parkRef).first ?? parkRef

        spotCommentsService.onNewComments = { [weak self] comments in
            self?.attachSpotComments(comments)
        }

        spotCommentsService.startPolling(
            activator: callsign,
            parkRef: primaryPark,
            sessionStart: session.startedAt
        )
    }

    /// Attach spot comments to matching QSOs in the current session
    /// Matches by callsign and ±5 minute time window
    func attachSpotComments(_ comments: [POTASpotComment]) {
        guard activeSession != nil else {
            return
        }

        let sessionQSOs = getSessionQSOs()
        guard !sessionQSOs.isEmpty else {
            return
        }

        for comment in comments {
            // Skip if already attached
            guard !attachedSpotCommentIds.contains(comment.spotId) else {
                continue
            }

            // Skip if no comment text
            guard let commentText = comment.comments, !commentText.isEmpty else {
                continue
            }

            guard let commentTimestamp = comment.timestamp else {
                continue
            }

            // Find matching QSO: same callsign, within ±5 minutes
            let spotter = comment.spotter.uppercased()
            let timeWindow: TimeInterval = 5 * 60 // 5 minutes

            for qso in sessionQSOs {
                let timeDiff = abs(qso.timestamp.timeIntervalSince(commentTimestamp))
                if qso.callsign.uppercased() == spotter, timeDiff <= timeWindow {
                    // Skip if this exact spot is already attached to the QSO
                    // (handles app restart where in-memory dedup set was cleared)
                    var existing = qso.spotComments
                    if existing.contains(where: { $0.spotId == comment.spotId }) {
                        attachedSpotCommentIds.insert(comment.spotId)
                        break
                    }

                    existing.append(comment)
                    qso.spotComments = existing
                    qso.cloudDirtyFlag = true
                    qso.modifiedAt = Date()

                    attachedSpotCommentIds.insert(comment.spotId)
                    try? modelContext.save()

                    SyncDebugLog.shared.info(
                        "Attached spot comment from \(comment.spotter) "
                            + "(\(commentText)) to QSO with \(qso.callsign)",
                        service: .pota
                    )
                    break // Only attach to first matching QSO
                }
            }
        }
    }

    /// Start spot monitoring for the current session
    func startSpotMonitoring() {
        guard let session = activeSession else {
            return
        }

        let callsign = session.stationCallsign ?? session.myCallsign
        guard !callsign.isEmpty else {
            return
        }

        // Include POTA spots only for POTA activations
        let includePOTA = session.isPOTA

        // Wire up spot persistence callback before starting
        spotMonitoringService.onSpotsReceived = { [weak self] enrichedSpots in
            self?.recordSpots(enrichedSpots)
        }

        // Pass friend callsigns for spot notifications
        spotMonitoringService.friendNotifier.updateFriends(friendCallsigns)

        // Seed dedup keys from any persisted spots (handles app restart mid-session)
        if recordedSpotDedupKeys.isEmpty {
            seedSpotDedupKeys()
        }

        spotMonitoringService.startMonitoring(
            callsign: callsign,
            myGrid: session.myGrid,
            includePOTA: includePOTA
        )
    }

    /// Seed the in-memory spot dedup set from SwiftData (call once on session load/start)
    func seedSpotDedupKeys() {
        guard let session = activeSession else {
            return
        }
        let sessionId = session.id
        let predicate = #Predicate<SessionSpot> { spot in
            spot.loggingSessionId == sessionId
        }
        var descriptor = FetchDescriptor<SessionSpot>(predicate: predicate)
        descriptor.fetchLimit = 1_000
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        recordedSpotDedupKeys = Set(existing.map(\.dedupKey))
    }

    /// Persist enriched spots to SwiftData, deduplicating via in-memory set
    func recordSpots(_ enrichedSpots: [EnrichedSpot]) {
        guard let session = activeSession else {
            return
        }

        let sessionId = session.id

        // Insert only new spots using in-memory dedup set
        var insertedSpots: [SessionSpot] = []
        for enriched in enrichedSpots {
            let candidate = SessionSpot.from(enriched, loggingSessionId: sessionId)
            guard !recordedSpotDedupKeys.contains(candidate.dedupKey) else {
                continue
            }
            candidate.cloudDirtyFlag = true
            modelContext.insert(candidate)
            recordedSpotDedupKeys.insert(candidate.dedupKey)
            insertedSpots.append(candidate)
        }

        if !insertedSpots.isEmpty {
            // Route through the seam: cw-store first in `.on`, suppressed save.
            try? EntityWriteSink.commitUpsert(insertedSpots, in: modelContext)
        }

        // Write spots to App Group for Watch consumption (top 15, most recent first)
        let sorted = enrichedSpots.sorted { $0.spot.timestamp > $1.spot.timestamp }
        let watchSpots = sorted.prefix(15).map { enriched in
            SharedSpot(
                id: enriched.spot.id,
                callsign: enriched.spot.callsign,
                frequencyMHz: enriched.spot.frequencyMHz,
                mode: enriched.spot.mode,
                band: enriched.spot.band,
                timestamp: enriched.spot.timestamp,
                source: enriched.spot.source == .rbn ? "rbn" : "pota",
                parkRef: enriched.spot.parkRef,
                parkName: enriched.spot.parkName,
                snr: enriched.spot.snr
            )
        }
        WidgetDataWriter.writeSpots(SharedSpotSnapshot(
            spots: Array(watchSpots), updatedAt: Date()
        ))
    }

    /// Post spots for every program selected on the active session.
    /// POTA fans out across all park references (supports n-fer); SOTA posts
    /// once per session for the configured summit reference.
    /// TOTA spotting is not yet supported and is silently skipped.
    func postSpot(comment: String? = nil, showToast: Bool = false) async {
        let spotCallsign = activeSession?.stationCallsign ?? activeSession?.myCallsign
        // Own frequency, never the one we're tuned to while hunting (CAR-296).
        guard let session = activeSession,
              let freq = spotFrequency(for: session),
              let spotCallsign, !spotCallsign.isEmpty,
              isFrequencyInBand(freq, mode: session.mode)
        else {
            return
        }

        var posted: [String] = []
        var failures: [String] = []

        if session.isPOTA, let parkRef = session.parkReference {
            let (successLabel, errors) = await postPOTASpot(
                spotCallsign: spotCallsign,
                parkRef: parkRef,
                freq: freq,
                mode: session.mode,
                comment: comment
            )
            if let successLabel {
                posted.append(successLabel)
            }
            failures.append(contentsOf: errors)
        }

        if session.isSOTA, let summitRef = session.sotaReference, !summitRef.isEmpty {
            do {
                try await postSOTASpot(
                    spotCallsign: spotCallsign,
                    summitRef: summitRef,
                    freq: freq,
                    mode: session.mode,
                    comment: comment
                )
                posted.append(summitRef)
            } catch {
                failures.append("SOTA \(summitRef): \(error.localizedDescription)")
            }
        }

        guard showToast else {
            return
        }
        presentSpotToast(posted: posted, failures: failures, freq: freq, comment: comment)
    }

    /// Post QRT spot for a specific park reference (used during rove stop transitions)
    func postQRTSpotForPark(_ parkRef: String, session: LoggingSession) async {
        let qrtCallsign = session.stationCallsign ?? session.myCallsign
        guard potaQRTSpotEnabled,
              let freq = spotFrequency(for: session),
              !qrtCallsign.isEmpty
        else {
            return
        }

        let parks = ParkReference.split(parkRef)
        let potaClient = POTAClient(authService: potaAuthService ?? POTAAuthService())

        for park in parks {
            do {
                _ = try await potaClient.postSpot(
                    callsign: qrtCallsign,
                    reference: park,
                    frequency: freq * 1_000,
                    mode: session.mode,
                    comments: potaRoveQRTMessage
                )
                SyncDebugLog.shared.info(
                    "\(potaRoveQRTMessage) spot posted for \(park) (rove stop change)",
                    service: .pota
                )
            } catch {
                SyncDebugLog.shared.warning(
                    "Failed to post QRT spot for \(park): \(error.localizedDescription)",
                    service: .pota
                )
            }
        }
    }

    /// Post QRT spots for all parks if enabled and the session had spots.
    /// `frequency` lets the caller pass the own frequency resolved *before* the
    /// session's record was cleared; nil resolves it here.
    func postQRTSpotIfNeeded(for session: LoggingSession, frequency: Double? = nil) async {
        let endCallsign = session.stationCallsign ?? session.myCallsign
        guard potaQRTSpotEnabled,
              session.isPOTA,
              let parkRef = session.parkReference,
              let freq = frequency ?? spotFrequency(for: session),
              !endCallsign.isEmpty
        else {
            return
        }

        let parks = ParkReference.split(parkRef)
        let potaClient = POTAClient(authService: potaAuthService ?? POTAAuthService())

        // Use the first park to check if activation was spotted
        let primaryPark = parks.first ?? parkRef
        do {
            let comments = try await potaClient.fetchSpotComments(
                activator: endCallsign,
                parkRef: primaryPark
            )

            guard !comments.isEmpty else {
                SyncDebugLog.shared.info(
                    "No spots found for \(primaryPark), skipping QRT spot",
                    service: .pota
                )
                return
            }

            // Post QRT spot for each park
            for park in parks {
                do {
                    _ = try await potaClient.postSpot(
                        callsign: endCallsign,
                        reference: park,
                        frequency: freq * 1_000,
                        mode: session.mode,
                        comments: "QRT"
                    )
                    SyncDebugLog.shared.info("QRT spot posted for \(park)", service: .pota)
                } catch {
                    SyncDebugLog.shared.warning(
                        "Failed to post QRT spot for \(park): \(error.localizedDescription)",
                        service: .pota
                    )
                }
            }
        } catch {
            SyncDebugLog.shared.warning(
                "Failed to check spots for QRT: \(error.localizedDescription)",
                service: .pota
            )
        }
    }

    /// Save average WPM from RBN spot comments to ActivationMetadata.
    /// For multi-park, saves to the first (primary) park. Does NOT save — it stages
    /// the mutation and returns the touched `ActivationMetadata` so the caller can
    /// route it through the coordinated session-end seam write (a suppressed save
    /// would otherwise drop it from cw-store in `.on` mode). `nil` if nothing changed.
    @discardableResult
    func saveAverageWPM(from comments: [POTASpotComment], session: LoggingSession) -> ActivationMetadata? {
        guard let parkRef = session.parkReference, !parkRef.isEmpty else {
            return nil
        }

        let wpms = comments.compactMap(\.wpm)
        guard !wpms.isEmpty else {
            return nil
        }

        let avgWPM = wpms.reduce(0, +) / wpms.count

        // Use first park for metadata storage
        let primaryPark = ParkReference.split(parkRef).first ?? parkRef

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.startOfDay(for: session.startedAt)

        var descriptor = FetchDescriptor<ActivationMetadata>(
            predicate: #Predicate {
                $0.parkReference == primaryPark && $0.date == date
            }
        )
        descriptor.fetchLimit = 1
        let existing = (try? modelContext.fetch(descriptor))?.first

        if let existing {
            existing.averageWPM = avgWPM
            return existing
        }
        let metadata = ActivationMetadata(
            parkReference: primaryPark, date: date, averageWPM: avgWPM
        )
        modelContext.insert(metadata)
        return metadata
    }
}
