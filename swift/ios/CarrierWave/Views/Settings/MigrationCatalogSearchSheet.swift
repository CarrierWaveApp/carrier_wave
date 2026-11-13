import CarrierWaveData
import SwiftUI

// MARK: - MigrationCatalogSearchSheet

/// Inline catalog search for manually matching equipment during migration.
struct MigrationCatalogSearchSheet: View {
    // MARK: Internal

    let originalName: String
    let category: CarrierWaveData.EquipmentCategory
    var onSelect: (CatalogEntry) -> Void
    var onKeepCustom: (() -> Void)?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Finding a match for \"\(originalName)\"")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        onKeepCustom?()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "wrench.and.screwdriver")
                                .foregroundStyle(.orange)
                                .frame(width: 24)
                            Text("Keep as Custom")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }

                if !results.isEmpty {
                    Section("Catalog Matches") {
                        ForEach(results, id: \.entry.id) { result in
                            Button {
                                onSelect(result.entry)
                            } label: {
                                searchResultRow(result.entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search catalog\u{2026}"
            )
            .navigationTitle("Find Match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: searchText) { _, newValue in
                updateResults(query: newValue)
            }
            .task {
                searchText = originalName
                updateResults(query: originalName)
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var results: [CatalogSearchResult] = []

    private func searchResultRow(
        _ entry: CatalogEntry
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.category.icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.fullName)
                    .font(.subheadline.weight(.medium))
                if let pw = entry.maxPowerWatts {
                    Text("\(pw)W")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.blue)
        }
    }

    private func updateResults(query: String) {
        guard query.count >= 2 else {
            results = []
            return
        }
        results = CatalogMatcher.search(
            query: query,
            in: EquipmentCatalogService.shared.catalog,
            category: category,
            limit: 10
        )
    }
}
