import CarrierWaveCore
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
              session.activationType == .pota
        else {
            return
        }

        // Post an initial spot immediately
        Task {
            await postSpot()
        }

        // Schedule recurring spots every 10 minutes
        autoSpotTimer = Timer.scheduledTimer(
            withTimeInterval: autoSpotInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.postSpot()
            }
        }
    }

    /// Stop the auto-spot timer
    func stopAutoSpotTimer() {
        autoSpotTimer?.invalidate()
        autoSpotTimer = nil
    }

    /// Start spot comments polling for POTA activations
    func startSpotCommentsPolling() {
        guard let session = activeSession,
              session.activationType == .pota,
              let parkRef = session.parkReference
        else {
            return
        }

        let callsign = session.myCallsign
        guard !callsign.isEmpty else {
            return
        }

        spotCommentsService.onNewComments = { [weak self] comments in
            self?.attachSpotComments(comments)
        }

        spotCommentsService.startPolling(
            activator: callsign,
            parkRef: parkRef,
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
                    // Attach comment to QSO
                    let spotNote = "[Spot: \(comment.spotter)] \(commentText)"
                    if let existingNotes = qso.notes, !existingNotes.isEmpty {
                        qso.notes = "\(existingNotes) | \(spotNote)"
                    } else {
                        qso.notes = spotNote
                    }

                    attachedSpotCommentIds.insert(comment.spotId)
                    try? modelContext.save()

                    SyncDebugLog.shared.info(
                        "Attached spot comment from \(comment.spotter) to QSO with \(qso.callsign)",
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

        let callsign = session.myCallsign
        guard !callsign.isEmpty else {
            return
        }

        // Include POTA spots only for POTA activations
        let includePOTA = session.activationType == .pota

        spotMonitoringService.startMonitoring(
            callsign: callsign,
            myGrid: session.myGrid,
            includePOTA: includePOTA
        )
    }

    /// Post a spot to POTA (used for both auto-spots and QSY spots)
    func postSpot(comment: String? = nil, showToast: Bool = false) async {
        guard let session = activeSession, session.activationType == .pota,
              let parkRef = session.parkReference, let freq = session.frequency,
              !session.myCallsign.isEmpty
        else {
            return
        }

        // Validate frequency is within amateur bands before spotting
        let violation = BandPlanService.validate(
            frequencyMHz: freq,
            mode: session.mode,
            license: .extra // Use most permissive for band boundary check
        )
        if let violation, violation.type == .outOfBand {
            SyncDebugLog.shared.warning(
                "Skipping spot: frequency \(FrequencyFormatter.format(freq)) is outside amateur bands",
                service: .pota
            )
            return
        }

        do {
            let potaClient = POTAClient(authService: POTAAuthService())
            _ = try await potaClient.postSpot(
                callsign: session.myCallsign, reference: parkRef,
                frequency: freq * 1_000, mode: session.mode, comments: comment
            )
            let msg = comment != nil ? "\(comment!) spot posted" : "Auto-spot posted"
            SyncDebugLog.shared.info("\(msg) for \(parkRef)", service: .pota)
            if showToast {
                ToastManager.shared.spotPosted(
                    park: parkRef, comment: "QSY to \(FrequencyFormatter.format(freq))"
                )
            }
        } catch {
            SyncDebugLog.shared.error("Spot failed: \(error.localizedDescription)", service: .pota)
        }
    }

    /// Post a QRT spot if enabled and the session had spots
    func postQRTSpotIfNeeded(for session: LoggingSession) async {
        guard potaQRTSpotEnabled,
              session.activationType == .pota,
              let parkRef = session.parkReference,
              let freq = session.frequency,
              !session.myCallsign.isEmpty
        else {
            return
        }

        // Check if this activation has any spots on POTA
        do {
            let potaClient = POTAClient(authService: POTAAuthService())
            let comments = try await potaClient.fetchSpotComments(
                activator: session.myCallsign,
                parkRef: parkRef
            )

            // If there are any spots/comments, the activation was spotted
            guard !comments.isEmpty else {
                SyncDebugLog.shared.info(
                    "No spots found for \(parkRef), skipping QRT spot",
                    service: .pota
                )
                return
            }

            // Post QRT spot
            _ = try await potaClient.postSpot(
                callsign: session.myCallsign,
                reference: parkRef,
                frequency: freq * 1_000,
                mode: session.mode,
                comments: "QRT"
            )

            SyncDebugLog.shared.info("QRT spot posted for \(parkRef)", service: .pota)
        } catch {
            SyncDebugLog.shared.warning(
                "Failed to post QRT spot: \(error.localizedDescription)",
                service: .pota
            )
        }
    }

    /// Save average WPM from RBN spot comments to ActivationMetadata
    func saveAverageWPM(from comments: [POTASpotComment], session: LoggingSession) {
        guard let parkRef = session.parkReference, !parkRef.isEmpty else {
            return
        }

        let wpms = comments.compactMap(\.wpm)
        guard !wpms.isEmpty else {
            return
        }

        let avgWPM = wpms.reduce(0, +) / wpms.count

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.startOfDay(for: session.startedAt)

        let descriptor = FetchDescriptor<ActivationMetadata>()
        let allMetadata = (try? modelContext.fetch(descriptor)) ?? []
        let existing = allMetadata.first { $0.parkReference == parkRef && $0.date == date }

        if let existing {
            existing.averageWPM = avgWPM
        } else {
            let metadata = ActivationMetadata(
                parkReference: parkRef, date: date, averageWPM: avgWPM
            )
            modelContext.insert(metadata)
        }
    }
}
