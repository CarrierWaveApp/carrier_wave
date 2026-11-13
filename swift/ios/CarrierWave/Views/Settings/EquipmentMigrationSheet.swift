import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - MigrationCandidate

/// A single piece of equipment to migrate, with its best catalog match.
struct MigrationCandidate: Identifiable {
    let id = UUID()
    let originalName: String
    let category: CarrierWaveData.EquipmentCategory
    var match: CatalogEntry?
    var confidence: Double
    var isIncluded: Bool = true
}

// MARK: - EquipmentMigrationSheet

/// One-time interactive migration that shows existing string-based equipment
/// matched against the catalog. Users confirm, correct, or skip each item
/// before creating structured EquipmentItems.
struct EquipmentMigrationSheet: View {
    // MARK: Internal

    var onComplete: () -> Void

    @Environment(\.modelContext) var modelContext

    @State var candidates: [MigrationCandidate] = []
    @State var searchingIndex: Int?

    /// Categories that have at least one candidate, in display order.
    var candidateCategories: [CarrierWaveData.EquipmentCategory] {
        let used = Set(candidates.map(\.category))
        return CarrierWaveData.EquipmentCategory.allCases
            .filter { used.contains($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                if candidates.isEmpty {
                    emptySection
                } else {
                    ForEach(candidateCategories, id: \.self) { category in
                        Section(category.displayName + "s") {
                            ForEach(
                                candidateBindings(for: category),
                                id: \.wrappedValue.id
                            ) { $candidate in
                                candidateRow($candidate)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Migrate Equipment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        markMigrated()
                        onComplete()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Migrate") {
                        performMigration()
                    }
                    .fontWeight(.semibold)
                    .disabled(candidates.isEmpty)
                }
            }
            .task { buildCandidates() }
            .sheet(isPresented: Binding(
                get: { searchingIndex != nil },
                set: { newValue in
                    if !newValue {
                        searchingIndex = nil
                    }
                }
            )) {
                if let idx = searchingIndex {
                    catalogSearchSheet(for: idx)
                }
            }
        }
    }

    /// Bindings to candidates filtered by category.
    func candidateBindings(
        for category: CarrierWaveData.EquipmentCategory
    ) -> [Binding<MigrationCandidate>] {
        $candidates.filter { $0.wrappedValue.category == category }
    }

    // MARK: Private

    // MARK: - Header

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "Equipment Upgrade",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.headline)
                Text(
                    "We matched your existing equipment against "
                        + "our catalog. Tap a row to change its "
                        + "match, or swipe left to keep as custom."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var emptySection: some View {
        Section {
            Text("No existing equipment found to migrate.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Building Candidates

    private func buildCandidates() {
        let catalog = EquipmentCatalogService.shared.catalog
        var results: [MigrationCandidate] = []
        var seenNames = Set<String>()

        func addUnique(
            name: String,
            category: CarrierWaveData.EquipmentCategory
        ) {
            let key = "\(category.rawValue):\(name.lowercased())"
            guard seenNames.insert(key).inserted else {
                return
            }
            results.append(
                matchCandidate(
                    name: name, category: category, catalog: catalog
                )
            )
        }

        // Radios from UserDefaults
        for name in RadioStorage.load() {
            addUnique(name: name, category: .radio)
        }

        // Antennas, keys, mics from iCloud KVS
        let sources: [(EquipmentType, CarrierWaveData.EquipmentCategory)] = [
            (.antenna, .antenna),
            (.key, .key),
            (.mic, .microphone),
        ]
        for (type, category) in sources {
            for name in EquipmentStorage.load(for: type) {
                addUnique(name: name, category: category)
            }
        }

        // Unique rigs from session history
        for rig in collectSessionRigs() {
            addUnique(name: rig, category: .radio)
        }

        candidates = results
    }

    private func matchCandidate(
        name: String,
        category: CarrierWaveData.EquipmentCategory,
        catalog: [CatalogEntry]
    ) -> MigrationCandidate {
        if let result = CatalogMatcher.bestMatch(
            for: name, in: catalog, category: category, threshold: 0.4
        ) {
            return MigrationCandidate(
                originalName: name,
                category: category,
                match: result.entry,
                confidence: result.confidence
            )
        }
        return MigrationCandidate(
            originalName: name,
            category: category,
            match: nil,
            confidence: 0
        )
    }

    private func collectSessionRigs() -> [String] {
        var descriptor = FetchDescriptor<LoggingSession>()
        descriptor.fetchLimit = 500
        guard let sessions = try? modelContext.fetch(descriptor) else {
            return []
        }
        var seen = Set<String>()
        var rigs: [String] = []
        for session in sessions {
            if let rig = session.myRig, !rig.isEmpty,
               !seen.contains(rig.lowercased())
            {
                seen.insert(rig.lowercased())
                rigs.append(rig)
            }
        }
        return rigs
    }

    // MARK: - Migration

    private func performMigration() {
        var existingNames = loadExistingNames()
        var usedCatalogIds = loadExistingCatalogIds()

        for candidate in candidates where candidate.isIncluded {
            let name = candidate.match?.name ?? candidate.originalName
            guard !existingNames.contains(name.lowercased()) else {
                continue
            }
            insertCandidate(
                candidate,
                existingNames: &existingNames,
                usedCatalogIds: &usedCatalogIds
            )
        }

        try? modelContext.save()
        syncAllCategoriesToKVS()
        markMigrated()
        onComplete()
    }

    private func insertCandidate(
        _ candidate: MigrationCandidate,
        existingNames: inout Set<String>,
        usedCatalogIds: inout Set<String>
    ) {
        if let match = candidate.match {
            guard usedCatalogIds.insert(match.id).inserted else {
                return
            }
            let item = EquipmentItem(
                catalogId: match.id,
                catalogName: match.name,
                category: candidate.category,
                nickname: candidate.originalName != match.name
                    ? candidate.originalName : nil,
                bands: match.bands,
                modes: match.modes.map(\.rawValue),
                maxPowerWatts: match.maxPowerWatts,
                portability: match.portability,
                manufacturer: match.manufacturer
            )
            modelContext.insert(item)
            existingNames.insert(match.name.lowercased())
        } else {
            let item = EquipmentItem.custom(
                name: candidate.originalName,
                category: candidate.category
            )
            modelContext.insert(item)
            existingNames.insert(candidate.originalName.lowercased())
            CustomEquipmentSubmitter.shared.submitCustomSnapshot(
                name: candidate.originalName,
                category: candidate.category,
                catalogId: item.catalogId
            )
        }
    }

    private func loadExistingNames() -> Set<String> {
        var descriptor = FetchDescriptor<EquipmentItem>()
        descriptor.fetchLimit = 500
        guard let items = try? modelContext.fetch(descriptor) else {
            return []
        }
        var names = Set<String>()
        for item in items {
            names.insert(item.catalogName.lowercased())
            if let nick = item.nickname {
                names.insert(nick.lowercased())
            }
        }
        return names
    }

    private func loadExistingCatalogIds() -> Set<String> {
        var descriptor = FetchDescriptor<EquipmentItem>()
        descriptor.fetchLimit = 500
        guard let items = try? modelContext.fetch(descriptor) else {
            return []
        }
        return Set(items.map(\.catalogId))
    }

    private func syncAllCategoriesToKVS() {
        for category in CarrierWaveData.EquipmentCategory.allCases {
            let categoryRaw = category.rawValue
            var descriptor = FetchDescriptor<EquipmentItem>()
            descriptor.fetchLimit = 200
            descriptor.predicate = #Predicate<EquipmentItem> { item in
                item.categoryRawValue == categoryRaw
            }
            if let fetched = try? modelContext.fetch(descriptor) {
                EquipmentInventorySync.pushToKVS(
                    category: category, items: fetched
                )
            }
        }
    }

    private func markMigrated() {
        UserDefaults.standard.set(
            true, forKey: "equipmentInventory.migrated"
        )
    }
}
