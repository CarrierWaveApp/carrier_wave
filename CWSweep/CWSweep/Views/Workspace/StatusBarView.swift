import CarrierWaveData
import SwiftData
import SwiftUI

/// Bottom status bar showing session info, QSO count, UTC time
struct StatusBarView: View {
    // MARK: Internal

    let radioManager: RadioManager

    var body: some View {
        HStack {
            // QSO count
            Label("QSO #\(qsoCount)", systemImage: "number")
                .font(.caption)

            Divider()
                .frame(height: 12)

            // Session duration
            if let session = activeSession {
                HStack(spacing: 4) {
                    Image(systemName: session.status == .paused ? "pause.circle" : "clock")
                        .foregroundStyle(session.status == .paused ? .orange : .green)
                    Text(formattedDuration(session.duration))
                        .monospacedDigit()
                    if !session.programsDisplayName.isEmpty {
                        Text("(\(session.programsDisplayName))")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            } else {
                Label("No active session", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(height: 12)

            // Radio status
            if radioManager.isConnected {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(String(format: "%.3f", radioManager.frequency))
                        .monospacedDigit()
                    Text(radioManager.mode)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "Radio connected, \(String(format: "%.3f", radioManager.frequency)) MHz, \(radioManager.mode)"
                )
            }

            // WinKeyer status
            if winKeyer.isConnected {
                Divider()
                    .frame(height: 12)

                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.yellow)
                    Text("\(winKeyer.speed) WPM")
                        .monospacedDigit()
                    if winKeyer.isSending {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                    }
                }
                .font(.caption)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "WinKeyer \(winKeyer.speed) words per minute\(winKeyer.isSending ? ", sending" : "")"
                )
            }

            // SDR status
            if tuneInManager.isActive {
                Divider()
                    .frame(height: 12)

                HStack(spacing: 4) {
                    Image(systemName: tuneInManager.session.state.statusIcon)
                        .foregroundStyle(.green)
                    if let spot = tuneInManager.spot {
                        Text(spot.callsign)
                        Text(String(format: "%.1f", spot.frequencyMHz * 1_000))
                            .monospacedDigit()
                    }
                    if let receiver = tuneInManager.session.receiver {
                        Text(receiver.name)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("SDR connected")
            }

            Divider()
                .frame(height: 12)

            // iCloud sync status
            SyncStatusIndicator(syncService: syncService) {
                Task { await syncService.syncPending() }
            }

            Spacer()

            // UTC time
            Text(utcTimeString)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
        .onReceive(timer) { time in
            currentTime = time
        }
        .task {
            await loadCounts()
        }
        .task { await observeStoreChanges(.NSPersistentStoreRemoteChange) }
        .task { await observeStoreChanges(ModelContext.didSave) }
    }

    // MARK: Private

    private static let utcFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HH:mm:ss 'UTC'"
        return formatter
    }()

    private static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

    @State private var currentTime = Date()
    @State private var qsoCount = 0
    @State private var activeSession: LoggingSession?
    @Environment(\.modelContext) private var modelContext
    @Environment(TuneInManager.self) private var tuneInManager
    @Environment(WinKeyerManager.self) private var winKeyer
    @State private var syncService = CloudSyncService.shared

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var utcTimeString: String {
        Self.utcFormatter.string(from: currentTime)
    }

    private func formattedDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3_600
        let minutes = (Int(interval) % 3_600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Observe a notification and re-fetch counts with debounce.
    private func observeStoreChanges(_ name: Notification.Name) async {
        for await _ in NotificationCenter.default.notifications(named: name) {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }
            await loadCounts()
        }
    }

    private func loadCounts() async {
        // Fetch and dedup by UUID to get accurate count — fetchCount includes
        // CloudKit mirror duplicates (~3x).
        var countDescriptor = FetchDescriptor<QSO>(
            predicate: #Predicate<QSO> { qso in
                !qso.isHidden && !qso.callsign.isEmpty
                    && qso.mode != "WEATHER" && qso.mode != "SOLAR" && qso.mode != "NOTE"
            }
        )
        countDescriptor.fetchLimit = 30_000
        let fetched = (try? modelContext.fetch(countDescriptor)) ?? []
        var seen = Set<UUID>()
        qsoCount = fetched.filter { seen.insert($0.id).inserted }.count

        var sessionDescriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.statusRawValue == "active" },
            sortBy: [SortDescriptor(\LoggingSession.startedAt, order: .reverse)]
        )
        sessionDescriptor.fetchLimit = 1
        activeSession = try? modelContext.fetch(sessionDescriptor).first
    }
}
