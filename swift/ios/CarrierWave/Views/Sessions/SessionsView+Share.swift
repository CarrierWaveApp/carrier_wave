// SessionsView Brag Sheet Generation
//
// Extracted from SessionsView+Actions to keep under the 500-line file limit.

import CarrierWaveData
import SwiftUI

// MARK: - ActivationExportRequest

/// View modifier that owns the share/export sheets + onChange handlers for the
/// Sessions tab. Pulled out of `SessionsView.body` to keep that file under
/// SwiftLint's file-length limit.
/// What the activation-keyed ADIF export sheet is opened for. `session` is
/// set when the export was asked for from a logging session (row menu or
/// detail view): the sheet then writes the whole session through Rust, keyed
/// by session id, and uses `activation` only for the header and stats it
/// shows. Orphan activations (no session) leave it nil.
struct ActivationExportRequest: Identifiable {
    let activation: POTAActivation
    var session: LoggingSession?

    var id: String {
        activation.id
    }
}

// MARK: - SessionsViewShareAndExport

struct SessionsViewShareAndExport: ViewModifier {
    @Binding var activationToShare: POTAActivation?
    @Binding var sessionToShare: LoggingSession?
    @Binding var activationToExport: ActivationExportRequest?
    @Binding var sessionToExportADIF: LoggingSession?

    let onShareActivation: (POTAActivation) -> Void
    let onShareSession: (LoggingSession) -> Void
    let activationExportSheet: (ActivationExportRequest) -> ADIFExportSheet
    let sessionExportSheet: (LoggingSession) -> SessionADIFExportSheet

    func body(content: Content) -> some View {
        content
            .onChange(of: activationToShare) { _, new in
                if let new {
                    onShareActivation(new)
                }
            }
            .onChange(of: sessionToShare) { _, new in
                if let new {
                    onShareSession(new)
                }
            }
            .sheet(item: $activationToExport) { activationExportSheet($0) }
            .sheet(item: $sessionToExportADIF) { sessionExportSheet($0) }
    }
}

extension SessionsView {
    func generateAndShare(activation: POTAActivation) async {
        isGeneratingShareImage = true
        let meta = activationMetadata(for: activation)
        let name = parkName(for: activation.parkReference)
        let equipmentList = buildEquipmentList(for: activation)

        let statisticianMode = UserDefaults.standard.bool(
            forKey: "statisticianMode"
        )
        let advancedStats: ActivationStatistics? =
            if statisticianMode {
                ActivationStatistics.compute(from: activation, metadata: meta)
            } else {
                nil
            }

        let render: @MainActor () async -> UIImage? = {
            await ActivationShareRenderer.renderWithMap(
                source: .pota(activation: activation, parkName: name),
                myGrid: activation.qsos.first?.myGrid,
                metadata: meta,
                equipment: equipmentList,
                statisticianStats: advancedStats
            )
        }
        if let image = await render() {
            sharePreviewData = SharePreviewData(
                image: image,
                activation: activation,
                parkName: name,
                referenceLabel: activation.parkReference,
                referenceIcon: "tree",
                displayDate: activation.displayDate,
                qsos: activation.qsos,
                rerender: render
            )
        }
        isGeneratingShareImage = false
        activationToShare = nil
    }

    func showMap(session: LoggingSession, activations: [POTAActivation]) {
        if session.isRove, activations.count > 1 {
            roveStopsForMap = session.mergedRoveStops
            activationToMap = mergedRoveActivation(activations)
        } else if let act = activations.first {
            activationToMap = act
        }
    }

    func sessionDetailForActivation(
        _ activation: POTAActivation, session: LoggingSession
    ) -> SessionDetailView {
        let jobs = jobsByActivationId[activation.id] ?? []
        let qsos = qsosBySessionId[session.id] ?? []
        return SessionDetailView(
            session: session,
            onShare: { activationToShare = activation },
            onExport: {
                exportSessionADIF(
                    session: session,
                    activations: activationsBySessionId[session.id] ?? [activation]
                )
            },
            onImport: { sessionToImport = session },
            onReopen: { performReopen(session) },
            onMerge: { sessionToMerge = session },
            activation: activation,
            activationMetadata: activationMetadata(for: activation),
            parkName: parkName(for: activation.parkReference),
            matchingJobs: jobs,
            potaClient: potaClient,
            isAuthenticated: isAuthenticated,
            isInMaintenance: isInMaintenance,
            onUpload: {
                await performUploadReturningErrors(for: activation)
            },
            onReject: { rejectActivation(activation) },
            onForceReupload: { forceReupload(activation) },
            qrzUploadCount: qrzPendingBySessionId[session.id] ?? 0,
            onQRZUpload: buildQRZUploadHandler(qsos: qsos)
        )
    }

    func roveSessionDetail(
        session: LoggingSession, activations: [POTAActivation]
    ) -> SessionDetailView {
        let primary = activations.first
        let merged = activations.count > 1
            ? mergedRoveActivation(activations) : primary
        let jobs = primary.flatMap { jobsByActivationId[$0.id] ?? [] } ?? []
        let meta = primary.flatMap { activationMetadata(for: $0) }

        return SessionDetailView(
            session: session,
            onShare: activations.isEmpty ? nil : {
                if activations.count > 1 {
                    activationToShare = mergedRoveActivation(activations)
                } else if let act = activations.first {
                    activationToShare = act
                }
            },
            onExport: activations.isEmpty ? nil : {
                exportSessionADIF(session: session, activations: activations)
            },
            onImport: { sessionToImport = session },
            onReopen: { performReopen(session) },
            onMerge: { sessionToMerge = session },
            activation: merged,
            activationMetadata: meta,
            parkName: primary.flatMap {
                parkName(for: $0.parkReference)
            },
            matchingJobs: jobs,
            potaClient: potaClient,
            isAuthenticated: isAuthenticated,
            isInMaintenance: isInMaintenance,
            onUpload: primary.map { act in
                { await performUploadReturningErrors(for: act) }
            },
            onReject: primary.map { act in
                { rejectActivation(act) }
            },
            onForceReupload: primary.map { act in
                { forceReupload(act) }
            },
            qrzUploadCount: qrzPendingBySessionId[session.id] ?? 0,
            onQRZUpload: buildQRZUploadHandler(
                qsos: qsosBySessionId[session.id] ?? []
            )
        )
    }

    /// Wraps the activation-keyed POTA export sheet so the parent view's body
    /// stays compact (SwiftLint 500-line cap).
    func activationADIFExportSheet(for request: ActivationExportRequest) -> ADIFExportSheet {
        ADIFExportSheet(
            activation: request.activation,
            parkName: parkName(for: request.activation.parkReference),
            session: request.session
        )
    }

    /// Bundle of share/export bindings + sheets — applied via `.modifier(...)`
    /// from the parent body so the activation/session share-and-export wiring
    /// doesn't bloat `SessionsView.swift` past SwiftLint's 500-line cap.
    var shareAndExportModifiers: some ViewModifier {
        SessionsViewShareAndExport(
            activationToShare: $activationToShare,
            sessionToShare: $sessionToShare,
            activationToExport: $activationToExport,
            sessionToExportADIF: $sessionToExportADIF,
            onShareActivation: { activation in
                Task { await generateAndShare(activation: activation) }
            },
            onShareSession: { session in
                Task { await generateAndShare(session: session) }
            },
            activationExportSheet: { activationADIFExportSheet(for: $0) },
            sessionExportSheet: { sessionADIFExportSheet(for: $0) }
        )
    }

    /// Session-level "Export ADIF" for POTA sessions. The file is written by
    /// Rust keyed on the session id, so a merged session that spans UTC
    /// midnight or two parks, a rove, or casual QSOs merged into a park
    /// session all come out together — the activation-keyed path re-scoped
    /// to one (park, callsign, UTC day) and silently dropped the rest. A
    /// session whose QSOs group into several activations shows the merged
    /// rove-style summary in the sheet header.
    func exportSessionADIF(session: LoggingSession, activations: [POTAActivation]) {
        guard !activations.isEmpty else {
            return
        }
        let summary = activations.count > 1 ? mergedRoveActivation(activations) : activations[0]
        activationToExport = ActivationExportRequest(activation: summary, session: session)
    }

    /// Builds the `SessionADIFExportSheet` with the SOTA summit name resolved
    /// from cache. Extracted from `SessionsView.body` to keep that file under
    /// SwiftLint's 500-line limit.
    func sessionADIFExportSheet(for session: LoggingSession) -> SessionADIFExportSheet {
        SessionADIFExportSheet(
            session: session,
            qsos: qsosBySessionId[session.id] ?? [],
            summitName: session.sotaReference.flatMap {
                SOTASummitsCache.shared.lookupSummit($0)?.name
            }
        )
    }

    func nonPOTASessionDetail(_ session: LoggingSession) -> SessionDetailView {
        let qsos = qsosBySessionId[session.id] ?? []
        let canShare = session.isSOTA || session.isPOTA
        return SessionDetailView(
            session: session,
            // SOTA (or any non-POTA) sessions get the unified share-card and
            // ADIF export — POTA-only sessions still go through the
            // activation-keyed `roveSessionDetail` / `sessionDetailForActivation`.
            onShare: canShare ? { sessionToShare = session } : nil,
            onExport: { sessionToExportADIF = session },
            onImport: { sessionToImport = session },
            onReopen: { performReopen(session) },
            onMerge: { sessionToMerge = session },
            qrzUploadCount: qrzPendingBySessionId[session.id] ?? 0,
            onQRZUpload: buildQRZUploadHandler(qsos: qsos)
        )
    }

    /// Render the unified share card from a session (SOTA-only path) and
    /// surface it through the same preview sheet POTA uses. The preview's
    /// activation field stays nil so the caption only references the session.
    func generateAndShare(session: LoggingSession) async {
        isGeneratingShareImage = true
        let qsos = qsosBySessionId[session.id] ?? []
        let summitName = session.sotaReference
            .flatMap { SOTASummitsCache.shared.lookupSummit($0)?.name }

        guard let source = BragSheetSource.session(
            session, qsos: qsos, summitName: summitName
        ) else {
            isGeneratingShareImage = false
            sessionToShare = nil
            return
        }

        let myGrid = qsos.first?.myGrid ?? session.myGrid

        let render: @MainActor () async -> UIImage? = {
            await ActivationShareRenderer.renderWithMap(
                source: source,
                myGrid: myGrid
            )
        }
        if let image = await render() {
            sharePreviewData = SharePreviewData(
                image: image,
                activation: nil,
                parkName: source.referenceName,
                referenceLabel: source.referenceCode,
                referenceIcon: source.referenceIcon,
                displayDate: source.displayDate,
                qsos: qsos,
                rerender: render
            )
        }
        isGeneratingShareImage = false
        sessionToShare = nil
    }

    func buildEquipmentList(
        for activation: POTAActivation
    ) -> [ShareCardEquipmentItem] {
        let includeEquipment = UserDefaults.standard.object(
            forKey: "shareCardIncludeEquipment"
        ) as? Bool ?? true
        guard includeEquipment else {
            return []
        }

        guard let session = findSession(for: activation) else {
            return []
        }

        var items: [ShareCardEquipmentItem] = []
        if let antenna = session.myAntenna, !antenna.isEmpty {
            items.append(ShareCardEquipmentItem(
                icon: "antenna.radiowaves.left.and.right", text: antenna
            ))
        }
        if let key = session.myKey, !key.isEmpty {
            items.append(ShareCardEquipmentItem(
                icon: "pianokeys", text: key
            ))
        }
        if let mic = session.myMic, !mic.isEmpty {
            items.append(ShareCardEquipmentItem(
                icon: "mic.fill", text: mic
            ))
        }
        if let extra = session.extraEquipment, !extra.isEmpty {
            items.append(ShareCardEquipmentItem(
                icon: "wrench.and.screwdriver", text: extra
            ))
        }
        return items
    }

    // MARK: - Row Builder Helpers

    func buildQRZUploadHandler(
        qsos: [QSO]
    ) -> (() async -> String?)? {
        guard hasQRZApiKey, qsos.contains(where: { $0.needsUpload(to: .qrz) }) else {
            return nil
        }
        return {
            await performQRZUpload(qsos: qsos)
        }
    }

    func buildShareHandler(
        session: LoggingSession,
        activations: [POTAActivation]
    ) -> (() -> Void)? {
        guard activations.first != nil else {
            return nil
        }
        return {
            if session.isRove, activations.count > 1 {
                activationToShare = mergedRoveActivation(activations)
            } else if let act = activations.first {
                activationToShare = act
            }
        }
    }
}
