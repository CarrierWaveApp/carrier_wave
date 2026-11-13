import CarrierWaveData
import SwiftUI

// MARK: - ContestDetailView

/// Detail page for a single contest: schedule, categories, exchange, and
/// which friends have participated (based on completed session activities).
struct ContestDetailView: View {
    // MARK: Internal

    let entry: ContestBrowserEntry
    let refresher: ContestDefinitionsRefresher

    var body: some View {
        List {
            headerSection
            if let definition = loadedDefinition {
                sourceSection(definition: definition)
            }
            scheduleSection
            if let definition = loadedDefinition {
                exchangeSection(definition: definition)
                scoringSection(definition: definition)
                rulesSection(definition: definition)
                categoriesSection(definition: definition)
            }
            participationSection
        }
        .navigationTitle(entry.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDefinitionIfNeeded()
            await loadParticipation()
        }
    }

    // MARK: Private

    @State private var loadedDefinition: ContestDefinition?
    @State private var participation = ContestParticipationStats()
    @State private var isLoadingParticipation = false

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.name)
                    .font(.title3.weight(.semibold))
                if let sponsor = entry.sponsorName {
                    Text(sponsor)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if entry.isLive {
                    Label("Live now", systemImage: "dot.radiowaves.left.and.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var scheduleSection: some View {
        if let occurrence = entry.occurrence {
            Section("Schedule") {
                LabeledContent("Starts") {
                    Text(occurrence.start.formatted(
                        .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()
                    ) + " UTC")
                }
                LabeledContent("Ends") {
                    Text(occurrence.end.formatted(
                        .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()
                    ) + " UTC")
                }
                LabeledContent("Duration") {
                    Text(formatDuration(occurrence.duration))
                }
                if entry.isLive {
                    LabeledContent("Ends in") {
                        Text(formatDuration(occurrence.end.timeIntervalSince(Date())))
                            .foregroundStyle(.green)
                    }
                }
            }
        }
    }

    private var participationSection: some View {
        Section("Participation") {
            if isLoadingParticipation {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if participation.friends.isEmpty, participation.me == nil {
                Text("No one you follow has logged a session for this contest yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                if let mine = participation.me {
                    participationRow(
                        callsign: mine.callsign,
                        subtitle: participantSubtitle(entry: mine),
                        badge: "YOU"
                    )
                }
                ForEach(participation.friends) { participant in
                    participationRow(
                        callsign: participant.callsign,
                        subtitle: participantSubtitle(entry: participant),
                        badge: nil
                    )
                }
            }
        }
    }

    private func sourceSection(definition: ContestDefinition) -> some View {
        Section("Source") {
            LabeledContent("ID", value: definition.id)
            if let sponsor = definition.sponsor {
                if let name = sponsor.name {
                    LabeledContent("Sponsor", value: name)
                }
                if let urlStr = sponsor.url, let url = URL(string: urlStr) {
                    Link(destination: url) {
                        HStack {
                            Text("Rules & Info")
                            Spacer()
                            Image(systemName: "arrow.up.forward.square")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func scoringSection(definition: ContestDefinition) -> some View {
        Section("Scoring") {
            ContestScoringPipelineView(scoring: definition.scoring)
        }
    }

    private func rulesSection(definition: ContestDefinition) -> some View {
        Section("Rules") {
            LabeledContent("Modes", value: definition.modes.joined(separator: ", "))
            LabeledContent("Bands", value: definition.bands.joined(separator: ", "))
            LabeledContent("Dupes", value: dupeSummary(definition.dupeRules))
            if let offTime = definition.operatingConstraints?.offTime?.minimumOffMinutes {
                LabeledContent("Minimum off-time", value: "\(offTime) min")
            }
        }
    }

    private func categoriesSection(definition: ContestDefinition) -> some View {
        Section("Categories") {
            ForEach(definition.categories) { category in
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.label)
                    if !category.powerClasses.isEmpty {
                        Text(category.powerClasses.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !definition.overlayCategories.isEmpty {
                ForEach(definition.overlayCategories) { overlay in
                    LabeledContent(overlay.label, value: "Overlay")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func exchangeSection(definition: ContestDefinition) -> some View {
        Section("Exchange") {
            if !definition.exchange.sent.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Send")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(definition.exchange.sent) { field in
                        exchangeFieldRow(field)
                    }
                }
            }
            if !definition.exchange.received.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Receive")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(definition.exchange.received) { field in
                        exchangeFieldRow(field)
                    }
                }
            }
            ContestExchangeExampleView(exchange: definition.exchange)
        }
    }

    private func exchangeFieldRow(_ field: ContestExchangeField) -> some View {
        HStack {
            Text(field.label)
                .font(.subheadline)
            Spacer()
            if !field.required {
                Text("optional")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func participationRow(callsign: String, subtitle: String?, badge: String?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(callsign)
                        .font(.body.monospaced().weight(.semibold))
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.heavy))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private func participantSubtitle(entry: ContestParticipant) -> String {
        var parts: [String] = []
        if entry.qsoCount > 0 {
            parts.append("\(entry.qsoCount) QSOs")
        }
        if let category = entry.category {
            parts.append(category)
        }
        if let score = entry.score, score > 0 {
            parts.append("Score \(score)")
        }
        if parts.isEmpty {
            return entry.timestamp.formatted(.relative(presentation: .named))
        }
        return parts.joined(separator: " · ")
    }

    private func dupeSummary(_ rules: ContestDupeRules) -> String {
        let scope = rules.scope == .contest ? "whole contest" : "per session"
        let key = rules.key.joined(separator: "+")
        return "\(scope) · \(key)"
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func loadDefinitionIfNeeded() async {
        if loadedDefinition == nil {
            if let existing = entry.definition {
                loadedDefinition = existing
            } else {
                loadedDefinition = await refresher.definition(id: entry.id)
            }
        }
    }

    private func loadParticipation() async {
        isLoadingParticipation = true
        defer { isLoadingParticipation = false }
        let gatherer = ContestParticipationGatherer()
        participation = await gatherer.gather(contestID: entry.id)
    }
}
