import SwiftUI

// MARK: - MutualPassRow

/// One mutual window: satellite, times, and the limiting peak elevation.
struct MutualPassRow: View {
    // MARK: Internal

    let pass: MutualPass
    let transmitter: SatNOGSTransmitter?
    let amsatStatus: AmsatSatelliteStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(pass.name)
                    .font(.subheadline.weight(.semibold).monospaced())
                    .lineLimit(1)
                if let detail = pass.detailName {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if let transmitter {
                    SatelliteModeBadge(mode: transmitter.mode)
                    if let downlink = transmitter.downlinkLow {
                        Text(String(format: "↓ %.3f", Double(downlink) / 1_000_000))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                if let amsatStatus {
                    AmsatStatusBadge(status: amsatStatus)
                }
                Spacer()
                if SatelliteWorkability.isMarginal(peakElevationDeg: pass.peakMinElevationDeg) {
                    MarginalPassTag()
                }
                Text(String(format: "min %.0f°", pass.peakMinElevationDeg))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(minStyle)
            }
            HStack(spacing: 6) {
                Text(timeRange)
                    .monospacedDigit()
                Text("·")
                Text("\(max(Int((pass.duration / 60).rounded()), 1)) min together")
                Spacer()
                Text(String(
                    format: "you %.0f° · them %.0f°",
                    pass.peakElevationADeg, pass.peakElevationBDeg
                ))
                .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            // Which way to point during the window, from YOUR sky.
            Text(
                "your sky "
                    + "\(SatellitePassRow.compassLabel(pass.startAzimuthADeg))"
                    + " → peaks \(SatellitePassRow.compassLabel(pass.peakAzimuthADeg))"
                    + " → \(SatellitePassRow.compassLabel(pass.endAzimuthADeg))"
            )
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    // MARK: Private

    private var timeRange: String {
        let start = pass.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        let end = pass.end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }

    private var minStyle: Color {
        if pass.peakMinElevationDeg >= 30 {
            return .green
        }
        if pass.peakMinElevationDeg >= 10 {
            return .primary
        }
        return .secondary
    }
}
