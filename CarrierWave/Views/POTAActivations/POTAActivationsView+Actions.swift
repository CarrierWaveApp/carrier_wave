// POTA Activations View - Actions and Subviews
//
// Extensions containing subview builders, helper methods, and action methods
// for POTAActivationsContentView.

import CarrierWaveCore
import SwiftData
import SwiftUI
import UIKit

// MARK: - Subviews

extension POTAActivationsContentView {
    var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Activations", systemImage: "tree")
        } description: {
            Text("QSOs with park references will appear here grouped by activation.")
        }
    }

    @ViewBuilder var shareImageOverlay: some View {
        if isGeneratingShareImage {
            Color.black.opacity(0.4).ignoresSafeArea().overlay {
                VStack(spacing: 16) {
                    ProgressView().scaleEffect(1.5).tint(.white)
                    Text("Generating share image...").foregroundStyle(.white)
                }.padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    var maintenanceBanner: some View {
        HStack {
            Image(systemName: "wrench.and.screwdriver").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("POTA Maintenance Window").font(.subheadline).fontWeight(.medium)
                Text(
                    maintenanceTimeRemaining.map { "Uploads disabled. Resumes in \($0)" }
                        ?? "Uploads temporarily disabled (2330-0400 UTC)"
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    var activationsList: some View {
        List {
            if let progress = bulkUploadProgress {
                Section {
                    BulkUploadProgressBanner(
                        progress: progress,
                        onCancel: { bulkUploadProgress?.isCancelled = true }
                    )
                }
            }

            if isInMaintenance {
                Section {
                    maintenanceBanner
                }
            }

            if let error = errorMessage {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                        Spacer()
                        Button("Retry") {
                            Task { await refreshJobs() }
                        }
                        .font(.caption)
                    }
                }
            }

            // Ready to Upload section - pending activations sorted by date
            if !pendingActivations.isEmpty, isAuthenticated, !isSelecting {
                Section {
                    ForEach(pendingActivations) { activation in
                        activationRow(activation)
                    }
                } header: {
                    Label("Ready to Upload", systemImage: "arrow.up.circle")
                }
            }

            // All activations grouped by date
            ForEach(activationsByDate, id: \.date) { dateGroup in
                Section {
                    ForEach(dateGroup.activations) { activation in
                        activationRow(activation)
                    }
                } header: {
                    Text(dateGroup.date)
                }
            }
        }
        .refreshable {
            await refreshJobs()
        }
        .navigationDestination(for: POTAActivation.self) { activation in
            POTAActivationDetailView(
                activation: activation,
                metadata: metadata(for: activation),
                parkName: parkName(for: activation.parkReference),
                matchingJobs: jobsByActivationId[activation.id] ?? [],
                potaClient: potaClient,
                isAuthenticated: isAuthenticated,
                isInMaintenance: isInMaintenance,
                onUpload: { await performUploadReturningErrors(for: activation) },
                onReject: { activationToReject = activation },
                onEdit: { activationToEdit = activation },
                onShare: { activationToShare = activation },
                onExport: { activationToExport = activation },
                onMap: { activationToMap = activation },
                onForceReupload: { forceReupload(activation) }
            )
        }
    }

    @ViewBuilder
    func activationRow(_ activation: POTAActivation) -> some View {
        let jobs = jobsByActivationId[activation.id] ?? []
        let row = ActivationRow(
            activation: activation,
            metadata: metadata(for: activation),
            isUploadDisabled: isInMaintenance || potaClient == nil,
            showUploadButton: isAuthenticated,
            onUploadTapped: { await performUploadReturningErrors(for: activation) },
            onRejectTapped: { activationToReject = activation },
            onShareTapped: { activationToShare = activation },
            onExportTapped: { activationToExport = activation },
            onMapTapped: { activationToMap = activation },
            onEditTapped: { activationToEdit = activation },
            onForceReuploadTapped: { forceReupload(activation) },
            parkName: parkName(for: activation.parkReference),
            hasFailedJob: jobs.contains { $0.status.isFailure },
            hasCompletedJob: jobs.contains { $0.status == .completed },
            isSelecting: isSelecting,
            isSelected: selectedActivationIds.contains(activation.id),
            onSelectionToggled: {
                if selectedActivationIds.contains(activation.id) {
                    selectedActivationIds.remove(activation.id)
                } else {
                    selectedActivationIds.insert(activation.id)
                }
            }
        )

        if isSelecting {
            row
        } else {
            NavigationLink(value: activation) {
                row
            }
        }
    }

    func startMaintenanceTimer() {
        updateMaintenanceTime()
        maintenanceTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [self] _ in
            Task { @MainActor in
                updateMaintenanceTime()
            }
        }
    }

    func stopMaintenanceTimer() {
        maintenanceTimer?.invalidate()
        maintenanceTimer = nil
    }

    func updateMaintenanceTime() {
        maintenanceTimeRemaining = POTAClient.formatMaintenanceTimeRemaining()
    }

    func parkName(for reference: String) -> String? {
        // First try from fetched jobs (most accurate for user's parks)
        if let name = jobs.first(where: {
            $0.reference.uppercased() == reference.uppercased()
        })?.parkName {
            return name
        }
        // Fall back to cached park names
        return cachedParkNames[reference.uppercased()]
    }

    func metadata(for activation: POTAActivation) -> ActivationMetadata? {
        metadataByKey["\(activation.parkReference)|\(activation.utcDateString)"]
    }

    func rejectMessage(for parkDisplay: String, pendingCount: Int) -> String {
        """
        Reject upload for \(parkDisplay)?

        This will hide \(pendingCount) QSO(s) from POTA uploads. \
        They will remain in your log but won't be prompted for upload again.
        """
    }
}

// MARK: - Upload & Reject Actions

extension POTAActivationsContentView {
    /// Upload an activation and return errors for display in the calling view.
    func performUploadReturningErrors(for activation: POTAActivation) async -> [String: String] {
        await performUpload(for: activation)
        return uploadErrorsByActivation[activation.id] ?? [:]
    }

    /// Upload an activation to POTA. Called from ActivationRow's upload button.
    func performUpload(for activation: POTAActivation) async {
        let debugLog = SyncDebugLog.shared
        guard let potaClient else {
            debugLog.error("performUpload: POTA client not available", service: .pota)
            errorMessage = "POTA client not available."
            return
        }

        let parksToUpload = activation.parksNeedingUpload
        guard !parksToUpload.isEmpty else {
            return
        }

        debugLog.info(
            "performUpload: \(activation.parkReference) - "
                + "\(parksToUpload.count) park(s), \(activation.pendingCount) pending",
            service: .pota
        )

        var errors: [String: String] = [:]
        for park in parksToUpload {
            if let error = await uploadPark(park, activation: activation, client: potaClient) {
                errors[park] = error
            }
        }

        // Refresh jobs to reconcile — upload API may return success=false for
        // duplicates even though the job completed.
        await refreshJobs()
        reconcileUploadErrors(errors, for: activation)
    }

    /// After upload + job refresh, check if POTA job log confirms the upload.
    /// Clears errors if a completed job exists for the activation.
    private func reconcileUploadErrors(_ errors: [String: String], for activation: POTAActivation) {
        let debugLog = SyncDebugLog.shared
        let matchingJobs = jobsByActivationId[activation.id] ?? []
        if matchingJobs.contains(where: { $0.status == .completed }) {
            uploadErrorsByActivation.removeValue(forKey: activation.id)
            debugLog.info(
                "performUpload: job confirmed \(activation.parkReference)"
                    + " (cleared \(errors.count) error(s))",
                service: .pota
            )
        } else if errors.isEmpty {
            uploadErrorsByActivation.removeValue(forKey: activation.id)
        } else {
            uploadErrorsByActivation[activation.id] = errors
            errorMessage = "Upload failed for \(errors.count) park(s)"
            debugLog.error(
                "performUpload: \(errors.count) park(s) failed for "
                    + "\(activation.parkReference): "
                    + errors.map { "\($0.key): \($0.value)" }.joined(separator: "; "),
                service: .pota
            )
        }
    }

    func uploadPark(
        _ park: String, activation: POTAActivation, client: POTAClient
    ) async -> String? {
        let debugLog = SyncDebugLog.shared
        let pendingQSOs = activation.pendingQSOs(forPark: park)
        guard !pendingQSOs.isEmpty else {
            debugLog.debug("uploadPark: no pending QSOs for park \(park)", service: .pota)
            return nil
        }

        debugLog.info(
            "uploadPark: uploading \(pendingQSOs.count) QSO(s) to park \(park)",
            service: .pota
        )
        logPendingParkQSOs(pendingQSOs, park: park)

        do {
            let result = try await client.uploadActivationWithRecording(
                parkReference: park, qsos: pendingQSOs, modelContext: modelContext
            )
            debugLog.info(
                "uploadPark: result for \(park) - success=\(result.success), "
                    + "qsosAccepted=\(result.qsosAccepted), "
                    + "message=\(result.message ?? "nil")",
                service: .pota
            )
            if result.success {
                markQSOsSubmitted(pendingQSOs, park: park)
                return nil
            }
            debugLog.warning(
                "uploadPark: upload returned success=false for \(park)", service: .pota
            )
            return "Upload returned success=false"
        } catch {
            debugLog.error(
                "uploadPark: exception for \(park): \(error.localizedDescription)",
                service: .pota
            )
            return error.localizedDescription
        }
    }

    /// Log summary of pending QSOs before upload
    func logPendingParkQSOs(_ qsos: [QSO], park: String) {
        let debugLog = SyncDebugLog.shared
        debugLog.debug(
            "uploadPark: \(qsos.count) QSO(s) pending for \(park)", service: .pota
        )
    }

    /// Mark QSOs as submitted to a park
    @MainActor
    func markQSOsSubmitted(_ qsos: [QSO], park: String) {
        for qso in qsos {
            qso.markSubmittedToPark(park, context: modelContext)
        }
    }

    func rejectActivation(_ activation: POTAActivation) {
        let pendingQSOs = activation.pendingQSOs()
        for qso in pendingQSOs {
            qso.markUploadRejected(for: .pota, context: modelContext)
        }
        activationToReject = nil
    }

    /// Force reset all QSOs in an activation back to needing upload, then upload (debug feature)
    func forceReupload(_ activation: POTAActivation) {
        let debugLog = SyncDebugLog.shared
        debugLog.info(
            "forceReupload: resetting \(activation.qsoCount) QSO(s) for "
                + "\(activation.parkReference) "
                + "parks=\(activation.parks.joined(separator: ", "))",
            service: .pota
        )

        for qso in activation.qsos {
            for park in activation.parks {
                qso.forceResetParkUpload(park, context: modelContext)
            }
        }

        try? modelContext.save()
        debugLog.info(
            "forceReupload: reset complete for \(activation.parkReference), triggering upload",
            service: .pota
        )

        // Reload QSOs then trigger the actual upload
        Task {
            await loadParkQSOs()
            let freshActivation = rebuildActivation(matching: activation)
            await performUpload(for: freshActivation ?? activation)
            await loadParkQSOs()
        }
    }

    /// Rebuild an activation from the current allParkQSOs to pick up fresh presence state
    func rebuildActivation(matching original: POTAActivation) -> POTAActivation? {
        let matchingQSOs = allParkQSOs.filter { qso in
            guard let ref = qso.parkReference else {
                return false
            }
            return original.parks.contains(where: { ParkReference.hasOverlap(ref, $0) })
        }
        guard !matchingQSOs.isEmpty else {
            return nil
        }
        return POTAActivation(
            parkReference: original.parkReference,
            utcDate: original.utcDate,
            callsign: original.callsign,
            qsos: matchingQSOs
        )
    }
}

// MARK: - Metadata & Share Actions

extension POTAActivationsContentView {
    /// Save metadata edits for an activation
    func saveMetadataEdit(
        _ result: ActivationMetadataEditResult, for activation: POTAActivation
    ) {
        let sanitizedNewPark = result.newParkReference.flatMap { ParkReference.sanitizeMulti($0) }
        let parkRef = sanitizedNewPark ?? activation.parkReference

        // Handle park reference change
        if let newPark = sanitizedNewPark {
            for qso in activation.qsos {
                qso.parkReference = newPark
                let potaPresence = qso.potaPresenceRecords()
                for presence in potaPresence {
                    modelContext.delete(presence)
                }
            }
        }

        // Find or create metadata record
        let existingMetadata = metadata(for: activation)
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

        // Apply radio to all QSOs in the activation
        for qso in activation.qsos {
            qso.myRig = result.radio
        }

        try? modelContext.save()

        Task {
            await loadParkQSOs()
            await loadCachedParkNames()
        }
    }

    func generateAndShare(activation: POTAActivation) async {
        isGeneratingShareImage = true
        activationToShare = nil

        let image = await ActivationShareRenderer.renderWithMap(
            activation: activation,
            parkName: parkName(for: activation.parkReference),
            myGrid: activation.qsos.first?.myGrid,
            metadata: metadata(for: activation)
        )

        isGeneratingShareImage = false

        guard let image else {
            return
        }

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootVC = window.rootViewController
        else {
            return
        }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        let activityVC = UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )

        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(
                x: topVC.view.bounds.midX,
                y: topVC.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }

        topVC.present(activityVC, animated: true)
    }
}
