import CarrierWaveData
import SwiftUI

// MARK: - SessionStartSheet Contest Section

extension SessionStartSheet {
    var contestSection: some View {
        Section {
            if let contest = selectedContest {
                contestSelectedCard(contest)
            } else {
                contestPickerButton
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "trophy")
                    .font(.subheadline)
                    .foregroundStyle(Color.purple)
                    .accessibilityHidden(true)
                Text("Contest")
            }
        } footer: {
            if selectedContest == nil {
                Text("Select a contest for scoring, dupe checking, and Cabrillo export.")
            } else if let occurrence = activeContestOccurrence {
                Text(scheduleFooter(for: occurrence))
                    .font(.caption)
            }
        }
        .headerProminence(.increased)
    }

    private var contestPickerButton: some View {
        Button {
            showContestPicker = true
        } label: {
            HStack {
                Label("Select Contest", systemImage: "trophy")
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    func contestSelectedCard(
        _ contest: ContestDefinition
    ) -> some View {
        contestHeaderCard(contest)
        contestCategoryPicker(contest)
        contestOverlayPicker(contest)
        contestPowerPicker(contest)
        contestBandPicker(contest)
        contestChangeButton
    }

    // MARK: - Row helpers

    private func contestHeaderCard(_ contest: ContestDefinition) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(contest.name)
                    .font(.headline)
                let receivedLabels = contest.exchange.received.map(\.label)
                Text("Exchange: \(receivedLabels.joined(separator: " + "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                selectedContest = nil
                contestCategory = ""
                contestOverlayCategory = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    @ViewBuilder
    private func contestCategoryPicker(_ contest: ContestDefinition) -> some View {
        if !contest.categories.isEmpty {
            Picker("Category", selection: $contestCategory) {
                ForEach(contest.categories) { category in
                    Text(category.label).tag(category.id)
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
    }

    @ViewBuilder
    private func contestOverlayPicker(_ contest: ContestDefinition) -> some View {
        if !contest.overlayCategories.isEmpty {
            Picker("Overlay", selection: $contestOverlayCategory) {
                Text("None").tag("")
                ForEach(contest.overlayCategories) { overlay in
                    Text(overlay.label).tag(overlay.id)
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
    }

    @ViewBuilder
    private func contestPowerPicker(_ contest: ContestDefinition) -> some View {
        let powers = contest.categories
            .first { $0.id == contestCategory }?
            .powerClasses ?? ["HIGH", "LOW", "QRP"]
        if !powers.isEmpty {
            Picker("Power", selection: $contestPowerClass) {
                ForEach(powers, id: \.self) { power in
                    Text(power.capitalized).tag(power)
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
    }

    private func contestBandPicker(_ contest: ContestDefinition) -> some View {
        Picker("Bands", selection: $contestBands) {
            Text("All Bands").tag("ALL")
            ForEach(contest.bands, id: \.self) { band in
                Text(band).tag(band)
            }
        }
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    private var contestChangeButton: some View {
        Button {
            showContestPicker = true
        } label: {
            Label("Change Contest", systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline)
        }
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    // MARK: - Picker sheet + selection handling

    var contestPickerSheetContent: some View {
        NavigationStack {
            ContestCalendarView(onSelectDefinition: { definition in
                selectedContest = definition
                showContestPicker = false
            })
        }
    }

    /// Persist the picked id so the next Contest intent tap bypasses the
    /// picker (returning contester gets one-tap entry).
    func handleContestSelection(_ newValue: ContestDefinition?) {
        applyContestDefaults(newValue)
        if let id = newValue?.id {
            defaultContestId = id
        } else {
            defaultContestId = ""
        }
    }

    // MARK: - Intent-driven contest pre-fill

    /// Honour the Contest intent's `initialContestId`:
    /// - `nil`: do nothing (sheet was opened via Activate/Casual or a deep
    ///   link without contest intent).
    /// - Empty string: auto-present the picker so the operator's first
    ///   interaction is choosing a contest.
    /// - Non-empty: try to load the matching `ContestDefinition` from the
    ///   server-published catalog and pre-select it. On failure (network
    ///   error / contest withdrawn), fall back to auto-presenting the
    ///   picker — the operator just sees an empty contest section and
    ///   picks again.
    @MainActor
    func applyContestIntentIfNeeded() async {
        guard let id = initialContestId, selectedContest == nil else {
            return
        }
        if id.isEmpty {
            showContestPicker = true
            return
        }
        let refresher = ContestDefinitionsRefresher()
        await refresher.refreshIfStale()
        if let definition = await refresher.definition(id: id) {
            selectedContest = definition
        } else {
            showContestPicker = true
        }
    }

    // MARK: - Defaults

    func applyContestDefaults(_ definition: ContestDefinition?) {
        guard let definition else {
            contestCategory = ""
            contestOverlayCategory = ""
            return
        }
        if contestCategory.isEmpty, let first = definition.categories.first {
            contestCategory = first.id
            if let firstPower = first.powerClasses.first {
                contestPowerClass = firstPower
            }
        }
    }

    // MARK: - Schedule footer

    private var activeContestOccurrence: ContestOccurrence? {
        guard let contest = selectedContest else {
            return nil
        }
        return ContestScheduleEvaluator.activeOccurrence(schedule: contest.schedule)
            ?? ContestScheduleEvaluator.nextOccurrence(schedule: contest.schedule)
    }

    private func scheduleFooter(for occurrence: ContestOccurrence) -> String {
        let now = Date()
        if occurrence.contains(now) {
            let remaining = occurrence.end.timeIntervalSince(now)
            return "In progress — \(Self.formatHours(remaining)) remaining"
        }
        let relative = occurrence.start.formatted(.relative(presentation: .named))
        return "Next session: \(relative)"
    }

    private static func formatHours(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3_600
        let minutes = (Int(seconds) % 3_600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
