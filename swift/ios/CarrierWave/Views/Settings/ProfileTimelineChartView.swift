import Charts
import SwiftUI

// MARK: - ProfileTimelineChartView

/// A stacked horizontal timeline chart showing startup profiling events.
///
/// Each bar spans the duration between consecutive milestones, stacked
/// vertically. Color intensity reflects duration (red > 1s, orange > 0.3s).
/// Supports pinch-to-zoom on the time axis and drag-to-pan.
struct ProfileTimelineChartView: View {
    let trace: StartupTrace

    var body: some View {
        let spans = buildSpans(from: trace)
        if spans.isEmpty {
            ContentUnavailableView(
                "Not Enough Data",
                systemImage: "chart.bar.xaxis",
                description: Text("At least two milestones are needed.")
            )
        } else {
            chartContent(spans: spans)
        }
    }
}

// MARK: - Chart Content

private extension ProfileTimelineChartView {
    func chartContent(spans: [ProfileSpan]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            chartHeader
            ZoomableChart(spans: spans, trace: trace)
            legend
        }
        .padding()
        .background(
            Color(.systemGray6),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    var chartHeader: some View {
        HStack {
            Label("Profile Timeline", systemImage: "chart.bar.fill")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(String(format: "%.2f s total", trace.totalSeconds))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontDesign(.monospaced)
        }
    }

    var legend: some View {
        HStack(spacing: 12) {
            legendItem(color: .green, label: "< 0.3s")
            legendItem(color: .orange, label: "0.3–1s")
            legendItem(color: .red, label: "> 1s")
            Spacer()
            Text("Pinch to zoom · drag to pan")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color.opacity(0.8))
                .frame(width: 8, height: 8)
            Text(label)
        }
    }
}

// MARK: - ZoomableChart

/// Inner view holding zoom/pan state for the chart.
private struct ZoomableChart: View {
    // MARK: Internal

    let spans: [ProfileSpan]
    let trace: StartupTrace

    var body: some View {
        let totalRange = trace.totalSeconds
        let visibleRange = totalRange / scale
        let clampedOffset = clampOffset(
            offset: panOffset,
            visibleRange: visibleRange,
            totalRange: totalRange
        )
        let lower = clampedOffset
        let upper = clampedOffset + visibleRange

        chart(lower: lower, upper: upper)
            .frame(height: chartHeight(spanCount: spans.count))
            .contentShape(Rectangle())
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                containerWidth = newWidth
            }
            .gesture(magnifyGesture(totalRange: totalRange))
            .simultaneousGesture(dragGesture(
                visibleRange: visibleRange,
                totalRange: totalRange
            ))
            .onTapGesture(count: 2) {
                withAnimation(.easeOut(duration: 0.3)) {
                    scale = 1.0
                    panOffset = 0
                }
            }
    }

    // MARK: Private

    @State private var scale: CGFloat = 1.0
    @State private var baseScale: CGFloat = 1.0
    @State private var panOffset: TimeInterval = 0
    @State private var basePanOffset: TimeInterval = 0
    @State private var containerWidth: CGFloat = 350

    private func chart(
        lower: TimeInterval,
        upper: TimeInterval
    ) -> some View {
        Chart(spans) { span in
            BarMark(
                xStart: .value("Start", span.startTime),
                xEnd: .value("End", span.endTime),
                y: .value("Phase", span.label)
            )
            .foregroundStyle(spanColor(span.duration))
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .chartXScale(domain: lower ... upper)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(formatAxisLabel(seconds))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(abbreviateLabel(label))
                            .font(.caption2)
                            .lineLimit(1)
                    }
                }
            }
        }
        .chartXAxisLabel(position: .bottom, alignment: .center) {
            Text("Elapsed (seconds)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func magnifyGesture(
        totalRange: TimeInterval
    ) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = max(1.0, min(20.0, baseScale * value.magnification))
                let oldVisible = totalRange / scale
                let newVisible = totalRange / newScale
                // Keep center stable
                let center = panOffset + oldVisible / 2
                scale = newScale
                panOffset = center - newVisible / 2
            }
            .onEnded { _ in
                baseScale = scale
                basePanOffset = panOffset
            }
    }

    private func dragGesture(
        visibleRange: TimeInterval,
        totalRange: TimeInterval
    ) -> some Gesture {
        DragGesture()
            .onChanged { value in
                // Convert pixel drag to time offset
                let pixelsPerSecond = containerWidth / visibleRange
                let timeDelta = -Double(value.translation.width)
                    / pixelsPerSecond
                panOffset = clampOffset(
                    offset: basePanOffset + timeDelta,
                    visibleRange: visibleRange,
                    totalRange: totalRange
                )
            }
            .onEnded { _ in
                basePanOffset = panOffset
            }
    }

    private func clampOffset(
        offset: TimeInterval,
        visibleRange: TimeInterval,
        totalRange: TimeInterval
    ) -> TimeInterval {
        let maxOffset = max(0, totalRange - visibleRange)
        return min(maxOffset, max(0, offset))
    }

    private func chartHeight(spanCount: Int) -> CGFloat {
        let perRow: CGFloat = 28
        let minimum: CGFloat = 120
        return max(minimum, CGFloat(spanCount) * perRow)
    }

    private func spanColor(_ duration: TimeInterval) -> Color {
        if duration > 1.0 {
            return .red
        } else if duration > 0.3 {
            return .orange
        }
        return .green
    }

    private func formatAxisLabel(_ seconds: Double) -> String {
        if seconds < 1.0 {
            return String(format: "%.0f ms", seconds * 1_000)
        }
        return String(format: "%.1f s", seconds)
    }

    private func abbreviateLabel(_ label: String) -> String {
        let maxLength = 24
        guard label.count > maxLength else {
            return label
        }
        return String(label.prefix(maxLength - 1)) + "…"
    }
}

// MARK: - Span Building

private extension ProfileTimelineChartView {
    func buildSpans(from trace: StartupTrace) -> [ProfileSpan] {
        let milestones = trace.milestones
        guard milestones.count >= 2 else {
            return []
        }

        var spans: [ProfileSpan] = []
        spans.reserveCapacity(milestones.count - 1)

        for idx in 0 ..< milestones.count - 1 {
            let current = milestones[idx]
            let next = milestones[idx + 1]
            let duration = next.elapsedSeconds - current.elapsedSeconds
            guard duration > 0.001 else {
                continue
            }

            spans.append(ProfileSpan(
                id: idx,
                label: next.label,
                startTime: current.elapsedSeconds,
                endTime: next.elapsedSeconds,
                duration: duration,
                threadName: next.threadName
            ))
        }
        return spans
    }
}

// MARK: - ProfileSpan

/// A time span between two consecutive startup milestones.
private struct ProfileSpan: Identifiable {
    let id: Int
    let label: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let duration: TimeInterval
    let threadName: String
}
