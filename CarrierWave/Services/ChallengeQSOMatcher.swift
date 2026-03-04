import CarrierWaveData
import Foundation

/// Helper for matching QSOs against challenge criteria
enum ChallengeQSOMatcher {
    // MARK: Internal

    // MARK: - Criteria Matching

    static func qsoMatchesCriteria(_ qso: QSO, criteria: QualificationCriteria?) -> Bool {
        guard let criteria else {
            return true
        }

        // Check bands
        if let bands = criteria.bands, !bands.isEmpty {
            let qsoBand = qso.band.uppercased()
            let normalizedBands = bands.map { $0.uppercased() }
            if !normalizedBands.contains(qsoBand) {
                return false
            }
        }

        // Check modes
        if let modes = criteria.modes, !modes.isEmpty {
            let qsoMode = qso.mode.uppercased()
            let normalizedModes = modes.map { $0.uppercased() }

            // Support mode families (e.g., "DIGITAL" matches FT8, FT4, etc.)
            let matched = normalizedModes.contains { mode in
                if mode == qsoMode {
                    return true
                }
                if mode == "DIGITAL" {
                    return isDigitalMode(qsoMode)
                }
                if mode == "PHONE" {
                    return isPhoneMode(qsoMode)
                }
                return false
            }

            if !matched {
                return false
            }
        }

        // Check required fields
        if let requiredFields = criteria.requiredFields {
            let hasFailingRequirement = requiredFields.contains {
                !qsoSatisfiesFieldRequirement(qso, requirement: $0)
            }
            if hasFailingRequirement {
                return false
            }
        }

        // Check date range
        if let dateRange = criteria.dateRange {
            if qso.timestamp < dateRange.startDate || qso.timestamp > dateRange.endDate {
                return false
            }
        }

        return true
    }

    static func qsoWithinTimeConstraints(_ qso: QSO, constraints: TimeConstraints?) -> Bool {
        guard let constraints else {
            return true
        }

        if let startDate = constraints.startDate, qso.timestamp < startDate {
            return false
        }

        if let endDate = constraints.endDate, qso.timestamp > endDate {
            return false
        }

        return true
    }

    // MARK: - Goal Matching

    static func findMatchedGoals(qso: QSO, definition: ChallengeDefinition) -> [String] {
        guard let criteria = definition.criteria,
              let matchRules = criteria.matchRules
        else {
            // No match rules - for cumulative challenges, return a placeholder
            if definition.type == .cumulative || definition.type == .timeBounded {
                return ["_count"]
            }
            return []
        }

        var matchedGoalIds: [String] = []

        for rule in matchRules {
            guard let qsoValue = getQSOField(qso, fieldName: rule.qsoField) else {
                continue
            }

            let transformedValue = applyTransformation(
                qsoValue,
                transformation: rule.transformation
            )

            // Validate format if specified
            if let pattern = rule.validationRegex {
                let regex = try? NSRegularExpression(pattern: pattern, options: [])
                let range = NSRange(transformedValue.startIndex..., in: transformedValue)
                if regex?.firstMatch(in: transformedValue, options: [], range: range) == nil {
                    continue
                }
            }

            // Find matching goal
            for goal in definition.goals {
                let goalValue: String? =
                    switch rule.goalField {
                    case "id":
                        goal.id
                    case "name":
                        goal.name
                    case "category":
                        goal.category
                    default:
                        goal.metadata?[rule.goalField]
                    }

                if let goalValue, transformedValue.uppercased() == goalValue.uppercased() {
                    matchedGoalIds.append(goal.id)
                }
            }
        }

        return matchedGoalIds
    }

    // MARK: - Field Access

    static func getQSOField(_ qso: QSO, fieldName: String) -> String? {
        switch fieldName.lowercased() {
        case "state":
            qso.state
        case "country":
            qso.country
        case "dxcc",
             "dxccentity":
            qso.dxcc.map { String($0) }
        case "dxccname":
            qso.dxcc.flatMap { DescriptionLookup.dxccEntity(forNumber: $0)?.name }
        case "parkreference",
             "park":
            qso.parkReference
        case "theirparkreference",
             "theirpark":
            qso.theirParkReference
        case "sotaref",
             "sota":
            qso.sotaRef
        case "grid",
             "theirgrid":
            qso.theirGrid
        case "mygrid":
            qso.myGrid
        case "callsign":
            qso.callsign
        case "prefix",
             "callsignprefix":
            qso.callsignPrefix
        case "band":
            qso.band
        case "mode":
            qso.mode
        default:
            nil
        }
    }

    // MARK: Private

    // MARK: - Private Helpers

    private static func qsoSatisfiesFieldRequirement(
        _ qso: QSO,
        requirement: FieldRequirement
    ) -> Bool {
        let value = getQSOField(qso, fieldName: requirement.fieldName)

        if requirement.mustExist {
            guard let value, !value.isEmpty else {
                return false
            }

            // Check pattern if specified
            if let pattern = requirement.pattern {
                let regex = try? NSRegularExpression(pattern: pattern, options: [])
                let range = NSRange(value.startIndex..., in: value)
                if regex?.firstMatch(in: value, options: [], range: range) == nil {
                    return false
                }
            }
        }

        return true
    }

    private static func applyTransformation(
        _ value: String,
        transformation: MatchTransformation?
    ) -> String {
        guard let transformation else {
            return value
        }

        switch transformation {
        case .uppercase:
            return value.uppercased()
        case .lowercase:
            return value.lowercased()
        case .stripPrefix:
            if let range = value.range(of: "/") {
                return String(value[range.upperBound...])
            }
            if let range = value.range(of: "-") {
                return String(value[range.upperBound...])
            }
            return value
        case .stripSuffix:
            if let range = value.range(of: "/", options: .backwards) {
                return String(value[..<range.lowerBound])
            }
            if let range = value.range(of: "-", options: .backwards) {
                return String(value[..<range.lowerBound])
            }
            return value
        }
    }

    private static func isDigitalMode(_ mode: String) -> Bool {
        let digitalModes = [
            "FT8", "FT4", "JS8", "RTTY", "PSK31", "PSK63", "OLIVIA",
            "JT65", "JT9", "WSPR", "MSK144", "Q65", "FST4", "MFSK",
        ]
        return digitalModes.contains(mode.uppercased())
    }

    private static func isPhoneMode(_ mode: String) -> Bool {
        let phoneModes = ["SSB", "USB", "LSB", "AM", "FM", "DV"]
        return phoneModes.contains(mode.uppercased())
    }
}
