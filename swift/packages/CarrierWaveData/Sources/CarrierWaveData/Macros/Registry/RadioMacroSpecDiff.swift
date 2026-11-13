import Foundation

// MARK: - RadioMacroSpecDiff

/// Field-level diff between two `RadioMacroSpec` values. Used by the
/// Updates tab review sheet to render a human-readable changelog before
/// the user accepts an update.
public enum RadioMacroSpecDiff {
    // MARK: Public

    public struct Change: Sendable, Equatable, Identifiable {
        // MARK: Lifecycle

        public init(field: String, before: String?, after: String?) {
            self.field = field
            self.before = before
            self.after = after
        }

        // MARK: Public

        public let field: String
        public let before: String?
        public let after: String?

        public var id: String {
            field
        }
    }

    /// Returns one `Change` per differing field. Capabilities expand into
    /// per-flag rows so the user can see exactly what new permissions an
    /// update wants. Steps roll into added/removed/changed buckets.
    public static func diff(local: RadioMacroSpec, remote: RadioMacroSpec) -> [Change] {
        var changes: [Change] = []
        if local.name != remote.name {
            changes.append(.init(field: "Name", before: local.name, after: remote.name))
        }
        if local.description != remote.description {
            changes.append(
                .init(field: "Description", before: local.description, after: remote.description)
            )
        }
        if (local.tags ?? []) != (remote.tags ?? []) {
            changes.append(.init(
                field: "Tags",
                before: (local.tags ?? []).joined(separator: ", "),
                after: (remote.tags ?? []).joined(separator: ", ")
            ))
        }
        if let appliesTo = appliesToChange(local: local, remote: remote) {
            changes.append(appliesTo)
        }
        changes.append(contentsOf: capabilityChanges(local: local.capabilities, remote: remote.capabilities))
        changes.append(contentsOf: stepChanges(local: local.steps, remote: remote.steps))
        return changes
    }

    // MARK: Private

    private static func appliesToChange(local: RadioMacroSpec, remote: RadioMacroSpec) -> Change? {
        let localList = (local.appliesTo ?? []).map(\.rawValue)
        let remoteList = (remote.appliesTo ?? []).map(\.rawValue)
        guard localList != remoteList else {
            return nil
        }
        return .init(
            field: "Applies To",
            before: localList.joined(separator: ", "),
            after: remoteList.joined(separator: ", ")
        )
    }

    private static func capabilityChanges(
        local: RadioMacroCapabilities,
        remote: RadioMacroCapabilities
    ) -> [Change] {
        var changes: [Change] = []
        func diff(_ field: String, _ lhs: Bool, _ rhs: Bool) {
            if lhs != rhs {
                changes.append(.init(field: "Capability: \(field)", before: yesNo(lhs), after: yesNo(rhs)))
            }
        }
        diff("Transmits", local.transmits, remote.transmits)
        diff("Changes frequency", local.changesFrequency, remote.changesFrequency)
        diff("Changes mode", local.changesMode, remote.changesMode)
        diff("Changes power", local.changesPower, remote.changesPower)
        diff("Uses raw bytes", local.usesRawBytes, remote.usesRawBytes)
        let localRegions = (local.regions ?? []).sorted()
        let remoteRegions = (remote.regions ?? []).sorted()
        if localRegions != remoteRegions {
            changes.append(.init(
                field: "Regions",
                before: localRegions.joined(separator: ", "),
                after: remoteRegions.joined(separator: ", ")
            ))
        }
        return changes
    }

    private static func stepChanges(
        local: [RadioMacroStep],
        remote: [RadioMacroStep]
    ) -> [Change] {
        guard local != remote else {
            return []
        }
        var changes: [Change] = []
        let oldCount = local.count
        let newCount = remote.count
        if oldCount != newCount {
            changes.append(.init(
                field: "Step count",
                before: String(oldCount),
                after: String(newCount)
            ))
        }
        let shared = min(oldCount, newCount)
        for index in 0 ..< shared where local[index] != remote[index] {
            changes.append(.init(
                field: "Step \(index + 1)",
                before: summary(local[index]),
                after: summary(remote[index])
            ))
        }
        for index in shared ..< newCount {
            changes.append(.init(
                field: "Step \(index + 1) (added)",
                before: nil,
                after: summary(remote[index])
            ))
        }
        for index in shared ..< oldCount {
            changes.append(.init(
                field: "Step \(index + 1) (removed)",
                before: summary(local[index]),
                after: nil
            ))
        }
        return changes
    }

    private static func summary(_ step: RadioMacroStep) -> String {
        if let detail = step.summaryDetailForDiff {
            "\(step.summaryTitleForDiff): \(detail)"
        } else {
            step.summaryTitleForDiff
        }
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }
}

// MARK: - Step summary helpers

extension RadioMacroStep {
    /// Diff-only summary title. Mirrors the title used by `MacroStepSummaryRow`
    /// but lives in CarrierWaveData so the diff utility can be exercised
    /// without pulling in the iOS view target.
    var summaryTitleForDiff: String {
        switch self {
        case .delay: "Wait"
        case .setFrequency: "Set Frequency"
        case .setMode: "Set Mode"
        case .setPowerWatts: "Set Power"
        case .setPTT: "Press PTT"
        case .sendCW: "Send CW"
        case .vendorCommand: "Vendor Command"
        case .rawBytes: "Raw Bytes"
        case .readField: "Read Field"
        case .waitUntil: "Wait Until"
        case .assert: "Assert"
        }
    }

    var summaryDetailForDiff: String? {
        switch self {
        case let .delay(durationMs):
            "\(durationMs) ms"
        case let .setFrequency(hz):
            String(format: "%.6f MHz", Double(hz) / 1_000_000)
        case let .setMode(mode):
            mode
        case let .setPowerWatts(watts):
            "\(watts) W"
        case let .setPTT(on):
            on ? "ON" : "OFF"
        case let .sendCW(text):
            "\"\(text)\""
        case let .vendorCommand(commandId, args):
            if let args, !args.isEmpty {
                "\(commandId)(\(RadioMacroStep.formatVendorArgs(args)))"
            } else {
                commandId
            }
        case let .rawBytes(protocolName, bytes):
            "\(protocolName): \(bytes)"
        case let .readField(field, into):
            "\(field) → ctx.\(into)"
        case let .waitUntil(expr, timeoutMs):
            "\(expr) (≤ \(timeoutMs) ms)"
        case let .assert(expr, message):
            "\(expr) — \"\(message)\""
        }
    }
}
