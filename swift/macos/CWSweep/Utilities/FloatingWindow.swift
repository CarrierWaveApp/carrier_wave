import AppKit
import SwiftUI

// MARK: - FloatingWindowModifier

/// Makes an auxiliary window float above the main workspace window.
/// Applied via `.floatingWindow()` on views inside `Window` scenes.
private struct FloatingWindowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(FloatingWindowHelper())
    }
}

// MARK: - FloatingWindowHelper

/// NSViewRepresentable that finds its hosting NSWindow and sets it to float.
private struct FloatingWindowHelper: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else {
                return
            }
            window.level = .floating
            window.collectionBehavior.insert(.canJoinAllSpaces)
        }
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}
}

extension View {
    func floatingWindow() -> some View {
        modifier(FloatingWindowModifier())
    }
}
