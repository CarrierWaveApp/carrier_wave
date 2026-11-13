import CarrierWaveData
import SwiftUI

// MARK: - SessionStartSheet Loadout Actions

/// A loadout is a named, equipment-only collection (radio/antenna/key/mic),
/// persisted in the Rust `loadout` table via `LoadoutStore`. The picking UI is
/// the Gear section's pull-down (`SessionStartSheet+GearSection.swift`); these
/// are the load/apply/create/rename/delete actions. Internal (not private)
/// because Swift extensions in other files can't reach private members.
extension SessionStartSheet {
    /// Kick off the initial load of saved loadouts (called from `.task`).
    func loadSavedLoadouts() {
        Task { await reloadLoadouts() }
    }

    func reloadLoadouts() async {
        guard let store = try? await Equipment.loadouts(),
              let list = try? await store.all()
        else {
            return
        }
        loadouts = list
    }

    /// Switch to a saved loadout — a full gear replace (empty slots clear).
    func applyLoadout(_ loadout: Loadout) {
        withAnimation(.easeOut(duration: 0.18)) {
            selectedRadio = loadout.radio
            selectedAntenna = loadout.antenna
            selectedKey = loadout.key
            selectedMic = loadout.mic
            selectedRadioItemID = loadout.radioItemID
            appliedLoadoutId = loadout.id
        }
    }

    /// Create a fresh, empty loadout: clear the slots and expand so the operator
    /// fills it in inline.
    func newLoadout(_ rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            return
        }
        let loadout = Loadout(name: name)
        withAnimation(.easeOut(duration: 0.18)) {
            selectedRadio = nil
            selectedAntenna = nil
            selectedKey = nil
            selectedMic = nil
            selectedRadioItemID = nil
            appliedLoadoutId = loadout.id
            gearExpanded = true
        }
        Task { await persist(loadout) }
    }

    /// Snapshot the current gear selections as a new named loadout.
    func saveCurrentGearAsLoadout(_ rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            return
        }
        let loadout = Loadout(
            name: name,
            radio: selectedRadio,
            antenna: selectedAntenna,
            key: selectedKey,
            mic: selectedMic,
            radioItemID: selectedRadioItemID
        )
        appliedLoadoutId = loadout.id
        Task { await persist(loadout) }
    }

    /// Rename the applied loadout in place.
    func renameActiveLoadout(_ rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, var loadout = activeLoadout else {
            return
        }
        loadout.name = name
        loadout.updatedAt = Date()
        Task { await persist(loadout) }
    }

    func deleteLoadout(_ loadout: Loadout) {
        if appliedLoadoutId == loadout.id {
            appliedLoadoutId = nil
        }
        withAnimation(.easeOut(duration: 0.2)) {
            loadouts.removeAll { $0.id == loadout.id }
        }
        Task {
            if let store = try? await Equipment.loadouts() {
                try? await store.delete(id: loadout.id)
            }
            await reloadLoadouts()
        }
    }

    // MARK: - Private

    private func persist(_ loadout: Loadout) async {
        guard let store = try? await Equipment.loadouts() else {
            return
        }
        try? await store.upsert(loadout)
        await reloadLoadouts()
    }
}
