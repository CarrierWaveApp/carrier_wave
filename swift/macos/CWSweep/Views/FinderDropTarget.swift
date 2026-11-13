import CarrierWaveData
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - FinderDropTarget

/// Accepts `.cwmacro` files dragged onto the wrapped content from
/// Finder. The dropped document data flows through
/// `MacroImportCoordinator` and surfaces a `MacroImportSheet` so the
/// user can review capabilities + steps before the spec lands in their
/// library. macOS-only flow — iOS uses the system Files importer.
struct FinderDropTarget<Content: View>: View {
    // MARK: Lifecycle

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    // MARK: Internal

    let content: Content

    var body: some View {
        content
            .onDrop(of: Self.acceptedTypes, isTargeted: $isTargeted, perform: handleDrop)
            .sheet(item: $pending) { dropped in
                MacroImportSheet(
                    documentData: dropped.data,
                    provenance: .files,
                    onInstall: { spec in
                        install(spec: spec)
                    }
                )
            }
            .sheet(item: bridgeBinding) { document in
                MacroImportSheet(
                    documentData: document.data,
                    provenance: document.provenance,
                    onInstall: { spec in
                        install(spec: spec)
                    }
                )
            }
    }

    // MARK: Private

    private struct DroppedDocument: Identifiable {
        let id = UUID()
        let data: Data
    }

    private static var acceptedTypes: [UTType] {
        var types: [UTType] = [.json]
        if let macroType = UTType("app.carrierwave.macro") {
            types.insert(macroType, at: 0)
        }
        return types
    }

    @Environment(\.modelContext) private var ctx
    @State private var pending: DroppedDocument?
    @State private var isTargeted = false

    /// Bridge to the URL handler — `MacroURLHandler.handle(_:)` sets
    /// `MacroURLBridge.shared.pending`; we observe it here so a single
    /// `MacroImportSheet` covers both drop and URL flows.
    private var bridge: MacroURLBridge {
        .shared
    }

    private var bridgeBinding: Binding<PendingMacroDocument?> {
        Binding(
            get: { bridge.pending },
            set: { bridge.pending = $0 }
        )
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else {
            return false
        }
        let macroTypeId = "app.carrierwave.macro"
        let typeIdentifier: String
        if provider.hasItemConformingToTypeIdentifier(macroTypeId) {
            typeIdentifier = macroTypeId
        } else if provider.hasItemConformingToTypeIdentifier(UTType.json.identifier) {
            typeIdentifier = UTType.json.identifier
        } else {
            return false
        }
        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
            guard let data else {
                return
            }
            Task { @MainActor in
                pending = DroppedDocument(data: data)
            }
        }
        return true
    }

    private func install(spec: RadioMacroSpec) {
        let macro = RadioMacro.from(spec: spec)
        ctx.insert(macro)
        try? ctx.save()
    }
}

// MARK: - View helper

extension View {
    /// Attach a Finder drop target for `.cwmacro` files on this subtree.
    func acceptsCwmacroDrop() -> some View {
        FinderDropTarget { self }
    }
}
