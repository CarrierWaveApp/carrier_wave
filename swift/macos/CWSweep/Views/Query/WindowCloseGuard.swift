import AppKit
import SwiftUI

// MARK: - WindowCloseGuard

/// Bridges into AppKit to intercept the host window's close button.
/// When `isDirty()` returns true, the close request is consumed and
/// `onAttemptClose` fires instead — letting SwiftUI present a Save /
/// Discard / Cancel dialog. SwiftUI's `Window` scene has no native
/// equivalent (no `windowShouldClose` modifier), so this hops down to
/// `NSWindowDelegate` via an invisible representable.
struct WindowCloseGuard: NSViewRepresentable {
    // MARK: - Coordinator

    final class Coordinator: NSObject, NSWindowDelegate {
        // MARK: Lifecycle

        init(
            isDirty: @escaping @Sendable () -> Bool,
            onAttemptClose: @escaping @Sendable () -> Void
        ) {
            self.isDirty = isDirty
            self.onAttemptClose = onAttemptClose
        }

        // MARK: Internal

        var isDirty: @Sendable () -> Bool
        var onAttemptClose: @Sendable () -> Void

        /// Forward the rest to the previously-installed delegate so
        /// SwiftUI's bookkeeping (e.g. window restoration) keeps
        /// working.
        override func responds(to aSelector: Selector!) -> Bool {
            if super.responds(to: aSelector) {
                return true
            }
            return previousDelegate?.responds(to: aSelector) ?? false
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            if let prev = previousDelegate, prev.responds(to: aSelector) {
                return prev
            }
            return super.forwardingTarget(for: aSelector)
        }

        @MainActor
        func attach(to window: NSWindow) {
            self.window = window
            // Preserve any delegate SwiftUI installed and forward
            // calls we don't override.
            previousDelegate = window.delegate
            window.delegate = self
        }

        // MARK: NSWindowDelegate

        @MainActor
        func windowShouldClose(_: NSWindow) -> Bool {
            if isDirty() {
                onAttemptClose()
                return false
            }
            return true
        }

        // MARK: Private

        private weak var window: NSWindow?
        private weak var previousDelegate: NSWindowDelegate?
    }

    let isDirty: @Sendable () -> Bool
    let onAttemptClose: @Sendable () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isDirty: isDirty, onAttemptClose: onAttemptClose)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Defer until the view is attached to a window.
        DispatchQueue.main.async {
            guard let window = view.window else {
                return
            }
            context.coordinator.attach(to: window)
        }
        return view
    }

    func updateNSView(_: NSView, context: Context) {
        // Refresh closures so the delegate sees current state. The
        // delegate captures by closure, but those closures are set
        // once at coordinator init — re-bind them on every update.
        context.coordinator.isDirty = isDirty
        context.coordinator.onAttemptClose = onAttemptClose
    }
}
