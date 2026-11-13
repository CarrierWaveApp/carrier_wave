import SwiftUI

// MARK: - BadgePillModifier

/// Applies capsule-shaped badge styling: horizontal/vertical padding + background + Capsule clip.
/// Replaces the repeated `.padding(.horizontal, _).padding(.vertical, _).background(_).clipShape(Capsule())` pattern.
struct BadgePillModifier<S: ShapeStyle>: ViewModifier {
    let background: S
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(background)
            .clipShape(Capsule())
    }
}

extension View {
    /// Apply capsule badge styling with a custom background.
    ///
    /// ```swift
    /// Text("FT8")
    ///     .font(.caption)
    ///     .badgePill(Color.green.opacity(0.15))
    ///
    /// Text("20m")
    ///     .font(.caption)
    ///     .badgePill(Color(.systemGray5), horizontalPadding: 8, verticalPadding: 4)
    /// ```
    func badgePill(
        _ background: some ShapeStyle,
        horizontalPadding: CGFloat = 6,
        verticalPadding: CGFloat = 2
    ) -> some View {
        modifier(BadgePillModifier(
            background: background,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding
        ))
    }
}
