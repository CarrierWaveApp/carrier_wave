import Foundation

// MARK: - QueryParser Condition Building

extension QueryParser {
    func buildCondition(
        field: QueryField,
        value: String,
        endValue: String?,
        comparison: QueryToken?,
        position: SourcePosition
    ) -> Result<TermCondition, QueryError> {
        // Handle date fields
        if field == .date || field == .after || field == .before {
            return buildDateCondition(
                field: field, value: value, endValue: endValue, position: position
            )
        }

        // Handle numeric fields with comparisons
        if field == .frequency || field == .power || field == .dxcc {
            return buildNumericCondition(
                value: value, endValue: endValue, comparison: comparison, position: position
            )
        }

        // Handle boolean/service fields
        if field == .confirmed || field == .synced || field == .pending {
            return buildStatusCondition(field: field, value: value, position: position)
        }

        // Handle source field
        if field == .source {
            return buildSourceCondition(value: value, position: position)
        }

        // Handle string range
        if let endValue {
            return .success(.range(value, endValue))
        }

        // Handle wildcards
        if value.contains("*") {
            if value.hasPrefix("*"), value.hasSuffix("*") {
                let inner = String(value.dropFirst().dropLast())
                return .success(.contains(inner))
            } else if value.hasPrefix("*") {
                return .success(.suffix(String(value.dropFirst())))
            } else if value.hasSuffix("*") {
                return .success(.prefix(String(value.dropLast())))
            }
        }

        // Default to equals match
        return .success(.equals(value))
    }

    func buildDateCondition(
        field: QueryField,
        value: String,
        endValue: String?,
        position: SourcePosition
    ) -> Result<TermCondition, QueryError> {
        guard let dateMatch = parseDateValue(value) else {
            return .failure(QueryError.invalidDateFormat(value, position: position))
        }

        if let endValue {
            guard let endMatch = parseDateValue(endValue) else {
                return .failure(QueryError.invalidDateFormat(endValue, position: position))
            }
            return .success(.dateRange(dateMatch, endMatch))
        }

        switch field {
        case .after:
            return .success(.dateAfter(dateMatch))
        case .before:
            return .success(.dateBefore(dateMatch))
        default:
            return .success(.dateEquals(dateMatch))
        }
    }

    func buildNumericCondition(
        value: String,
        endValue: String?,
        comparison: QueryToken?,
        position: SourcePosition
    ) -> Result<TermCondition, QueryError> {
        guard let number = Double(value) else {
            return .failure(QueryError.invalidNumberFormat(value, position: position))
        }

        if let endValue {
            guard let endNumber = Double(endValue) else {
                return .failure(QueryError.invalidNumberFormat(endValue, position: position))
            }
            return .success(.numericRange(number, endNumber))
        }

        if let comparison {
            switch comparison {
            case .greaterThan:
                return .success(.greaterThan(number))
            case .lessThan:
                return .success(.lessThan(number))
            case .greaterThanOrEqual:
                return .success(.greaterThanOrEqual(number))
            case .lessThanOrEqual:
                return .success(.lessThanOrEqual(number))
            default:
                break
            }
        }

        // Exact match with small tolerance for frequencies
        return .success(.numericRange(number - 0.0005, number + 0.0005))
    }

    func buildStatusCondition(
        field: QueryField,
        value: String,
        position: SourcePosition
    ) -> Result<TermCondition, QueryError> {
        let lowered = value.lowercased()

        // Boolean values
        if lowered == "yes" || lowered == "true" || lowered == "1" {
            return .success(.boolean(true))
        }
        if lowered == "no" || lowered == "false" || lowered == "0" {
            return .success(.boolean(false))
        }

        // Service type
        if let service = ServiceType(rawValue: lowered) {
            return .success(.service(service))
        }

        // Try common aliases
        switch lowered {
        case "lotw",
             "logbookoftheworld":
            return .success(.service(.lotw))
        case "qrz":
            return .success(.service(.qrz))
        case "pota":
            return .success(.service(.pota))
        case "lofi",
             "ham2k":
            return .success(.service(.lofi))
        case "hamrs":
            return .success(.service(.hamrs))
        case "clublog",
             "club log":
            return .success(.service(.clublog))
        default:
            return .failure(
                QueryError.unexpectedToken(
                    expected: "yes/no or service name (lotw, qrz, pota, lofi, hamrs, clublog)",
                    got: value,
                    position: position
                )
            )
        }
    }

    func buildSourceCondition(value: String, position: SourcePosition) -> Result<
        TermCondition, QueryError
    > {
        let lowered = value.lowercased()

        // Map to service type for source filtering
        switch lowered {
        case "lotw",
             "logbookoftheworld":
            return .success(.service(.lotw))
        case "qrz":
            return .success(.service(.qrz))
        case "pota":
            return .success(.service(.pota))
        case "lofi",
             "ham2k":
            return .success(.service(.lofi))
        case "hamrs":
            return .success(.service(.hamrs))
        case "clublog",
             "club log":
            return .success(.service(.clublog))
        case "manual",
             "local":
            return .success(.equals("manual"))
        default:
            return .failure(
                QueryError.unexpectedToken(
                    expected: "source name (lotw, qrz, pota, lofi, hamrs, clublog, manual)",
                    got: value,
                    position: position
                )
            )
        }
    }

    func buildBareTermCondition(value: String, endValue: String?) -> TermCondition {
        if let endValue {
            return .range(value, endValue)
        }

        // Handle wildcards
        if value.contains("*") {
            if value.hasPrefix("*"), value.hasSuffix("*") {
                return .contains(String(value.dropFirst().dropLast()))
            } else if value.hasPrefix("*") {
                return .suffix(String(value.dropFirst()))
            } else if value.hasSuffix("*") {
                return .prefix(String(value.dropLast()))
            }
        }

        // For bare terms, use contains to match across callsign/park/sota
        return .contains(value)
    }

    func parseDateValue(_ value: String) -> DateMatch? {
        let lowered = value.lowercased()

        // Special keywords
        if lowered == "today" {
            return .today
        }
        if lowered == "yesterday" {
            return .yesterday
        }

        // Relative dates (e.g., "7d", "30d", "3m")
        if lowered.hasSuffix("d"), let days = Int(lowered.dropLast()) {
            return .relative(days: days)
        }
        if lowered.hasSuffix("m"), let months = Int(lowered.dropLast()) {
            return .relative(days: months * 30)
        }

        // Year only (e.g., "2024")
        if value.count == 4, let year = Int(value) {
            return .year(year)
        }

        // Year-month (e.g., "2024-01")
        if value.count == 7, value.contains("-") {
            let parts = value.split(separator: "-")
            if parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) {
                return .yearMonth(year, month)
            }
        }

        // Full date (e.g., "2024-01-15")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: value) {
            return .specific(date)
        }

        return nil
    }
}
