import CarrierWaveData
import SwiftUI

// MARK: - SunlightModeKey

/// Environment key for sunlight mode, which boosts contrast and readability
/// for outdoor use in bright conditions.
private struct SunlightModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var sunlightMode: Bool {
        get { self[SunlightModeKey.self] }
        set { self[SunlightModeKey.self] = newValue }
    }
}

// MARK: - SunlightModeModifier

/// Applies sunlight-optimized rendering to a view hierarchy.
///
/// When active, this modifier:
/// - Boosts overall contrast for better screen readability in bright light
/// - Forces light color scheme (bright backgrounds reflect more light)
/// - Reduces translucency effects that wash out in sunlight
struct SunlightModeModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content
                .preferredColorScheme(.light)
                .contrast(1.2)
                .environment(\.sunlightMode, true)
        } else {
            content
                .environment(\.sunlightMode, false)
        }
    }
}

extension View {
    /// Applies sunlight mode optimizations when active.
    func sunlightMode(_ isActive: Bool) -> some View {
        modifier(SunlightModeModifier(isActive: isActive))
    }
}
