import CarrierWaveData
import SwiftUI

// MARK: - LoggerView Session Header

extension LoggerView {
    // MARK: - Session Header

    /// Session header - shows active session info
    @ViewBuilder
    var sessionHeader: some View {
        if let session = sessionManager?.activeSession {
            activeSessionHeader(session)
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
            Button("Review Spot Mismatches") {
                spotMismatchesDismissed = false
                refreshSpotMismatches()
            }
            Button("Pause Session") {
                sessionManager?.pauseSession()
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                if session.isPOTA, !session.isRove {
                    parkHeaderView(session)
                }

                if session.isPOTA,
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

                // SDR status pill (always visible when active)
                sdrTitleBarPill

                // Inline WebSDR recording badge (visible when panel is closed)
                if let manager = sessionManager,
                   !showWebSDRPanel,
                   manager.webSDRSession.state.isActive
                {
                    webSDRInlineBadge(session: manager.webSDRSession)
                }

                // BLE radio badge
                if !showBLERadioPanel {
                    bleRadioInlineBadge
                }
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
        } else if session.isPOTA || session.isSOTA {
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
            .fixedSize()
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

    /// SDR status pill for the title bar (always visible when SDR is active)
    @ViewBuilder
    var sdrTitleBarPill: some View {
        if let manager = sessionManager,
           manager.webSDRSession.state.isActive
        {
            Button {
                showWebSDRPanel = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: manager.webSDRSession.state.statusIcon)
                        .font(.system(size: 8))
                        .foregroundStyle(.red)
                        .symbolEffect(
                            .pulse,
                            isActive: manager.webSDRSession.state == .recording
                        )
                    Text("SDR")
                        .font(.caption2.weight(.medium))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.red.opacity(0.15))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    /// Compact inline WebSDR recording badge for the session controls bar
    func webSDRInlineBadge(session: WebSDRSession) -> some View {
        Button {
            showWebSDRPanel = true
        } label: {
            HStack(spacing: 3) {
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
                Text(formatWebSDRDuration(session.recordingDuration))
                    .font(.caption2.monospacedDigit())
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.red.opacity(0.15))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Inline BLE radio status badge for the session controls bar
    @ViewBuilder
    var bleRadioInlineBadge: some View {
        let service = BLERadioService.shared
        if service.isConnected {
            Button {
                showBLERadioPanel = true
            } label: {
                HStack(spacing: 3) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text("Radio")
                        .font(.caption2)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.green.opacity(0.15))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        } else if service.isConfigured {
            Button {
                showBLERadioPanel = true
            } label: {
                HStack(spacing: 3) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                    Text("Radio")
                        .font(.caption2)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.orange.opacity(0.15))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    func equipmentCapsuleLabel(_ session: LoggingSession) -> String {
        if let rig = session.myRig, !rig.isEmpty {
            let extras = [session.myAntenna, session.myKey, session.myMic]
                .compactMap { $0 }.filter { !$0.isEmpty }.count
            let truncatedRig = rig.count > 12 ? String(rig.prefix(10)) + "…" : rig
            return extras > 0 ? "\(truncatedRig) +\(extras)" : truncatedRig
        }
        if hasAnyEquipment(session) {
            return "Equipment"
        }
        return "Equip"
    }
}
