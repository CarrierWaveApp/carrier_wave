import SwiftUI

// MARK: - LayoutPicker

/// Toolbar control for switching between layouts.
/// Shows the active layout name with a dropdown menu for all available layouts.
struct LayoutPicker: View {
    // MARK: Internal

    let layoutStore: LayoutStore
    /// Owned by WorkspaceView: a `.sheet` attached here (inside a toolbar Menu)
    /// never presents on macOS, so the editor sheet lives on the window content.
    @Binding var showEditor: Bool

    var body: some View {
        Menu {
            Section("Built-in") {
                ForEach(CustomLayout.builtInPresets) { layout in
                    layoutButton(for: layout)
                }
            }

            if !layoutStore.customLayouts.isEmpty {
                Section("Custom") {
                    ForEach(layoutStore.customLayouts) { layout in
                        layoutButton(for: layout)
                    }
                }
            }

            Divider()

            Button("New Layout...", systemImage: "plus") {
                showEditor = true
            }

            Button("Duplicate Current...", systemImage: "doc.on.doc") {
                duplicateCurrent()
            }

            if !layoutStore.activeLayout.isBuiltIn {
                Button("Edit Layout...", systemImage: "pencil") {
                    showEditor = true
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: layoutStore.activeLayout.isActivatorStyle
                    ? "antenna.radiowaves.left.and.right"
                    : "binoculars")
                Text(layoutStore.activeLayout.name)
                    .font(.callout)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.bar, in: RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: Private

    private func layoutButton(for layout: CustomLayout) -> some View {
        Button {
            layoutStore.setActiveLayout(layout)
        } label: {
            if layout.id == layoutStore.activeLayoutId {
                Label(layout.name, systemImage: "checkmark")
            } else {
                Text(layout.name)
            }
        }
    }

    private func duplicateCurrent() {
        let source = layoutStore.activeLayout
        let newName = source.isBuiltIn
            ? "My \(source.name)"
            : "\(source.name) Copy"
        let newLayout = layoutStore.duplicateLayout(source, name: newName)
        layoutStore.setActiveLayout(newLayout)
        showEditor = true
    }
}
