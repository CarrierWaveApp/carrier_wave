import SwiftData
import SwiftUI

// MARK: - BandScopeContainerView

/// Band Scope v2 root: the Scope/Heard segmented toggle with BOTH lenses
/// kept mounted (§0/§15 — flipping preserves scroll position, expanded
/// pileups, and the pending pill), the goal-profile mode pill with the
/// honest `173 → 41` count (§17), and the shared peek sheet.
struct BandScopeContainerView: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            header
            filterBar
            if lens == .scope {
                ScrubberStrip(model: model)
            }
            ZStack {
                ScopeListView(model: model, peekSpot: $peekSpot, peekQSY: $peekQSY)
                    .opacity(lens == .scope ? 1 : 0)
                    .allowsHitTesting(lens == .scope)
                HeardListView(model: model, peekSpot: $peekSpot)
                    .opacity(lens == .heard ? 1 : 0)
                    .allowsHitTesting(lens == .heard)
            }
        }
        .background(BandScopeTheme.background)
        .navigationTitle("Band Scope")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if activityLogManager == nil {
                activityLogManager = ActivityLogManager(modelContext: modelContext)
            }
            model.start()
        }
        .onDisappear {
            model.stop()
        }
        .sheet(item: $peekSpot) { spot in
            if let manager = activityLogManager {
                PeekSheet(spot: spot, model: model, manager: manager)
            }
        }
        .sheet(item: $peekQSY) { gap in
            QSYSheet(gap: gap, band: model.activeBand, model: model)
        }
        .sheet(isPresented: $showProfilePicker) {
            GoalProfileSheet(model: model)
        }
    }

    // MARK: Private

    private enum Lens {
        case scope
        case heard
    }

    private static let hfBands = [
        "160m", "80m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m",
    ]

    @Environment(\.modelContext) private var modelContext

    @State private var model = BandScopeViewModel()
    @State private var activityLogManager: ActivityLogManager?
    @State private var lens: Lens = .scope
    @State private var peekSpot: EnrichedSpot?
    @State private var peekQSY: ScopeGap?
    @State private var showProfilePicker = false

    /// Segmented lens toggle left, contextual control right (§15).
    private var header: some View {
        HStack(spacing: 12) {
            Picker("Lens", selection: $lens) {
                Text("Scope").tag(Lens.scope)
                Text("Heard").tag(Lens.heard)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)

            Spacer()

            if lens == .scope {
                bandMenu
            } else {
                Text("\(model.heardVisibleCount) stations")
                    .font(.caption.monospaced())
                    .foregroundStyle(BandScopeTheme.dim)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// Mode pill (always shows the active profile, §17) + honest count +
    /// quick toggles.
    private var filterBar: some View {
        HStack(spacing: 10) {
            Button {
                showProfilePicker = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "scope")
                        .font(.caption2)
                    Text(model.activeProfile.name)
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(BandScopeTheme.surface2, in: Capsule())
                .foregroundStyle(BandScopeTheme.text)
            }

            countIndicator

            Spacer()

            quickToggleButtons
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// `173 → 41` whenever any filtering is active — suppression must be
    /// impossible to forget (§17).
    @ViewBuilder
    private var countIndicator: some View {
        let unfiltered = lens == .scope
            ? model.scopeUnfilteredCount : model.heardUnfilteredCount
        let visible = lens == .scope
            ? model.filterService.scopePassIDs.count : model.heardVisibleCount
        if model.filterService.isFiltering {
            Text("\(unfiltered) → \(min(visible, unfiltered))")
                .font(.caption.monospaced())
                .foregroundStyle(BandScopeTheme.amber)
        } else {
            Text("\(unfiltered)")
                .font(.caption.monospaced())
                .foregroundStyle(BandScopeTheme.dim)
        }
    }

    private var quickToggleButtons: some View {
        HStack(spacing: 8) {
            modeFilterMenu
            QuickToggleButton(
                label: model.profileStore.quickToggles.wpmCeiling.map { "≤\($0) wpm" }
                    ?? "wpm",
                isOn: model.profileStore.quickToggles.wpmCeiling != nil
            ) {
                cycleWPMCeiling()
            }
            QuickToggleButton(
                label: "dupes",
                isOn: model.profileStore.quickToggles.suppressWorkedToday
            ) {
                model.profileStore.quickToggles.suppressWorkedToday.toggle()
                model.applyProfile()
            }
            QuickToggleButton(
                label: "rbn",
                isOn: model.profileStore.quickToggles.rbnEnabled
            ) {
                model.profileStore.quickToggles.rbnEnabled.toggle()
                model.applyProfile()
            }
        }
    }

    /// Radio-mode filter (hide in Heard, dim in Scope): menu chip with one
    /// checkable entry per mode group; empty selection = all modes.
    private var modeFilterMenu: some View {
        let enabled = model.profileStore.quickToggles.modeGroups ?? []
        return Menu {
            ForEach(QuickToggles.ModeGroup.allCases, id: \.self) { group in
                Button {
                    toggleModeGroup(group)
                } label: {
                    if enabled.contains(group) {
                        Label(group.label, systemImage: "checkmark")
                    } else {
                        Text(group.label)
                    }
                }
            }
            if !enabled.isEmpty {
                Divider()
                Button("All modes") {
                    model.profileStore.quickToggles.modeGroups = nil
                    model.applyProfile()
                }
            }
        } label: {
            Text(
                enabled.isEmpty
                    ? "mode"
                    : enabled.map(\.label).joined(separator: "·").lowercased()
            )
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                enabled.isEmpty ? BandScopeTheme.surface : BandScopeTheme.blue.opacity(0.2),
                in: Capsule()
            )
            .foregroundStyle(enabled.isEmpty ? BandScopeTheme.dim : BandScopeTheme.text)
            .overlay(Capsule().strokeBorder(BandScopeTheme.line))
        }
    }

    private var bandMenu: some View {
        Menu {
            Button("Follow radio") {
                model.manualBand = nil
            }
            ForEach(Self.hfBands, id: \.self) { band in
                Button(band) {
                    model.manualBand = band
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(model.activeBand)
                    .font(.subheadline.monospaced().weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(BandScopeTheme.text)
        }
    }

    private func toggleModeGroup(_ group: QuickToggles.ModeGroup) {
        var groups = model.profileStore.quickToggles.modeGroups ?? []
        if let index = groups.firstIndex(of: group) {
            groups.remove(at: index)
        } else {
            groups.append(group)
        }
        model.profileStore.quickToggles.modeGroups = groups.isEmpty ? nil : groups
        model.applyProfile()
    }

    /// WPM ceiling stepper-in-a-button: off → 15 → 18 → 22 → 28 → off.
    private func cycleWPMCeiling() {
        let steps = [15, 18, 22, 28]
        var toggles = model.profileStore.quickToggles
        let currentIndex = toggles.wpmCeiling.flatMap { steps.firstIndex(of: $0) }
        if let currentIndex, currentIndex + 1 < steps.count {
            toggles.wpmCeiling = steps[currentIndex + 1]
        } else if toggles.wpmCeiling == nil {
            toggles.wpmCeiling = steps[0]
        } else {
            toggles.wpmCeiling = nil
        }
        model.profileStore.quickToggles = toggles
        model.applyProfile()
    }
}

// MARK: - QuickToggleButton

private struct QuickToggleButton: View {
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    isOn ? BandScopeTheme.blue.opacity(0.2) : BandScopeTheme.surface,
                    in: Capsule()
                )
                .foregroundStyle(isOn ? BandScopeTheme.text : BandScopeTheme.dim)
                .overlay(Capsule().strokeBorder(BandScopeTheme.line))
        }
    }
}
