import CarrierWaveCore
import SwiftUI

// MARK: - BoundaryMarkerRow

/// Inline separator row for UTC day changes and POTA shift boundaries in QSO lists.
struct BoundaryMarkerRow: View {
    // MARK: Internal

    let marker: SessionBoundaryMarker

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.caption)
                .foregroundStyle(markerColor)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(markerColor)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(timeLabel)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(markerColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: Private

    private static let timeFmt: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    private var iconName: String {
        switch marker.kind {
        case .utcDayChange:
            "calendar.badge.clock"
        case .shiftStart:
            "arrow.right.circle.fill"
        case .shiftEnd:
            "arrow.left.circle.fill"
        }
    }

    private var markerColor: Color {
        switch marker.kind {
        case .utcDayChange:
            .red
        case let .shiftStart(shift, _),
             let .shiftEnd(shift, _):
            shift == .late ? .indigo : .orange
        }
    }

    private var title: String {
        switch marker.kind {
        case let .utcDayChange(dateLabel):
            "UTC Day Change — \(dateLabel)"
        case let .shiftStart(shift, _):
            "\(shift.displayLabel) Begins"
        case let .shiftEnd(shift, _):
            "\(shift.displayLabel) Ends"
        }
    }

    private var subtitle: String? {
        switch marker.kind {
        case .utcDayChange:
            nil
        case let .shiftStart(_, window):
            window.formattedRange
        case let .shiftEnd(_, window):
            window.formattedRange
        }
    }

    private var timeLabel: String {
        switch marker.kind {
        case .utcDayChange:
            "00:00z"
        case let .shiftStart(_, window):
            "\(Self.timeFmt.string(from: window.start))z"
        case let .shiftEnd(_, window):
            "\(Self.timeFmt.string(from: window.end))z"
        }
    }
}
