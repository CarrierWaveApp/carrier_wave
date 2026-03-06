// Network Health Banner
//
// Shows a persistent warning when the network is degraded (device appears
// connected but requests are failing). Dismissable per-session.

import SwiftUI

// MARK: - NetworkHealthBanner

struct NetworkHealthBanner: View {
    // MARK: Internal

    let health: NetworkHealth
    let onDismiss: () -> Void

    var body: some View {
        switch health {
        case .healthy:
            EmptyView()

        case .disconnected:
            bannerContent(
                icon: "wifi.slash",
                iconColor: .red,
                title: "No Internet Connection",
                subtitle: "QRZ lookups, syncing, and other online features are unavailable.",
                background: Color.red.opacity(0.15)
            )

        case let .degraded(failures):
            bannerContent(
                icon: "exclamationmark.icloud",
                iconColor: .orange,
                title: "Network Issues Detected",
                subtitle: "\(failures) requests failed. Lookups and syncing may not work.",
                background: Color.orange.opacity(0.15)
            )
        }
    }

    // MARK: Private

    private func bannerContent(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        background: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    VStack(spacing: 16) {
        NetworkHealthBanner(
            health: .disconnected,
            onDismiss: {}
        )
        NetworkHealthBanner(
            health: .degraded(consecutiveFailures: 5),
            onDismiss: {}
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
