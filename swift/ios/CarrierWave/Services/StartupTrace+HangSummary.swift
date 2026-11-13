import Foundation

// MARK: - Hang Summary Text Generation

nonisolated extension StartupTrace {
    /// A measured phase with start/end milestones and optional record count.
    struct PhaseDuration {
        let name: String
        let durationSeconds: TimeInterval
        let recordCount: Int?
        let memoryDeltaMB: Int?
    }

    func appendEnvironmentLines(to lines: inout [String]) {
        lines.append("Environment:")
        if let version = appVersion, let build = buildNumber {
            lines.append("  App: \(version) (\(build))")
        } else if let version = appVersion {
            lines.append("  App: \(version)")
        }
        lines.append("  Device: \(deviceModel)")
        lines.append("  OS: \(osVersion)")
        if let cpuCount = processorCount {
            lines.append("  CPUs: \(cpuCount)")
        }
        if let memMB = physicalMemoryMB {
            lines.append("  Physical Memory: \(memMB) MB")
        }
        if let diskMB = availableDiskMB {
            lines.append("  Free Disk: \(diskMB) MB")
        }
        if let thermal = thermalState {
            lines.append("  Thermal: \(thermal)")
        }
        if let lowPower = isLowPowerMode, lowPower {
            lines.append("  Low Power Mode: On")
        }
        if let count = qsoCount {
            lines.append("  QSO Count: \(count)")
        }
        lines.append(String(format: "  Startup Duration: %.3f s", startupSeconds))
        lines.append(String(format: "  Total Duration: %.3f s", totalSeconds))
        if let peakMB = peakMemoryMB {
            lines.append("  Peak Memory: \(peakMB) MB")
        }
        if let growthMB = memoryGrowthMB, growthMB > 0 {
            lines.append("  Memory Growth: +\(growthMB) MB")
        }
    }

    func appendHangDetail(
        _ hang: Milestone,
        index: Int,
        to lines: inout [String]
    ) {
        let hangDuration = hang.hangDurationSeconds ?? 0
        let hangStart = hang.hangStartElapsed ?? hang.elapsedSeconds
        let hangEnd = hangStart + hangDuration
        lines.append(String(
            format: "--- Hang %d: %.3f s (%.3f s – %.3f s elapsed) ---",
            index, hangDuration, hangStart, hangEnd
        ))
        if let memMB = hang.residentMemoryMB {
            lines.append("  Memory at hang: \(memMB) MB")
        }
        let corr = correlatedMilestones(for: hang)
        if let before = corr.before {
            lines.append(String(
                format: "  After: \"%@\" at %.3f s",
                before.label, before.elapsedSeconds
            ))
        }
        for during in corr.during {
            lines.append(String(
                format: "  During: \"%@\" at %.3f s",
                during.label, during.elapsedSeconds
            ))
        }
        for bg in corr.background {
            lines.append(String(
                format: "  Background: \"%@\" at %.3f s",
                bg.label, bg.elapsedSeconds
            ))
        }
        if let after = corr.after {
            lines.append(String(
                format: "  Until: \"%@\" at %.3f s",
                after.label, after.elapsedSeconds
            ))
        }
        lines.append("")
    }

    func appendTimelineLines(to lines: inout [String]) {
        for (idx, ms) in milestones.enumerated() {
            let prefix = ms.isHang ? "HANG " : "     "
            var line = String(
                format: "%@%.3f s  %@",
                prefix, ms.elapsedSeconds, ms.label
            )
            if let memMB = ms.residentMemoryMB {
                line += "  [\(memMB) MB]"
            }
            line += "  (\(ms.threadName))"
            if idx == startupEndIndex {
                line += "  <-- startup end"
            }
            lines.append(line)
        }
    }
}

// MARK: - Orientation Events

nonisolated extension StartupTrace {
    func appendOrientationEvents(to lines: inout [String]) {
        let events = orientationMilestones
        guard !events.isEmpty else {
            return
        }

        lines.append("=== Orientation Transitions (\(events.count)) ===")
        for (idx, event) in events.enumerated() {
            var line = String(
                format: "  %d. %.3f s  %@",
                idx + 1, event.elapsedSeconds, event.label
            )
            if let memMB = event.residentMemoryMB {
                line += "  [\(memMB) MB]"
            }
            // Check if a hang overlaps this transition
            let nearbyHangs = hangMilestones.filter { hang in
                guard let hangStart = hang.hangStartElapsed,
                      let hangDur = hang.hangDurationSeconds
                else {
                    return false
                }
                let hangEnd = hangStart + hangDur
                let window = 0.5 // within 500ms
                return event.elapsedSeconds >= hangStart - window
                    && event.elapsedSeconds <= hangEnd + window
            }
            if !nearbyHangs.isEmpty {
                let hangDurations = nearbyHangs
                    .compactMap(\.hangDurationSeconds)
                let total = hangDurations.reduce(into: 0.0) { $0 += $1 }
                line += String(format: "  ⚠ hang %.3f s", total)
            }
            lines.append(line)
        }
        lines.append("")
    }
}

// MARK: - Phase Duration Analysis

nonisolated extension StartupTrace {
    func computePhaseDurations() -> [PhaseDuration] {
        let nonHangs = milestones.filter { !$0.isHang }
        var phases: [PhaseDuration] = []
        var matched = Set<String>()

        let startSuffixes = [".start", ".query"]
        let endSuffixes = [".done", ".queryDone", ".complete"]

        for ms in nonHangs {
            let base = stripCount(from: ms.label)
            for suffix in startSuffixes where base.hasSuffix(suffix) {
                let prefix = String(base.dropLast(suffix.count))
                guard !matched.contains(prefix) else {
                    continue
                }
                if let phase = matchPhaseEnd(
                    prefix: prefix, startMs: ms,
                    endSuffixes: endSuffixes, in: nonHangs
                ) {
                    phases.append(phase)
                    matched.insert(prefix)
                }
            }
        }

        return phases.sorted { $0.durationSeconds > $1.durationSeconds }
    }

    func appendPhaseDurations(to lines: inout [String]) {
        let phases = computePhaseDurations()
        guard !phases.isEmpty else {
            return
        }

        lines.append("=== Phase Durations (sorted by time) ===")
        for phase in phases {
            var line = String(
                format: "  %-40s %7.3f s",
                (phase.name as NSString).utf8String ?? phase.name,
                phase.durationSeconds
            )
            if let count = phase.recordCount {
                let perRecord = phase.durationSeconds / Double(count) * 1_000
                line += String(
                    format: "  (%d records, %.2f ms/rec)",
                    count, perRecord
                )
            }
            if let memDelta = phase.memoryDeltaMB {
                let sign = memDelta > 0 ? "+" : ""
                line += "  [\(sign)\(memDelta) MB]"
            }
            lines.append(line)
        }

        if let count = qsoCount, count > 0 {
            appendScalingProjection(
                phases: phases, qsoCount: count, to: &lines
            )
        }

        lines.append("")
    }
}

// MARK: - Scaling Projection

nonisolated extension StartupTrace {
    /// Phases known to scale linearly with QSO count.
    private static let linearPhases: Set<String> = [
        "stats.fetch", "stats.sessions", "stats.basicCounts",
        "stats.activations", "stats.streaks", "stats.countMetrics",
        "gridTracker.load", "needs.compute",
        "scp.userCallsigns", "presence",
    ]

    func appendScalingProjection(
        phases: [PhaseDuration],
        qsoCount: Int,
        to lines: inout [String]
    ) {
        let scalable = phases.filter { phase in
            Self.linearPhases.contains { phase.name.hasPrefix($0) }
        }
        guard !scalable.isEmpty else {
            return
        }

        lines.append("")
        lines.append("  Scaling projection (linear extrapolation):")
        let targets = [5_000, 10_000, 25_000]
        for target in targets where target != qsoCount {
            let scale = Double(target) / Double(qsoCount)
            let totalProjected = scalable.reduce(into: 0.0) {
                $0 += $1.durationSeconds * scale
            }
            lines.append(String(
                format: "    %6d QSOs: ~%.1f s cumulative (%.1fx)",
                target, totalProjected, scale
            ))
        }
    }
}

// MARK: - Label Parsing Helpers

nonisolated extension StartupTrace {
    func stripCount(from label: String) -> String {
        guard let parenStart = label.lastIndex(of: "("),
              label.hasSuffix(")")
        else {
            return label
        }
        return String(label[..<parenStart])
    }

    func extractCount(from label: String) -> Int? {
        guard let parenStart = label.lastIndex(of: "("),
              label.hasSuffix(")")
        else {
            return nil
        }
        let numStart = label.index(after: parenStart)
        let numEnd = label.index(before: label.endIndex)
        return Int(label[numStart ..< numEnd])
    }

    private func matchPhaseEnd(
        prefix: String,
        startMs: Milestone,
        endSuffixes: [String],
        in milestones: [Milestone]
    ) -> PhaseDuration? {
        for endSuffix in endSuffixes {
            let endLabel = prefix + endSuffix
            guard let endMs = milestones.first(where: {
                stripCount(from: $0.label) == endLabel
            }) else {
                continue
            }
            let duration = endMs.elapsedSeconds - startMs.elapsedSeconds
            let count = extractCount(from: endMs.label)
            let memDelta: Int? = {
                guard let startMem = startMs.residentMemoryMB,
                      let endMem = endMs.residentMemoryMB
                else {
                    return nil
                }
                let delta = endMem - startMem
                return delta != 0 ? delta : nil
            }()
            return PhaseDuration(
                name: prefix,
                durationSeconds: duration,
                recordCount: count,
                memoryDeltaMB: memDelta
            )
        }
        return nil
    }
}
