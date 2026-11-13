import SwiftUI

// MARK: - Sections

extension StartupProfileView {
    func timelineChartSection(
        _ trace: StartupTrace
    ) -> some View {
        Section {
            DisclosureGroup(isExpanded: $showTimeline) {
                ProfileTimelineChartView(trace: trace)
                    .listRowInsets(EdgeInsets(
                        top: 8, leading: 0, bottom: 8, trailing: 0
                    ))
            } label: {
                Label("Profile Timeline", systemImage: "chart.bar.fill")
            }
        }
    }

    func traceHeader(_ trace: StartupTrace) -> some View {
        Section {
            row("Date", value: dateFormatter.string(from: trace.date))
            if let version = trace.appVersion {
                if let build = trace.buildNumber {
                    row("App", value: "\(version) (\(build))")
                } else {
                    row("App", value: version)
                }
            }
            row("Device", value: trace.deviceModel)
            row("OS", value: trace.osVersion)
            deviceAndMemoryRows(trace)
            timingRows(trace)
        } header: {
            Text("Summary")
        }
    }

    func milestonesSection(
        _ milestones: [StartupTrace.Milestone],
        header: String,
        trace: StartupTrace? = nil
    ) -> some View {
        Section {
            ForEach(
                Array(milestones.enumerated()),
                id: \.offset
            ) { index, milestone in
                let delta = index > 0
                    ? milestone.elapsedSeconds
                    - milestones[index - 1].elapsedSeconds
                    : 0
                if milestone.isHang, let trace {
                    hangMilestoneRow(milestone, delta: delta, trace: trace)
                } else {
                    milestoneRow(milestone, delta: delta, isFirst: index == 0)
                }
            }
        } header: {
            Text(header)
        }
    }

    func runtimeSection(_ trace: StartupTrace) -> some View {
        milestonesSection(
            trace.runtimeMilestones,
            header: "Runtime Events (\(trace.runtimeMilestones.count))",
            trace: trace
        )
    }

    func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .fontDesign(.monospaced)
        }
    }
}

// MARK: - Detail Rows

extension StartupProfileView {
    @ViewBuilder
    func deviceAndMemoryRows(_ trace: StartupTrace) -> some View {
        if let cpuCount = trace.processorCount {
            row("CPUs", value: "\(cpuCount)")
        }
        if let memoryMB = trace.physicalMemoryMB {
            row("Memory", value: formatMB(memoryMB))
        }
        if let diskMB = trace.availableDiskMB {
            row("Free Disk", value: formatMB(diskMB))
        }
        if let thermal = trace.thermalState {
            row("Thermal", value: thermal)
        }
        if let lowPower = trace.isLowPowerMode, lowPower {
            row("Low Power", value: "On")
        }
        if let qsoCount = trace.qsoCount {
            row("QSOs", value: "\(qsoCount)")
        }
        if let peakMB = trace.peakMemoryMB {
            row("Peak Memory", value: formatMB(peakMB))
        }
        if let growthMB = trace.memoryGrowthMB, growthMB > 0 {
            row("Mem Growth", value: "+\(formatMB(growthMB))")
        }
    }

    @ViewBuilder
    func timingRows(_ trace: StartupTrace) -> some View {
        row("Startup", value: String(format: "%.3f s", trace.startupSeconds))
        if !trace.runtimeMilestones.isEmpty {
            row("Total", value: String(format: "%.3f s", trace.totalSeconds))
        }
        row("Milestones", value: "\(trace.milestones.count)")
        hangRows(trace)
        if profiler.isRunning {
            HStack {
                Label("Monitoring", systemImage: "record.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
                Spacer()
                Button("Refresh") { refreshID = UUID() }
                    .font(.caption)
                Button("Stop") { profiler.stop() }
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    func hangRows(_ trace: StartupTrace) -> some View {
        if trace.hangCount > 0 {
            row("Hangs", value: "\(trace.hangCount)")
            if let longest = trace.longestHangSeconds {
                HStack {
                    Text("Longest Hang")
                    Spacer()
                    Text(String(format: "%.3f s", longest))
                        .foregroundStyle(deltaColor(longest))
                        .fontDesign(.monospaced)
                }
            }
            let cumulative = trace.cumulativeHangSeconds
            HStack {
                Text("Blocked Time")
                Spacer()
                Text(String(format: "%.3f s", cumulative))
                    .foregroundStyle(deltaColor(cumulative))
                    .fontDesign(.monospaced)
            }
        } else {
            row("Hangs", value: "None")
        }
    }
}

// MARK: - Hangs List

extension StartupProfileView {
    func hangsListSection(_ trace: StartupTrace) -> some View {
        Section {
            ForEach(
                Array(trace.hangMilestones.enumerated()),
                id: \.offset
            ) { index, hang in
                hangListRow(hang, index: index + 1, trace: trace)
            }
        } header: {
            Text("Detected Hangs (\(trace.hangCount))")
        }
    }

    private func hangListRow(
        _ hang: StartupTrace.Milestone,
        index: Int,
        trace: StartupTrace
    ) -> some View {
        let duration = hang.hangDurationSeconds ?? 0
        let correlation = trace.correlatedMilestones(for: hang)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(
                    "Hang \(index)",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(deltaColor(duration))
                Spacer()
                Text(String(format: "%.3f s", duration))
                    .font(.caption.weight(.medium))
                    .fontDesign(.monospaced)
                    .foregroundStyle(deltaColor(duration))
            }
            hangTimingDetail(hang)
            hangCorrelationView(correlation)
        }
    }

    private func hangTimingDetail(
        _ hang: StartupTrace.Milestone
    ) -> some View {
        let hangStart = hang.hangStartElapsed ?? hang.elapsedSeconds
        let duration = hang.hangDurationSeconds ?? 0
        let hangEnd = hangStart + duration
        return HStack(spacing: 4) {
            Text(String(format: "%.3f s", hangStart))
            Text("–")
            Text(String(format: "%.3f s elapsed", hangEnd))
            if let memMB = hang.residentMemoryMB {
                Text("·")
                Text(formatMB(memMB))
            }
        }
        .font(.caption2)
        .fontDesign(.monospaced)
        .foregroundStyle(.secondary)
    }
}
