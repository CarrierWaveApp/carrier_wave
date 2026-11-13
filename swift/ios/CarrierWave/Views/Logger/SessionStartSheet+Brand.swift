import SwiftUI

// MARK: - BrandCardModifier

/// Apply to a custom container (not a Form row) to get the same dark-tinted
/// purple-bordered card surface — for hero / loadout strip / etc.
struct BrandCardModifier: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.purple.opacity(0.18), lineWidth: 0.5)
            )
    }
}

extension View {
    func brandCard(padding: CGFloat = 16, cornerRadius: CGFloat = 14) -> some View {
        modifier(BrandCardModifier(padding: padding, cornerRadius: cornerRadius))
    }
}
