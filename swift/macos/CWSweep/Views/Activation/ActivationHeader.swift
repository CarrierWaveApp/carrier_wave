import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - ActivationHeader

struct ActivationHeader: View {
    // MARK: Internal

    var onSessionChanged: (() async -> Void)?

    /// Properties consumed by `ActivationHeader+Spotting` are kept at
    /// internal access so the spot-controls extension can read/write
    /// them. The Swift compiler doesn't allow extensions in separate
    /// files to touch `private` storage.
    @Environment(POTASpotService.self) var spotService
    @AppStorage("potaReSpotIntervalMinutes") var potaReSpotIntervalMinutes = 30
    @State var activeSession: LoggingSession?
    @State var isSpotting = false
    @State var showSpotError = false
    @State var lastSpotError: String?
    @State var lastSpotSentAt: Date?

    var body: some View {
        HStack {
            if let session = activeSession {
                activeHeaderContent(session)
            } else {
                inactiveHeaderContent
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .task { await loadActiveSession() }
        .onReceive(timer) { _ in
            if let session = activeSession {
                elapsed = session.duration
            }
        }
        .alert(spotErrorTitle, isPresented: $showSpotError, presenting: lastSpotError) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error)
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @State private var elapsed: TimeInterval = 0
    @State private var showParkChange = false
    @State private var showSessionHistory = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let spotErrorTitle = "Couldn't post POTA spot"

    @ViewBuilder
    private var inactiveHeaderContent: some View {
        VStack(alignment: .leading) {
            Text("No Active Activation")
                .font(.headline)
            Text("Start a POTA/SOTA session to begin")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Spacer()

        VStack(alignment: .trailing) {
            Text("0 / 10 QSOs")
                .font(.caption.monospacedDigit())
            ProgressView(value: 0, total: 10)
                .frame(width: 120)
                .accessibilityLabel("Activation progress: 0 of 10 QSOs")
        }
    }

    private var sessionHistoryButton: some View {
        Button {
            showSessionHistory = true
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title3)
        }
        .buttonStyle(.borderless)
        .help("Session History")
        .accessibilityLabel("Session history")
        .popover(isPresented: $showSessionHistory) {
            SessionHistoryPopover()
        }
    }

    @ViewBuilder
    private func activeHeaderContent(_ session: LoggingSession) -> some View {
        // Left: Session info
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: session.programsIcon)
                    .foregroundStyle(Color.accentColor)
                Text(session.programsDisplayName)
                    .font(.headline)
            }

            HStack(spacing: 8) {
                parkChip(session)
                if let sota = session.sotaReference {
                    Text(sota).font(.caption).foregroundStyle(.secondary)
                }
                Text(formattedDuration(elapsed))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }

        Spacer()

        // Right: QSO count + progress + spot controls + history + session controls
        HStack(spacing: 12) {
            qsoProgressView(session)
            potaSpotControls(session)

            Divider().frame(height: 28)

            sessionHistoryButton

            Divider().frame(height: 28)

            sessionControls(session)
        }
    }

    @ViewBuilder
    private func parkChip(_ session: LoggingSession) -> some View {
        if let park = session.parkReference {
            Button {
                showParkChange = true
            } label: {
                HStack(spacing: 4) {
                    Text("\u{1F332}")
                        .font(.caption2)
                    Text(park)
                        .font(.caption)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showParkChange) {
                ParkChangeDropdown(session: session, onParkChanged: {
                    Task { await loadActiveSession() }
                })
            }
        }
    }

    private func qsoProgressView(_ session: LoggingSession) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            let count = session.qsoCount
            let qualified = count >= 10

            Text("\(count) / 10 QSOs")
                .font(.caption.monospacedDigit())
                .foregroundStyle(qualified ? .green : .primary)

            ProgressView(value: Double(min(count, 10)), total: 10)
                .frame(width: 120)
                .tint(qualified ? .green : .accentColor)
                .accessibilityLabel("Activation progress: \(count) of 10 QSOs")

            if qualified {
                Text("Activation qualified!")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private func sessionControls(_ session: LoggingSession) -> some View {
        if session.isActive {
            Button {
                session.pause()
                Task {
                    await loadActiveSession()
                    await onSessionChanged?()
                }
            } label: {
                Image(systemName: "pause.circle")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .help("Pause Session")
            .accessibilityLabel("Pause session")
        } else if session.status == .paused {
            Button {
                session.resume()
                Task {
                    await loadActiveSession()
                    await onSessionChanged?()
                }
            } label: {
                Image(systemName: "play.circle")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .help("Resume Session")
            .accessibilityLabel("Resume session")
        }

        Button {
            session.end()
            Task {
                await loadActiveSession()
                await onSessionChanged?()
            }
        } label: {
            Image(systemName: "stop.circle")
                .font(.title3)
        }
        .buttonStyle(.borderless)
        .help("End Session")
        .accessibilityLabel("End session")
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
            elapsed = session.duration
        }
    }

    private func formattedDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3_600
        let minutes = (Int(interval) % 3_600) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
}
