// SessionsView POTA Actions, Data Loading, and Helpers
//
// Extracted from SessionsView to keep under the 500-line file limit.

import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - Data Loading

extension SessionsView {
    func loadSessions() async {
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.statusRawValue == "completed" },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200

        sessions = (try? modelContext.fetch(descriptor)) ?? []

        // Load QSOs per session
        var qsoMap: [UUID: [QSO]] = [:]
        var activationMap: [UUID: POTAActivation] = [:]

        for session in sessions {
            let sessionId = session.id
            var qsoDescriptor = FetchDescriptor<QSO>(
                predicate: #Predicate {
                    $0.loggingSessionId == sessionId && !$0.isHidden
                },
                sortBy: [SortDescriptor(\.timestamp)]
            )
            qsoDescriptor.fetchLimit = 500
            let qsos = (try? modelContext.fetch(qsoDescriptor)) ?? []
            qsoMap[sessionId] = qsos

            // Build POTAActivation for POTA sessions
            if session.activationType == .pota, !qsos.isEmpty {
                let grouped = POTAActivation.groupQSOs(qsos)
                if let activation = grouped.first {
                    activationMap[sessionId] = activation
                }
            }

            await Task.yield()
        }

        qsosBySessionId = qsoMap
        activationsBySessionId = activationMap

        loadMetadata()
        rebuildJobIndex()
    }

    /// Load POTA activations that don't have a matching LoggingSession
    func loadOrphanActivations() async {
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate { $0.parkReference != nil && !$0.isHidden }
        )
        descriptor.fetchLimit = 5000
        let parkQSOs = (try? modelContext.fetch(descriptor)) ?? []

        let sessionIds = Set(sessions.map(\.id))

        let orphanQSOs = parkQSOs.filter { qso in
            guard let sid = qso.loggingSessionId else { return true }
            return !sessionIds.contains(sid)
        }

        let allOrphan = POTAActivation.groupQSOs(orphanQSOs)
        let sessionActivationIds = Set(activationsBySessionId.values.map(\.id))
        orphanActivations = allOrphan.filter { !sessionActivationIds.contains($0.id) }

        rebuildJobIndex()
    }

    func loadRecordings() async {
        let sessionIds = sessions.map(\.id)
        guard !sessionIds.isEmpty else { return }

        let recordings = (try? WebSDRRecording.findRecordings(
            forSessionIds: sessionIds, in: modelContext
        )) ?? []

        var dict: [UUID: WebSDRRecording] = [:]
        for recording in recordings {
            dict[recording.loggingSessionId] = recording
        }
        recordingsBySessionId = dict
    }

    func loadMetadata() {
        let descriptor = FetchDescriptor<ActivationMetadata>()
        let allMetadata = (try? modelContext.fetch(descriptor)) ?? []

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")

        var dict: [String: ActivationMetadata] = [:]
        for item in allMetadata {
            let dateStr = formatter.string(from: item.date)
            dict["\(item.parkReference)|\(dateStr)"] = item
        }
        metadataByKey = dict
    }

    func loadCachedParkNames() async {
        await POTAParksCache.shared.ensureLoaded()
        let activations = Array(activationsBySessionId.values) + orphanActivations
        var names: [String: String] = [:]
        for activation in activations {
            let ref = activation.parkReference.uppercased()
            if let name = await POTAParksCache.shared.name(for: ref) {
                names[ref] = name
            }
        }
        await MainActor.run {
            cachedParkNames = names
        }
    }
}

// MARK: - POTA Actions

extension SessionsView {
    func refreshJobs() async {
        guard isAuthenticated, let potaClient else { return }
        isLoadingJobs = true
        errorMessage = nil

        do {
            let fetchedJobs = try await potaClient.fetchJobs()
            await MainActor.run {
                jobs = fetchedJobs
                rebuildJobIndex()
                let didReconcile = confirmUploadsFromJobs()
                if didReconcile {
                    Task {
                        await loadSessions()
                        await loadOrphanActivations()
                    }
                }
            }
        } catch POTAError.notAuthenticated {
            await MainActor.run {
                errorMessage = "Session expired. Please re-authenticate in Settings."
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }

        await MainActor.run { isLoadingJobs = false }
    }

    func performUploadReturningErrors(
        for activation: POTAActivation
    ) async -> [String: String] {
        guard let potaClient else { return ["": "POTA client not available"] }

        let parksToUpload = activation.parksNeedingUpload
        guard !parksToUpload.isEmpty else { return [:] }

        var errors: [String: String] = [:]
        for park in parksToUpload {
            let pendingQSOs = activation.pendingQSOs(forPark: park)
            guard !pendingQSOs.isEmpty else { continue }

            do {
                let result = try await potaClient.uploadActivationWithRecording(
                    parkReference: park, qsos: pendingQSOs, modelContext: modelContext
                )
                if result.success {
                    for qso in pendingQSOs {
                        qso.markSubmittedToPark(park, context: modelContext)
                    }
                } else {
                    errors[park] = "Upload returned success=false"
                }
            } catch {
                errors[park] = error.localizedDescription
            }
        }

        await refreshJobs()
        return errors
    }

    func rejectActivation(_ activation: POTAActivation) {
        for qso in activation.pendingQSOs() {
            qso.markUploadRejected(for: .pota, context: modelContext)
        }
        activationToReject = nil
        Task {
            await loadSessions()
            await loadOrphanActivations()
        }
    }

    func forceReupload(_ activation: POTAActivation) {
        for qso in activation.qsos {
            for park in activation.parks {
                qso.forceResetParkUpload(park, context: modelContext)
            }
        }
        try? modelContext.save()
        Task {
            await loadSessions()
            await loadOrphanActivations()
            if let fresh = allActivations.first(where: { $0.id == activation.id }) {
                _ = await performUploadReturningErrors(for: fresh)
            }
            await loadSessions()
            await loadOrphanActivations()
        }
    }

    @discardableResult
    func confirmUploadsFromJobs() -> Bool {
        var changed = false
        for activation in allActivations {
            let matching = jobsByActivationId[activation.id] ?? []
            guard !matching.isEmpty else { continue }

            let hasCompleted = matching.contains { $0.status == .completed }
            let hasFailed = !hasCompleted && matching.contains { $0.status.isFailure }

            for park in activation.parks {
                if hasCompleted {
                    for qso in activation.qsos where !qso.isUploadedToPark(park) {
                        qso.confirmUploadedToPark(park, context: modelContext)
                        changed = true
                    }
                } else if hasFailed {
                    for qso in activation.qsos where qso.isSubmittedToPark(park) {
                        qso.resetSubmittedToPark(park, context: modelContext)
                        changed = true
                    }
                }
            }
        }
        if changed { try? modelContext.save() }
        return changed
    }

    func rebuildJobIndex() {
        var index: [String: [POTAJob]] = [:]
        for activation in allActivations {
            let matching = activation.matchingJobs(from: jobs)
            if !matching.isEmpty {
                index[activation.id] = matching
            }
        }
        jobsByActivationId = index
    }

    // MARK: - Helpers

    func parkName(for reference: String) -> String? {
        if let name = jobs.first(where: {
            $0.reference.uppercased() == reference.uppercased()
        })?.parkName {
            return name
        }
        return cachedParkNames[reference.uppercased()]
    }

    func activationMetadata(for activation: POTAActivation) -> ActivationMetadata? {
        metadataByKey["\(activation.parkReference)|\(activation.utcDateString)"]
    }

    func saveMetadataEdit(
        _ result: ActivationMetadataEditResult, for activation: POTAActivation
    ) {
        let sanitizedNewPark = result.newParkReference.flatMap {
            ParkReference.sanitizeMulti($0)
        }
        let parkRef = sanitizedNewPark ?? activation.parkReference

        if let newPark = sanitizedNewPark {
            for qso in activation.qsos {
                qso.parkReference = newPark
                let potaPresence = qso.potaPresenceRecords()
                for presence in potaPresence {
                    modelContext.delete(presence)
                }
            }
        }

        let existingMetadata = activationMetadata(for: activation)
        let meta: ActivationMetadata
        if let existing = existingMetadata {
            meta = existing
            if result.newParkReference != nil {
                meta.parkReference = parkRef
            }
        } else {
            meta = ActivationMetadata(parkReference: parkRef, date: activation.utcDate)
            modelContext.insert(meta)
        }

        meta.title = result.title
        meta.watts = result.watts

        if let session = findSession(for: activation) {
            applySessionEdits(result, to: session)
        }

        for qso in activation.qsos {
            qso.myRig = result.radio
        }

        try? modelContext.save()

        Task {
            await loadSessions()
            await loadOrphanActivations()
            await loadCachedParkNames()
        }
    }

    func applySessionEdits(
        _ result: ActivationMetadataEditResult, to session: LoggingSession
    ) {
        session.myRig = result.radio
        session.myAntenna = result.antenna
        session.myKey = result.key
        session.myMic = result.mic
        session.extraEquipment = result.extraEquipment
        session.attendees = result.attendees
        session.notes = result.notes

        for photo in result.addedPhotos {
            if let filename = try? SessionPhotoManager.savePhoto(
                photo, sessionID: session.id
            ) {
                session.photoFilenames.append(filename)
            }
        }
        for filename in result.deletedPhotoFilenames {
            try? SessionPhotoManager.deletePhoto(
                filename: filename, sessionID: session.id
            )
            session.photoFilenames.removeAll { $0 == filename }
        }
    }

    func findSession(for activation: POTAActivation) -> LoggingSession? {
        guard let sessionId = activation.qsos.compactMap(\.loggingSessionId).first else {
            return nil
        }
        return sessions.first { $0.id == sessionId }
    }

    func engineFor(_ sessionId: UUID) -> RecordingPlaybackEngine {
        if let existing = engines[sessionId] {
            return existing
        }
        let engine = RecordingPlaybackEngine()
        engines[sessionId] = engine
        return engine
    }

    func startMaintenanceTimer() {
        updateMaintenanceTime()
        maintenanceTimer = Timer.scheduledTimer(
            withTimeInterval: 60, repeats: true
        ) { [self] _ in
            Task { @MainActor in updateMaintenanceTime() }
        }
    }

    func stopMaintenanceTimer() {
        maintenanceTimer?.invalidate()
        maintenanceTimer = nil
    }

    func updateMaintenanceTime() {
        maintenanceTimeRemaining = POTAClient.formatMaintenanceTimeRemaining()
    }
}

// MARK: - Share Card Generation

extension SessionsView {
    func generateAndShare(activation: POTAActivation) async {
        isGeneratingShareImage = true
        let meta = activationMetadata(for: activation)
        let name = parkName(for: activation.parkReference)

        let renderer = ActivationShareRenderer()
        if let image = await renderer.render(
            activation: activation,
            metadata: meta,
            parkName: name
        ) {
            sharePreviewData = SharePreviewData(
                image: image,
                activation: activation,
                parkName: name
            )
        }
        isGeneratingShareImage = false
        activationToShare = nil
    }
}
