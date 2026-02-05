// swiftlint:disable function_body_length identifier_name
// Band Plan Service
//
// Validates frequency and mode combinations against license class privileges.

import CarrierWaveCore
import Foundation

// MARK: - FrequencyWarning

/// Unified warning for frequency/mode issues (replaces BandPlanViolation)
struct FrequencyWarning: Sendable, Equatable {
    // MARK: Lifecycle

    init(
        type: WarningType,
        message: String,
        suggestion: String? = nil,
        activity: FrequencyActivity.ActivityType? = nil
    ) {
        self.type = type
        self.message = message
        self.suggestion = suggestion
        self.activity = activity
    }

    // MARK: Internal

    enum WarningType: Sendable, Equatable {
        // License violations (high priority)
        case noPrivileges
        case wrongMode
        case outOfBand

        // Activity warnings (medium priority)
        case activityConflict // Mode mismatch with expected activity
        case activityCrowded // Time-based event active (CWT, etc.)
        case spotNearby // Other operator spotted near this frequency

        // Informational (low priority)
        case unusualFrequency // CW in phone segment, etc.
        case activityInfo // Matching activity - "You're on QRP freq!"
    }

    let type: WarningType
    let message: String
    let suggestion: String?
    let activity: FrequencyActivity.ActivityType?

    /// Priority for sorting (lower = higher priority, shown first)
    var priority: Int {
        switch type {
        case .noPrivileges,
             .outOfBand:
            0
        case .wrongMode: 1
        case .activityConflict,
             .activityCrowded,
             .spotNearby:
            2
        case .unusualFrequency: 3
        case .activityInfo: 4
        }
    }

    /// Whether this warning blocks operation (vs informational)
    var isBlocking: Bool {
        switch type {
        case .noPrivileges,
             .wrongMode,
             .outOfBand:
            true
        default: false
        }
    }
}

// MARK: - BandPlanViolation

/// Describes a band plan violation
/// - Note: Deprecated. Use `FrequencyWarning` instead.
struct BandPlanViolation: Sendable {
    enum ViolationType: Sendable {
        case noPrivileges
        case wrongMode
        case outOfBand
        case unusualFrequency // Soft warning - not prohibited, just unusual
    }

    let type: ViolationType
    let message: String
    let suggestion: String?

    /// Convert to FrequencyWarning
    var asFrequencyWarning: FrequencyWarning {
        let warningType: FrequencyWarning.WarningType =
            switch type {
            case .noPrivileges: .noPrivileges
            case .wrongMode: .wrongMode
            case .outOfBand: .outOfBand
            case .unusualFrequency: .unusualFrequency
            }
        return FrequencyWarning(type: warningType, message: message, suggestion: suggestion)
    }
}

// MARK: - BandPlanService

/// Service for validating frequency/mode against license class
enum BandPlanService {
    // MARK: Internal

    /// Check if a frequency/mode combination is valid for a license class
    /// - Parameters:
    ///   - frequencyMHz: Operating frequency in MHz
    ///   - mode: Operating mode (CW, SSB, etc.)
    ///   - license: User's license class
    /// - Returns: A violation if the operation is not allowed, nil if allowed
    static func validate(
        frequencyMHz: Double,
        mode: String,
        license: LicenseClass
    ) -> BandPlanViolation? {
        let normalizedMode = normalizeMode(mode)

        // Find all segments that contain this frequency
        let matchingSegments = BandPlan.segments.filter { $0.contains(frequencyMHz: frequencyMHz) }

        // If no segments match, frequency is out of band
        guard !matchingSegments.isEmpty else {
            return BandPlanViolation(
                type: .outOfBand,
                message:
                "Frequency \(FrequencyFormatter.formatWithUnit(frequencyMHz)) is outside amateur bands",
                suggestion: suggestNearestBand(frequencyMHz: frequencyMHz)
            )
        }

        // Check for segments that allow this mode
        let modeSegments = matchingSegments.filter { $0.allowsMode(normalizedMode) }

        if modeSegments.isEmpty {
            // CW is allowed anywhere in amateur bands, but warn if unusual
            if normalizedMode == "CW" {
                let typicalModes = Set(matchingSegments.flatMap(\.modes))
                let typicalModesStr = typicalModes.sorted().joined(separator: ", ")
                return BandPlanViolation(
                    type: .unusualFrequency,
                    message:
                    "\(FrequencyFormatter.formatWithUnit(frequencyMHz)) is not a typical CW frequency",
                    suggestion: "Usually \(typicalModesStr) here"
                )
            }

            // Mode not allowed at this frequency
            let allowedModes = Set(matchingSegments.flatMap(\.modes))
            return BandPlanViolation(
                type: .wrongMode,
                message:
                "\(mode) is not allowed at \(FrequencyFormatter.formatWithUnit(frequencyMHz))",
                suggestion: "Try: \(allowedModes.joined(separator: ", "))"
            )
        }

        // Check license class privileges
        let privilegeOrder: [LicenseClass] = [.technician, .general, .extra]
        let userPrivilegeIndex = privilegeOrder.firstIndex(of: license) ?? 0

        // Find segments where user has privileges
        let allowedSegments = modeSegments.filter { segment in
            let requiredIndex = privilegeOrder.firstIndex(of: segment.minimumLicense) ?? 0
            return userPrivilegeIndex >= requiredIndex
        }

        if allowedSegments.isEmpty {
            // User doesn't have privileges
            let requiredLicense =
                modeSegments
                    .map(\.minimumLicense)
                    .min { a, b in
                        (privilegeOrder.firstIndex(of: a) ?? 0)
                            < (privilegeOrder.firstIndex(of: b) ?? 0)
                    } ?? .extra

            // For Technicians, check if they have ANY privileges on this band
            // If not, show a clearer message that the entire band is off-limits
            if license == .technician, let band = matchingSegments.first?.band {
                let techPrivilegesOnBand = BandPlan.segments.filter { segment in
                    segment.band == band && segment.minimumLicense == .technician
                }

                if techPrivilegesOnBand.isEmpty {
                    return BandPlanViolation(
                        type: .noPrivileges,
                        message: "Technicians cannot operate in any mode within the \(band) band",
                        suggestion: "Requires General or higher"
                    )
                }
            }

            let freqStr = FrequencyFormatter.formatWithUnit(frequencyMHz)
            return BandPlanViolation(
                type: .noPrivileges,
                message: "\(license.displayName) license cannot operate \(mode) at \(freqStr)",
                suggestion: "Requires \(requiredLicense.displayName) or higher"
            )
        }

        return nil
    }

    /// Get the band name for a frequency
    static func bandFor(frequencyMHz: Double) -> String? {
        BandPlan.segments.first { $0.contains(frequencyMHz: frequencyMHz) }?.band
    }

    /// Get suggested frequencies for a mode and license
    static func suggestedFrequencies(
        mode: String,
        license: LicenseClass
    ) -> [(band: String, frequencyMHz: Double)] {
        let normalizedMode = normalizeMode(mode)

        if normalizedMode == "CW" {
            return BandPlan.cwCallingFrequencies
                .filter { validate(frequencyMHz: $0.value, mode: mode, license: license) == nil }
                .sorted { $0.value < $1.value }
                .map { ($0.key, $0.value) }
        } else if normalizedMode == "SSB" || normalizedMode == "PHONE" {
            return BandPlan.ssbCallingFrequencies
                .filter { validate(frequencyMHz: $0.value, mode: mode, license: license) == nil }
                .sorted { $0.value < $1.value }
                .map { ($0.key, $0.value) }
        }

        return []
    }

    /// Get all segments where a license class has privileges
    static func privilegedSegments(for license: LicenseClass) -> [BandSegment] {
        let privilegeOrder: [LicenseClass] = [.technician, .general, .extra]
        let userPrivilegeIndex = privilegeOrder.firstIndex(of: license) ?? 0

        return BandPlan.segments.filter { segment in
            let requiredIndex = privilegeOrder.firstIndex(of: segment.minimumLicense) ?? 0
            return userPrivilegeIndex >= requiredIndex
        }
    }

    /// Suggest the typical operating mode for a frequency
    /// Returns CW for CW/DATA segments, SSB for phone segments, nil if ambiguous or out of band
    static func suggestedMode(for frequencyMHz: Double) -> String? {
        let matchingSegments = BandPlan.segments.filter { $0.contains(frequencyMHz: frequencyMHz) }

        guard !matchingSegments.isEmpty else {
            return nil
        }

        // Check what modes are allowed
        let allModes = Set(matchingSegments.flatMap(\.modes))

        // If only CW/DATA modes, suggest CW
        if allModes.isSubset(of: ["CW", "DATA"]) {
            return "CW"
        }

        // If only phone modes, suggest SSB
        if allModes.isSubset(of: ["SSB", "PHONE", "USB", "LSB", "AM", "FM"]) {
            return "SSB"
        }

        // If ALL modes allowed (VHF/UHF), don't auto-switch
        if allModes.contains("ALL") {
            return nil
        }

        // Mixed segment - don't auto-switch
        return nil
    }

    // MARK: - Unified Frequency Validation

    /// Full frequency validation - returns all applicable warnings sorted by priority
    /// - Parameters:
    ///   - frequencyMHz: Operating frequency in MHz
    ///   - mode: Operating mode (CW, SSB, etc.)
    ///   - license: User's license class
    /// - Returns: All warnings sorted by priority (highest priority first)
    static func validateFrequency(
        frequencyMHz: Double,
        mode: String,
        license: LicenseClass
    ) -> [FrequencyWarning] {
        var warnings: [FrequencyWarning] = []

        // 1. Check license privileges (existing logic)
        if let licenseViolation = validate(
            frequencyMHz: frequencyMHz,
            mode: mode,
            license: license
        ) {
            warnings.append(licenseViolation.asFrequencyWarning)
        }

        // 2. Check activity frequencies
        warnings.append(
            contentsOf: checkActivityWarnings(
                frequencyMHz: frequencyMHz,
                mode: mode
            )
        )

        // Return sorted by priority (highest priority first)
        return warnings.sorted { $0.priority < $1.priority }
    }

    /// Check for activity-related warnings
    /// - Parameters:
    ///   - frequencyMHz: Operating frequency in MHz
    ///   - mode: Operating mode
    /// - Returns: Activity warnings (conflicts or informational)
    static func checkActivityWarnings(
        frequencyMHz: Double,
        mode: String
    ) -> [FrequencyWarning] {
        var warnings: [FrequencyWarning] = []

        // Check CWT first (time-based, takes priority)
        if let cwtRange = BandPlan.isInCWTRange(frequencyMHz: frequencyMHz) {
            let freqStr = FrequencyFormatter.formatWithUnit(frequencyMHz)
            let rangeStr =
                "\(FrequencyFormatter.format(cwtRange.startMHz))-\(FrequencyFormatter.formatWithUnit(cwtRange.endMHz))"

            // CWT is CW only - warn if not in CW mode
            let normalizedMode = mode.uppercased()
            if normalizedMode != "CW" {
                warnings.append(
                    FrequencyWarning(
                        type: .activityConflict,
                        message: "\(freqStr) is in the CWOps CWT range",
                        suggestion: "CWT uses CW mode only (\(rangeStr))",
                        activity: .cwtContest
                    )
                )
            } else {
                warnings.append(
                    FrequencyWarning(
                        type: .activityCrowded,
                        message: "CWOps CWT is active",
                        suggestion: "Expect heavy CW traffic \(rangeStr)",
                        activity: .cwtContest
                    )
                )
            }
        }

        // Check other activities
        let matchingActivities = BandPlan.activitiesMatching(frequencyMHz: frequencyMHz)

        for activity in matchingActivities {
            // Skip time-based activities that aren't active
            guard activity.isActive() else {
                continue
            }

            let freqStr = FrequencyFormatter.formatWithUnit(activity.centerMHz)

            if activity.matchesMode(mode) {
                // Mode matches - informational notice
                warnings.append(
                    FrequencyWarning(
                        type: .activityInfo,
                        message: "\(freqStr) is the \(activity.description)",
                        suggestion: nil,
                        activity: activity.type
                    )
                )
            } else {
                // Mode mismatch - warning
                let expectedModes = activity.modes.sorted().joined(separator: "/")
                warnings.append(
                    FrequencyWarning(
                        type: .activityConflict,
                        message: "\(freqStr) is the \(activity.description)",
                        suggestion: "Expected mode: \(expectedModes), you're in \(mode)",
                        activity: activity.type
                    )
                )
            }
        }

        return warnings
    }

    /// Check if currently within a CWT time window (with buffer)
    static func isWithinCWTWindow(at date: Date = Date()) -> Bool {
        BandPlan.cwtTimeWindows.contains { $0.contains(date: date) }
    }

    /// Find all activities near a frequency
    static func activitiesNear(frequencyMHz: Double) -> [FrequencyActivity] {
        BandPlan.activitiesMatching(frequencyMHz: frequencyMHz)
    }

    // MARK: Private

    private static func normalizeMode(_ mode: String) -> String {
        let upper = mode.uppercased()

        // Map common mode variants
        switch upper {
        case "LSB",
             "USB",
             "AM",
             "FM":
            return "PHONE"
        case "RTTY",
             "PSK",
             "FT8",
             "FT4",
             "JS8",
             "WSPR",
             "JT65",
             "JT9":
            return "DATA"
        default: return upper
        }
    }

    private static func suggestNearestBand(frequencyMHz: Double) -> String? {
        // Find the nearest band edge
        var nearestBand: String?
        var nearestDistance = Double.infinity

        for segment in BandPlan.segments {
            let distanceToStart = abs(frequencyMHz - segment.startMHz)
            let distanceToEnd = abs(frequencyMHz - segment.endMHz)
            let minDistance = min(distanceToStart, distanceToEnd)

            if minDistance < nearestDistance {
                nearestDistance = minDistance
                nearestBand = segment.band
            }
        }

        if let band = nearestBand, nearestDistance < 1.0 {
            return "Nearest band: \(band)"
        }

        return nil
    }
}
