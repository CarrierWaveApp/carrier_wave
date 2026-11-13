import AppKit
import SwiftUI

// MARK: - ScrollWheelEvent

/// Rich scroll wheel event carrying deltas and modifier key state.
struct ScrollWheelEvent {
    let deltaX: CGFloat
    let deltaY: CGFloat
    let isShiftHeld: Bool
}

// MARK: - ScrollWheelModifier

/// ViewModifier that captures trackpad/mouse scroll wheel events using
/// an NSEvent local monitor. The background NSView approach doesn't work
/// because AppKit dispatches scrollWheel to the frontmost view under the
/// cursor (the SwiftUI Canvas), not to background NSViews.
struct ScrollWheelModifier: ViewModifier {
    let action: (ScrollWheelEvent) -> Void

    func body(content: Content) -> some View {
        content.background(
            ScrollWheelRepresentable(action: action)
        )
    }
}

// MARK: - ScrollWheelRepresentable

private struct ScrollWheelRepresentable: NSViewRepresentable {
    let action: (ScrollWheelEvent) -> Void

    func makeNSView(context _: Context) -> ScrollWheelNSView {
        ScrollWheelNSView(action: action)
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context _: Context) {
        nsView.action = action
    }
}

// MARK: - ScrollWheelNSView

/// Captures scroll wheel events via a local event monitor.
/// Checks whether the event location falls within this view's bounds
/// before forwarding to the action closure.
private class ScrollWheelNSView: NSView {
    // MARK: Lifecycle

    init(action: @escaping (ScrollWheelEvent) -> Void) {
        self.action = action
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        let captured = monitor
        if let captured {
            NSEvent.removeMonitor(captured)
        }
    }

    // MARK: Internal

    var action: (ScrollWheelEvent) -> Void

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let ownWindow = window else {
                    return event
                }
                // `addLocalMonitorForEvents` is app-wide — it fires for
                // scroll wheels in EVERY window of the app, not just
                // the window this view lives in. Without this guard,
                // a scroll in (e.g.) the Query Workbench window's
                // schema browser would convert `event.locationInWindow`
                // (a point in the workbench window) into THIS view's
                // coordinate space (the workspace window), and if the
                // converted point happened to land inside the band
                // scope canvas's bounds the action would fire AND the
                // event would be swallowed — making the foreground
                // window's scroll wheel "scroll the window underneath."
                guard event.window === ownWindow else {
                    return event
                }
                let locationInWindow = event.locationInWindow
                let locationInView = convert(locationInWindow, from: nil)
                guard bounds.contains(locationInView) else {
                    return event
                }
                let evt = ScrollWheelEvent(
                    deltaX: event.deltaX,
                    deltaY: event.deltaY,
                    isShiftHeld: event.modifierFlags.contains(.shift)
                )
                action(evt)
                return nil
            }
        } else if window == nil, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    // MARK: Private

    nonisolated(unsafe) private var monitor: Any?
}

extension View {
    func onScrollWheel(_ action: @escaping (ScrollWheelEvent) -> Void) -> some View {
        modifier(ScrollWheelModifier(action: action))
    }
}
