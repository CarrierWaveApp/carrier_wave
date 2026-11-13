import AppKit
import CarrierWaveData
import SwiftUI

// MARK: - MacroRunWindowController

/// Opens `MacroRunSheetView` in a dedicated non-modal `NSWindow`. macOS
/// flavour of the iOS sheet-based runner: the run UI lives in its own
/// window so the operator can keep the library / detail view in view
/// while a macro is in flight.
///
/// Windows are retained via a small static registry until they close;
/// the registry releases them in the close-notification handler so we
/// don't leak macros that were dismissed via the red traffic-light
/// close button.
@MainActor
enum MacroRunWindowController {
    // MARK: Internal

    /// Open a new runner window for `spec`. Multiple windows can be open
    /// at once (e.g. for parallel CW macros against split slots). When
    /// `plan` is non-nil the sheet shows a Terraform-style diff above the
    /// args section — that's the path the `operate <intent>` flow uses.
    /// `menuPlanRows` adds a parallel Menu section showing diff for KX2
    /// menu items snapshotted before the user confirmed the run.
    static func present(
        spec: RadioMacroSpec,
        plan: RadioStatePlan? = nil,
        menuPlanRows: [MenuPlanRow]? = nil
    ) {
        let view = MacroRunWindowView(spec: spec, plan: plan, menuPlanRows: menuPlanRows)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Run · \(spec.name)"
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)

        registry.insert(window)
        observe(window: window)
    }

    // MARK: Private

    /// Strong references to live windows so they survive while the user
    /// is interacting. SwiftUI hosting views are owned by their NSWindow
    /// content view, but the window itself needs to stay alive — without
    /// `isReleasedWhenClosed = false` + this registry, the window
    /// disappears the moment the focus drops.
    private static var registry: Set<NSWindow> = []

    private static func observe(window: NSWindow) {
        // Capture the window value (Sendable enough for our purposes —
        // we only touch it back on the main actor) and avoid sending the
        // non-Sendable `Notification` across actors.
        nonisolated(unsafe) let captured = window
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in
                registry.remove(captured)
            }
        }
    }
}

// MARK: - MacroRunWindowView

/// Thin wrapper around `MacroRunSheetView` for the window-hosting path.
/// Adds a min-size frame and lets `MacroRunSheetView` own its own
/// `MacroExecutionModel` so the body matches the iOS sheet exactly.
struct MacroRunWindowView: View {
    let spec: RadioMacroSpec
    let plan: RadioStatePlan?
    let menuPlanRows: [MenuPlanRow]?

    var body: some View {
        MacroRunSheetView(spec: spec, plan: plan, menuPlanRows: menuPlanRows)
            .frame(minWidth: 460, minHeight: 540)
    }
}
