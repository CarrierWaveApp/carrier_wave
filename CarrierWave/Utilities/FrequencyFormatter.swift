import Foundation

/// Formats frequency values with appropriate precision
enum FrequencyFormatter {
    /// Format a frequency in MHz with appropriate precision
    /// Shows at least 3 decimal places (kHz), up to 5 if needed (10 Hz precision)
    /// Trailing zeros beyond 3 decimals are trimmed
    /// - Parameters:
    ///   - frequencyMHz: Frequency in MHz
    ///   - includeUnit: Whether to append " MHz" suffix
    /// - Returns: Formatted frequency string
    static func format(_ frequencyMHz: Double, includeUnit: Bool = false) -> String {
        // Format with 5 decimal places (10 Hz precision)
        let formatted = String(format: "%.5f", frequencyMHz)

        // Trim trailing zeros, but keep at least 3 decimal places
        var result = formatted

        // Find decimal point position
        guard let decimalIndex = result.firstIndex(of: ".") else {
            return includeUnit ? "\(result) MHz" : result
        }

        // Remove trailing zeros beyond 3 decimal places
        while result.hasSuffix("0") {
            let currentDecimals = result.distance(
                from: result.index(after: decimalIndex),
                to: result.endIndex
            )
            if currentDecimals > 3 {
                result.removeLast()
            } else {
                break
            }
        }

        return includeUnit ? "\(result) MHz" : result
    }

    /// Format a frequency for display in headers/labels
    /// Same as format() but always includes MHz suffix
    static func formatWithUnit(_ frequencyMHz: Double) -> String {
        format(frequencyMHz, includeUnit: true)
    }

    /// Parse a frequency string, handling various input formats
    /// Supports: "14.060", "14.06050", "14060.5" (kHz)
    /// - Parameter input: User input string
    /// - Returns: Frequency in MHz, or nil if invalid
    static func parse(_ input: String) -> Double? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)

        guard let value = Double(trimmed) else {
            return nil
        }

        // If value is > 1000, assume it's in kHz and convert to MHz
        if value > 1_000 {
            return value / 1_000.0
        }

        // If value is in amateur band range (1.8-450 MHz), return as-is
        if value >= 1.8, value <= 450.0 {
            return value
        }

        return nil
    }
}
