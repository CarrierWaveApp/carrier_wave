import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - ActivatorLayout

/// Activator layout: shows cold-start wizard when no session is active,
/// or the operating layout (header + logger + spots) when a session is active.
struct ActivatorLayout: View {
    // MARK: Internal

    let radioManager: RadioManager

    @Environment(\.modelContext) var modelContext
    @Environment(SelectionState.self) var selectionState
    @Environment(POTASpotService.self) var spotService
    @State var activeSession: LoggingSession?
    @State var activationFrequencyMHz: Double?
    @State var activationMode: String?

    @AppStorage("myCallsign") var myCallsign = ""
    @AppStorage("potaAutoSpotOnStart") var potaAutoSpotOnStart = false
    @AppStorage("potaReSpotEnabled") var potaReSpotEnabled = false
    @AppStorage("potaReSpotIntervalMinutes") var potaReSpotIntervalMinutes = 30
    @AppStorage("potaSpotCommentTemplate") var potaSpotCommentTemplate = "[MODE] [BAND]"

    var body: some View {
        Group {
            if activeSession != nil {
                operatingLayout
            } else {
                ColdStartView(radioManager: radioManager, onSessionStarted: { session in
                    activationFrequencyMHz = session.frequency
                    activationMode = session.mode
                    applySessionFrequency(session)
                    Task { await loadActiveSession() }
                })
            }
        }
        .task {
            selectionState.activatorEditMode = true
            selectionState.availablePanes = [.qsoLog, .spotList]
            await loadActiveSession()
        }
        .onDisappear {
            selectionState.activatorEditMode = false
            selectionState.availablePanes = []
        }
        // Keep the POTA spot service in lockstep with the active session.
        // The service is shared (SharedEnvironment) and stays around across
        // session transitions, so we have to explicitly re-configure on
        // start and tear down on end — otherwise vim `:spot` and the
        // header button silently no-op (postCurrentSpot throws when the
        // service isn't configured, and the call site uses `try?`).
        .onChange(of: activeSession?.id) { _, _ in syncSpotServiceWithSession() }
        .onChange(of: radioManager.frequency) { _, _ in
            refreshSpotSessionParameters()
            persistRadioStateToSession()
        }
        .onChange(of: radioManager.mode) { _, _ in
            refreshSpotSessionParameters()
            persistRadioStateToSession()
        }
    }

    // MARK: Private

    /// Derive band from activation frequency for spot filter default.
    private var activationBand: String? {
        guard let freq = activationFrequencyMHz else {
            return nil
        }
        return BandUtilities.deriveBand(from: freq * 1_000)
    }

    /// Derive mode filter from activation mode.
    private var activationModeFilter: SpotModeFilter? {
        guard let mode = activationMode?.uppercased() else {
            return nil
        }
        if mode == "CW" {
            return .cw
        }
        if ["SSB", "AM", "FM"].contains(mode) {
            return .phone
        }
        if ["FT8", "FT4", "RTTY", "JTTY", "PSK31", "JS8"].contains(mode) {
            return .digital
        }
        return nil
    }

    private var operatingLayout: some View {
        VStack(spacing: 0) {
            ActivationHeader(onSessionChanged: { await loadActiveSession() })

            Divider()

            VSplitView {
                // Top: Logger (full width)
                VStack(spacing: 0) {
                    ParsedEntryView(
                        radioManager: radioManager,
                        activeSession: activeSession
                    )
                    .padding()

                    Divider()

                    QSOLogTableView(sessionId: activeSession?.id)
                }
                .frame(minHeight: 200)
                .vimPaneFocus(.qsoLog)

                // Bottom: Spots + Map side by side
                HSplitView {
                    SpotListView(
                        initialBand: activationBand,
                        initialMode: activationModeFilter,
                        compact: true
                    )
                    .vimPaneFocus(.spotList)
                    .frame(minWidth: 300)

                    ActivationMapPane(sessionId: activeSession?.id)
                        .frame(minWidth: 250)
                }
                .frame(minHeight: 120)
            }
        }
        .onChange(of: selectionState.logRemovedQSOId) { _, newId in
            guard newId != nil else {
                return
            }
            activeSession?.decrementQSOCount()
        }
    }

    private func loadActiveSession() async {
        let descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate<LoggingSession> { session in
                session.statusRawValue == "active" && session.activationTypeRawValue != "casual"
            },
            sortBy: [SortDescriptor(\LoggingSession.startedAt, order: .reverse)]
        )
        activeSession = try? modelContext.fetch(descriptor).first
        if let session = activeSession {
            recountQSOs(for: session)
            applySessionFrequency(session)
        }
    }

    /// Configure or tear down the shared POTASpotService whenever the
    /// active session changes. Honors `potaAutoSpotOnStart` and
    /// `potaReSpotEnabled` from the POTA settings tab.
    private func syncSpotServiceWithSession() {
        guard let session = activeSession,
              let parkReference = session.parkReference,
              !myCallsign.isEmpty
        else {
            spotService.endSession()
            return
        }
        let frequencyKHz = currentSpotFrequencyKHz(for: session)
        let mode = currentSpotMode(for: session)
        spotService.configureForSession(
            callsign: myCallsign,
            reference: parkReference,
            frequencyKHz: frequencyKHz,
            mode: mode,
            commentTemplate: potaSpotCommentTemplate
        )
        if potaAutoSpotOnStart {
            Task { _ = try? await spotService.postCurrentSpot() }
        }
        if potaReSpotEnabled {
            spotService.startReSpotTimer(
                intervalMinutes: potaReSpotIntervalMinutes,
                parameters: SpotParameters(
                    callsign: myCallsign,
                    reference: parkReference,
                    frequencyKHz: frequencyKHz,
                    mode: mode,
                    comment: spotService.sessionComment
                )
            )
        }
    }

    /// Re-call configureForSession on freq/mode changes so the next
    /// spot uses the radio's current state. The service has no
    /// "update parameter" hook — re-configuring is the path of least
    /// resistance and is cheap (just struct field assignments).
    private func refreshSpotSessionParameters() {
        guard let session = activeSession,
              let parkReference = session.parkReference,
              !myCallsign.isEmpty
        else {
            return
        }
        spotService.configureForSession(
            callsign: myCallsign,
            reference: parkReference,
            frequencyKHz: currentSpotFrequencyKHz(for: session),
            mode: currentSpotMode(for: session),
            commentTemplate: potaSpotCommentTemplate
        )
    }

    /// Prefer live radio frequency (kHz) over the session's stored
    /// frequency so spots reflect QSY's. Falls back to the session
    /// frequency, then 14_074 (a safe FT8-band default) if neither
    /// is available — the API rejects 0.
    private func currentSpotFrequencyKHz(for session: LoggingSession) -> Double {
        if radioManager.frequency > 0 {
            return radioManager.frequency * 1_000
        }
        if let sessionMHz = session.frequency, sessionMHz > 0 {
            return sessionMHz * 1_000
        }
        return 14_074
    }

    private func currentSpotMode(for session: LoggingSession) -> String {
        if !radioManager.mode.isEmpty {
            return radioManager.mode
        }
        return session.mode.isEmpty ? "CW" : session.mode
    }

    /// Push session frequency/mode to RadioManager so QSOs inherit them.
    /// Only applies when no physical radio is providing live frequency data.
    private func applySessionFrequency(_ session: LoggingSession) {
        if !radioManager.isConnected {
            if let freq = session.frequency, freq > 0 {
                radioManager.frequency = freq
            }
            if !session.mode.isEmpty {
                radioManager.mode = session.mode
            }
        }
    }

    /// Mirror manual frequency/mode changes back onto the active session so a
    /// QSY made without a radio survives a session reload — otherwise
    /// `applySessionFrequency` would restore the stale stored value. No-op
    /// while a radio is connected (the poll loop drives those fields then).
    private func persistRadioStateToSession() {
        guard !radioManager.isConnected, let session = activeSession else {
            return
        }
        var changed = false
        if radioManager.frequency > 0, session.frequency != radioManager.frequency {
            session.frequency = radioManager.frequency
            changed = true
        }
        if !radioManager.mode.isEmpty, session.mode != radioManager.mode {
            session.mode = radioManager.mode
            changed = true
        }
        guard changed else {
            return
        }
        session.cloudDirtyFlag = true
        try? CwStoreSeams.save(modelContext, sessions: [session])
    }

    /// Recount actual deduplicated QSOs for the session to fix any counter drift.
    private func recountQSOs(for session: LoggingSession) {
        let sessionId = session.id
        let qsoDescriptor = BoundedDescriptor<QSO>(
            predicate: #Predicate<QSO> { $0.loggingSessionId == sessionId && !$0.isHidden },
            limit: BoundedDescriptor<QSO>.maxLimit
        )
        guard let qsos = try? modelContext.boundedFetch(qsoDescriptor) else {
            return
        }
        let dedupedCount = Set(qsos.map(\.deduplicationKey)).count
        if session.qsoCount != dedupedCount {
            session.qsoCount = dedupedCount
            try? CwStoreSeams.save(modelContext, sessions: [session])
        }
    }
}
