import Foundation

// MARK: - StartupTrace

/// Codable representation of a single profiled launch.
nonisolated struct StartupTrace: Codable {
    // MARK: Lifecycle

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(Date.self, forKey: .date)
        deviceModel = try container.decode(String.self, forKey: .deviceModel)
        osVersion = try container.decode(String.self, forKey: .osVersion)
        milestones = try container.decode([Milestone].self, forKey: .milestones)
        startupEndIndex = try container.decodeIfPresent(Int.self, forKey: .startupEndIndex)
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
        buildNumber = try container.decodeIfPresent(String.self, forKey: .buildNumber)
        physicalMemoryMB = try container.decodeIfPresent(Int.self, forKey: .physicalMemoryMB)
        availableDiskMB = try container.decodeIfPresent(Int.self, forKey: .availableDiskMB)
        thermalState = try container.decodeIfPresent(String.self, forKey: .thermalState)
        isLowPowerMode = try container.decodeIfPresent(Bool.self, forKey: .isLowPowerMode)
        processorCount = try container.decodeIfPresent(Int.self, forKey: .processorCount)
        qsoCount = try container.decodeIfPresent(Int.self, forKey: .qsoCount)
    }

    init(
        date: Date,
        deviceModel: String,
        osVersion: String,
        milestones: [Milestone],
        startupEndIndex: Int? = nil,
        appVersion: String? = nil,
        buildNumber: String? = nil,
        physicalMemoryMB: Int? = nil,
        availableDiskMB: Int? = nil,
        thermalState: String? = nil,
        isLowPowerMode: Bool? = nil,
        processorCount: Int? = nil,
        qsoCount: Int? = nil
    ) {
        self.date = date
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        self.milestones = milestones
        self.startupEndIndex = startupEndIndex
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.physicalMemoryMB = physicalMemoryMB
        self.availableDiskMB = availableDiskMB
        self.thermalState = thermalState
        self.isLowPowerMode = isLowPowerMode
        self.processorCount = processorCount
        self.qsoCount = qsoCount
    }

    // MARK: Internal

    nonisolated struct Milestone: Codable {
        // MARK: Lifecycle

        init(
            label: String,
            wallTime: Date,
            elapsedSeconds: TimeInterval,
            threadName: String,
            residentMemoryMB: Int?,
            hangStartElapsed: TimeInterval?,
            hangDurationSeconds: TimeInterval?
        ) {
            self.label = label
            self.wallTime = wallTime
            self.elapsedSeconds = elapsedSeconds
            self.threadName = threadName
            self.residentMemoryMB = residentMemoryMB
            self.hangStartElapsed = hangStartElapsed
            self.hangDurationSeconds = hangDurationSeconds
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            label = try container.decode(String.self, forKey: .label)
            wallTime = try container.decode(Date.self, forKey: .wallTime)
            elapsedSeconds = try container.decode(TimeInterval.self, forKey: .elapsedSeconds)
            threadName = try container.decode(String.self, forKey: .threadName)
            residentMemoryMB = try container.decodeIfPresent(Int.self, forKey: .residentMemoryMB)
            hangStartElapsed = try container.decodeIfPresent(TimeInterval.self, forKey: .hangStartElapsed)
            hangDurationSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .hangDurationSeconds)
        }

        // MARK: Internal

        let label: String
        let wallTime: Date
        let elapsedSeconds: TimeInterval
        let threadName: String
        /// Resident memory in MB at the time the milestone was recorded.
        let residentMemoryMB: Int?

        /// For hang milestones: elapsed time when the hang started.
        /// `nil` for regular milestones. Used for milestone correlation.
        let hangStartElapsed: TimeInterval?

        /// For hang milestones: how long the main thread was blocked.
        /// `nil` for regular milestones.
        let hangDurationSeconds: TimeInterval?

        /// Whether this milestone represents a detected main thread hang.
        var isHang: Bool {
            hangStartElapsed != nil
        }
    }

    let date: Date
    let deviceModel: String
    let osVersion: String
    let milestones: [Milestone]
    let appVersion: String?
    let buildNumber: String?
    let physicalMemoryMB: Int?
    let availableDiskMB: Int?
    let thermalState: String?
    let isLowPowerMode: Bool?
    let processorCount: Int?

    /// Total QSO count at the time of profiling — provides dataset size context.
    let qsoCount: Int?

    /// Index where startup milestones end and runtime monitoring begins.
    /// `nil` means all milestones are startup (legacy traces or recording phase).
    var startupEndIndex: Int?

    /// Milestones recorded during the startup phase.
    var startupMilestones: [Milestone] {
        if let endIdx = startupEndIndex {
            return Array(milestones.prefix(endIdx))
        }
        return milestones
    }

    /// Milestones recorded after startup (view appears, tab switches).
    var runtimeMilestones: [Milestone] {
        guard let endIdx = startupEndIndex, endIdx < milestones.count else {
            return []
        }
        return Array(milestones.suffix(from: endIdx))
    }

    /// Total elapsed seconds from first to last milestone.
    var totalSeconds: TimeInterval {
        guard let first = milestones.first,
              let last = milestones.last
        else {
            return 0
        }
        return last.elapsedSeconds - first.elapsedSeconds
    }

    /// Elapsed seconds for the startup phase only.
    var startupSeconds: TimeInterval {
        let startup = startupMilestones
        guard let first = startup.first, let last = startup.last else {
            return totalSeconds
        }
        return last.elapsedSeconds - first.elapsedSeconds
    }

    /// Peak resident memory across all milestones, in MB.
    var peakMemoryMB: Int? {
        milestones.compactMap(\.residentMemoryMB).max()
    }

    /// Memory growth from first to last milestone, in MB.
    var memoryGrowthMB: Int? {
        guard let first = milestones.first?.residentMemoryMB,
              let last = milestones.last?.residentMemoryMB
        else {
            return nil
        }
        return last - first
    }

    // MARK: - Orientation Transitions

    /// All milestones recording an orientation/size class change.
    var orientationMilestones: [Milestone] {
        milestones.filter { $0.label.hasPrefix("orientation.") }
    }

    // MARK: - Hang Detection Stats

    /// All hang milestones (those with `hangStartElapsed` set).
    var hangMilestones: [Milestone] {
        milestones.filter(\.isHang)
    }

    /// Number of main thread hangs detected.
    var hangCount: Int {
        hangMilestones.count
    }

    /// Duration of the longest main thread hang, or nil if none detected.
    var longestHangSeconds: TimeInterval? {
        hangMilestones.compactMap(\.hangDurationSeconds).max()
    }

    /// Total time the main thread was blocked by detected hangs.
    var cumulativeHangSeconds: TimeInterval {
        hangMilestones.compactMap(\.hangDurationSeconds)
            .reduce(into: 0.0) { $0 += $1 }
    }

    /// Plain-text summary of all hangs with environment context and correlated milestones.
    /// Designed for pasting into debugging conversations or issue trackers.
    var hangSummaryText: String {
        var lines: [String] = []
        lines.append("=== Carrier Wave Hang Report ===")
        lines.append("")
        appendEnvironmentLines(to: &lines)
        lines.append("")

        let hangs = hangMilestones
        if hangs.isEmpty {
            lines.append("No hangs detected.")
            return lines.joined(separator: "\n")
        }

        lines.append(String(
            format: "Hangs: %d (%.3f s cumulative)",
            hangCount, cumulativeHangSeconds
        ))
        if let longest = longestHangSeconds {
            lines.append(String(format: "Longest: %.3f s", longest))
        }
        lines.append("")

        for (idx, hang) in hangs.enumerated() {
            appendHangDetail(hang, index: idx + 1, to: &lines)
        }

        appendPhaseDurations(to: &lines)
        appendOrientationEvents(to: &lines)

        lines.append("=== Full Timeline ===")
        appendTimelineLines(to: &lines)

        return lines.joined(separator: "\n")
    }

    /// Find milestones that bracket a hang's time window.
    /// Only main-thread milestones are shown as "during" (causal).
    /// Background milestones that happen to overlap are listed separately
    /// to avoid false-positive hang attribution.
    func correlatedMilestones(for hang: Milestone) -> HangCorrelation {
        guard let hangStart = hang.hangStartElapsed,
              let hangDuration = hang.hangDurationSeconds
        else {
            return HangCorrelation(
                before: nil, after: nil,
                during: [], background: []
            )
        }
        let hangEnd = hangStart + hangDuration

        let nonHangs = milestones.filter { !$0.isHang }
        let overlapping = nonHangs.filter {
            $0.elapsedSeconds > hangStart && $0.elapsedSeconds < hangEnd
        }
        return HangCorrelation(
            before: nonHangs.last { $0.elapsedSeconds <= hangStart },
            after: nonHangs.first { $0.elapsedSeconds >= hangEnd },
            during: overlapping.filter { $0.threadName == "main" },
            background: overlapping.filter { $0.threadName != "main" }
        )
    }
}

// MARK: - HangCorrelation

/// Milestones bracketing a detected main thread hang.
nonisolated struct HangCorrelation {
    /// Last milestone before the hang started.
    let before: StartupTrace.Milestone?
    /// First milestone after the hang ended.
    let after: StartupTrace.Milestone?
    /// Main-thread milestones recorded during the hang (potential causes).
    let during: [StartupTrace.Milestone]
    /// Background milestones that overlapped but did not cause the hang.
    let background: [StartupTrace.Milestone]
}

// MARK: - JSON Coding Helpers

nonisolated extension JSONEncoder {
    static let iso8601: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        nonisolated(unsafe) let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime, .withFractionalSeconds,
        ]
        encoder.dateEncodingStrategy = .custom { date, enc in
            var container = enc.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }()
}

nonisolated extension JSONDecoder {
    static let iso8601: JSONDecoder = {
        let decoder = JSONDecoder()
        nonisolated(unsafe) let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime, .withFractionalSeconds,
        ]
        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let str = try container.decode(String.self)
            guard let date = formatter.date(from: str) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO 8601 date: \(str)"
                )
            }
            return date
        }
        return decoder
    }()
}

/// Thread name for the calling thread (main, or dispatch queue label).
nonisolated func currentThreadName() -> String {
    if Thread.isMainThread {
        return "main"
    }
    if let name = Thread.current.name, !name.isEmpty {
        return name
    }
    let label = String(cString: __dispatch_queue_get_label(nil))
    if !label.isEmpty, label != "com.apple.root.default-qos" {
        return label
    }
    return "background"
}

/// Returns the current process resident memory in MB using Mach task_info.
nonisolated func currentResidentMemoryMB() -> Int? {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
        MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(
            to: integer_t.self, capacity: Int(count)
        ) { ptr in
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), ptr, &count)
        }
    }
    guard result == KERN_SUCCESS else {
        return nil
    }
    return Int(info.resident_size / (1_024 * 1_024))
}
