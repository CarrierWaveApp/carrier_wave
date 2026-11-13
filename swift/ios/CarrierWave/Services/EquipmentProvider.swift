// Equipment Provider
//
// Shared access to the Rust equipment core (`EquipmentApi` over the encrypted
// FieldStore) — fuzzy catalog search and equipment construction (custom +
// catalog items). Modeled on `ReferenceDataProvider`: one lazily-built API held
// behind an actor. Loadout CRUD uses `LoadoutStore` over the same store.

import CarrierWaveCore
import CarrierWaveData
import UIKit

nonisolated enum Equipment {
    // MARK: Internal

    /// The shared `EquipmentApi` over the app's FieldStore.
    static func api() async throws -> EquipmentApi {
        if let api = await Holder.shared.api {
            return api
        }
        let store = try await CwStoreProvider.shared.store()
        let api = EquipmentApi(store: store)
        await Holder.shared.set(api)
        return api
    }

    /// A `LoadoutStore` over the app's FieldStore.
    static func loadouts() async throws -> LoadoutStore {
        let store = try await CwStoreProvider.shared.store()
        return LoadoutStore(store: store)
    }

    // MARK: - Off-main FFI helpers (nonisolated so the SQLite touch never runs on main)

    /// Fuzzy catalog search for the inline typeahead. Returns `[]` on any error.
    static func searchCatalog(_ query: String, category: EquipmentCategory) async -> [FfiCatalogMatch] {
        guard let api = try? await api() else {
            return []
        }
        return (try? api.searchCatalog(query: query, category: category.rawValue, limit: 5)) ?? []
    }

    /// Add a catalog item to inventory (Rust constructs + persists), returning it.
    static func addCatalogItem(_ catalogId: String) async throws -> FfiEquipmentItem {
        try await api().addCatalogItem(catalogId: catalogId)
    }

    /// Add a free-form custom item to inventory (Rust constructs + persists).
    static func addCustomItem(_ input: FfiCustomEquipmentInput) async throws -> FfiEquipmentItem {
        try await api().addCustomItem(input: input)
    }

    // MARK: Private

    private actor Holder {
        static let shared = Holder()

        private(set) var api: EquipmentApi?

        func set(_ api: EquipmentApi) {
            self.api = api
        }
    }
}
