// Timeline Slider View
//
// Custom slider with QSO and RBN spot tick marks for the session replay timeline.
// Blue ticks represent QSOs (taller), green ticks represent RBN spots (shorter).

import SwiftUI

// MARK: - TimelineSliderView

/// A custom slider showing event tick marks along a time range.
struct TimelineSliderView: View {
    // MARK: Internal

    @Binding var currentTime: TimeInterval

    let duration: TimeInterval
    let events: [TimelineMapEvent]
    let startDate: Date

    var body: some View {
        VStack(spacing: 6) {
            timeLabels
            sliderWithTicks
        }
        .padding(.horizontal, 16)
    }

    // MARK: Private

    private var timeLabels: some View {
        HStack {
            Text(formatElapsed(currentTime))
                .monospacedDigit()
            Spacer()
            Text("-\(formatElapsed(max(0, duration - currentTime)))")
                .monospacedDigit()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var sliderWithTicks: some View {
        ZStack(alignment: .leading) {
            tickMarksOverlay
                .allowsHitTesting(false)
            Slider(value: $currentTime, in: 0 ... max(duration, 1))
                .tint(.accentColor)
        }
    }

    private var tickMarksOverlay: some View {
        GeometryReader { geometry in
            let trackWidth = geometry.size.width
            ForEach(events) { event in
                let offset = event.timestamp.timeIntervalSince(startDate)
                let fraction = duration > 0 ? offset / duration : 0
                let xPos = fraction * trackWidth
                let isQSO = event.kind == .qso
                tickMark(isQSO: isQSO, xPos: xPos, height: geometry.size.height)
            }
        }
        .frame(height: 28)
    }

    private func tickMark(
        isQSO: Bool, xPos: Double, height: Double
    ) -> some View {
        let tickHeight: Double = isQSO ? 14 : 8
        let color: Color = isQSO ? .blue : .green
        return Rectangle()
            .fill(color.opacity(0.7))
            .frame(width: 2, height: tickHeight)
            .position(x: xPos, y: height / 2)
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(max(0, seconds))
        let hrs = totalSeconds / 3_600
        let mins = (totalSeconds % 3_600) / 60
        let secs = totalSeconds % 60
        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }
}
