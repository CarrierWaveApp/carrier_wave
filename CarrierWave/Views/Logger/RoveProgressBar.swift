import CarrierWaveData
import SwiftUI

// MARK: - RoveProgressBar

/// Horizontally scrolling bar showing all rove stops with the current stop highlighted
struct RoveProgressBar: View {
    let stops: [RoveStop]
    let currentStopId: UUID?
    /// Park reference being viewed (nil = viewing current active stop)
    let viewingPark: String?
    let onNextStop: () -> Void
    let onTapStop: (RoveStop) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(stops) { stop in
                    let isActive = stop.id == currentStopId
                    let isViewed = viewingPark != nil
                        ? stop.parkReference == viewingPark
                        : isActive
                    RoveStopPill(
                        stop: stop,
                        isActive: isActive,
                        isViewed: isViewed,
                        onTap: { onTapStop(stop) }
                    )
                }

                Button {
                    onNextStop()
                } label: {
                    Label("Next Stop", systemImage: "arrow.right")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .controlSize(.small)
                .accessibilityLabel("Advance to next park stop")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

// MARK: - RoveStopPill

/// Individual stop capsule showing park reference and QSO count
private struct RoveStopPill: View {
    // MARK: Internal

    let stop: RoveStop
    /// Whether this is the currently active rove stop (green dot)
    let isActive: Bool
    /// Whether this stop's QSOs are currently displayed in the logger
    let isViewed: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    if isActive {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                    }
                    Text(primaryPark)
                        .font(.caption.monospaced().weight(isViewed ? .bold : .regular))
                        .foregroundStyle(pillColor)
                }

                Text("\(stop.qsoCount)Q")
                    .font(.caption2.monospaced())
                    .foregroundStyle(isViewed ? pillColor : Color(uiColor: .tertiaryLabel))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(pillBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(primaryPark), \(stop.qsoCount) QSOs")
    }

    // MARK: Private

    private var primaryPark: String {
        ParkReference.split(stop.parkReference).first ?? stop.parkReference
    }

    private var pillColor: Color {
        if isActive {
            return .green
        }
        if isViewed {
            return .blue
        }
        return .secondary
    }

    private var pillBackground: Color {
        if isActive, isViewed {
            return Color.green.opacity(0.12)
        }
        if isViewed {
            return Color.blue.opacity(0.12)
        }
        return Color(.systemGray5)
    }
}

// MARK: - RoveStopPopover

/// Popover showing details for a tapped rove stop
struct RoveStopPopover: View {
    // MARK: Internal

    let stop: RoveStop

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Park reference(s)
            let parks = ParkReference.split(stop.parkReference)
            ForEach(parks, id: \.self) { park in
                HStack(spacing: 6) {
                    Text(park)
                        .font(.subheadline.monospaced().weight(.semibold))
                        .foregroundStyle(.green)
                    if let name = POTAParksCache.shared.nameSync(for: park) {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            // Time range
            HStack(spacing: 4) {
                Text(Self.timeFormatter.string(from: stop.startedAt))
                if let endedAt = stop.endedAt {
                    Text("–")
                    Text(Self.timeFormatter.string(from: endedAt))
                } else {
                    Text("– now")
                }
                Text("UTC")
                    .foregroundStyle(.secondary)
            }
            .font(.caption.monospaced())

            // Stats row
            HStack(spacing: 12) {
                Label("\(stop.qsoCount) QSOs", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption)

                if let grid = stop.myGrid {
                    Label(grid, systemImage: "square.grid.3x3")
                        .font(.caption.monospaced())
                }

                Text(stop.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 200)
    }

    // MARK: Private

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
