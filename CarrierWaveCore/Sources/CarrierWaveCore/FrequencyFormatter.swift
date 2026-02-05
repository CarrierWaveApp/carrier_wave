//
//  FrequencyFormatter.swift
//  CarrierWaveCore
//

import Foundation

/// Formats frequency values with appropriate precision
public enum FrequencyFormatter: Sendable {
    /// Format a frequency in MHz with appropriate precision
    /// Shows at least 3 decimal places (kHz), up to 5 if needed (10 Hz precision)
    /// Trailing zeros beyond 3 decimals are trimmed
    /// - Parameters:
    ///   - frequencyMHz: Frequency in MHz
    ///   - includeUnit: Whether to append " MHz" suffix
    /// - Returns: Formatted frequency string
    public static func format(_ frequencyMHz: Double, includeUnit: Bool = false) -> String {
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
    public static func formatWithUnit(_ frequencyMHz: Double) -> String {
        format(frequencyMHz, includeUnit: true)
    }

    /// Parse a frequency string, handling various input formats
    /// Supports:
    /// - Plain numbers: "14.060" (MHz if 1.8-450), "14060" (kHz, auto-converted to MHz)
    /// - With units: "14.060 MHz", "14060 kHz", "14060kHz", "14.060mhz"
    /// - Parameter input: User input string
    /// - Returns: Frequency in MHz, or nil if invalid
    public static func parse(_ input: String) -> Double? {
        var trimmed = input.trimmingCharacters(in: .whitespaces).lowercased()

        // Check for unit suffix and extract multiplier
        var explicitKHz = false
        var explicitMHz = false

        if trimmed.hasSuffix("khz") {
            trimmed = String(trimmed.dropLast(3)).trimmingCharacters(in: .whitespaces)
            explicitKHz = true
        } else if trimmed.hasSuffix("mhz") {
            trimmed = String(trimmed.dropLast(3)).trimmingCharacters(in: .whitespaces)
            explicitMHz = true
        }

        guard let value = Double(trimmed) else {
            return nil
        }

        // If explicit unit was provided, use it
        if explicitKHz {
            return value / 1_000.0
        }
        if explicitMHz {
            return value
        }

        // No explicit unit - use heuristics
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
