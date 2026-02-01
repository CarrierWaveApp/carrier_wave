import SwiftUI

// MARK: - POTASpotRow

/// A row displaying a single POTA spot
struct POTASpotRow: View {
    // MARK: Internal

    let spot: POTASpot
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                // Frequency column
                VStack(alignment: .trailing, spacing: 2) {
                    frequencyDisplay
                    bandModeDisplay
                }
                .frame(width: 80, alignment: .trailing)

                // Callsign and park info
                VStack(alignment: .leading, spacing: 2) {
                    callsignRow
                    parkInfoRow
                }

                Spacer()

                // Time ago
                Text(spot.timeAgo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Private

    private var parkDisplayText: String {
        var parts: [String] = [spot.reference]

        // Add location if available
        if let loc = spot.locationDesc, !loc.isEmpty {
            // Extract state from "US-CA" format
            let state = loc.components(separatedBy: "-").last ?? loc
            parts.append(state)
        }

        // Add park name if available
        if let name = spot.parkName, !name.isEmpty {
            parts.append(name)
        }

        return parts.joined(separator: " - ")
    }

    // MARK: - Subviews

    private var frequencyDisplay: some View {
        Group {
            if let freqKHz = spot.frequencyKHz {
                Text(formatFrequency(freqKHz / 1_000.0))
                    .font(.subheadline.monospaced())
            } else {
                Text(spot.frequency)
                    .font(.subheadline.monospaced())
            }
        }
    }

    private var bandModeDisplay: some View {
        HStack(spacing: 4) {
            if let band = BandUtilities.deriveBand(from: spot.frequencyKHz) {
                Text(band)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(spot.mode)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var callsignRow: some View {
        Text(spot.activator)
            .font(.subheadline.weight(.semibold).monospaced())
            .foregroundStyle(.primary)
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

    // MARK: - Helpers

    private func formatFrequency(_ mhz: Double) -> String {
        // Round to nearest 100Hz and format with consistent width for alignment
        // Pads with leading spaces so decimals align (e.g., " 7.034" vs "14.034")
        let kHz = mhz * 1_000.0
        let rounded100Hz = (kHz * 10).rounded() / 10 // Round to nearest 0.1 kHz (100Hz)
        let wholekHz = Int(rounded100Hz)
        let subkHz = Int((rounded100Hz - Double(wholekHz)) * 10 + 0.5) // 0-9 representing .0-.9

        let wholeMHz = wholekHz / 1_000
        let remainderkHz = wholekHz % 1_000

        if subkHz > 0 {
            // With sub-kHz: "14.061.5" - pad MHz to 2 chars for alignment
            return String(format: "%2d.%03d.%d", wholeMHz, remainderkHz, subkHz)
        } else {
            // Without sub-kHz: "14.061  " - pad with trailing spaces to match width
            return String(format: "%2d.%03d  ", wholeMHz, remainderkHz)
        }
    }
}
