import CarrierWaveData
import SwiftUI

// MARK: - RotatorPointTrackButton

/// One tap to slew the linked rotator onto a satellite and keep it there.
/// Shown whenever a rotator is linked: with a selection it tracks that
/// bird; with none it offers the satellite under the sky-view reticle
/// ("Point & Track AO-27") and selects it on tap; with nothing in view it
/// sits disabled with a hint. While tracking it shows the commanded
/// pointing and a second tap stops the rotor and leaves Follow.
struct RotatorPointTrackButton: View {
    // MARK: Internal

    let model: SatelliteTrackerModel
    /// Satellite currently under the sky-view reticle, if any.
    var hovered: SatellitePosition?

    var body: some View {
        if service.rotator.isConnected {
            Button {
                Task { await toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isTracking ? "stop.fill" : "scope")
                    Text(label)
                        .fontWeight(.semibold)
                    if isTracking, let target = service.rotator.commandedTarget ?? service.desiredTarget {
                        Text(String(format: "%03.0f° / %.0f°", target.azimuthDeg, target.elevationDeg))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    (isTracking ? Color.green : Color.accentColor).opacity(0.22),
                    in: Capsule()
                )
                .overlay(Capsule().stroke(isTracking ? Color.green : Color.accentColor, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(!isTracking && candidate == nil)
            .accessibilityLabel(
                isTracking ? "Stop tracking with the rotator" : "Point the rotator at the satellite and track it"
            )
        }
    }

    // MARK: Private

    @State private var service = SatelliteRotatorService.shared

    private var isTracking: Bool {
        service.rotator.isFollowing
    }

    /// The satellite a tap would track: the selection, else the one in view.
    private var candidate: SatellitePosition? {
        model.selectedPosition ?? hovered
    }

    private var label: String {
        if isTracking {
            return "Tracking"
        }
        guard let candidate else {
            return "Point & Track — aim at a satellite"
        }
        if candidate.noradID == model.selectedNoradID {
            return "Point & Track"
        }
        return "Point & Track \(candidate.name)"
    }

    private func toggle() async {
        if isTracking {
            await service.rotator.stop()
            return
        }
        guard let candidate else {
            return
        }
        if candidate.noradID != model.selectedNoradID {
            model.select(candidate.noradID)
        }
        if !service.isRunning {
            service.start(model: model)
        }
        // Slew now from the live look; Follow keeps it there (and handles the
        // below-horizon pre-positioning once the feed loop ticks).
        if candidate.isAboveHorizon, let az = candidate.azimuthDeg, let el = candidate.elevationDeg {
            await service.rotator.moveTo(RotatorPosition(azimuthDeg: az, elevationDeg: el))
        } else if let target = service.desiredTarget {
            await service.rotator.moveTo(target)
        }
        await service.rotator.startFollowing()
    }
}
