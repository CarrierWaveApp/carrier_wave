import CarrierWaveCore
import SwiftUI

// MARK: - RoveProgressBar

/// Horizontally scrolling bar showing all rove stops with the current stop highlighted
struct RoveProgressBar: View {
    let stops: [RoveStop]
    let currentStopId: UUID?
    let onNextStop: () -> Void
    let onTapStop: (RoveStop) -> Void

    private var totalQSOs: Int {
        stops.reduce(0) { $0 + $1.qsoCount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(headerText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

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

            // Stop pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(stops) { stop in
                        RoveStopPill(
                            stop: stop,
                            isCurrent: stop.id == currentStopId,
                            onTap: { onTapStop(stop) }
                        )
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var headerText: String {
        let stopIndex = stops.firstIndex { $0.id == currentStopId }
        let current = stopIndex.map { $0 + 1 } ?? stops.count
        let total = stops.count
        return "Rove: Stop \(current) of \(total) \u{00B7} \(totalQSOs) QSOs total"
    }
}

// MARK: - RoveStopPill

/// Individual stop capsule showing park reference and QSO count
private struct RoveStopPill: View {
    let stop: RoveStop
    let isCurrent: Bool
    let onTap: () -> Void

    private var primaryPark: String {
        ParkReference.split(stop.parkReference).first ?? stop.parkReference
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    if isCurrent {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                    }
                    Text(primaryPark)
                        .font(.caption.monospaced().weight(isCurrent ? .bold : .regular))
                        .foregroundStyle(isCurrent ? .green : .secondary)
                }

                Text("\(stop.qsoCount)Q")
                    .font(.caption2.monospaced())
                    .foregroundStyle(isCurrent ? .green : .tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isCurrent
                    ? Color.green.opacity(0.12)
                    : Color(.systemGray5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(primaryPark), \(stop.qsoCount) QSOs")
    }
}

// MARK: - RoveStopPopover

/// Popover showing details for a tapped rove stop
struct RoveStopPopover: View {
    let stop: RoveStop

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

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
}
