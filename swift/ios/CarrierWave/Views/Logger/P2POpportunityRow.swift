import CarrierWaveData
import SwiftUI

// MARK: - P2POpportunityRow

/// A row displaying a single P2P opportunity
struct P2POpportunityRow: View {
    // MARK: Internal

    let opportunity: P2POpportunity
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .trailing, spacing: 2) {
                    frequencyDisplay
                    bandModeDisplay
                }
                .frame(width: 80, alignment: .trailing)

                VStack(alignment: .leading, spacing: 2) {
                    callsignRow
                    parkInfoRow
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    snrDisplay
                    Text(opportunity.timeAgo)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Private

    private var snrColor: Color {
        switch opportunity.snr {
        case ..<10:
            .red
        case ..<20:
            .orange
        case ..<30:
            .yellow
        default:
            .green
        }
    }

    private var parkDisplayText: String {
        var parts: [String] = [opportunity.parkRef]

        if let loc = opportunity.locationDesc, !loc.isEmpty {
            let state = loc.components(separatedBy: "-").last ?? loc
            parts.append(state)
        }

        if let name = opportunity.parkName, !name.isEmpty {
            parts.append(name)
        }

        return parts.joined(separator: " - ")
    }

    // MARK: - Subviews

    private var frequencyDisplay: some View {
        Text(formatFrequency(opportunity.frequencyMHz))
            .font(.subheadline.monospaced())
    }

    private var bandModeDisplay: some View {
        HStack(spacing: 4) {
            Text(opportunity.band)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(opportunity.mode)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var callsignRow: some View {
        HStack(spacing: 4) {
            Text(opportunity.callsign)
                .font(.subheadline.weight(.semibold).monospaced())
                .foregroundStyle(.primary)

            Text("P2P")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange)
                .clipShape(Capsule())
        }
    }

    private var parkInfoRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "tree.fill")
                .font(.caption2)
                .foregroundStyle(.green)

            Text(parkDisplayText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var snrDisplay: some View {
        HStack(spacing: 2) {
            snrBar
            Text("\(opportunity.snr) dB")
                .font(.caption.weight(.medium).monospaced())
                .foregroundStyle(snrColor)
        }
    }

    private var snrBar: some View {
        let normalizedSNR = min(max(Double(opportunity.snr), 0), 40) / 40.0
        return RoundedRectangle(cornerRadius: 2)
            .fill(snrColor)
            .frame(width: 30 * normalizedSNR, height: 8)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(snrColor.opacity(0.3), lineWidth: 1)
                    .frame(width: 30, height: 8),
                alignment: .leading
            )
    }

    private func formatFrequency(_ mhz: Double) -> String {
        let kHz = mhz * 1_000.0
        let rounded100Hz = (kHz * 10).rounded() / 10
        let wholekHz = Int(rounded100Hz)
        let subkHz = Int((rounded100Hz - Double(wholekHz)) * 10 + 0.5)

        let wholeMHz = wholekHz / 1_000
        let remainderkHz = wholekHz % 1_000

        if subkHz > 0 {
            return String(format: "%2d.%03d.%d", wholeMHz, remainderkHz, subkHz)
        } else {
            return String(format: "%2d.%03d  ", wholeMHz, remainderkHz)
        }
    }
}
