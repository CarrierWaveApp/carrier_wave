import CarrierWaveCore
import SwiftUI

// MARK: - POTASpotRow

/// A row displaying a single POTA spot
struct POTASpotRow: View {
    // MARK: Internal

    let spot: POTASpot
    let userCallsign: String?
    var friendCallsigns: Set<String> = []
    var workedResult: WorkedBeforeResult = .notWorked
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
                    workedBeforeBadges
                }

                Spacer()

                // Time ago
                Text(spot.timeAgo)
                    .font(.caption)
                    .foregroundStyle(spot.ageColor)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .opacity(isDupe ? 0.5 : 1.0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Private

    private var spotBand: String {
        BandUtilities.deriveBand(from: spot.frequencyKHz) ?? ""
    }

    private var isDupe: Bool {
        workedResult.isDupe(on: spotBand, mode: spot.mode)
    }

    private var isFriend: Bool {
        friendCallsigns.contains(spot.activator.uppercased())
    }

    private var isSelf: Bool {
        if let userCallsign {
            return spot.isSelfSpot(userCallsign: userCallsign)
        }
        return false
    }

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
        HStack(spacing: 4) {
            // Human spots get a star indicator
            if spot.isHumanSpot {
                Image(systemName: "person.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Text(spot.activator)
                .font(.subheadline.weight(.semibold).monospaced())
                .foregroundStyle(spot.isHumanSpot ? .primary : .secondary)
                .strikethrough(isDupe)

            if isSelf {
                Text("SELF")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.indigo)
                    .clipShape(Capsule())
            } else if isFriend {
                Text("FRIEND")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green)
                    .clipShape(Capsule())
            }

            // Show RBN badge for automated spots
            if spot.isAutomatedSpot {
                Text("RBN")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
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

    // MARK: - Worked Before Badges

    @ViewBuilder
    private var workedBeforeBadges: some View {
        if isDupe {
            dupeBadge
        } else if !workedResult.todayBands.isEmpty {
            todayWorkedBadge
        } else if !workedResult.previousBands.isEmpty {
            previousWorkedBadge
        }
    }

    private var dupeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
            Text("DUPE \(spotBand) \(spot.mode)")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.15))
        .clipShape(Capsule())
    }

    private var todayWorkedBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "checkmark")
                .font(.caption2)
            Text(workedResult.todayBands.sorted().joined(separator: " "))
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.15))
        .clipShape(Capsule())
    }

    private var previousWorkedBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "checkmark")
                .font(.caption2)
            Text(workedResult.previousBands.sorted().joined(separator: " "))
                .font(.caption2.weight(.medium))
            Text("(prev)")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
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
