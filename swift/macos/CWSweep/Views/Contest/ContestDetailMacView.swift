import CarrierWaveData
import SwiftUI

// MARK: - ContestDetailMacView

/// Rich detail view for a selected contest definition showing header,
/// schedule, exchange, scoring pipeline, rules, categories, and constraints.
/// Optimized for macOS with additional screen real estate.
struct ContestDetailMacView: View {
    // MARK: Internal

    let entry: ContestBrowserEntry
    let refresher: ContestDefinitionsRefresher

    var body: some View {
        Group {
            if let definition = loadedDefinition ?? entry.definition {
                definitionDetail(definition)
            } else if isLoading {
                ProgressView("Loading definition...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("Definition Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("The full definition for this contest couldn't be loaded.")
                } actions: {
                    Button("Retry") {
                        Task { await loadDefinition() }
                    }
                }
            }
        }
        .task(id: entry.id) {
            if entry.definition == nil {
                await loadDefinition()
            }
        }
    }

    // MARK: Private

    @State private var isLoading = false
    @State private var loadedDefinition: ContestDefinition?

    private var liveIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
            Text("LIVE")
                .font(.caption.weight(.heavy))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.green.opacity(0.15), in: Capsule())
        .foregroundStyle(.green)
    }

    private func definitionDetail(_ definition: ContestDefinition) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(definition)
                chipBar(definition)

                if let occurrence = entry.occurrence {
                    scheduleSection(occurrence)
                }

                // Two-column layout for exchange and scoring
                HStack(alignment: .top, spacing: 16) {
                    exchangeSection(definition)
                    if !definition.scoring.phases.isEmpty {
                        scoringSection(definition)
                    }
                }

                rulesSection(definition)

                HStack(alignment: .top, spacing: 16) {
                    if !definition.categories.isEmpty {
                        categoriesSection(definition.categories)
                    }
                    if let constraints = definition.operatingConstraints {
                        constraintsSection(constraints)
                    }
                }

                sourceSection(definition)
            }
            .padding()
        }
    }

    // MARK: - Header

    private func header(_ definition: ContestDefinition) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(definition.displayName)
                        .font(.title.weight(.bold))
                    if definition.displayName != definition.name {
                        Text(definition.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let sponsor = definition.sponsor, let name = sponsor.name {
                        HStack(spacing: 4) {
                            Text(name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let urlStr = sponsor.url, URL(string: urlStr) != nil {
                                Image(systemName: "arrow.up.forward.square")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                Spacer()
                if entry.isLive {
                    liveIndicator
                }
            }
        }
    }

    // MARK: - Chip Bar

    private func chipBar(_ definition: ContestDefinition) -> some View {
        HStack(spacing: 8) {
            ContestModeChips(modes: definition.modes)
            ContestBandChips(bands: definition.bands)
            if let occurrence = entry.occurrence {
                let hours = Int(occurrence.duration) / 3_600
                ContestChip(text: "\(hours)h", color: .purple, systemImage: "clock")
            }
        }
    }

    // MARK: - Schedule

    private func scheduleSection(_ occurrence: ContestOccurrence) -> some View {
        GroupBox {
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(occurrence.start.formatted(
                        .dateTime.weekday(.abbreviated).month(.abbreviated)
                            .day().hour().minute()
                    ) + " UTC")
                        .font(.body.monospaced())
                }
                Divider().frame(height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("End")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(occurrence.end.formatted(
                        .dateTime.weekday(.abbreviated).month(.abbreviated)
                            .day().hour().minute()
                    ) + " UTC")
                        .font(.body.monospaced())
                }
                Divider().frame(height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Duration")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(formatDuration(occurrence.duration))
                        .font(.body.monospaced())
                }
                if entry.isLive {
                    Divider().frame(height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remaining")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(formatDuration(occurrence.end.timeIntervalSince(Date())))
                            .font(.body.monospaced())
                            .foregroundStyle(.green)
                    }
                }
                Spacer()
            }
        } label: {
            Label("Schedule", systemImage: "calendar")
        }
    }

    // MARK: - Exchange

    private func exchangeSection(_ definition: ContestDefinition) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if !definition.exchange.sent.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SEND")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        exchangeSummary(definition.exchange.sent)
                        ForEach(definition.exchange.sent) { field in
                            exchangeFieldRow(field)
                        }
                    }
                }
                if !definition.exchange.received.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("RECEIVE")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        exchangeSummary(definition.exchange.received)
                        ForEach(definition.exchange.received) { field in
                            exchangeFieldRow(field)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Exchange", systemImage: "arrow.left.arrow.right")
        }
    }

    private func exchangeSummary(_ fields: [ContestExchangeField]) -> some View {
        Text(fields.map(\.label).joined(separator: " + "))
            .font(.body.monospaced().weight(.medium))
            .foregroundStyle(.primary)
    }

    private func exchangeFieldRow(_ field: ContestExchangeField) -> some View {
        HStack {
            Text(field.label)
                .font(.caption)
            Spacer()
            HStack(spacing: 4) {
                if !field.required {
                    Text("optional")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text(field.type.rawValue.replacingOccurrences(of: "_", with: " "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
            }
        }
    }

    // MARK: - Scoring

    private func scoringSection(_ definition: ContestDefinition) -> some View {
        GroupBox {
            ContestScoringPipelineView(scoring: definition.scoring)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Scoring Pipeline", systemImage: "function")
        }
    }

    private func loadDefinition() async {
        isLoading = true
        loadedDefinition = await refresher.definition(id: entry.id)
        isLoading = false
    }
}
