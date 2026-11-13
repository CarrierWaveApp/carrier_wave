import CarrierWaveData
import SwiftUI

// MARK: - RotatorStatusChip

/// Logger-style status chip for the station rotator ("PSR-100 · 207°/0°"):
/// green while tracking, blue when linked, gray while connecting, red on
/// error; hidden when no rotator is linked or remembered. Same shape as the
/// session header chips.
struct RotatorStatusChip: View {
    // MARK: Internal

    var action: (() -> Void)?

    var body: some View {
        if let endpoint = rotator.endpoint ?? rotator.savedEndpoint {
            Button {
                action?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "dial.medium")
                        .font(.caption2)
                    Text(endpoint.kind.shortLabel)
                    if let position = rotator.position, rotator.isConnected {
                        Text(String(format: "%03.0f°/%.0f°", position.azimuthDeg, position.elevationDeg))
                            .monospacedDigit()
                    } else {
                        Text(stateWord)
                    }
                }
                .font(.caption)
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tint.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(action == nil)
            .accessibilityLabel("Rotator \(endpoint.kind.displayName): \(rotator.state.label)")
        }
    }

    // MARK: Private

    private var rotator: RotatorController {
        SatelliteRotatorService.shared.rotator
    }

    private var stateWord: String {
        switch rotator.state {
        case .disconnected: "off"
        case .connecting: "linking"
        case .idle: "linked"
        case .following: "tracking"
        case .error: "error"
        }
    }

    private var tint: Color {
        switch rotator.state {
        case .following: .green
        case .idle: .blue
        case .connecting: .gray
        case .error: .red
        case .disconnected: .secondary
        }
    }
}
