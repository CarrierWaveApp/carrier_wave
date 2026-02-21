import CarrierWaveCore
import SwiftUI

// MARK: - LoggerView Session Header

extension LoggerView {
    // MARK: - Session Header

    /// Session header - shows active session info or "no session" prompt
    var sessionHeader: some View {
        Group {
            if let session = sessionManager?.activeSession {
                activeSessionHeader(session)
            } else {
                noSessionHeader
            }
        }
    }

    func activeSessionHeader(_ session: LoggingSession) -> some View {
        VStack(spacing: 4) {
            sessionTitleBar(session)

            if session.isRove {
                roveProgressSection(session)
            }

            sessionControlsBar(session)
        }
        .padding([.horizontal, .top])
        .padding(.bottom, session.isRove ? 8 : 16)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - No Session Header

    var noSessionHeader: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("No Active Session")
                        .font(.headline)
                    Text(
                        activeSessions.isEmpty
                            ? "Start a session to begin logging"
                            : "Continue a session or start a new one"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showSessionSheet = true
                } label: {
                    Label("New", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))

            if !activeSessions.isEmpty {
                activeSessionsList
            }
        }
        .confirmationDialog(
            "Finish Session",
            isPresented: Binding(
                get: { sessionToFinish != nil },
                set: {
                    if !$0 {
                        sessionToFinish = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Finish Session") {
                if let session = sessionToFinish {
                    sessionManager?.finishSession(session)
                    refreshActiveSessions()
                }
            }
            Button("Cancel", role: .cancel) {
                sessionToFinish = nil
            }
        } message: {
            if let session = sessionToFinish {
                Text(
                    "Finish \"\(session.displayTitle)\"? "
                        + "It will move to your Sessions list."
                )
            }
        }
        .alert(
            "Delete Session",
            isPresented: Binding(
                get: { sessionToDelete != nil },
                set: {
                    if !$0 {
                        sessionToDelete = nil
                    }
                }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let session = sessionToDelete {
                    sessionManager?.deleteSession(session)
                    refreshActiveSessions()
                }
                sessionToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                sessionToDelete = nil
            }
        } message: {
            if let session = sessionToDelete {
                let count = activeSessionQSOCounts[session.id] ?? 0
                Text(
                    "Delete \"\(session.displayTitle)\" and hide "
                        + "\(count) QSO(s)? Hidden QSOs will not be "
                        + "synced or counted in statistics."
                )
            }
        }
    }

    var activeSessionsList: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Active Sessions")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ForEach(activeSessions, id: \.id) { session in
                ActiveSessionRow(
                    session: session,
                    qsoCount: activeSessionQSOCounts[session.id] ?? 0,
                    onContinue: {
                        sessionManager?.resumeSession(session)
                        refreshSessionQSOs()
                        refreshActiveSessions()
                    },
                    onPause: {
                        sessionManager?.pauseOtherSession(session)
                        refreshActiveSessions()
                    },
                    onFinish: {
                        sessionToFinish = session
                    },
                    onDelete: {
                        sessionToDelete = session
                    }
                )
            }
        }
        .padding()
    }

    // MARK: - Title Bar

    func sessionTitleBar(_ session: LoggingSession) -> some View {
        HStack {
            Button {
                editingTitle = session.customTitle ?? ""
                showTitleEditSheet = true
            } label: {
                HStack(spacing: 4) {
                    Text(session.displayTitle)
                        .font(.headline.monospaced())
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Text(session.formattedDuration)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text("\(displayQSOs.count) QSOs")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.green)

            sessionActionsButton(session)
        }
    }

    func sessionActionsButton(_ session: LoggingSession) -> some View {
        Button {
            callsignFieldFocused = false
            showEndSessionConfirmation = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.systemGray4))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .confirmationDialog(
            "Session Actions",
            isPresented: $showEndSessionConfirmation,
            titleVisibility: .visible
        ) {
            Button("Pause Session") {
                sessionManager?.pauseSession()
                refreshActiveSessions()
            }
            Button("End Session") {
                handleEndSession()
            }
            Button("Delete Session", role: .destructive) {
                showDeleteSessionSheet = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if session.frequency == nil, !sessionQSOs.isEmpty {
                Text(
                    "Pause keeps the session active for later. "
                        + "End keeps your \(sessionQSOs.count) QSOs for sync. "
                        + "QSOs were logged without a frequency and will show as \"Unknown\" band. "
                        + "Delete hides them permanently."
                )
            } else {
                Text(
                    "Pause keeps the session active for later. "
                        + "End keeps your \(sessionQSOs.count) QSOs for sync. "
                        + "Delete hides them permanently."
                )
            }
        }
    }

    // MARK: - Rove Progress

    func roveProgressSection(_ session: LoggingSession) -> some View {
        RoveProgressBar(
            stops: session.roveStops,
            currentStopId: session.currentRoveStop?.id,
            viewingPark: viewingParkOverride,
            onNextStop: {
                viewingParkOverride = nil
                showNextStopSheet = true
            },
            onTapStop: { stop in
                let stopPark = stop.parkReference
                let activePark = session.parkReference
                if stopPark == activePark {
                    viewingParkOverride = nil
                } else {
                    viewingParkOverride = stopPark
                }
            }
        )
    }

    // MARK: - Session Controls Bar

    func sessionControlsBar(_ session: LoggingSession) -> some View {
        HStack {
            if session.activationType == .pota, !session.isRove {
                parkHeaderView(session)
            }

            freqBandCapsule(session)

            Button {
                showModeEditSheet = true
            } label: {
                HStack(spacing: 2) {
                    Text(session.mode)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
                .font(.caption.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.2))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            equipmentCapsule(session)

            Spacer()

            if session.activationType == .pota,
               let parkRef = session.parkReference,
               let commentsService = sessionManager?.spotCommentsService
            {
                SpotCommentsButton(
                    comments: commentsService.comments,
                    newCount: commentsService.newCommentCount,
                    parkRef: parkRef,
                    onMarkRead: { commentsService.markAllRead() }
                )
            }
        }
    }

    // MARK: - Park Header

    /// Park header: tappable ref(s) that open the park editor directly
    @ViewBuilder
    func parkHeaderView(_ session: LoggingSession) -> some View {
        let parkRef = session.parkReference
        Button {
            editingParkReference = parkRef ?? ""
            showParkEditSheet = true
        } label: {
            parkRefLabels(parkRef)
        }
        .buttonStyle(.plain)
    }

    /// Park reference label(s) — always shows ref numbers
    @ViewBuilder
    func parkRefLabels(_ parkRef: String?) -> some View {
        if let parkRef, !parkRef.isEmpty {
            let parks = ParkReference.split(parkRef)
            HStack(spacing: 4) {
                ForEach(parks, id: \.self) { park in
                    Text(park)
                        .font(.caption.monospaced().weight(.medium))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        } else {
            Text("No park")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Frequency / Band / Equipment Capsules

    /// Merged frequency + band capsule (or "Set Freq" / "Band" when unset)
    @ViewBuilder
    func freqBandCapsule(_ session: LoggingSession) -> some View {
        if let freq = session.frequency {
            bandCapsule(color: .blue) {
                Text(FrequencyFormatter.format(freq)).fontDesign(.monospaced)
                if let band = session.band {
                    Text(band)
                }
            }
        } else if session.activationType == .pota || session.activationType == .sota {
            bandCapsule(color: .orange) { Text("Set Freq") }
        } else {
            bandCapsule(color: .blue) { Text("Band").foregroundStyle(.secondary) }
        }
    }

    func bandCapsule(
        color: Color, @ViewBuilder content: () -> some View
    ) -> some View {
        Button { showBandEditSheet = true } label: {
            HStack(spacing: 4) {
                content()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Equipment capsule — shows radio name, equipment count, or placeholder
    func equipmentCapsule(_ session: LoggingSession) -> some View {
        Button {
            showRigEditSheet = true
        } label: {
            HStack(spacing: 2) {
                Text(equipmentCapsuleLabel(session))
                    .lineLimit(1)
                    .foregroundStyle(hasAnyEquipment(session) ? .primary : .secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue.opacity(0.2))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    func hasAnyEquipment(_ session: LoggingSession) -> Bool {
        [session.myRig, session.myAntenna, session.myKey, session.myMic]
            .contains { $0 != nil && !$0!.isEmpty }
    }

    func equipmentCapsuleLabel(_ session: LoggingSession) -> String {
        if let rig = session.myRig, !rig.isEmpty {
            let extras = [session.myAntenna, session.myKey, session.myMic]
                .compactMap { $0 }.filter { !$0.isEmpty }.count
            return extras > 0 ? "\(rig) +\(extras)" : rig
        }
        if hasAnyEquipment(session) {
            return "Equipment"
        }
        return "Equip"
    }
}
