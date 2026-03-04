import SwiftUI

// MARK: - LoggerTourOverlay

/// Full-screen overlay that displays the interactive logger tour.
/// Shows mock logger UI driven by the tour manager's state machine,
/// with a TourGuideBubble for KI5GTR's narration.
struct LoggerTourOverlay: View {
    @Bindable var tourManager: LoggerTourManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                mockLoggerContent
                    .frame(maxHeight: .infinity)

                // Tour guide bubble
                if let message = tourManager.currentMessage {
                    TourGuideBubble(
                        message: message,
                        stepIndex: tourManager.currentStep.rawValue,
                        totalSteps: LoggerTourStep.allCases.count,
                        onNext: {
                            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.3)) {
                                tourManager.advance()
                            }
                        },
                        onSkip: { tourManager.skip() }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .sheet(isPresented: tourSessionSheetBinding) {
            TourSessionStartSheet(tourManager: tourManager)
        }
    }

    // MARK: - Mock Logger Content

    @ViewBuilder
    private var mockLoggerContent: some View {
        VStack(spacing: 0) {
            switch tourManager.currentStep {
            case .welcome:
                welcomeContent
            case .startSession, .pickEquipment, .setPark:
                // Logger behind the sheet — show empty state
                emptyLoggerContent
            case .activeSession, .logQSO, .moreQSOs,
                 .commands, .sdrRecording, .wrapUp:
                activeSessionContent
            }
        }
    }

    // MARK: - Welcome (Empty Logger)

    private var welcomeContent: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Active Session")
                .font(.title3)
                .foregroundStyle(.secondary)

            Button {} label: {
                Label("Start Session", systemImage: "play.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyLoggerContent: some View {
        VStack {
            Spacer()
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.3))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Active Session Content

    private var activeSessionContent: some View {
        VStack(spacing: 0) {
            mockSessionHeader

            ScrollView {
                VStack(spacing: 12) {
                    if tourManager.showCallsignInput {
                        mockCallsignInput
                    }

                    if tourManager.showCommandHelp {
                        mockCommandHelpOverlay
                    }

                    if tourManager.showSDRIndicator {
                        mockSDRBanner
                    }

                    mockQSOList
                }
                .padding()
            }
        }
    }

    // MARK: - Mock Session Header

    private var mockSessionHeader: some View {
        let session = tourManager.mockSession
        return VStack(spacing: 4) {
            // Title bar
            HStack {
                Text(session.callsign)
                    .font(.headline.monospaced())

                Spacer()

                Text("0:04:32")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Text("\(tourManager.visibleQSOs.count) QSOs")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)

                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray4))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Controls bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    mockCapsule(session.park, color: .green, monospaced: true)
                    mockCapsule(session.formattedFrequency, color: .blue, monospaced: true)
                    mockCapsule(session.band, color: .blue)
                    mockCapsule(session.mode, color: .blue)
                    mockCapsule(session.equipmentSummary, color: .blue)

                    if tourManager.showSDRIndicator {
                        mockSDRPill
                    }
                }
            }
        }
        .padding([.horizontal, .top])
        .padding(.bottom, 16)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func mockCapsule(
        _ text: String,
        color: Color,
        monospaced: Bool = false
    ) -> some View {
        Text(text)
            .font(monospaced ? .caption.monospaced().weight(.medium) : .caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .clipShape(Capsule())
    }

    private var mockSDRPill: some View {
        HStack(spacing: 3) {
            Image(systemName: "waveform")
                .font(.system(size: 8))
                .foregroundStyle(.red)
            Text("SDR")
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.red.opacity(0.15))
        .clipShape(Capsule())
    }

    // MARK: - Mock Callsign Input

    private var mockCallsignInput: some View {
        HStack(spacing: 8) {
            HStack(spacing: 12) {
                Text(tourManager.mockCallsignText.isEmpty ? "Callsign or command..." : tourManager.mockCallsignText)
                    .font(.body)
                    .foregroundStyle(
                        tourManager.mockCallsignText.isEmpty
                            ? .secondary
                            : (tourManager.showCommandHelp ? .purple : .primary)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !tourManager.mockCallsignText.isEmpty {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        tourManager.showCommandHelp ? Color.purple : Color.accentColor,
                        lineWidth: 2
                    )
            )

            Text(tourManager.showCommandHelp ? "Run" : "Log")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(height: 48)
                .frame(width: 48)
                .background(tourManager.showCommandHelp ? Color.purple : Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Mock Command Help

    private var mockCommandHelpOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(mockCommands, id: \.name) { cmd in
                HStack(spacing: 10) {
                    Image(systemName: cmd.icon)
                        .font(.caption)
                        .frame(width: 20)
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(cmd.name)
                            .font(.caption.weight(.semibold).monospaced())
                        Text(cmd.desc)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var mockCommands: [(name: String, icon: String, desc: String)] {
        [
            ("FREQ", "antenna.radiowaves.left.and.right", "Set frequency"),
            ("MODE", "waveform", "Change mode"),
            ("SPOT", "mappin.and.ellipse", "Self-spot to POTA"),
            ("RBN", "dot.radiowaves.up.forward", "Reverse Beacon Network"),
            ("HUNT", "binoculars", "Find activator spots"),
            ("MAP", "map", "Session QSO map"),
            ("SOLAR", "sun.max", "Solar conditions"),
            ("SDR", "radio", "WebSDR recording"),
        ]
    }

    // MARK: - Mock SDR Banner

    private var mockSDRBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)

            Text("Recording from KiwiSDR Tucson")
                .font(.subheadline)

            Spacer()

            Text("0:01:47")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Mock QSO List

    @ViewBuilder
    private var mockQSOList: some View {
        let qsos = tourManager.visibleQSOs
        if !qsos.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(qsos.enumerated()), id: \.element.id) { index, qso in
                    mockQSORow(qso)
                    if index < qsos.count - 1 {
                        Divider()
                            .padding(.leading, 40)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func mockQSORow(_ qso: MockTourQSO) -> some View {
        HStack(spacing: 10) {
            // QSO number
            Text("#\(tourManager.visibleQSOs.firstIndex(where: { $0.id == qso.id }).map { $0 + 1 } ?? 0)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(qso.callsign)
                        .font(.subheadline.weight(.semibold).monospaced())

                    if qso.isDuplicate {
                        Text("DUPE")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.orange)
                            .clipShape(Capsule())
                    }

                    if qso.isParkToPark, let park = qso.theirPark {
                        Text("P2P \(park)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 8) {
                    Text("\(qso.rstSent)/\(qso.rstReceived)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(qso.qth)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(qso.grid)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(qso.time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Session Sheet Binding

    private var tourSessionSheetBinding: Binding<Bool> {
        Binding(
            get: { tourManager.showSessionSheet },
            set: { newValue in
                // If the user dismisses the sheet, advance past the sheet steps
                if !newValue, tourManager.showSessionSheet {
                    withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.3)) {
                        // Skip to activeSession step
                        while tourManager.showSessionSheet {
                            tourManager.advance()
                        }
                    }
                }
            }
        )
    }
}

// MARK: - TourSessionStartSheet

/// Wrapper around SessionStartSheet for the tour.
/// Pre-fills mock data and intercepts the Start button.
struct TourSessionStartSheet: View {
    @Bindable var tourManager: LoggerTourManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            Form {
                tourCallsignSection
                tourModeSection
                tourFrequencySection
                tourPowerSection
                tourEquipmentSection
                tourActivationSection
                tourSDRSection
            }
            .navigationTitle("Start Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        tourManager.skip()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        // Intercepted — advance tour instead of creating real session
                        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.3)) {
                            // Advance to activeSession (skip past remaining sheet steps)
                            while tourManager.showSessionSheet {
                                tourManager.advance()
                            }
                        }
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                tourSheetGuideBubble
            }
        }
    }

    // MARK: - Tour Guide Bubble (inside sheet)

    @ViewBuilder
    private var tourSheetGuideBubble: some View {
        if let message = tourManager.currentMessage {
            TourGuideBubble(
                message: message,
                stepIndex: tourManager.currentStep.rawValue,
                totalSteps: LoggerTourStep.allCases.count,
                onNext: {
                    withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.3)) {
                        tourManager.advance()
                        // Dismiss sheet when advancing past sheet steps
                        if !tourManager.showSessionSheet {
                            dismiss()
                        }
                    }
                },
                onSkip: {
                    tourManager.skip()
                    dismiss()
                }
            )
        }
    }

    // MARK: - Form Sections (pre-filled mock data)

    private var session: MockTourSession { tourManager.mockSession }

    private var tourCallsignSection: some View {
        Section("Station") {
            HStack {
                Text("Callsign")
                Spacer()
                Text(session.callsign)
                    .foregroundStyle(.secondary)
                    .font(.body.monospaced())
            }
            HStack {
                Text("Grid")
                Spacer()
                Text(session.grid)
                    .foregroundStyle(.secondary)
                    .font(.body.monospaced())
            }
        }
    }

    private var tourModeSection: some View {
        Section("Mode") {
            HStack {
                ForEach(["CW", "SSB", "FT8"], id: \.self) { mode in
                    Text(mode)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(mode == session.mode ? Color.accentColor : Color(.systemGray5))
                        .foregroundStyle(mode == session.mode ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Spacer()
            }
        }
    }

    private var tourFrequencySection: some View {
        Section("Frequency") {
            HStack {
                Text("Frequency")
                Spacer()
                Text("\(session.formattedFrequency) MHz")
                    .foregroundStyle(.secondary)
                    .font(.body.monospacedDigit())
            }
        }
    }

    private var tourPowerSection: some View {
        Section("Power") {
            HStack {
                Text("Transmit Power")
                Spacer()
                Text("\(session.power)W")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tourEquipmentSection: some View {
        Section("Equipment") {
            tourEquipmentRow("Radio", value: session.radio, icon: "radio")
            tourEquipmentRow("Antenna", value: session.antenna, icon: "antenna.radiowaves.left.and.right")
            tourEquipmentRow("Key", value: session.key, icon: "pianokeys")
        }
        .listRowBackground(
            tourManager.currentStep == .pickEquipment
                ? Color.accentColor.opacity(0.08)
                : nil
        )
    }

    private func tourEquipmentRow(
        _ label: String,
        value: String,
        icon: String
    ) -> some View {
        HStack {
            Label(label, systemImage: icon)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var tourActivationSection: some View {
        Section("Activation") {
            HStack {
                Text("Program")
                Spacer()
                Text("POTA")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.2))
                    .clipShape(Capsule())
            }
            HStack {
                Text("Park Reference")
                Spacer()
                Text(session.park)
                    .foregroundStyle(.secondary)
                    .font(.body.monospaced())
            }
            HStack {
                Text("")
                Spacer()
                Text(session.parkName)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .listRowBackground(
            tourManager.currentStep == .setPark
                ? Color.green.opacity(0.08)
                : nil
        )
    }

    private var tourSDRSection: some View {
        Section("WebSDR") {
            HStack {
                Text("Auto-start Recording")
                Spacer()
                Image(systemName: "checkmark")
                    .foregroundStyle(.green)
            }
            HStack {
                Text("Receiver")
                Spacer()
                Text("KiwiSDR Tucson")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview("Tour Overlay") {
    let manager = LoggerTourManager()
    LoggerTourOverlay(tourManager: manager)
        .onAppear { manager.start() }
}

#Preview("Tour - Active Session") {
    let manager = LoggerTourManager()
    LoggerTourOverlay(tourManager: manager)
        .onAppear {
            manager.start()
            // Advance to activeSession step
            for _ in 0 ..< 4 {
                manager.advance()
            }
        }
}

#Preview("Tour - Commands") {
    let manager = LoggerTourManager()
    LoggerTourOverlay(tourManager: manager)
        .onAppear {
            manager.start()
            for _ in 0 ..< 7 {
                manager.advance()
            }
        }
}
