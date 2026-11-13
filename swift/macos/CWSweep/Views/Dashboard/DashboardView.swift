import CarrierWaveCore
import CarrierWaveData
import Combine
import SwiftData
import SwiftUI

// MARK: - QSOStats

/// Sendable snapshot of QSO statistics computed on a background thread.
private struct QSOStats {
    let totalQSOs: Int
    let todayQSOs: Int
    let uniqueCallsigns: Int
    let bandCounts: [(String, Int)]
    let modeCounts: [(String, Int)]
    /// Session (activation) QSOs per UTC day, for the activity grid.
    let activationByDay: [Date: Int]
    /// Non-session (hunter / imported) QSOs per UTC day.
    let hunterByDay: [Date: Int]
}

private let dashboardValidBands: Set<String> = [
    "160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m",
    "12m", "10m", "6m", "2m", "70cm", "23cm", "13cm",
]

// MARK: - QSOTally

/// Running totals for the dashboard scan (one pass over every real QSO).
private struct QSOTally {
    let sessionIds: Set<UUID>
    let startOfDay = Calendar.current.startOfDay(for: Date())
    var totalCount = 0
    var todayCount = 0
    var callsigns = Set<String>()
    var bands: [String: Int] = [:]
    var modes: [String: Int] = [:]
    var activationByDay: [Date: Int] = [:]
    var hunterByDay: [Date: Int] = [:]

    var stats: QSOStats {
        QSOStats(
            totalQSOs: totalCount,
            todayQSOs: todayCount,
            uniqueCallsigns: callsigns.count,
            bandCounts: bands.sorted { $0.value > $1.value },
            modeCounts: modes.sorted { $0.value > $1.value },
            activationByDay: activationByDay,
            hunterByDay: hunterByDay
        )
    }

    mutating func add(_ qso: QSO) {
        totalCount += 1
        if qso.timestamp >= startOfDay {
            todayCount += 1
        }
        callsigns.insert(qso.callsign.uppercased())
        if dashboardValidBands.contains(qso.band) {
            bands[qso.band, default: 0] += 1
        }
        modes[qso.mode, default: 0] += 1
        let day = qso.utcDateOnly
        if let sessionId = qso.loggingSessionId, sessionIds.contains(sessionId) {
            activationByDay[day, default: 0] += 1
        } else {
            hunterByDay[day, default: 0] += 1
        }
    }
}

// MARK: - DashboardView

/// Dashboard with operating statistics
struct DashboardView: View {
    // MARK: Internal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary cards
                HStack(spacing: 16) {
                    StatCard(title: "Total QSOs", value: "\(totalQSOs)", icon: "number", color: .blue)
                    StatCard(title: "Today", value: "\(todayQSOs)", icon: "calendar", color: .green)
                    StatCard(title: "Unique Calls", value: "\(uniqueCallsigns)", icon: "person.2", color: .purple)
                    StatCard(
                        title: "Sessions",
                        value: "\(totalSessions)",
                        icon: "clock.arrow.circlepath",
                        color: .orange
                    )
                    if amt.isSignedIn {
                        // Another Morse Trainer practice streak (Settings › Accounts).
                        StatCard(
                            title: "Morse Streak",
                            value: amt.currentStreak.map { "\($0)d" } ?? "…",
                            icon: "graduationcap.fill",
                            color: .purple
                        )
                    }
                }

                HStack(alignment: .top, spacing: 20) {
                    // Band breakdown
                    GroupBox("QSOs by Band") {
                        if bandCounts.isEmpty {
                            Text("No QSOs logged yet")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 100)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(bandCounts, id: \.0) { band, count in
                                    HStack {
                                        Text(band)
                                            .frame(width: 50, alignment: .trailing)
                                            .font(.caption.monospacedDigit())
                                        BarSegment(value: count, max: bandCounts.map(\.1).max() ?? 1, color: .blue)
                                        Text("\(count)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .frame(width: 40, alignment: .trailing)
                                    }
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel("\(band): \(count) QSOs")
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    // Mode breakdown
                    GroupBox("QSOs by Mode") {
                        if modeCounts.isEmpty {
                            Text("No QSOs logged yet")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 100)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(modeCounts, id: \.0) { mode, count in
                                    HStack {
                                        Text(mode)
                                            .frame(width: 50, alignment: .trailing)
                                            .font(.caption.monospacedDigit())
                                        BarSegment(value: count, max: modeCounts.map(\.1).max() ?? 1, color: .purple)
                                        Text("\(count)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .frame(width: 40, alignment: .trailing)
                                    }
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel("\(mode): \(count) QSOs")
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                // Activity grid — same data split as Field's dashboard card.
                GroupBox {
                    ActivityGridMac(
                        activationData: activationByDay,
                        activityLogData: hunterByDay,
                        amtData: amt.isSignedIn ? amt.activityByUTCDay : nil
                    )
                    .padding(.vertical, 4)
                } label: {
                    HStack {
                        Text("Activity")
                        Spacer()
                        Text("\(totalQSOs) QSOs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Recent sessions
                GroupBox("Recent Sessions") {
                    if recentSessions.isEmpty {
                        Text("No sessions yet")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 60)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(recentSessions) { session in
                                HStack {
                                    Circle()
                                        .fill(session.isActive ? Color(nsColor: .systemGreen) : Color.secondary)
                                        .frame(width: 6, height: 6)
                                        .accessibilityHidden(true)
                                    Text(session.customTitle ?? session.programsDisplayName)
                                        .fontWeight(.medium)
                                    if session.isActive {
                                        Text("Active")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let park = session.parkReference {
                                        Text(park)
                                            .font(.caption)
                                            .foregroundStyle(Color.accentColor)
                                    }
                                    Spacer()
                                    Text("\(session.qsoCount) QSOs")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(session.startedAt.formatted(.dateTime.month(.abbreviated).day()))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding()
        }
        .task {
            await loadStatistics()
        }
        .task {
            await amt.refreshStatsIfNeeded()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: ModelContext.didSave)
                .debounce(for: .seconds(1), scheduler: RunLoop.main)
        ) { _ in
            Task { await loadStatistics() }
        }
    }

    // MARK: Private

    @State private var totalQSOs = 0
    @State private var todayQSOs = 0
    @State private var uniqueCallsigns = 0
    @State private var bandCounts: [(String, Int)] = []
    @State private var modeCounts: [(String, Int)] = []
    @State private var totalSessions = 0
    @State private var recentSessions: [LoggingSession] = []
    @State private var activationByDay: [Date: Int]?
    @State private var hunterByDay: [Date: Int]?
    @Environment(\.modelContext) private var modelContext

    private var amt: AMTService {
        AMTService.shared
    }

    /// Heavy QSO scan on background thread to avoid blocking main thread.
    private static func computeQSOStats(container: ModelContainer) async -> QSOStats {
        await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let predicate = #Predicate<QSO> { !$0.isHidden }
            var tally = QSOTally(sessionIds: loggingSessionIds(in: context))
            var seenKeys = Set<String>()
            var offset = 0

            while true {
                let descriptor = BoundedDescriptor<QSO>(
                    predicate: predicate,
                    limit: BoundedDescriptor<QSO>.maxLimit,
                    offset: offset
                )
                let batch = (try? context.boundedFetch(descriptor)) ?? []
                if batch.isEmpty {
                    break
                }

                for qso in batch {
                    guard seenKeys.insert(qso.deduplicationKey).inserted,
                          !QSOMode.isMetadata(qso.mode)
                    else {
                        continue
                    }
                    tally.add(qso)
                }
                offset += batch.count
            }

            return tally.stats
        }.value
    }

    /// Ids of every logging session: a QSO linked to one is an activation QSO,
    /// everything else (imported, no session) is a hunter QSO — Field's rule.
    nonisolated private static func loggingSessionIds(in context: ModelContext) -> Set<UUID> {
        var descriptor = FetchDescriptor<LoggingSession>()
        descriptor.propertiesToFetch = [\.id]
        return Set(((try? context.fetch(descriptor)) ?? []).map(\.id))
    }

    private func loadStatistics() async {
        let container = modelContext.container
        let stats = await Self.computeQSOStats(container: container)

        totalQSOs = stats.totalQSOs
        todayQSOs = stats.todayQSOs
        uniqueCallsigns = stats.uniqueCallsigns
        bandCounts = stats.bandCounts
        modeCounts = stats.modeCounts
        activationByDay = stats.activationByDay
        hunterByDay = stats.hunterByDay

        loadSessions()
    }

    /// Load sessions — bounded fetch (max 200), safe on main thread.
    private func loadSessions() {
        var sessionDescriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate<LoggingSession> { $0.qsoCount > 0 },
            sortBy: [SortDescriptor(\LoggingSession.startedAt, order: .reverse)]
        )
        sessionDescriptor.fetchLimit = 200
        let allSessions = (try? modelContext.fetch(sessionDescriptor)) ?? []

        // Content-based dedup — keep copy with highest qsoCount
        var bestByKey: [String: LoggingSession] = [:]
        for session in allSessions {
            let key = "\(Int(session.startedAt.timeIntervalSince1970))|\(session.myCallsign)"
            if let existing = bestByKey[key] {
                if session.qsoCount > existing.qsoCount {
                    bestByKey[key] = session
                }
            } else {
                bestByKey[key] = session
            }
        }

        // Verify actual QSO count — qsoCount can be stale after deletes
        let verified = bestByKey.values
            .filter { hasRealQSOs(session: $0) }
            .sorted { $0.startedAt > $1.startedAt }
        totalSessions = verified.count
        recentSessions = Array(verified.prefix(10))
    }

    private func hasRealQSOs(session: LoggingSession) -> Bool {
        let sessionId = session.id
        var qsoDescriptor = FetchDescriptor<QSO>(
            predicate: #Predicate<QSO> {
                $0.loggingSessionId == sessionId && !$0.isHidden
            }
        )
        qsoDescriptor.fetchLimit = 1
        return ((try? modelContext.fetchCount(qsoDescriptor)) ?? 0) > 0
    }
}

// MARK: - StatCard

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        GroupBox {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Text(value)
                    .font(.title.bold().monospacedDigit())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 100, maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title): \(value)")
        }
    }
}

// MARK: - BarSegment

struct BarSegment: View {
    let value: Int
    let max: Int
    let color: Color

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(0.7))
                .frame(width: max > 0 ? geo.size.width * CGFloat(value) / CGFloat(max) : 0)
        }
        .frame(height: 14)
    }
}
