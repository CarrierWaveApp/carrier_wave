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
                // Format as MHz with sub-kHz precision like "14.031.900"
                let mhz = freqKHz / 1_000.0
                let formatted = formatFrequencyWithSubKHz(mhz)
                Text(formatted)
                    .font(.subheadline.monospaced())
            } else {
                Text(spot.frequency)
                    .font(.subheadline.monospaced())
            }
        }
    }

    private var bandModeDisplay: some View {
        HStack(spacing: 4) {
            if let band = deriveBand(from: spot.frequencyKHz) {
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
        HStack(spacing: 4) {
            Text(spot.activator)
                .font(.subheadline.weight(.semibold).monospaced())
                .foregroundStyle(.primary)

            // Activity type icon based on reference prefix
            if spot.reference.hasPrefix("K-") || spot.reference.hasPrefix("US-") {
                Image(systemName: "tree.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else if spot.reference.contains("FF-") {
                // Flora & Fauna
                Image(systemName: "leaf.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "mappin.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
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

    // MARK: - Helpers

    private func formatFrequencyWithSubKHz(_ mhz: Double) -> String {
        // Format like "14.031.900" for 14031.9 kHz
        let wholeMHz = Int(mhz)
        let remainder = mhz - Double(wholeMHz)
        let kHz = Int(remainder * 1_000)
        let subKHz = Int((remainder * 1_000 - Double(kHz)) * 1_000)

        if subKHz > 0 {
            return String(format: "%d.%03d.%03d", wholeMHz, kHz, subKHz)
        } else {
            return String(format: "%d.%03d", wholeMHz, kHz)
        }
    }

    private func deriveBand(from frequencyKHz: Double?) -> String? {
        guard let kHz = frequencyKHz else {
            return nil
        }
        let mhz = kHz / 1_000.0

        switch mhz {
        case 1.8 ..< 2.0: return "160m"
        case 3.5 ..< 4.0: return "80m"
        case 5.3 ..< 5.4: return "60m"
        case 7.0 ..< 7.3: return "40m"
        case 10.1 ..< 10.15: return "30m"
        case 14.0 ..< 14.35: return "20m"
        case 18.068 ..< 18.168: return "17m"
        case 21.0 ..< 21.45: return "15m"
        case 24.89 ..< 24.99: return "12m"
        case 28.0 ..< 29.7: return "10m"
        case 50.0 ..< 54.0: return "6m"
        case 144.0 ..< 148.0: return "2m"
        case 420.0 ..< 450.0: return "70cm"
        default: return nil
        }
    }
}
