import CarrierWaveData
import SwiftUI

// MARK: - SatellitePointTrackButton

/// Under the sky plot: one click slews the linked rotator onto the selected
/// satellite (its live az/el, or the rise azimuth before AOS) and turns
/// Follow on; while tracking it shows the commanded pointing and a second
/// click stops the rotor. Hidden unless a rotator is linked and a pass is
/// selected.
struct SatellitePointTrackButton: View {
    // MARK: Internal

    let model: SatellitePassModel

    var body: some View {
        if model.rotator.isConnected, model.selectedPass != nil {
            Button {
                Task { await toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isTracking ? "stop.fill" : "scope")
                    Text(isTracking ? "Tracking" : "Point & Track")
                        .font(SatelliteTheme.label(12, weight: .semibold))
                    if isTracking, let target = model.rotator.commandedTarget {
                        Text(String(format: "%03.0f° / %.0f°", target.azimuthDeg, target.elevationDeg))
                            .font(SatelliteTheme.mono(12, weight: .medium))
                            .foregroundStyle(SatelliteTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    (isTracking ? SatelliteTheme.rx : SatelliteTheme.accent).opacity(0.18),
                    in: Capsule()
                )
                .overlay(Capsule().stroke(isTracking ? SatelliteTheme.rx : SatelliteTheme.accent, lineWidth: 1))
                .foregroundStyle(isTracking ? SatelliteTheme.rx : SatelliteTheme.accent)
            }
            .buttonStyle(.plain)
            .disabled(!isTracking && desiredTarget == nil)
            .help(isTracking ? "Stop the rotator and leave follow mode" :
                "Slew the rotator to the satellite and follow it")
        }
    }

    // MARK: Private

    private var isTracking: Bool {
        model.rotator.isFollowing
    }

    /// Satellite az/el while up, else the rise azimuth within the lead time.
    private var desiredTarget: RotatorPosition? {
        let frame = model.frame
        if let look = frame.look, look.isAboveHorizon {
            return RotatorPosition(azimuthDeg: look.azimuthDeg, elevationDeg: look.elevationDeg)
        }
        if let pass = frame.pass, let toAOS = frame.secondsToAOS, toAOS <= SatellitePassModel.prePositionLead {
            return RotatorPosition(azimuthDeg: pass.aosAzimuthDeg, elevationDeg: 0)
        }
        return nil
    }

    private func toggle() async {
        if isTracking {
            await model.rotator.stop()
            return
        }
        guard let desiredTarget else {
            return
        }
        await model.rotator.moveTo(desiredTarget)
        await model.rotator.startFollowing()
    }
}
