import SwiftUI

// MARK: - LandscapeAdaptiveDetents

/// Switches sheet detents based on vertical size class.
/// In landscape (compact vertical), sheets expand to avoid being clipped.
private struct LandscapeAdaptiveDetents: ViewModifier {
    // MARK: Internal

    let portraitDetents: Set<PresentationDetent>

    func body(content: Content) -> some View {
        content
            .presentationDetents(verticalSizeClass == .compact ? landscapeDetents : portraitDetents)
    }

    // MARK: Private

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var landscapeDetents: Set<PresentationDetent> {
        var result = Set<PresentationDetent>()
        for detent in portraitDetents {
            switch detent {
            case .medium:
                result.insert(.large)
            case .large:
                result.insert(.large)
            default:
                // Fixed heights (.height(N)) become .medium in landscape
                result.insert(.medium)
            }
        }
        // If portrait was [.medium, .large], landscape collapses to [.large]
        // If portrait was [.medium], landscape becomes [.large]
        // If portrait was [.height(N)], landscape becomes [.medium]
        return result.isEmpty ? [.large] : result
    }
}

extension View {
    /// Apply landscape-adaptive sheet detents.
    /// In portrait, uses the provided detents. In landscape, expands them
    /// to avoid sheets being clipped at unusable heights.
    func landscapeAdaptiveDetents(
        portrait detents: Set<PresentationDetent>
    ) -> some View {
        modifier(LandscapeAdaptiveDetents(portraitDetents: detents))
    }
}
