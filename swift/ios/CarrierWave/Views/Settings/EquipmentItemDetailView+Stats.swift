import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - Equipment Stats Sections

extension EquipmentItemDetailView {
    @ViewBuilder
    func statsContent(
        _ detail: ComputedEquipmentItemDetail
    ) -> some View {
        usageSummarySection(detail)
        if !detail.bandBreakdown.isEmpty {
            breakdownSection(detail)
        }
        if detail.farthestQSOKm != nil {
            distanceSection(detail)
        }
        if !detail.pairedItems.isEmpty {
            pairedSection(detail)
        }
        if !detail.sessions.isEmpty {
            sessionsSection(detail)
        }
    }

    // MARK: - Usage Summary

    private func usageSummarySection(
        _ detail: ComputedEquipmentItemDetail
    ) -> some View {
        Section("Usage") {
            statRow(
                "QSOs",
                value: "\(detail.totalQSOs)",
                icon: "wave.3.right"
            )
            statRow(
                "Sessions",
                value: "\(detail.sessions.count)",
                icon: "clock"
            )
            if detail.uniqueEntities > 0 {
                statRow(
                    "DXCC Entities",
                    value: "\(detail.uniqueEntities)",
                    icon: "globe"
                )
            }
            if let first = detail.firstUsed {
                statRow(
                    "First Used",
                    value: first.formatted(date: .abbreviated, time: .omitted),
                    icon: "calendar"
                )
            }
            if let last = detail.lastUsed {
                statRow(
                    "Last Used",
                    value: last.formatted(date: .abbreviated, time: .omitted),
                    icon: "calendar.badge.clock"
                )
            }
        }
    }

    // MARK: - Breakdown

    private func breakdownSection(
        _ detail: ComputedEquipmentItemDetail
    ) -> some View {
        Section("Breakdown") {
            if !detail.bandBreakdown.isEmpty {
                breakdownRow(
                    "Bands",
                    items: detail.bandBreakdown.prefix(6).map {
                        "\($0.band) (\($0.count))"
                    }
                )
            }
            if !detail.modeBreakdown.isEmpty {
                breakdownRow(
                    "Modes",
                    items: detail.modeBreakdown.prefix(6).map {
                        "\($0.mode) (\($0.count))"
                    }
                )
            }
        }
    }

    // MARK: - Distance

    private func distanceSection(
        _ detail: ComputedEquipmentItemDetail
    ) -> some View {
        Section("Distance") {
            if let km = detail.farthestQSOKm {
                statRow(
                    "Farthest",
                    value: UnitFormatter.distanceCompact(km),
                    icon: "arrow.up.right"
                )
            }
            if let km = detail.averageQSOKm {
                statRow(
                    "Average",
                    value: UnitFormatter.distanceCompact(km),
                    icon: "equal"
                )
            }
            if let km = detail.shortestQSOKm {
                statRow(
                    "Shortest",
                    value: UnitFormatter.distanceCompact(km),
                    icon: "arrow.down.right"
                )
            }
        }
    }

    // MARK: - Paired Equipment

    private func pairedSection(
        _ detail: ComputedEquipmentItemDetail
    ) -> some View {
        Section("Commonly Used With") {
            ForEach(detail.pairedItems.prefix(5)) { paired in
                HStack(spacing: 10) {
                    Image(systemName: paired.category.icon)
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .frame(width: 20)
                    Text(paired.name)
                        .font(.subheadline)
                    Spacer()
                    Text(
                        "\(paired.sessionCount) session\(paired.sessionCount == 1 ? "" : "s")"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Sessions

    private func sessionsSection(
        _ detail: ComputedEquipmentItemDetail
    ) -> some View {
        let capped = Array(detail.sessions.prefix(50))
        return Section {
            ForEach(capped) { summary in
                sessionSummaryRow(summary)
            }
        } header: {
            HStack {
                Text("Sessions")
                Spacer()
                if detail.sessions.count > 50 {
                    Text("\(detail.sessions.count) total")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sessionSummaryRow(
        _ summary: EquipmentSessionSummary
    ) -> some View {
        NavigationLink {
            LazySessionDetailView(sessionId: summary.id)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sessionTitle(summary))
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(
                        summary.startedAt.formatted(
                            date: .abbreviated, time: .shortened
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(summary.qsoCount) Qs")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func sessionTitle(
        _ summary: EquipmentSessionSummary
    ) -> String {
        if let park = summary.parkReference {
            return "\(park) — \(summary.myCallsign)"
        }
        let type = ActivationType(rawValue: summary.activationType)
            ?? .casual
        if type == .casual {
            return summary.myCallsign
        }
        return "\(type.displayName) — \(summary.myCallsign)"
    }

    private func statRow(
        _ label: String, value: String, icon: String
    ) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func breakdownRow(
        _ label: String, items: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline)
            FlowLayout(spacing: 4) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - LazySessionDetailView

/// Loads a LoggingSession by ID on demand for navigation.
struct LazySessionDetailView: View {
    // MARK: Internal

    let sessionId: UUID

    @Environment(\.modelContext) var modelContext

    var body: some View {
        Group {
            if let session {
                SessionDetailView(session: session)
            } else if hasLoaded {
                ContentUnavailableView(
                    "Session Not Found",
                    systemImage: "clock.badge.questionmark"
                )
            } else {
                ProgressView()
            }
        }
        .task { loadSession() }
    }

    // MARK: Private

    @State private var session: LoggingSession?
    @State private var hasLoaded = false

    private func loadSession() {
        let targetId = sessionId
        var descriptor = FetchDescriptor<LoggingSession>()
        descriptor.fetchLimit = 1
        descriptor.predicate = #Predicate<LoggingSession> { session in
            session.id == targetId
        }
        session = try? modelContext.fetch(descriptor).first
        hasLoaded = true
    }
}
