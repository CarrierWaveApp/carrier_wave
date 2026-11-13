import CarrierWaveCwFfi
import Foundation

// Bridge to the Rust query analyzer in `cw-domain` via the UniFFI surface.
//
// Phase-0 closure point (see `docs/plans/2026-06-13-rust-core-handoff.md`):
// keeps the Swift `QueryAnalysis` shape, parses and analyzes via Rust, so
// callers can opt into the Rust path without changing their consumption.
// Parity is asserted in `QueryAnalyzerRustParityTests`.

public extension QueryAnalyzer {
    /// Parse + analyze `source` in Rust (`cw-domain`) and lift the result into
    /// the Swift `QueryAnalysis` shape.
    ///
    /// Throws `CwError.Query` for parse errors so callers can distinguish a
    /// failed parse (caller's input is wrong) from an analysis result.
    static func analyzeViaRust(_ source: String, qsoCount: Int) throws -> QueryAnalysis {
        let ffi = try analyzeQuery(input: source, qsoCount: Int64(qsoCount))
        return liftAnalysis(ffi)
    }

    /// Validate `source` in Rust and return its canonical text. Throws on
    /// parse errors. Used by live as-you-type validation.
    static func validateViaRust(_ source: String) throws -> String {
        try validateQuery(input: source)
    }

    // MARK: Private

    private static func liftAnalysis(_ ffi: FfiQueryAnalysis) -> QueryAnalysis {
        QueryAnalysis(
            warnings: ffi.warnings.map(liftWarning),
            estimatedCost: liftCost(ffi.cost),
            usesIndex: ffi.usesIndex
        )
    }

    private static func liftCost(_ cost: FfiQueryCost) -> QueryCost {
        switch cost {
        case .indexed: .indexed
        case .bounded: .bounded
        case .fullScan: .fullScan
        }
    }

    private static func liftWarning(_ warning: FfiQueryWarning) -> QueryWarning {
        QueryWarning(
            severity: liftSeverity(warning.severity),
            message: warning.message,
            suggestion: warning.suggestion
        )
    }

    private static func liftSeverity(_ severity: FfiSeverity) -> QueryWarning.Severity {
        switch severity {
        case .hint: .hint
        case .medium: .medium
        case .high: .high
        }
    }
}
