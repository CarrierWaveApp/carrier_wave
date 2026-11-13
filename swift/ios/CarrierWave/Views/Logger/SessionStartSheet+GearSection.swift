import CarrierWaveData
import SwiftUI

// MARK: - SessionStartSheet Gear Section

/// The form-native Gear section (approved "Option A" mockup). A loadout
/// pull-down selector on top, then — expanded — four inline component menus
/// (Radio/Antenna/Key/Mic) with fully-inline add. Collapsed, it shows a gear
/// summary that expands on tap. Replaces the old hero gear strip +
/// LoadoutEditSheet/InventoryPickerSheet drill-down.
extension SessionStartSheet {
    var gearSection: some View {
        Section {
            loadoutMenuRow
            if gearExpanded {
                GearComponentMenu(
                    category: .radio,
                    selection: $selectedRadio,
                    inventory: inventoryModel,
                    onSelect: { onGearComponentPicked(.radio, $0) }
                )
                GearComponentMenu(
                    category: .antenna,
                    selection: $selectedAntenna,
                    inventory: inventoryModel,
                    onSelect: { onGearComponentPicked(.antenna, $0) }
                )
                GearComponentMenu(
                    category: .key,
                    selection: $selectedKey,
                    inventory: inventoryModel,
                    enabled: modeUsesKey,
                    onSelect: { onGearComponentPicked(.key, $0) }
                )
                GearComponentMenu(
                    category: .microphone,
                    selection: $selectedMic,
                    inventory: inventoryModel,
                    enabled: modeUsesMic,
                    onSelect: { onGearComponentPicked(.microphone, $0) }
                )
                hideItemsRow
            } else {
                gearSummaryRow
            }
            powerRow
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            if let warning = powerWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.subheadline)
                    .foregroundStyle(Color.purple)
                    .accessibilityHidden(true)
                Text("Gear")
            }
        } footer: {
            Text(gearExpanded
                ? "Editing an item marks the loadout “Custom.” Key/mic follows your mode."
                : "Tap the loadout to switch it. Tap the gear list to adjust today’s items.")
        }
        .headerProminence(.increased)
        .alert("New Loadout", isPresented: $showNewLoadoutDialog) {
            TextField("e.g. Backpack CW", text: $loadoutNameField)
            Button("Cancel", role: .cancel) {}
            Button("Create") { newLoadout(loadoutNameField) }
        } message: {
            Text("Name it, then add your gear below.")
        }
        .alert("Save Gear as Loadout", isPresented: $showSaveLoadoutDialog) {
            TextField("e.g. KX2 POTA", text: $loadoutNameField)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveCurrentGearAsLoadout(loadoutNameField) }
        } message: {
            Text("Save today’s gear as a reusable loadout.")
        }
        .alert("Rename Loadout", isPresented: $showRenameLoadoutDialog) {
            TextField("Loadout name", text: $loadoutNameField)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { renameActiveLoadout(loadoutNameField) }
        } message: {
            Text("Enter a new name for this loadout.")
        }
    }

    // MARK: - Loadout selector row (the primary pull-down)

    private var loadoutMenuRow: some View {
        Menu {
            if !loadouts.isEmpty {
                Section("Switch loadout") {
                    ForEach(loadouts) { loadout in
                        Button {
                            applyLoadout(loadout)
                        } label: {
                            if appliedLoadoutId == loadout.id {
                                Label(loadout.name, systemImage: "checkmark")
                            } else {
                                Text(loadout.name)
                            }
                        }
                    }
                }
            }
            Button {
                presentNewLoadoutDialog()
            } label: {
                Label("New loadout…", systemImage: "plus")
            }
            if hasAnyGearSelected {
                Button {
                    presentSaveLoadoutDialog()
                } label: {
                    Label("Save current gear as loadout…", systemImage: "square.and.arrow.down")
                }
            }
            if let active = activeLoadout {
                Button {
                    presentRenameLoadoutDialog()
                } label: {
                    Label("Rename “\(active.name)”…", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    deleteLoadout(active)
                } label: {
                    Label("Delete “\(active.name)”", systemImage: "trash")
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(loadoutRowTitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Color.purple)
            }
            .contentShape(Rectangle())
        }
    }

    // MARK: - Collapsed summary / expand-collapse rows

    private var gearSummaryRow: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { gearExpanded = true }
        } label: {
            HStack {
                Text(gearSummaryText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var hideItemsRow: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { gearExpanded = false }
        } label: {
            HStack {
                Text("Hide items")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Derived state

    /// The four equipment display names in slot order, quiet-joined.
    var gearNames: String {
        [selectedRadio, selectedAntenna, selectedKey, selectedMic]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var gearSummaryText: String {
        hasAnyGearSelected ? gearNames : "No gear selected"
    }

    var hasAnyGearSelected: Bool {
        [selectedRadio, selectedAntenna, selectedKey, selectedMic].contains { !($0?.isEmpty ?? true) }
    }

    var activeLoadout: Loadout? {
        guard let id = appliedLoadoutId else {
            return nil
        }
        return loadouts.first { $0.id == id }
    }

    private var loadoutRowTitle: String {
        if let active = activeLoadout {
            return active.name
        }
        return hasAnyGearSelected ? "Custom" : "No loadout"
    }

    /// CW uses a key/paddle; phone modes use a mic. Digital dims both.
    var modeUsesKey: Bool {
        selectedMode == "CW"
    }

    var modeUsesMic: Bool {
        ["SSB", "AM", "FM"].contains(selectedMode)
    }

    // MARK: - Component pick → capture radioItemID + mark Custom

    private func onGearComponentPicked(_ category: EquipmentCategory, _ snapshot: EquipmentInventorySnapshot?) {
        if category == .radio {
            selectedRadioItemID = snapshot?.id
        }
        // A manual component change breaks the applied loadout (now "Custom").
        appliedLoadoutId = nil
    }

    // MARK: - Dialog presentation

    private func presentNewLoadoutDialog() {
        loadoutNameField = ""
        showNewLoadoutDialog = true
    }

    private func presentSaveLoadoutDialog() {
        loadoutNameField = ""
        showSaveLoadoutDialog = true
    }

    private func presentRenameLoadoutDialog() {
        loadoutNameField = activeLoadout?.name ?? ""
        showRenameLoadoutDialog = true
    }
}
