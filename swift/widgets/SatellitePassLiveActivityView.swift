import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - SatellitePassLiveActivity

/// Countdown to AOS for a favorited satellite pass. The whole activity is
/// date-driven: `Text(_:style:.timer)` counts down to AOS on its own (and up
/// once the pass begins), so no ContentState updates are needed mid-pass;
/// `staleDate` = LOS lets the system dim it after the bird sets.
struct SatellitePassLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SatellitePassAttributes.self) { context in
            SatellitePassLockScreenView(attributes: context.attributes)
                .activityBackgroundTint(Color(.systemBackground))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.satelliteName, systemImage: "satellite")
                        .font(.headline.monospaced())
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.aos, style: .timer)
                        .font(.headline.monospacedDigit())
                        .frame(maxWidth: 60)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(SatellitePassCopy.detail(for: context.attributes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "satellite")
            } compactTrailing: {
                Text(context.attributes.aos, style: .timer)
                    .font(.caption.monospacedDigit())
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "satellite")
            }
        }
    }
}

// MARK: - SatellitePassLockScreenView

private struct SatellitePassLockScreenView: View {
    let attributes: SatellitePassAttributes

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label(attributes.satelliteName, systemImage: "satellite")
                    .font(.headline.monospaced())
                if attributes.isMarginal {
                    Text("marginal")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("AOS")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(attributes.aos, style: .timer)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .frame(maxWidth: 72, alignment: .trailing)
                }
            }
            Text(SatellitePassCopy.detail(for: attributes))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
    }
}

// MARK: - SatellitePassCopy

private enum SatellitePassCopy {
    // MARK: Internal

    /// "Peaks 62° · W → E · LOS 12:34"
    static func detail(for attributes: SatellitePassAttributes) -> String {
        let path = "\(compassPoint(attributes.aosAzimuthDeg)) → "
            + compassPoint(attributes.losAzimuthDeg)
        let los = attributes.los.formatted(date: .omitted, time: .shortened)
        return String(
            format: "Peaks %.0f° · %@ · LOS %@", attributes.peakElevationDeg, path, los
        )
    }

    // MARK: Private

    private static func compassPoint(_ degrees: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int(((degrees + 22.5) / 45).rounded(.down)) % points.count
        return points[index]
    }
}
