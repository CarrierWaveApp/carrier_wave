import SwiftUI

// MARK: - LoggerTourOverlay

/// Full-screen overlay that displays the interactive logger tour.
/// Shows mock logger UI driven by the tour manager's state machine,
/// with a TourGuideBubble for KI5GTR's narration.
struct LoggerTourOverlay: View {
    // MARK: Internal

    @Bindable var tourManager: LoggerTourManager

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

    // MARK: Private

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    // MARK: - Mock Logger Content

    private var mockLoggerContent: some View {
        VStack(spacing: 0) {
            switch tourManager.currentStep {
            case .welcome:
                welcomeContent
            case .startSession,
                 .pickEquipment,
                 .setPark:
                // Logger behind the sheet — show empty state
                emptyLoggerContent
            case .activeSession,
                 .logQSO,
                 .moreQSOs,
                 .commands,
                 .sdrRecording,
                 .wrapUp:
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

    // MARK: - Mock Callsign Input

    private var mockCallsignInput: some View {
        HStack(spacing: 8) {
            HStack(spacing: 12) {
                Text(tourManager.mockCallsignText.isEmpty ? "Callsign or command..." : tourManager.mockCallsignText)
                    .font(.body)
                    .foregroundStyle(
                        tourManager.mockCallsignText.isEmpty
                            ? Color.secondary
                            : (tourManager.showCommandHelp ? Color.purple : Color.primary)
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
}

// MARK: - MockCommand

struct MockCommand {
    let name: String
    let icon: String
    let desc: String
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
