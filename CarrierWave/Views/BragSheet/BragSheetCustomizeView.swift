import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - BragSheetCustomizeView

/// Sheet for customizing which stats appear on the brag sheet.
/// Supports preset selection and per-stat enable/hero toggles.
struct BragSheetCustomizeView: View {
    // MARK: Internal

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext
    @Bindable var bragStats: AsyncBragSheetStats

    var body: some View {
        NavigationStack {
            List {
                presetSection
                statSections
            }
            .navigationTitle("Customize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    periodPickerMenu
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onDisappear {
                bragStats.saveAndRecompute(from: modelContext.container)
            }
        }
        .presentationDetents([.large])
        .onAppear {
            editingPeriod = bragStats.selectedPeriod
        }
    }

    // MARK: Private

    @State private var editingPeriod: BragSheetPeriod = .weekly

    private var periodConfig: BragSheetPeriodConfig {
        bragStats.configuration.config(for: editingPeriod)
    }

    // MARK: - Period Picker

    private var periodPickerMenu: some View {
        Menu {
            ForEach(BragSheetPeriod.allCases) { period in
                Button {
                    editingPeriod = period
                } label: {
                    HStack {
                        Text(period.displayName)
                        if period == editingPeriod {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(editingPeriod.displayName)
                    .font(.subheadline)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
        }
    }

    // MARK: - Preset Chips

    private var presetSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BragSheetPreset.allCases) { preset in
                        presetChip(preset)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Presets")
        }
    }

    // MARK: - Stat Category Sections

    private var statSections: some View {
        ForEach(BragSheetCategory.allCases) { category in
            Section {
                ForEach(category.stats) { stat in
                    BragStatCustomizeRow(
                        stat: stat,
                        isEnabled: periodConfig.enabledStats.contains(stat),
                        isHero: periodConfig.heroStats.contains(stat),
                        heroCount: periodConfig.heroStats.count,
                        onToggleEnabled: {
                            bragStats.configuration.config(for: editingPeriod)
                                .enabledStats.contains(stat)
                                ? removeStat(stat) : addStat(stat)
                        },
                        onToggleHero: { toggleHero(stat) }
                    )
                }
            } header: {
                Label(category.displayName, systemImage: category.systemImage)
            }
        }
    }

    private func presetChip(_ preset: BragSheetPreset) -> some View {
        let isActive = periodConfig.basePreset == preset

        return Button {
            bragStats.configuration.applyPreset(preset, to: editingPeriod)
        } label: {
            HStack(spacing: 4) {
                Text(preset.displayName)
                    .font(.subheadline)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isActive ? Color.accentColor : Color(.systemGray5))
            .foregroundStyle(isActive ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mutations

    private func addStat(_ stat: BragSheetStatType) {
        var config = bragStats.configuration.config(for: editingPeriod)
        config.enabledStats.append(stat)
        config.basePreset = nil
        bragStats.configuration.setConfig(config, for: editingPeriod)
    }

    private func removeStat(_ stat: BragSheetStatType) {
        var config = bragStats.configuration.config(for: editingPeriod)
        config.enabledStats.removeAll { $0 == stat }
        config.heroStats.removeAll { $0 == stat }
        config.basePreset = nil
        bragStats.configuration.setConfig(config, for: editingPeriod)
    }

    private func toggleHero(_ stat: BragSheetStatType) {
        var config = bragStats.configuration.config(for: editingPeriod)
        let success = config.toggleHero(stat)
        if !success {
            // At hero limit — provide haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
            return
        }
        config.basePreset = nil
        bragStats.configuration.setConfig(config, for: editingPeriod)
    }
}
