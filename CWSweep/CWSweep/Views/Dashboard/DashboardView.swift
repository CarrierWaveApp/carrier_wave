import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

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
    }

    // MARK: Private

    /// Modes that represent activation metadata, not actual QSOs (from Ham2K PoLo)
    private static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

    private static let validBands: Set<String> = [
        "160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m",
        "12m", "10m", "6m", "2m", "70cm", "23cm", "13cm",
    ]

    @State private var totalQSOs = 0
    @State private var todayQSOs = 0
    @State private var uniqueCallsigns = 0
    @State private var bandCounts: [(String, Int)] = []
    @State private var modeCounts: [(String, Int)] = []
    @State private var totalSessions = 0
    @State private var recentSessions: [LoggingSession] = []
    @Environment(\.modelContext) private var modelContext

    private func loadStatistics() async {
        // Fetch all non-hidden QSOs
        let allDescriptor = FetchDescriptor<QSO>(
            predicate: #Predicate { !$0.isHidden }
        )
        let allQSOs = (try? modelContext.fetch(allDescriptor)) ?? []

        // Deduplicate by ID — SwiftData may return the same record multiple
        // times when the store contains CloudKit mirroring metadata.
        // Then filter out metadata records (WEATHER, SOLAR, NOTE from Ham2K PoLo).
        var seenIds = Set<UUID>()
        seenIds.reserveCapacity(allQSOs.count)
        let realQSOs = allQSOs.filter { qso in
            seenIds.insert(qso.id).inserted
                && !Self.metadataModes.contains(qso.mode.uppercased())
        }

        totalQSOs = realQSOs.count

        // Today's QSOs
        let startOfDay = Calendar.current.startOfDay(for: Date())
        todayQSOs = realQSOs.filter { $0.timestamp >= startOfDay }.count

        // Unique callsigns
        uniqueCallsigns = Set(realQSOs.map { $0.callsign.uppercased() }).count

        // Band counts (only real bands)
        var bands: [String: Int] = [:]
        for qso in realQSOs {
            if Self.validBands.contains(qso.band) {
                bands[qso.band, default: 0] += 1
            }
        }
        bandCounts = bands.sorted { $0.value > $1.value }

        // Mode counts
        var modes: [String: Int] = [:]
        for qso in realQSOs {
            modes[qso.mode, default: 0] += 1
        }
        modeCounts = modes.sorted { $0.value > $1.value }

        // Sessions (non-empty only)
        let sessionDescriptor = FetchDescriptor<LoggingSession>(
            sortBy: [SortDescriptor(\LoggingSession.startedAt, order: .reverse)]
        )
        let allSessions = (try? modelContext.fetch(sessionDescriptor)) ?? []
        let nonEmptySessions = allSessions.filter { $0.qsoCount > 0 }
        totalSessions = nonEmptySessions.count
        recentSessions = Array(nonEmptySessions.prefix(10))
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
