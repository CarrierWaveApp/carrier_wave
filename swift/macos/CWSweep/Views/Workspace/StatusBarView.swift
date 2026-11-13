import CarrierWaveData
import SwiftData
import SwiftUI

/// Bottom status bar showing session info, QSO count, UTC time
struct StatusBarView: View {
    // MARK: Internal

    let radioManager: RadioManager

    var body: some View {
        HStack {
            if vimEngine.isEnabled {
                VimStatusBadge(
                    mode: vimEngine.mode,
                    pendingKeys: vimEngine.pendingKeys,
                    lastEcho: vimEngine.lastCommandEcho
                )
                Divider()
                    .frame(height: 12)
            }

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
                .contextMenu {
                    Button("End Session") {
                        endActiveSession()
                    }
                }
            } else {
                Label("No active session", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(height: 12)

            // WSJT-X listener — renders (with its trailing divider) only while
            // running; carries the last QSO it logged (CAR-282).
            WsjtxStatusBadge()

            // Radio status — one pill per connected slot. Click a pill to
            // focus that slot.
            radioSlotPills

            // Keyer status — bridge takes priority, falls back to WinKeyer.
            if radioManager.isBridgeKeyerAvailable {
                Divider()
                    .frame(height: 12)
                keyerBadge(
                    label: "Bridge",
                    wpm: radioManager.bridgeCWSpeed,
                    sending: radioManager.bridgeCWIsSending,
                    color: .blue
                )
            } else if winKeyer.isConnected {
                Divider()
                    .frame(height: 12)
                keyerBadge(
                    label: "WinKeyer",
                    wpm: winKeyer.speed,
                    sending: winKeyer.isSending,
                    color: .yellow
                )
            }

            Divider()
                .frame(height: 12)

            // Satellite station (rotator / Doppler CAT / TLE age) — only
            // while a rotator is linked or CAT is armed.
            SatelliteStatusBadge()

            // Carrier Wave Sync status
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
            sessionCheckCounter += 1
            if sessionCheckCounter >= Self.sessionCheckInterval {
                sessionCheckCounter = 0
                refreshActiveSession()
            }
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

    /// Re-check active session every 30 timer ticks (30s) to catch
    /// cross-context changes from CloudSyncJournalEngine.
    private static let sessionCheckInterval = 30

    @Environment(VimEngine.self) private var vimEngine

    @State private var currentTime = Date()
    @State private var qsoCount = 0
    @State private var activeSession: LoggingSession?
    @State private var sessionCheckCounter = 0
    /// IDs of sessions recently ended from CWSweep — suppresses re-fetch
    /// until changes propagate through iCloud sync.
    @State private var recentlyEndedSessionIds: Set<UUID> = []
    @Environment(\.modelContext) private var modelContext
    @Environment(WinKeyerManager.self) private var winKeyer
    @State private var syncService = ServerSyncService.shared

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var utcTimeString: String {
        Self.utcFormatter.string(from: currentTime)
    }

    @ViewBuilder
    private var radioSlotPills: some View {
        let activeSlots = RadioSlot.allCases.filter { radioManager.slots[$0] != nil }
        if activeSlots.isEmpty {
            EmptyView()
        } else if activeSlots.count == 1, let only = activeSlots.first,
                  let state = radioManager.slotStates[only]
        {
            slotPill(for: only, state: state, showLabel: false)
        } else {
            ForEach(activeSlots) { slot in
                if let state = radioManager.slotStates[slot] {
                    slotPill(for: slot, state: state, showLabel: true)
                }
            }
            audioRoutingPill(activeSlots: activeSlots)
        }
    }

    @ViewBuilder
    private func audioRoutingPill(activeSlots: [RadioSlot]) -> some View {
        let routed = radioManager.audioRoutedSlot
        Button {
            // Toggle routing among connected slots.
            if let nextSlot = activeSlots.first(where: { $0 != routed }) {
                radioManager.setAudioRoutedSlot(nextSlot)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.blue)
                Text(routed.shortLabel)
                    .font(.caption.weight(.semibold))
            }
        }
        .buttonStyle(.plain)
        .help("Audio: \(routed.label) — click to toggle")
        .accessibilityLabel("Audio routed to \(routed.label)")
    }

    @ViewBuilder
    private func slotPill(for slot: RadioSlot, state: RadioSlotState, showLabel: Bool) -> some View {
        let isFocused = radioManager.focusedSlot == slot
        Button {
            radioManager.setFocusedSlot(slot)
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(isFocused ? .green : .secondary)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                if showLabel {
                    Text(slot.shortLabel)
                        .fontWeight(isFocused ? .semibold : .regular)
                        .foregroundStyle(isFocused ? .primary : .secondary)
                }
                Text(String(format: "%.3f", state.frequency))
                    .monospacedDigit()
                Text(state.mode)
                    .foregroundStyle(.secondary)
                if state.contestRole != .none {
                    Text(state.contestRole.label)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(state.contestRole == .run ? Color.blue.opacity(0.2) : Color.purple.opacity(0.2))
                        .foregroundStyle(state.contestRole == .run ? Color.blue : Color.purple)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .font(.caption)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Section("Contest Role") {
                ForEach(ContestSlotRole.allCases) { role in
                    Button(role.label) {
                        radioManager.setContestRole(role, for: slot)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(slot.label)\(isFocused ? " focused" : ""), \(String(format: "%.3f", state.frequency)) MHz, \(state.mode)"
        )
    }

    private func keyerBadge(label: String, wpm: UInt8, sending: Bool, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(color)
            Text("\(label) \(wpm) WPM")
                .monospacedDigit()
            if sending {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
            }
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(wpm) words per minute\(sending ? ", sending" : "")")
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

    /// End the active session and mark it for cloud sync.
    /// Ends ALL CloudKit mirror duplicates sharing the same UUID
    /// so the session doesn't reappear from un-ended mirror rows.
    private func endActiveSession() {
        guard let session = activeSession else {
            return
        }
        let sessionId = session.id
        recentlyEndedSessionIds.insert(sessionId)

        // Fetch all active sessions and end every mirror duplicate
        // sharing this UUID — CloudKit can create ~3x mirror rows.
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.statusRawValue == "active" }
        )
        descriptor.fetchLimit = 20
        var ended: [LoggingSession] = []
        if let activeSessions = try? modelContext.fetch(descriptor) {
            for copy in activeSessions where copy.id == sessionId {
                copy.end()
                copy.cloudDirtyFlag = true
                ended.append(copy)
            }
        }

        try? CwStoreSeams.save(modelContext, sessions: ended)
        activeSession = nil
    }

    /// Fetch the most recent active session, deduplicating CloudKit mirrors
    /// and skipping any session we recently ended locally.
    private func fetchActiveSession() -> LoggingSession? {
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.statusRawValue == "active" },
            sortBy: [SortDescriptor(\LoggingSession.startedAt, order: .reverse)]
        )
        // Fetch a few to dedup CloudKit mirror rows
        descriptor.fetchLimit = 10
        guard let sessions = try? modelContext.fetch(descriptor) else {
            return nil
        }
        // Dedup by UUID, skip recently ended session
        var seen = Set<UUID>()
        for session in sessions {
            guard seen.insert(session.id).inserted else {
                continue
            }
            if recentlyEndedSessionIds.contains(session.id) {
                continue
            }
            return session
        }
        return nil
    }

    /// Lightweight session-only check for periodic timer refresh.
    private func refreshActiveSession() {
        activeSession = fetchActiveSession()
    }

    private func loadCounts() async {
        // Dedup by content key (callsign+band+mode+timestamp) — CloudKit
        // private+shared mirrors can share content but carry different UUIDs,
        // so a UUID-only set still over-counts. Mirrors the Dashboard /
        // Sync Diagnostic Report logic. Batched to stay within 1,000 limit.
        var seenKeys = Set<String>()
        var offset = 0
        let batchSize = BoundedDescriptor<QSO>.maxLimit

        while true {
            let descriptor = BoundedDescriptor<QSO>(
                predicate: #Predicate<QSO> { qso in
                    !qso.isHidden && !qso.callsign.isEmpty
                },
                limit: batchSize,
                offset: offset
            )
            guard let batch = try? modelContext.boundedFetch(descriptor),
                  !batch.isEmpty
            else {
                break
            }
            for qso in batch where !QSOMode.isMetadata(qso.mode) {
                seenKeys.insert(qso.deduplicationKey)
            }
            offset += batch.count
            if batch.count < batchSize {
                break
            }
        }
        qsoCount = seenKeys.count

        activeSession = fetchActiveSession()
    }
}
