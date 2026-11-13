import SwiftUI
import UniformTypeIdentifiers

// MARK: - LayoutEditorView

/// Sheet for editing, creating, and exporting/importing layouts.
/// Uses a visual grid editor with draggable dividers and drag-and-drop panels.
struct LayoutEditorView: View {
    // MARK: Internal

    let layoutStore: LayoutStore

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            Divider()
            treeEditor
            Divider()
            editorFooter
        }
        .frame(
            minWidth: 600, idealWidth: 900, maxWidth: .infinity,
            minHeight: 500, idealHeight: 700, maxHeight: .infinity
        )
        .onAppear { loadEditingState() }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var editingLayout: CustomLayout?
    @State private var layoutName = ""
    @State private var showExporter = false
    @State private var showImporter = false

    private var exportDocument: LayoutDocument? {
        guard let layout = editingLayout,
              let data = layoutStore.exportLayout(layout)
        else {
            return nil
        }
        return LayoutDocument(data: data)
    }

    private var editingRootBinding: Binding<LayoutNode> {
        Binding(
            get: { editingLayout?.root ?? CustomLayout.hunterPreset.root },
            set: { newRoot in
                if editingLayout == nil {
                    editingLayout = newLayout()
                }
                editingLayout?.root = newRoot
            }
        )
    }

    private var editorHeader: some View {
        HStack {
            TextField("Layout Name", text: $layoutName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 250)
            Spacer()
            importExportButtons
        }
        .padding()
    }

    private var importExportButtons: some View {
        HStack {
            Button("Import...", systemImage: "square.and.arrow.down") {
                showImporter = true
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json]
            ) { result in
                importLayout(result: result)
            }

            Button("Export...", systemImage: "square.and.arrow.up") {
                showExporter = true
            }
            .disabled(editingLayout == nil)
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "\(layoutName).json"
            ) { _ in }
        }
    }

    private var treeEditor: some View {
        LayoutGridEditor(root: editingRootBinding, onMutate: {
            editingLayout?.modifiedAt = .now
        })
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editorFooter: some View {
        HStack {
            if let editing = editingLayout, !editing.isBuiltIn {
                Button("Delete Layout", role: .destructive) {
                    layoutStore.deleteLayout(id: editing.id)
                    dismiss()
                }
            }
            Spacer()
            Button("Cancel") { dismiss() }
            Button("Save") {
                saveLayout()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(layoutName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
    }

    // MARK: - Helpers

    private func loadEditingState() {
        let active = layoutStore.activeLayout
        if active.isBuiltIn {
            editingLayout = nil
            layoutName = "New Layout"
        } else {
            editingLayout = active
            layoutName = active.name
        }
    }

    private func saveLayout() {
        guard var layout = editingLayout else {
            var fresh = newLayout()
            fresh.name = layoutName
            layoutStore.addLayout(fresh)
            layoutStore.setActiveLayout(fresh)
            return
        }
        layout.name = layoutName
        layout.modifiedAt = .now
        // Layout may have been created by the root binding but not yet added to the store
        if layoutStore.customLayouts.contains(where: { $0.id == layout.id }) {
            layoutStore.updateLayout(layout)
        } else {
            layoutStore.addLayout(layout)
        }
        layoutStore.setActiveLayout(layout)
    }

    private func newLayout() -> CustomLayout {
        CustomLayout(
            id: UUID().uuidString, name: layoutName,
            root: CustomLayout.hunterPreset.root,
            isBuiltIn: false, createdAt: .now, modifiedAt: .now
        )
    }

    private func importLayout(result: Result<URL, Error>) {
        guard case let .success(url) = result,
              url.startAccessingSecurityScopedResource()
        else {
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url),
              let layout = try? layoutStore.importLayout(from: data)
        else {
            return
        }
        editingLayout = layout
        layoutName = layout.name
        layoutStore.setActiveLayout(layout)
    }
}
