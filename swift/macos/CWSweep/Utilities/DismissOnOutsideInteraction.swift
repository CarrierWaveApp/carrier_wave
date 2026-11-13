import AppKit
import SwiftUI

// MARK: - DismissOnOutsideInteraction

/// View modifier that closes a typeahead-style overlay when the user
/// (a) presses Escape, or (b) left-clicks outside both the field row and
/// the overlay's visible bounds.
///
/// Installs an `NSEvent.addLocalMonitorForEvents` while `isOpen` is true so
/// clicks anywhere in the app window are observed. The monitor is removed
/// when the dropdown closes or the view leaves the hierarchy.
///
/// Caller responsibilities:
/// - Track field/overlay frames in `.global` coordinates (use
///   `.captureFrameInGlobal(into:)` on each).
/// - Toggle `isOpen` to reflect overlay visibility.
/// - Implement `onDismiss` to flip focus state (typically
///   `isFieldFocused = false`).
struct DismissOnOutsideInteraction: ViewModifier {
    // MARK: Internal

    let isOpen: Bool
    let fieldFrame: CGRect
    let overlayFrame: CGRect
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: isOpen) { _, newValue in
                if newValue {
                    install()
                } else {
                    remove()
                }
            }
            .onDisappear { remove() }
            .onExitCommand { onDismiss() }
    }

    // MARK: Private

    @State private var eventMonitor: Any?

    private func install() {
        remove()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            handle(event: event)
            return event
        }
    }

    private func remove() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    /// Convert the AppKit window-space click point to SwiftUI's top-left
    /// global coordinate system and dismiss if it falls outside both frames.
    private func handle(event: NSEvent) {
        guard let window = event.window else {
            return
        }
        let height = window.contentLayoutRect.height
        let point = CGPoint(
            x: event.locationInWindow.x,
            y: height - event.locationInWindow.y
        )
        if !fieldFrame.contains(point), !overlayFrame.contains(point) {
            DispatchQueue.main.async { onDismiss() }
        }
    }
}

// MARK: - View helpers

extension View {
    /// Installs Escape + click-outside dismissal for a typeahead overlay.
    func dismissOnOutsideInteraction(
        isOpen: Bool,
        fieldFrame: CGRect,
        overlayFrame: CGRect,
        onDismiss: @escaping () -> Void
    ) -> some View {
        modifier(
            DismissOnOutsideInteraction(
                isOpen: isOpen,
                fieldFrame: fieldFrame,
                overlayFrame: overlayFrame,
                onDismiss: onDismiss
            )
        )
    }

    /// Writes the view's `.global` frame into the supplied binding whenever
    /// it changes. Used together with `dismissOnOutsideInteraction` so the
    /// click-monitor can do hit-testing against the field + overlay.
    func captureFrameInGlobal(into binding: Binding<CGRect>) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { binding.wrappedValue = proxy.frame(in: .global) }
                    .onChange(of: proxy.frame(in: .global)) { _, new in
                        binding.wrappedValue = new
                    }
            }
        )
    }
}
