// Equipment Inventory Model
//
// The shared, live inventory surface for the gear picker (and other read
// sites). Reads active equipment from the Rust FieldStore (alphabetical) and
// stays fresh via the `.equipmentItem` store observer — the `@Query`
// replacement. The inventory table is tiny (dozens of rows), so a full reload
// on each change is cheap and off-main.

import CarrierWaveCore
import CarrierWaveData
import Foundation

@MainActor
@Observable
final class EquipmentInventoryModel {
    // MARK: Internal

    /// All active (non-retired) inventory items, alphabetical by display name.
    private(set) var items: [EquipmentInventorySnapshot] = []

    /// Items in a single category.
    func items(for category: EquipmentCategory) -> [EquipmentInventorySnapshot] {
        items.filter { $0.category == category }
    }

    /// The first item whose display name matches `name` (used to resolve a
    /// selection string back to a snapshot — e.g. capturing `radioItemID`).
    func snapshot(named name: String) -> EquipmentInventorySnapshot? {
        items.first { $0.displayName == name }
    }

    func snapshot(id: UUID) -> EquipmentInventorySnapshot? {
        items.first { $0.id == id }
    }

    /// Begin loading + observing. Idempotent.
    func start() {
        guard observerTask == nil else {
            return
        }
        observerTask = Task { [weak self] in
            await self?.reload()
            do {
                let store = try await CwStoreProvider.shared.store()
                for await _ in store.changes(for: .equipmentItem) {
                    if Task.isCancelled {
                        break
                    }
                    await self?.reload()
                }
            } catch {
                // Store unavailable — leave the last-loaded items in place.
            }
        }
    }

    func stop() {
        observerTask?.cancel()
        observerTask = nil
    }

    func reload() async {
        guard let loaded = try? await Self.fetch() else {
            return
        }
        items = loaded
    }

    // MARK: Private

    private var observerTask: Task<Void, Never>?

    /// Off-main fetch of active inventory, alphabetical by display name.
    nonisolated private static func fetch() async throws -> [EquipmentInventorySnapshot] {
        let store = try await CwStoreProvider.shared.store()
        let filter = FfiEquipmentItemFilter(
            categoryRawValue: nil,
            isRetired: false,
            sort: .nameAsc
        )
        return try store.fetchEquipmentItems(filter: filter, limit: 1_000, offset: 0)
            .map(EquipmentInventorySnapshot.init(ffi:))
    }
}
