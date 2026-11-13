import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - CallsignQSORow

/// Compact row displaying a single QSO in the callsign history timeline.
struct CallsignQSORow: View {
    // MARK: Internal

    let qso: QSO
    var clip: QSORecordingClip?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            dateRow
            detailRow
            parkRow
            clipRow
        }
        .padding(.vertical, 8)
    }

    // MARK: Private

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        return fmt
    }()

    private static let timeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    private var dateRow: some View {
        HStack(spacing: 4) {
            Text(Self.dateFormatter.string(from: qso.timestamp))
                .font(.subheadline.weight(.medium))
            Text("·")
                .foregroundStyle(.secondary)
            Text("\(Self.timeFormatter.string(from: qso.timestamp)) UTC")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private var detailRow: some View {
        HStack(spacing: 6) {
            bandModeBadge(qso.band)
            bandModeBadge(qso.mode)

            if let freq = qso.frequency {
                Text(FrequencyFormatter.formatWithUnit(freq))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let sent = qso.rstSent, let rcvd = qso.rstReceived {
                Text("\(sent)/\(rcvd)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var parkRow: some View {
        if let park = qso.theirParkReference, !park.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "leaf")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text(park)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private var clipRow: some View {
        if let clip {
            QSORecordingClipView(clip: clip)
        }
    }

    private func bandModeBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue.opacity(0.2))
            .clipShape(Capsule())
    }
}
