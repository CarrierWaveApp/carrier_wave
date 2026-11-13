import CarrierWaveData
import SwiftUI

// MARK: - SatelliteStatusBadge

/// Status-bar pill for the satellite station: rotator link state (and
/// position while tracking), Doppler CAT state, and TLE age. Renders — with
/// its trailing divider — only when a rotator is linked or CAT is armed, so
/// non-satellite operators never see it. Clicking jumps to the Satellites
/// workspace.
struct SatelliteStatusBadge: View {
    // MARK: Internal

    var body: some View {
        if rotator.isConnected || cat.isEnabled {
            Button {
                NotificationCenter.default.post(name: .showSatellites, object: nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "dot.radiowaves.up.forward")
                        .foregroundStyle(rotatorColor)
                    Text(rotatorText)
                        .font(.caption.monospacedDigit())
                    if cat.isEnabled {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(cat.summaryLabel)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(cat.linkState == .following ? .green : .secondary)
                    }
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(model.tleAgeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help("Satellite station — click to open the Satellites workspace")
            Divider()
                .frame(height: 12)
        }
    }

    // MARK: Private

    private let rotator = SharedEnvironment.shared.rotatorController
    private let cat = SharedEnvironment.shared.satelliteCAT
    private let model = SharedEnvironment.shared.satellitePassModel

    private var rotatorText: String {
        guard rotator.isConnected else {
            return rotator.state.label
        }
        let name = rotator.endpoint?.kind.displayName ?? "Rotator"
        if let position = rotator.position {
            return String(
                format: "%@ %@ %03.0f°/%02.0f°",
                name, rotator.isFollowing ? "tracking" : "linked", position.azimuthDeg, position.elevationDeg
            )
        }
        return "\(name) \(rotator.isFollowing ? "tracking" : "linked")"
    }

    private var rotatorColor: Color {
        switch rotator.state {
        case .following: .green
        case .idle: .blue
        case .connecting: .orange
        case .error: .red
        case .disconnected: .secondary
        }
    }
}

extension Notification.Name {
    /// Posted by the satellite status pill; `WorkspaceView` selects the
    /// Satellites sidebar item.
    static let showSatellites = Notification.Name("CWSweep.showSatellites")
}
