import SwiftUI

// MARK: - CommunityDot

/// The community signal where the operator already looks (pass rows, the
/// info card, map markers): a dot in AMSAT's legend colour for the last
/// 24 h — blue heard, yellow telemetry-only, magenta not heard, gray quiet
/// — and a hollow ring when AMSAT doesn't track the bird at all.
struct CommunityDot: View {
    // MARK: Internal

    let status: AmsatSatelliteStatus?
    var size: CGFloat = 8

    var body: some View {
        Group {
            if let status {
                Circle()
                    .fill(status.dayStatus.color)
            } else {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1.2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(label)
    }

    // MARK: Private

    private var label: String {
        guard let status else {
            return "Not tracked by AMSAT"
        }
        switch status.dayStatus {
        case .quiet: return "No community reports today"
        case .heard: return "Heard by the community today"
        case .telemetryOnly: return "Telemetry only today"
        case .notHeard: return "Not heard by the community today"
        case .conflicting: return "Conflicting community reports today"
        }
    }
}
