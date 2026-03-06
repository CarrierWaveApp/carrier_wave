import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - ActivatorLayout

/// Activator layout: Activation header + logger + session log + self-spot
struct ActivatorLayout: View {
    let radioManager: RadioManager

    var body: some View {
        VStack(spacing: 0) {
            // Activation header
            ActivationHeader()

            Divider()

            HSplitView {
                // Left: Logger + session log
                VStack(spacing: 0) {
                    ParsedEntryView(radioManager: radioManager)
                        .padding()

                    Divider()

                    QSOLogTableView()
                }
                .frame(minWidth: 300)

                // Right: Spot monitor + self-spot controls
                VStack {
                    SpotListView()
                }
                .frame(minWidth: 200)
            }
        }
    }
}

// MARK: - ActivationHeader

struct ActivationHeader: View {
    // MARK: Internal

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
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @State private var activeSession: LoggingSession?
    @State private var elapsed: TimeInterval = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var inactiveHeaderContent: some View {
        Group {
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
                if let park = session.parkReference {
                    Text(park).font(.caption).foregroundStyle(.secondary)
                }
                if let sota = session.sotaReference {
                    Text(sota).font(.caption).foregroundStyle(.secondary)
                }
                Text(formattedDuration(elapsed))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }

        Spacer()

        // Right: QSO count + progress
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
