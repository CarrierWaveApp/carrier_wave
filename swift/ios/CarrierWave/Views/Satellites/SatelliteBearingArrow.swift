import SwiftUI

// MARK: - SatelliteHeadingSampler

/// A slow, quantized copy of the device heading for list rows. The raw
/// 30 Hz attitude stream re-rendered every row's arrow per sample, and a
/// List cell that reconfigures mid-touch drops the tap (rows needed a
/// second tap). 5 Hz in 2° steps is invisible to the eye and leaves the
/// cells alone while you hold still.
@MainActor
@Observable
final class SatelliteHeadingSampler {
    private(set) var headingDeg: Double?

    /// Sample until cancelled (reads outside a view body are untracked).
    func run(motion: AntennaMotionService) async {
        while !Task.isCancelled {
            let sampled = motion.screenHeadingDeg.map { ($0 / 2).rounded() * 2 }
            if sampled != headingDeg {
                headingDeg = sampled
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }
}

// MARK: - SatelliteBearingArrow

/// A compass arrow toward an azimuth, counter-rotated by the sampled
/// device heading so it points at the real sky (north-up when no heading
/// is available, e.g. the simulator). Green while the bird is up, dimmed
/// when it's pointing at where the bird will rise.
struct SatelliteBearingArrow: View {
    let azimuthDeg: Double
    let isAboveHorizon: Bool
    let sampler: SatelliteHeadingSampler
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: "location.north.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(isAboveHorizon ? Color.green : Color.secondary)
            .rotationEffect(.degrees(azimuthDeg - (sampler.headingDeg ?? 0)))
            .accessibilityHidden(true)
    }
}
