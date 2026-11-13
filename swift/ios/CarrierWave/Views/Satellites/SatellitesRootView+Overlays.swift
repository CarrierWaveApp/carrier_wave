import CarrierWaveData
import SwiftUI

// MARK: - Bottom overlays

/// The root's bottom-overlay chrome (time scrubber + status capsule) and
/// the list → pointing handoff, split out of the main root-view file.
extension SatellitesRootView {
    var timeOffsetLabel: String {
        let offset = model.timeOffset
        if offset == 0 {
            return "Now"
        }
        let totalMinutes = Int((abs(offset) / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let sign = offset < 0 ? "−" : "+"
        if hours > 0 {
            return "\(sign)\(hours)h \(String(format: "%02d", minutes))m"
        }
        return "\(sign)\(minutes)m"
    }

    /// Scrub simulated time ±12 h to preview where satellites will be;
    /// snaps back to live when released near "now".
    var timeScrubber: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { model.timeOffset },
                    set: { model.setTimeOffset($0) }
                ),
                in: -Self.scrubRange ... Self.scrubRange
            ) { editing in
                if !editing, abs(model.timeOffset) < Self.scrubSnapWindow {
                    model.setTimeOffset(0)
                }
            }
            Text(timeOffsetLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(model.timeOffset == 0 ? .secondary : .primary)
                .frame(minWidth: 56, alignment: .trailing)
            if model.timeOffset != 0 {
                Button("Now") {
                    model.setTimeOffset(0)
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
    }

    var statusBar: some View {
        HStack(spacing: 6) {
            ExperimentalBadge(feature: .satellites)
            Text("\(model.positions.count) ham satellites")
            Text("·")
            if let observer = model.observerCoordinate {
                Text("QTH \(MaidenheadConverter.grid(from: observer, precision: .six))")
                    .monospaced()
            } else {
                Text("QTH not set")
                    .foregroundStyle(.orange)
            }
            if let fetched = model.tlesFetchedAt {
                Text("·")
                Text("TLEs \(fetched, format: .relative(presentation: .named))")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
    }

    /// The satellite list asked to point at a bird: open the pointing
    /// cover now that the sheet is gone.
    func openPointingIfPending() {
        if pointAfterList {
            pointAfterList = false
            showPointing = true
        }
    }
}
