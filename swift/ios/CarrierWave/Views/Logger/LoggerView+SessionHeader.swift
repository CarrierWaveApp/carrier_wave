import CarrierWaveCore
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
                        .font(.subheadline.monospaced().weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "pencil")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            sessionEndButton(session)
            sessionMoreButton(session)
        }
    }

    /// QSO count chip for the controls bar — shows target for POTA/SOTA and split counts
    @ViewBuilder
    func qsoCountChip(_ session: LoggingSession) -> some View {
        let count = displayQSOs.count
        let uniqueCount = uniqueDisplayQSOCount(session)
        let target = session.activationThreshold
        let targetMet = target.map { uniqueCount >= $0 } ?? false

        if session.isPOTA, let prevCount = sessionManager?.previousDayQSOCount,
           let target
        {
            // Split session: show yesterday + today
            HStack(spacing: 3) {
                Text("Y:\(prevCount)")
                    .foregroundStyle(prevCount >= target ? .green : .orange)
                Text("T:\(uniqueCount)/\(target)")
                    .foregroundStyle(targetMet ? .green : .primary)
            }
            .font(.caption2.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                (targetMet ? Color.green : Color.orange).opacity(0.15)
            )
            .clipShape(Capsule())
        } else if let target {
            Text("\(uniqueCount)/\(target)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(targetMet ? .green : .primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    (targetMet ? Color.green : Color(.tertiarySystemBackground))
                        .opacity(targetMet ? 0.15 : 1)
                )
                .clipShape(Capsule())
        } else {
            Text("\(count) QSOs")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.15))
                .clipShape(Capsule())
        }
    }

    /// Count unique QSOs for activation progress (deduplicated by callsign + band + mode + park)
    private func uniqueDisplayQSOCount(_ session: LoggingSession) -> Int {
        let park = session.parkReference?.uppercased() ?? ""
        var seen = Set<String>()
        for qso in displayQSOs {
            let key = "\(qso.callsign.uppercased())|\(qso.band)|\(qso.mode)|\(park)"
            seen.insert(key)
        }
        return seen.count
    }

    func sessionEndButton(_: LoggingSession) -> some View {
        Button {
            callsignFieldFocused = false
            handleEndSession()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 8))
                Text("END")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.red)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    func sessionMoreButton(_ session: LoggingSession) -> some View {
        Menu {
            Button {
                spotMismatchesDismissed = false
                refreshSpotMismatches()
            } label: {
                Label("Review Spot Mismatches", systemImage: "exclamationmark.triangle")
            }
            Button {
                sessionManager?.pauseSession()
            } label: {
                Label("Pause Session", systemImage: "pause")
            }
            Divider()
            Button(role: .destructive) {
                showDeleteSessionSheet = true
            } label: {
                Label("Delete Session", systemImage: "trash")
            }
        } label: {
            // Hidden text to match End button height
            Text("End").hidden()
                .overlay {
                    Image(systemName: "ellipsis")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(.systemGray4))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .accessibilityLabel("Session options")
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
                myCallsignChip(session)
                spotCommentsChip(session)
                qsoCountChip(session)
                if session.isPOTA, !session.isRove {
                    parkHeaderView(session)
                }
                freqBandCapsule(session)
                modeCapsule(session)
                if session.isMultiOp {
                    multiOpPill(session)
                }
                // Situational detail — muted in Simple Logging Mode.
                if !loggerSimpleMode {
                    situationalChips(session)
                }
            }
            .padding(.horizontal, 4)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newValue in
                chipContentWidth = newValue
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .named("chipScroll")).minX
            } action: { newValue in
                chipScrollOffset = newValue
            }
        }
        .coordinateSpace(name: "chipScroll")
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newValue in
            chipScrollViewWidth = newValue
        }
        .mask(scrollFadeMask)
    }

    func modeCapsule(_ session: LoggingSession) -> some View {
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
    }

    @ViewBuilder
    func webSDRBadgeIfNeeded(_ session: LoggingSession) -> some View {
        if let manager = sessionManager,
           !showWebSDRPanel,
           manager.webSDRSession.state.isActive
        {
            webSDRInlineBadge(session: manager.webSDRSession)
        }
    }

    /// Duration chip with clock icon
    func durationChip(_ session: LoggingSession) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "clock")
                .font(.system(size: 8))
            Text(session.formattedDuration)
                .font(.caption2.weight(.medium).monospacedDigit())
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(.tertiarySystemBackground))
        .clipShape(Capsule())
    }

    /// Fade gradient on edges to hint more content is available
    private var scrollFadeMask: some View {
        let overflow = chipContentWidth - chipScrollViewWidth
        let scrolledLeft = -chipScrollOffset > 4
        let scrolledToEnd = -chipScrollOffset >= overflow - 4
        let canScrollRight = overflow > 4 && !scrolledToEnd
        return HStack(spacing: 0) {
            if scrolledLeft {
                LinearGradient(
                    colors: [.clear, .black],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 16)
            }
            Color.black
            if canScrollRight {
                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 16)
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

    // MARK: - Active Shift Pill

    @ViewBuilder
    func activeShiftPill(_ session: LoggingSession) -> some View {
        if session.isPOTA,
           let parkRef = session.parkReference,
           let park = POTAParksCache.shared.parkSync(for: ParkReference.split(parkRef).first ?? parkRef),
           let longitude = park.longitude
        {
            let now = Date()
            let windows = POTAShift.windows(for: now, longitude: longitude)
            if let active = windows.first(where: { $0.contains(now) }) {
                let color: Color = active.shift == .late ? .indigo : .orange
                let icon = active.shift == .late ? "moon.fill" : "sunrise.fill"
                HStack(spacing: 3) {
                    Image(systemName: icon)
                        .font(.system(size: 8))
                    Text(active.shift.displayLabel)
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.15))
                .clipShape(Capsule())
            }
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

    func multiOpPill(_ session: LoggingSession) -> some View {
        let count = session.allOperatorCallsigns.count
        return Button {
            showOperatorsSheet = true
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 8))
                Text("\(count) ops")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.2))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - My Callsign Chip

    /// Shows the session callsign when it differs from the app's configured callsign
    @ViewBuilder
    func myCallsignChip(_ session: LoggingSession) -> some View {
        let defaultCall = UserDefaults.standard.string(forKey: "loggerDefaultCallsign") ?? ""
        if !session.myCallsign.isEmpty,
           session.myCallsign.uppercased() != defaultCall.uppercased()
        {
            HStack(spacing: 3) {
                Image(systemName: "person.text.rectangle")
                    .font(.system(size: 8))
                Text(session.myCallsign)
                    .font(.caption.monospaced().weight(.semibold))
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.15))
            .clipShape(Capsule())
        }
    }

    /// Spot comments as a chip matching the controls bar style
    @ViewBuilder
    func spotCommentsChip(_ session: LoggingSession) -> some View {
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
    }
}
