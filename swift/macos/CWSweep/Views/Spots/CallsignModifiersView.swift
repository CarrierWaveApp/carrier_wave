import SwiftUI

/// Displays parsed callsign prefix/suffix modifiers as inline capsule badges.
/// Used by both SpotDetailInspector and ClusterSpotDetailView.
struct CallsignModifiersView: View {
    // MARK: Internal

    let components: CallsignComponents

    var body: some View {
        HStack(spacing: 6) {
            Text(components.baseCallsign)
                .font(.caption.monospaced().weight(.medium))
                .foregroundStyle(.secondary)

            if let pfx = components.prefix {
                modifierBadge(pfx.meaning, icon: "globe")
            }

            if let sfx = components.suffix {
                modifierBadge(sfx.meaning, icon: "location")
            }
        }
    }

    // MARK: Private

    private func modifierBadge(
        _ text: String,
        icon: String
    ) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.15))
            .clipShape(Capsule())
    }
}
