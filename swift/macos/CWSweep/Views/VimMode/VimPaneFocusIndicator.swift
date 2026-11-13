import SwiftUI

// MARK: - VimPaneFocusIndicator

/// Draws a border and pane-number badge when the pane has vim focus.
/// Only active when vim mode is enabled.
struct VimPaneFocusIndicator: ViewModifier {
    // MARK: Internal

    let pane: FocusedPane

    func body(content: Content) -> some View {
        content
            .background(ClickFocusView(
                pane: pane, vimEngine: vimEngine, selectionState: selectionState
            ))
            .overlay {
                if vimEngine.isEnabled {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            selectionState.focusedPane == pane
                                ? Color.accentColor
                                : Color.clear,
                            lineWidth: 2
                        )
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                if vimEngine.isEnabled {
                    Text("\(paneBadgeIndex)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(
                            selectionState.focusedPane == pane
                                ? AnyShapeStyle(.primary)
                                : AnyShapeStyle(.tertiary)
                        )
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 3))
                        .padding(4)
                }
            }
    }

    // MARK: Private

    @Environment(VimEngine.self) private var vimEngine
    @Environment(SelectionState.self) private var selectionState

    /// 1-based index of this pane in the current layout's available panes.
    private var paneBadgeIndex: String {
        if let idx = selectionState.availablePanes.firstIndex(of: pane) {
            return "\(idx + 1)"
        }
        return "–"
    }
}

// MARK: - ClickFocusView

/// Invisible NSView that monitors mouse-down events to set vim pane focus.
/// Works even when NSTableView or other AppKit views consume the click.
private struct ClickFocusView: NSViewRepresentable {
    let pane: FocusedPane
    let vimEngine: VimEngine
    let selectionState: SelectionState

    func makeNSView(context: Context) -> ClickFocusNSView {
        let view = ClickFocusNSView()
        view.pane = pane
        view.vimEngine = vimEngine
        view.selectionState = selectionState
        return view
    }

    func updateNSView(_ nsView: ClickFocusNSView, context: Context) {
        nsView.pane = pane
        nsView.vimEngine = vimEngine
        nsView.selectionState = selectionState
    }
}

// MARK: - ClickFocusNSView

/// NSView subclass that installs a local mouse-down monitor scoped to its bounds.
private final class ClickFocusNSView: NSView {
    // MARK: Internal

    var pane: FocusedPane = .spotList
    var vimEngine: VimEngine?
    var selectionState: SelectionState?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                self?.handleMouseDown(event)
                return event
            }
        }
    }

    override func removeFromSuperview() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        super.removeFromSuperview()
    }

    // MARK: Private

    private var monitor: Any?

    private func handleMouseDown(_ event: NSEvent) {
        guard let window, event.window === window else {
            return
        }
        let pointInView = convert(event.locationInWindow, from: nil)
        guard bounds.contains(pointInView) else {
            return
        }
        if let vimEngine, vimEngine.isEnabled {
            selectionState?.focusedPane = pane
        }
    }
}

// MARK: - View Extension

extension View {
    func vimPaneFocus(_ pane: FocusedPane) -> some View {
        modifier(VimPaneFocusIndicator(pane: pane))
    }
}
