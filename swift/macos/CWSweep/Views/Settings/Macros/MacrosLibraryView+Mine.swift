import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - MacrosLibraryMineTab

/// User-authored macros. `@Query` is acceptable here because the macro
/// library is tiny (counted in dozens, not QSO-scale). Filters out
/// locally-deleted rows so deleted macros don't reappear pending sync.
struct MacrosLibraryMineTab: View {
    // MARK: Lifecycle

    init(model: MacroLibraryModel) {
        self.model = model
        let userDeleted = MacroTombstoneReason.userDeleted.rawValue
        let predicate = #Predicate<RadioMacro> { macro in
            !macro.tombstoned || macro.tombstoneReason != userDeleted
        }
        _macros = Query(filter: predicate, sort: \RadioMacro.sortOrder)
    }

    // MARK: Internal

    let model: MacroLibraryModel

    var body: some View {
        Group {
            if macros.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addPending = newMacro()
                } label: {
                    Image(systemName: "plus")
                }
                .help("New macro")
            }
        }
        .sheet(item: $addPending) { macro in
            NavigationStack {
                MacroEditorView(macro: macro, isNewlyCreated: true)
            }
            .frame(minWidth: 560, minHeight: 640)
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var ctx
    @Query private var macros: [RadioMacro]
    @State private var addPending: RadioMacro?

    private var filteredMacros: [RadioMacro] {
        guard !model.searchText.isEmpty else {
            return macros
        }
        let needle = model.searchText.lowercased()
        return macros.filter { macro in
            macro.name.lowercased().contains(needle)
                || macro.tagsCSV.lowercased().contains(needle)
        }
    }

    private var list: some View {
        @Bindable var boundModel = model
        return List {
            ForEach(filteredMacros) { macro in
                NavigationLink {
                    MacroDetailView(macro: macro)
                } label: {
                    MacroRowLabel(macro: macro)
                }
                .contextMenu {
                    Button {
                        duplicate(macro)
                    } label: {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }
                    Button(role: .destructive) {
                        delete(macro)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .searchable(text: $boundModel.searchText)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("No Macros Yet")
                .font(.headline)
            Text("Macros automate repetitive radio commands — set frequency, switch mode, send CW, all in one click.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                addPending = newMacro()
            } label: {
                Label("Create Macro", systemImage: "plus")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    private func newMacro() -> RadioMacro {
        let macro = model.newDraft()
        macro.sortOrder = (macros.map(\.sortOrder).max() ?? 0) + 1
        ctx.insert(macro)
        try? ctx.save()
        return macro
    }

    private func duplicate(_ source: RadioMacro) {
        var spec = source.toSpec()
        spec.id = UUID()
        spec.name = "\(source.name) Copy"
        let clone = RadioMacro.from(spec: spec, sortOrder: source.sortOrder + 1)
        ctx.insert(clone)
        try? ctx.save()
    }

    private func delete(_ macro: RadioMacro) {
        macro.tombstoned = true
        macro.tombstoneReason = "user-deleted"
        macro.updatedAt = Date()
        try? ctx.save()
    }
}

// MARK: - MacroRowLabel

struct MacroRowLabel: View {
    // MARK: Internal

    let macro: RadioMacro

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: macro.icon ?? "wand.and.stars")
                .font(.system(size: 18))
                .foregroundStyle(tombstoneReason == nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(macro.name)
                        .font(.body)
                        .foregroundStyle(tombstoneReason == nil ? .primary : .secondary)
                    if let reason = tombstoneReason {
                        Text(reason.headlineLabel)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                    }
                }
                if let summary = macro.macroDescription, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                MacroCapabilityChipsCompact(capabilities: macro.capabilities)
            }
        }
    }

    // MARK: Private

    private var tombstoneReason: MacroTombstoneReason? {
        guard macro.tombstoned else {
            return nil
        }
        let parsed = MacroTombstoneReason.from(raw: macro.tombstoneReason)
        return (parsed?.isServerOriginated == true) ? parsed : nil
    }
}
