import CarrierWaveData
import SwiftData
import SwiftUI

/// Menu bar extra showing solar conditions and session summary
struct MenuBarExtraView: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CW Sweep")
                .font(.headline)

            Divider()

            // Solar conditions
            solarSection

            Divider()

            // Session status
            sessionSection

            Divider()

            // Today's stats
            Label("\(todayQSOCount) QSOs today", systemImage: "list.bullet.rectangle")
                .font(.caption)

            Divider()

            Button("Open CW Sweep") {
                NSApplication.shared.activate()
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding()
        .frame(width: 250)
        .task { await loadData() }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @State private var activeSession: LoggingSession?
    @State private var todayQSOCount: Int = 0

    // MARK: - Solar Section

    @ViewBuilder
    private var solarSection: some View {
        if let session = activeSession, session.hasSolarData {
            VStack(alignment: .leading, spacing: 4) {
                Label("Solar Conditions", systemImage: "sun.max")
                    .font(.caption.bold())

                HStack(spacing: 12) {
                    if let sfi = session.solarFlux {
                        VStack(alignment: .leading) {
                            Text("SFI").font(.caption2).foregroundStyle(.secondary)
                            Text(String(format: "%.0f", sfi)).font(.caption.monospacedDigit())
                        }
                    }
                    if let k = session.solarKIndex {
                        VStack(alignment: .leading) {
                            Text("K").font(.caption2).foregroundStyle(.secondary)
                            Text(String(format: "%.0f", k))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(k <= 3 ? .green : k <= 5 ? .yellow : .red)
                        }
                    }
                    if let ssn = session.solarSunspots {
                        VStack(alignment: .leading) {
                            Text("SSN").font(.caption2).foregroundStyle(.secondary)
                            Text("\(ssn)").font(.caption.monospacedDigit())
                        }
                    }
                }
            }
        } else {
            Label("Solar: No data", systemImage: "sun.max")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Session Section

    @ViewBuilder
    private var sessionSection: some View {
        if let session = activeSession {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: session.programsIcon)
                        .foregroundStyle(.green)
                    Text(session.programsDisplayName)
                        .font(.caption.bold())
                }

                if let park = session.parkReference {
                    Text(park).font(.caption).foregroundStyle(.secondary)
                }
                if let sota = session.sotaReference {
                    Text(sota).font(.caption).foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Text("\(session.qsoCount) QSOs")
                        .font(.caption.monospacedDigit())
                    Text(formattedDuration(session.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Label("No active session", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        // Fetch active session
        let sessionDescriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate<LoggingSession> { session in
                session.statusRawValue == "active"
            },
            sortBy: [SortDescriptor(\LoggingSession.startedAt, order: .reverse)]
        )
        activeSession = try? modelContext.fetch(sessionDescriptor).first

        // Count today's QSOs
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let qsoDescriptor = FetchDescriptor<QSO>(
            predicate: #Predicate<QSO> { qso in
                qso.timestamp >= startOfDay && !qso.isHidden
            }
        )
        todayQSOCount = (try? modelContext.fetchCount(qsoDescriptor)) ?? 0
    }

    private func formattedDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3_600
        let minutes = (Int(interval) % 3_600) / 60
        return String(format: "%dh %02dm", hours, minutes)
    }
}
