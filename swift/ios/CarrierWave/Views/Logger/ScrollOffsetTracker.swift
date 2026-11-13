import SwiftUI

// MARK: - ScrollOffsetPreferenceKey

// Tracks whether a view has scrolled past the top of a named coordinate space.
// Used to show a pinned duplicate of the command bar when the original scrolls off-screen.

/// PreferenceKey that reports the minY of a view in its scroll container
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - ScrollOffsetReporter

/// Modifier that reports the view's top edge position relative to a coordinate space
struct ScrollOffsetReporter: ViewModifier {
    let coordinateSpace: String

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .named(coordinateSpace)).minY
                        )
                }
            )
    }
}

extension View {
    /// Reports this view's top-edge scroll offset within the named coordinate space
    func trackScrollOffset(in coordinateSpace: String) -> some View {
        modifier(ScrollOffsetReporter(coordinateSpace: coordinateSpace))
    }
}
