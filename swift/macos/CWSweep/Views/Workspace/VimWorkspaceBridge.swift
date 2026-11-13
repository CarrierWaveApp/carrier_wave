import SwiftUI

// MARK: - VimWorkspaceBridge

/// Consumes the fire-and-forget vim requests on `SelectionState` that need
/// workspace-level state — sidebar destination (`:spots`, `:log`, …), role /
/// layout preset (`:role`), inspector visibility (`o`, `:inspector`), and
/// QSO deletion (`x` on the log pane). Each request is reset as soon as it is
/// handled so the same command can fire again.
///
/// The handlers are the *same* closures the command palette uses, so a vim
/// command and its palette counterpart can never drift apart.
struct VimWorkspaceBridge: ViewModifier {
    let selectionState: SelectionState
    let onNavigate: (SidebarItem) -> Void
    let onSetRole: (OperatingRole) -> Void
    let onToggleInspector: () -> Void
    let onDeleteQSO: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: selectionState.vimToggleInspector) { _, newValue in
                guard newValue else {
                    return
                }
                selectionState.vimToggleInspector = false
                onToggleInspector()
            }
            .onChange(of: selectionState.vimDeleteQSO) { _, newValue in
                guard newValue else {
                    return
                }
                selectionState.vimDeleteQSO = false
                onDeleteQSO()
            }
            .onChange(of: selectionState.vimNavigateTo) { _, item in
                guard let item else {
                    return
                }
                selectionState.vimNavigateTo = nil
                onNavigate(item)
            }
            .onChange(of: selectionState.vimSetRole) { _, role in
                guard let role else {
                    return
                }
                selectionState.vimSetRole = nil
                onSetRole(role)
            }
    }
}
