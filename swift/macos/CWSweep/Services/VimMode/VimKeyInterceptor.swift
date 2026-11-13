import Cocoa

@MainActor
final class VimKeyInterceptor {
    // MARK: Internal

    func install(engine: VimEngine) {
        self.engine = engine
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let engine = self.engine,
                  engine.isEnabled, !engine.isPaletteActive
            else {
                return event
            }
            let focusedPane = engine.executor?.selectionState.focusedPane
            // Pass through keys when a text field is focused in a
            // non-workspace window (Settings, floating panels, etc.)
            // or when the focused pane is settings-like (Radio Control)
            // where vim consuming keys breaks credentials text fields.
            if Self.shouldPassThrough(event, mode: engine.mode, focusedPane: focusedPane) {
                return event
            }
            return handleKeyEvent(event, engine: engine)
        }
    }

    func uninstall() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    // MARK: Private

    /// Title set on the workspace `Window("CW Sweep", id: "workspace")`
    /// scene. Compared against `event.window?.title` to identify the
    /// workspace regardless of which window currently has focus.
    private static let workspaceWindowTitle = "CW Sweep"

    private var monitor: Any?
    private weak var engine: VimEngine?

    /// True when the event should reach the focused control without
    /// vim consuming it. Cases:
    ///   1. The event isn't in the workspace window (Settings, the
    ///      Query Workbench, floating panels). `NSApp.mainWindow`
    ///      follows focus, so once the user focuses an auxiliary
    ///      window it BECOMES the main window — making a naive
    ///      `window != mainWindow` check fail. We compare against the
    ///      workspace window's title instead, which is stable.
    ///   2. Vim is in a non-Normal mode AND a text-editing view is
    ///      first responder — Entry/Command/Search modes legitimately
    ///      want keys to reach a text field (the parsed-entry input,
    ///      vim's own command-line text field, the SQL editor, etc.).
    ///      In Normal mode we must NOT honor this, otherwise the
    ///      activator's always-focused entry field silently swallows
    ///      every navigation keystroke and vim looks broken.
    @MainActor private static func shouldPassThrough(
        _ event: NSEvent, mode: VimMode, focusedPane: FocusedPane?
    ) -> Bool {
        guard let window = event.window else {
            return false
        }
        if window.title != Self.workspaceWindowTitle {
            return true
        }
        // Escape inside the workspace must always reach vim so the user
        // can drop back to Normal from Entry/Command/Search even when a
        // text field has focus. Outside the workspace (Settings, etc.)
        // the title check above already passes Esc through to AppKit so
        // sheets and panels close normally.
        if event.keyCode == 53 {
            return false
        }
        // The Radio Control pane is settings-like — host/credentials
        // text fields would silently swallow input if vim consumed
        // keys here. Pass everything through; the user can click or
        // Tab into another pane to re-engage vim.
        if focusedPane == .radioControl {
            return true
        }
        if mode == .normal {
            return false
        }
        if let responder = window.firstResponder,
           responder.isKind(of: NSText.self)
        {
            return true
        }
        return false
    }

    private func handleKeyEvent(_ event: NSEvent, engine: VimEngine) -> NSEvent? {
        // Cmd+key shortcuts always pass through (menu items)
        if event.modifierFlags.contains(.command) {
            return event
        }

        // Ctrl+C = abort CW (all modes)
        if event.modifierFlags.contains(.control),
           event.charactersIgnoringModifiers == "c"
        {
            engine.handleControlC()
            return nil // consumed
        }

        // Escape always returns to Normal
        if event.keyCode == 53 { // Escape
            engine.handleEscape()
            return nil
        }

        if engine.mode == .entry {
            return handleEntryModeEvent(event, engine: engine)
        }

        if engine.mode == .command || engine.mode == .search {
            return handleLineModeEvent(event, engine: engine)
        }

        // Normal mode — consume everything
        return handleNormalModeEvent(event, engine: engine)
    }

    private func handleEntryModeEvent(_ event: NSEvent, engine: VimEngine) -> NSEvent? {
        // Return in Entry mode triggers log
        if event.keyCode == 36 { // Return
            engine.handleEntryReturn()
            return nil
        }
        // F1-F6 work in Entry mode too (CW memories)
        if let fKey = fKeyNumber(event), fKey >= 1, fKey <= 6 {
            engine.handleFKey(fKey)
            return nil
        }
        return event // all other keys go to text field
    }

    private func handleLineModeEvent(_ event: NSEvent, engine: VimEngine) -> NSEvent? {
        // In Command/Search mode: only intercept Return and Tab.
        // All other keys (including Backspace) pass through to the TextField.
        if event.keyCode == 36 { // Return
            engine.handleLineReturn()
            return nil
        }
        if event.keyCode == 48 { // Tab (completion)
            engine.handleTab()
            return nil
        }
        return event
    }

    private func handleNormalModeEvent(_ event: NSEvent, engine: VimEngine) -> NSEvent? {
        // Tab in Normal mode cycles pane focus
        if event.keyCode == 48 {
            engine.handleTab()
            return nil
        }
        guard let chars = event.characters, !chars.isEmpty else {
            return event
        }
        if let fKey = fKeyNumber(event), fKey >= 1, fKey <= 6 {
            engine.handleFKey(fKey)
            return nil
        }
        engine.handleKey(chars)
        return nil
    }

    private func fKeyNumber(_ event: NSEvent) -> Int? {
        switch event.keyCode {
        case 122: 1 // F1
        case 120: 2 // F2
        case 99: 3 // F3
        case 118: 4 // F4
        case 96: 5 // F5
        case 97: 6 // F6
        default: nil
        }
    }
}
