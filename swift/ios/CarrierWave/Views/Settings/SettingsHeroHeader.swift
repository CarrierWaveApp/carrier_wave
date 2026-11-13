import SwiftUI

// MARK: - SettingsHeroHeader

/// Large icon + title + description at the top of a settings sub-screen,
/// mirroring the hero headers Apple uses on inner pages of the iOS
/// Settings app. Place as the first element inside a `List`/`Form` and pair
/// with `.navigationBarTitleDisplayMode(.inline)` so the hero carries the
/// large title role.
struct SettingsHeroHeader: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 68, height: 68)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(tint.gradient)
                    )
                    .accessibilityHidden(true)

                Text(title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }
}

#Preview {
    NavigationStack {
        List {
            SettingsHeroHeader(
                icon: "paintbrush.fill",
                tint: .purple,
                title: "Appearance",
                subtitle: "Theme, units, and how the app is laid out."
            )
        }
    }
}
