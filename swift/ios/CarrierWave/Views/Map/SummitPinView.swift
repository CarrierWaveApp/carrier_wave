import CarrierWaveCore
import SwiftUI

// MARK: - SummitPinView

/// Compact pin for SOTA summit locations on the map
struct SummitPinView: View {
    let summit: SOTASummit
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? .white : .orange)
                .padding(6)
                .background(
                    isSelected ? Color.orange : Color(.systemBackground),
                    in: Circle()
                )
                .overlay(Circle().stroke(.orange, lineWidth: 1.5))
                .shadow(radius: isSelected ? 4 : 2)
        }
    }
}

// MARK: - SummitCalloutView

/// Detail callout shown when a SOTA summit is selected
struct SummitCalloutView: View {
    // MARK: Internal

    let summit: SOTASummit
    var onStartSession: ((SOTASummit) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            Text(summit.name)
                .font(.subheadline)
                .foregroundStyle(.primary)
            locationRow
            statsRow
            lastActivationRow
            startSessionButton
            sotlasLink
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    @Environment(\.openURL) private var openURL

    private var sharePayload: EnrichedLinkPayload {
        EnrichedLinkPayload.summit(
            reference: summit.code,
            name: summit.name,
            associationName: summit.associationName,
            regionName: summit.regionName,
            altitudeMeters: summit.altitudeM,
            points: summit.points,
            latitude: summit.latitude,
            longitude: summit.longitude,
            activationCount: summit.activationCount
        )
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack {
            Text(summit.code)
                .font(.headline.monospaced())
            Spacer()
            Label("\(summit.points) pts", systemImage: "star.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
            EnrichedShareButton(payload: sharePayload)
                .accessibilityLabel("Share \(summit.code)")
        }
    }

    private var locationRow: some View {
        HStack(spacing: 16) {
            Label(
                "\(summit.altitudeFt) ft",
                systemImage: "arrow.up.right"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if !summit.regionName.isEmpty {
                Label(summit.regionName, systemImage: "mappin")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 16) {
            if summit.activationCount > 0 {
                Label(
                    "\(summit.activationCount) activations",
                    systemImage: "antenna.radiowaves.left.and.right"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if summit.bonusPoints > 0 {
                Text("+\(summit.bonusPoints) bonus")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Color.orange.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
            }

            if let grid = summit.grid {
                Label(grid, systemImage: "grid")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var lastActivationRow: some View {
        if summit.lastActivationCall != nil || summit.formattedLastActivation != nil {
            Divider()
            HStack(spacing: 12) {
                if let dateStr = summit.formattedLastActivation {
                    Label(dateStr, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let callsign = summit.lastActivationCall {
                    Label(callsign, systemImage: "person.fill")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                if let days = summit.daysSinceLastActivation {
                    freshnessBadge(days: days)
                }
            }
        }
    }

    @ViewBuilder
    private var startSessionButton: some View {
        if onStartSession != nil {
            Divider()
            Button {
                onStartSession?(summit)
            } label: {
                Label("Start SOTA Session", systemImage: "play.fill")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
    }

    @ViewBuilder
    private var sotlasLink: some View {
        if summit.sotlasURL != nil {
            Divider()
            Button {
                if let url = summit.sotlasURL {
                    openURL(url)
                }
            } label: {
                Label("View on SOTL.as", systemImage: "safari")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
        }
    }

    private func freshnessBadge(days: Int) -> some View {
        let label: String
        let color: Color
        if days <= 30 {
            label = "Recent"
            color = .green
        } else if days <= 365 {
            label = "\(days / 30)mo ago"
            color = .yellow
        } else {
            label = "\(days / 365)yr ago"
            color = .gray
        }
        return Text(label)
            .font(.caption2)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                color.opacity(0.15),
                in: RoundedRectangle(cornerRadius: 4)
            )
    }
}
