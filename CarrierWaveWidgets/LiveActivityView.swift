import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - LoggingSessionLiveActivity

struct LoggingSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LoggingSessionAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color(.systemBackground))
                .widgetURL(URL(string: WidgetShared.DeepLink.logger))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    expandedLeading(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    expandedTrailing(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    expandedBottom(context: context)
                }
                DynamicIslandExpandedRegion(.center) {
                    expandedCenter(context: context)
                }
            } compactLeading: {
                compactLeadingContent(context: context)
            } compactTrailing: {
                compactTrailingContent(context: context)
            } minimal: {
                Text("\(context.state.qsoCount)")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.green)
            }
            .widgetURL(URL(string: WidgetShared.DeepLink.logger))
        }
    }
}

// MARK: - ActivationGoal

private enum ActivationGoal {
    static func goal(for activationType: String) -> Int? {
        switch activationType {
        case "POTA": 10
        case "SOTA": 4
        default: nil
        }
    }
}

// MARK: - UTCFormat

private enum UTCFormat {
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date) + "z"
    }
}

// MARK: - LockScreenView

private struct LockScreenView: View {
    // MARK: Internal

    let context: ActivityViewContext<LoggingSessionAttributes>

    var body: some View {
        VStack(spacing: 8) {
            // Top row: status + UTC time
            HStack {
                statusIndicator
                Spacer()
                Text(UTCFormat.string(from: context.state.updatedAt))
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
            }

            // Middle row: frequency/mode + park/rove info
            HStack {
                if let freq = context.state.frequency {
                    Text("\(freq) MHz")
                        .font(.subheadline.weight(.medium).monospaced())
                }
                Text(context.state.mode)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .clipShape(Capsule())
                Spacer()
                parkLabel
            }

            // Bottom row: QSO progress + last callsign
            HStack {
                qsoProgress
                Spacer()
                if let callsign = context.state.lastCallsign {
                    HStack(spacing: 4) {
                        Text("Last:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(callsign)
                            .font(.subheadline.weight(.medium).monospaced())
                    }
                }
            }
        }
        .padding()
    }

    // MARK: Private

    private var isRove: Bool {
        context.state.stopNumber != nil
    }

    private var activationGoal: Int? {
        ActivationGoal.goal(for: context.attributes.activationType)
    }

    private var statusIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.caption2)
            if context.state.isPaused {
                Text("Paused")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            } else {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("On Air")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private var parkLabel: some View {
        if isRove, let stop = context.state.stopNumber,
           let total = context.state.totalStops,
           let park = context.state.currentStopPark
        {
            // Rove: show current stop park + stop indicator
            VStack(alignment: .trailing, spacing: 1) {
                Text(park)
                    .font(.subheadline.weight(.semibold).monospaced())
                    .lineLimit(1)
                Text("Stop \(stop)/\(total)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        } else if let park = context.state.parkReference {
            Text(park)
                .font(.subheadline.weight(.semibold).monospaced())
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var qsoProgress: some View {
        if isRove, let goal = activationGoal,
           let stopQSOs = context.state.currentStopQSOs
        {
            // Rove: show per-stop progress + total
            roveProgress(stopQSOs: stopQSOs, goal: goal)
        } else if let goal = activationGoal {
            let count = context.state.qsoCount
            let met = count >= goal
            HStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(count)")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(met ? .green : .primary)
                    Text("/\(goal)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                progressBar(count: count, goal: goal, met: met)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(context.state.qsoCount)")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text("QSOs")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func roveProgress(stopQSOs: Int, goal: Int) -> some View {
        let met = stopQSOs >= goal
        return HStack(spacing: 8) {
            // Per-stop progress
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(stopQSOs)")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(met ? .green : .primary)
                Text("/\(goal)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            progressBar(count: stopQSOs, goal: goal, met: met)
            // Total session QSOs
            Text("\(context.state.qsoCount) total")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func progressBar(count: Int, goal: Int, met: Bool) -> some View {
        let progress = min(Double(count) / Double(goal), 1.0)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(.systemGray4))
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 3)
                    .fill(met ? Color.green : Color.blue)
                    .frame(width: geo.size.width * progress, height: 6)
            }
        }
        .frame(width: 50, height: 6)
    }
}

// MARK: - Dynamic Island Expanded

private extension LoggingSessionLiveActivity {
    func expandedLeading(
        context: ActivityViewContext<LoggingSessionAttributes>
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if context.state.isPaused {
                Text("Paused")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            } else {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text("On Air")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
            Text(context.attributes.myCallsign)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    func expandedTrailing(
        context: ActivityViewContext<LoggingSessionAttributes>
    ) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(UTCFormat.string(from: context.state.updatedAt))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Text(context.attributes.startedAt, style: .timer)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.trailing)
        }
    }

    func expandedCenter(
        context: ActivityViewContext<LoggingSessionAttributes>
    ) -> some View {
        HStack {
            if let freq = context.state.frequency {
                Text("\(freq) MHz")
                    .font(.caption.weight(.medium).monospaced())
            }
            Text(context.state.mode)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            expandedParkLabel(context: context)
        }
    }

    @ViewBuilder
    func expandedParkLabel(
        context: ActivityViewContext<LoggingSessionAttributes>
    ) -> some View {
        if let stop = context.state.stopNumber,
           let total = context.state.totalStops,
           let park = context.state.currentStopPark
        {
            HStack(spacing: 4) {
                Text(park)
                    .font(.caption.weight(.semibold).monospaced())
                Text("\(stop)/\(total)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if let park = context.state.parkReference {
            Text(park)
                .font(.caption.weight(.semibold).monospaced())
        }
    }

    func expandedBottom(
        context: ActivityViewContext<LoggingSessionAttributes>
    ) -> some View {
        HStack {
            expandedQSOProgress(context: context)
            Spacer()
            if let callsign = context.state.lastCallsign {
                HStack(spacing: 4) {
                    Text("Last:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(callsign)
                        .font(.caption.weight(.medium).monospaced())
                }
            }
        }
    }

    @ViewBuilder
    func expandedQSOProgress(
        context: ActivityViewContext<LoggingSessionAttributes>
    ) -> some View {
        let goal = ActivationGoal.goal(for: context.attributes.activationType)
        let count = context.state.qsoCount
        let isRove = context.state.stopNumber != nil

        if isRove, let goal, let stopQSOs = context.state.currentStopQSOs {
            let met = stopQSOs >= goal
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(stopQSOs)")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(met ? .green : .primary)
                Text("/\(goal)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("(\(count) total)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } else if let goal {
            let met = count >= goal
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(count)")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(met ? .green : .primary)
                Text("/\(goal)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(count)")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Text("QSOs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Dynamic Island Compact

private extension LoggingSessionLiveActivity {
    func compactLeadingContent(
        context: ActivityViewContext<LoggingSessionAttributes>
    ) -> some View {
        let goal = ActivationGoal.goal(for: context.attributes.activationType)
        let isRove = context.state.stopNumber != nil
        // For roves, show per-stop count; otherwise session count
        let count = isRove
            ? (context.state.currentStopQSOs ?? context.state.qsoCount)
            : context.state.qsoCount

        return Group {
            if let goal {
                let met = count >= goal
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(count)")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(met ? .green : .primary)
                    Text("/\(goal)")
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("\(count)")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.green)
            }
        }
    }

    func compactTrailingContent(
        context: ActivityViewContext<LoggingSessionAttributes>
    ) -> some View {
        HStack(spacing: 2) {
            if let band = context.state.band {
                Text(band)
                    .font(.caption2)
            }
            Text(context.state.mode)
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
    }
}
