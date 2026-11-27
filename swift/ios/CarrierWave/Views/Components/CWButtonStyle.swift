import SwiftUI

// MARK: - CWButtonStyle

/// The app's action-button look, taken from the logger's LOG button: a
/// rectangle with slightly rounded corners and an all-caps semibold label.
///
/// Use `.buttonStyle(.cwProminent)` for the primary action on a surface and
/// `.buttonStyle(.cwTinted)` for secondary actions. Both follow `.tint(_:)`,
/// `.controlSize(_:)`, the disabled state and `Button(role: .destructive)`,
/// so they are drop-in replacements for `.borderedProminent` / `.bordered`.
struct CWButtonStyle: ButtonStyle {
    enum Kind {
        /// Solid tint fill, white label (the LOG button).
        case prominent
        /// Faint tint fill, tint-colored label.
        case tinted
    }

    let kind: Kind
    /// Fixed size for navigation/tool bars, which ignore `.controlSize(_:)`.
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        CWButtonBody(kind: kind, compact: compact, configuration: configuration)
    }
}

// MARK: - CWButtonBody

private struct CWButtonBody: View {
    // MARK: Internal

    let kind: CWButtonStyle.Kind
    let compact: Bool
    let configuration: ButtonStyleConfiguration

    var body: some View {
        configuration.label
            .font(metrics.font)
            .fontWeight(.semibold)
            .textCase(.uppercase)
            .foregroundStyle(foreground)
            .padding(.horizontal, metrics.horizontal)
            .padding(.vertical, metrics.vertical)
            .background(background)
            .clipShape(shape)
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }

    // MARK: Private

    private struct Metrics {
        let font: Font
        let horizontal: CGFloat
        let vertical: CGFloat
        let cornerRadius: CGFloat
    }

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: metrics.cornerRadius)
    }

    private var tint: AnyShapeStyle {
        configuration.role == .destructive ? AnyShapeStyle(Color.red) : AnyShapeStyle(.tint)
    }

    private var foreground: AnyShapeStyle {
        kind == .prominent ? AnyShapeStyle(Color.white) : tint
    }

    private var background: AnyShapeStyle {
        kind == .prominent ? tint : AnyShapeStyle(tint.opacity(0.15))
    }

    private var metrics: Metrics {
        if compact {
            return Metrics(font: .subheadline, horizontal: 10, vertical: 6, cornerRadius: 8)
        }
        return switch controlSize {
        case .mini:
            Metrics(font: .caption, horizontal: 8, vertical: 4, cornerRadius: 6)
        case .small:
            Metrics(font: .subheadline, horizontal: 10, vertical: 5, cornerRadius: 8)
        case .large,
             .extraLarge:
            Metrics(font: .body, horizontal: 20, vertical: 14, cornerRadius: 12)
        default:
            Metrics(font: .body, horizontal: 12, vertical: 8, cornerRadius: 10)
        }
    }
}

extension ButtonStyle where Self == CWButtonStyle {
    /// Primary action: solid fill, white all-caps label.
    static var cwProminent: CWButtonStyle {
        CWButtonStyle(kind: .prominent)
    }

    /// Secondary action: faint tint fill, tint-colored all-caps label.
    static var cwTinted: CWButtonStyle {
        CWButtonStyle(kind: .tinted)
    }

    /// Bar-sized primary action (Save, Add). Pair with
    /// `.sharedBackgroundVisibility(.hidden)` on the `ToolbarItem` so the
    /// system glass capsule doesn't sit behind it.
    static var cwToolbarProminent: CWButtonStyle {
        CWButtonStyle(kind: .prominent, compact: true)
    }

    /// Bar-sized secondary action (Done, Cancel). Pair with
    /// `.sharedBackgroundVisibility(.hidden)` on the `ToolbarItem`.
    static var cwToolbarTinted: CWButtonStyle {
        CWButtonStyle(kind: .tinted, compact: true)
    }
}
