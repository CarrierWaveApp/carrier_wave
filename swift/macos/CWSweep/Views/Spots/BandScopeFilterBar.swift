import CarrierWaveData
import SwiftUI

// MARK: - BandScopeFilterBar

/// Collapsible filter bar for the band scope.
/// Controls source toggles, status filter, region filter, and the
/// optional SQL query mode that overrides the widget filters with a
/// user-picked saved query's allow-list of `spot_id`s.
struct BandScopeFilterBar: View {
    // MARK: Internal

    @Binding var enabledSources: Set<SpotSource>
    @Binding var statusFilter: SpotStatusFilter
    @Binding var enabledContinents: Set<SpotContinent>
    @Binding var isExpanded: Bool
    @Binding var filterMode: BandScopeFilterMode

    var savedQueries: [SavedQuery] = []
    var validQueryIDs: Set<UUID> = []
    var queryError: String?

    var body: some View {
        VStack(spacing: 0) {
            compactBar
            if filterMode != .widgets, let queryError {
                errorBanner(queryError)
            }
            if isExpanded {
                Divider()
                expandedFilters
            }
        }
        .background(.background)
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow

    private var modeLabel: String {
        switch filterMode {
        case .widgets:
            "Filter: Widgets"
        case let .savedQuery(uuid):
            if let query = savedQueries.first(where: { $0.id == uuid }) {
                "Query: \(query.name)"
            } else {
                "Query: (missing)"
            }
        }
    }

    private var compactBar: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                Label("Filters", systemImage: "line.3.horizontal.decrease")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(filterMode != .widgets)

            if !isExpanded, filterMode == .widgets {
                compactSummary
            }

            Spacer()

            modePicker
            if filterMode == .widgets {
                Picker("Status", selection: $statusFilter) {
                    ForEach(SpotStatusFilter.allCases) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }

    /// Two-state picker that swaps between the widget-driven filter and
    /// a saved SQL query as the source of truth for what the band scope
    /// renders.
    private var modePicker: some View {
        Menu {
            Button("Widgets") {
                filterMode = .widgets
            }
            if !savedQueries.isEmpty {
                Divider()
                let usable = savedQueries.filter { validQueryIDs.contains($0.id) }
                let unusable = savedQueries.filter { !validQueryIDs.contains($0.id) }
                ForEach(usable) { query in
                    Button(query.name) {
                        filterMode = .savedQuery(query.id)
                    }
                }
                if !unusable.isEmpty {
                    Divider()
                    ForEach(unusable) { query in
                        Button {
                            openWindow(id: "query-workbench")
                        } label: {
                            Label(
                                "\(query.name)  —  ⚠ Missing spot_id (tap to fix)",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                        }
                    }
                }
                Divider()
                Button("Open Query Workbench…") {
                    openWindow(id: "query-workbench")
                }
            } else {
                Text("No saved queries — open the Query Workbench (⌘K → Open Query Workbench) to create one.")
                    .foregroundStyle(.secondary)
            }
        } label: {
            HStack(spacing: 3) {
                Text(modeLabel)
                    .font(.caption)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.5), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var compactSummary: some View {
        HStack(spacing: 4) {
            let disabledCount = SpotSource.allCases.count - enabledSources.count
            if disabledCount > 0 {
                Text("\(disabledCount) source\(disabledCount == 1 ? "" : "s") hidden")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            let hiddenContinents = SpotContinent.allCases.count - enabledContinents.count
            if hiddenContinents > 0 {
                Text("\(hiddenContinents) continent\(hiddenContinents == 1 ? "" : "s") hidden")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var expandedFilters: some View {
        VStack(alignment: .leading, spacing: 6) {
            sourceToggles
            continentToggles
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var sourceToggles: some View {
        HStack(spacing: 4) {
            Text("Sources:").font(.caption2).foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            ForEach(SpotSource.allCases, id: \.rawValue) { source in
                sourceChip(source)
            }
            Spacer()
            Button("All") {
                enabledSources = Set(SpotSource.allCases)
            }
            .font(.caption2)
            .buttonStyle(.borderless)
            .disabled(enabledSources.count == SpotSource.allCases.count)
        }
    }

    private var continentToggles: some View {
        HStack(spacing: 4) {
            Text("Continents:").font(.caption2).foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            ForEach(SpotContinent.allCases, id: \.rawValue) { cont in
                continentChip(cont)
            }
            Spacer()
            Button("All") {
                enabledContinents = SpotContinent.allSet
            }
            .font(.caption2)
            .buttonStyle(.borderless)
            .disabled(enabledContinents.count == SpotContinent.allCases.count)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.08))
    }

    private func sourceChip(_ source: SpotSource) -> some View {
        let isOn = enabledSources.contains(source)
        return Button {
            if isOn {
                enabledSources.remove(source)
            } else {
                enabledSources.insert(source)
            }
        } label: {
            Text(source.displayName)
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    isOn
                        ? SpotColorScheme.sourceColor(source).opacity(0.25)
                        : Color.secondary.opacity(0.1),
                    in: Capsule()
                )
                .foregroundStyle(isOn ? .primary : .tertiary)
        }
        .buttonStyle(.borderless)
    }

    private func continentChip(_ cont: SpotContinent) -> some View {
        let isOn = enabledContinents.contains(cont)
        return Button {
            if isOn {
                enabledContinents.remove(cont)
            } else {
                enabledContinents.insert(cont)
            }
        } label: {
            Text(cont.rawValue)
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    isOn
                        ? Color.accentColor.opacity(0.2)
                        : Color.secondary.opacity(0.1),
                    in: Capsule()
                )
                .foregroundStyle(isOn ? .primary : .tertiary)
        }
        .buttonStyle(.borderless)
    }
}
