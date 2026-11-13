import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - EquipmentItemDetailView

struct EquipmentItemDetailView: View {
    // MARK: Internal

    // MARK: - Data

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    let itemId: UUID
    var onUpdate: (() -> Void)?

    @Environment(\.modelContext) var modelContext

    @State var item: EquipmentItem?
    @State var computedDetail: ComputedEquipmentItemDetail?
    @State var isComputingStats = false

    @State var editNickname = ""
    @State var editNotes = ""

    @State var showConnectionSheet = false

    var body: some View {
        Group {
            if let item {
                detailContent(item)
            } else {
                ContentUnavailableView(
                    "Equipment Not Found",
                    systemImage: "questionmark.circle"
                )
            }
        }
        .navigationTitle("Equipment Detail")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadItem() }
    }

    func saveAndNotify() {
        if let item {
            try? EntityWriteSink.commitUpsert(item, in: modelContext)
            syncCategoryToKVS(item.category)
            if item.isCustom {
                CustomEquipmentSubmitter.shared.submit(item)
            }
        } else {
            try? modelContext.save()
        }
        onUpdate?()
    }

    // MARK: Private

    @State private var showingDeleteConfirm = false

    @Environment(\.dismiss) private var dismiss

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                HStack {
                    Spacer()
                    Text("Delete Equipment")
                    Spacer()
                }
            }
            .confirmationDialog(
                "Delete this equipment?",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    deleteItem()
                }
            } message: {
                Text(
                    "This will remove it from your inventory. "
                        + "Session history is not affected."
                )
            }
        }
    }

    private func detailContent(_ item: EquipmentItem) -> some View {
        List {
            if item.isCustom {
                catalogSuggestionBanner(item)
            }
            identitySection(item)
            if item.isCustom {
                customSpecsSection(item)
                similarInCatalogSection(item)
            } else {
                specsSection(item)
            }
            connectionSection(item)
            bandsSection(item)
            if let computedDetail {
                statsContent(computedDetail)
            } else if isComputingStats {
                Section("Usage") {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading stats\u{2026}")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            notesSection(item)
            statusSection(item)
            deleteSection
        }
        .task(id: item.displayName) {
            await loadStats(for: item)
        }
    }

    // MARK: - Sections

    private func identitySection(_ item: EquipmentItem) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: item.category.icon)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 40)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.catalogName)
                        .font(.headline)
                    if !item.manufacturer.isEmpty {
                        Text(item.manufacturer)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(item.category.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            HStack {
                Text("Nickname")
                Spacer()
                TextField(
                    "Optional nickname",
                    text: $editNickname
                )
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .onChange(of: editNickname) { _, newValue in
                    item.nickname = newValue.isEmpty ? nil : newValue
                    saveAndNotify()
                }
            }
        }
        .onAppear {
            editNickname = item.nickname ?? ""
            editNotes = item.notes ?? ""
        }
    }

    private func loadStats(for item: EquipmentItem) async {
        isComputingStats = true
        let actor = EquipmentItemDetailActor()
        let name = item.displayName
        let container = modelContext.container
        do {
            let result = try await actor.computeDetail(
                displayName: name, container: container
            )
            computedDetail = result
        } catch is CancellationError {
            // View disappeared
        } catch {
            // Silent degradation
        }
        isComputingStats = false
    }

    private func loadItem() {
        var descriptor = FetchDescriptor<EquipmentItem>()
        descriptor.fetchLimit = 1
        let targetId = itemId
        descriptor.predicate = #Predicate<EquipmentItem> { eq in
            eq.id == targetId
        }
        item = try? modelContext.fetch(descriptor).first
    }

    private func deleteItem() {
        guard let item else {
            return
        }
        let category = item.category
        try? EntityWriteSink.commitDelete(item, in: modelContext)
        syncCategoryToKVS(category)
        onUpdate?()
        dismiss()
    }

    private func syncCategoryToKVS(
        _ category: CarrierWaveData.EquipmentCategory
    ) {
        let categoryRaw = category.rawValue
        var descriptor = FetchDescriptor<EquipmentItem>()
        descriptor.fetchLimit = 200
        descriptor.predicate = #Predicate<EquipmentItem> { eq in
            eq.categoryRawValue == categoryRaw
        }
        guard let fetched = try? modelContext.fetch(descriptor) else {
            return
        }
        EquipmentInventorySync.pushToKVS(
            category: category, items: fetched
        )
    }
}
