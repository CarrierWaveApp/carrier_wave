import CarrierWaveCore
import SwiftUI

// MARK: - SkyDomeFooter

/// Bottom overlay of the sky dome: hover metadata card, selected-satellite
/// status, or a hint when nothing is selected.
struct SkyDomeFooter: View {
    // MARK: Internal

    let hovered: SkySighting?
    let selected: SkySighting?
    let selectedNoradID: Int?
    let isOnTarget: Bool
    let elementTiltDeg: Double?
    let transmitters: (Int) -> [SatNOGSTransmitter]
    /// Curated downlink polarization from the engine's table, by NORAD id.
    let polarization: (Int) -> FfiSatPolarization?

    var body: some View {
        if let hovered {
            hoverCard(for: hovered)
        } else if let selected {
            selectedStatus(for: selected)
        } else {
            Text("Select a satellite on the map to highlight it here")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
        }
    }

    // MARK: Private

    /// Curated downlink polarization for the selected satellite, if known.
    private var selectedPolarization: FfiSatPolarization? {
        selectedNoradID.flatMap { polarization($0) }
    }

    private var lockLine: some View {
        VStack(spacing: 2) {
            Label("On target", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
            if let polarization = selectedPolarization, polarization.isCircular {
                Text(polarization.pointingHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let tilt = elementTiltDeg {
                Text(String(
                    format: "Polarization roll %.0f°%@ — twist to peak, flip 90° if it fades",
                    tilt,
                    abs(tilt) < 20 ? " (H)" : (abs(tilt) > 70 ? " (V)" : "")
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func selectedStatus(for selected: SkySighting) -> some View {
        VStack(spacing: 4) {
            if selected.elDeg <= 0 {
                Text("\(selected.position.name) is below the horizon")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 12) {
                    Text(selected.position.name)
                        .font(.headline.monospaced())
                        .foregroundStyle(isOnTarget ? .green : .orange)
                    Text(String(format: "AZ %.0f°  EL %.0f°", selected.azDeg, selected.elDeg))
                        .font(.subheadline)
                        .monospacedDigit()
                }
                if isOnTarget {
                    lockLine
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// Info + metadata for whichever satellite the crosshair is hovering.
    private func hoverCard(for hovered: SkySighting) -> some View {
        let isSelected = hovered.position.noradID == selectedNoradID
        let transmitterList = transmitters(hovered.position.noradID)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(hovered.position.name)
                    .font(.headline.monospaced())
                    .foregroundStyle(isSelected ? Color.orange : Color.primary)
                    .lineLimit(1)
                if let detail = hovered.position.detailName {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("NORAD \(String(hovered.position.noradID))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if let polarization = polarization(hovered.position.noradID) {
                    SatellitePolarizationBadge(polarization: polarization)
                }
            }
            HStack(spacing: 12) {
                Text(String(format: "AZ %.0f°", hovered.azDeg))
                Text(String(format: "EL %.0f°", hovered.elDeg))
                if let range = hovered.position.rangeKm {
                    Text(String(format: "%.0f km", range))
                }
                Text("alt \(Int(hovered.position.altitudeKm)) km")
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            ForEach(Array(transmitterList.prefix(3).enumerated()), id: \.offset) { _, transmitter in
                transmitterLine(transmitter)
            }
            if transmitterList.count > 3 {
                Text("+ \(transmitterList.count - 3) more transmitters")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if isSelected, isOnTarget {
                lockLine
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 360, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func transmitterLine(_ transmitter: SatNOGSTransmitter) -> some View {
        HStack(spacing: 6) {
            TransmitterHeardDot(transmitter: transmitter)
            SatelliteModeBadge(mode: transmitter.mode)
            if let downlink = transmitter.downlinkLow {
                Text(String(format: "↓ %.3f", Double(downlink) / 1_000_000))
                    .font(.caption2.monospaced())
            }
            if let uplink = transmitter.uplinkLow {
                Text(String(format: "↑ %.3f", Double(uplink) / 1_000_000))
                    .font(.caption2.monospaced())
            }
            Text(transmitter.description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if !transmitter.isActive {
                Text("inactive")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
