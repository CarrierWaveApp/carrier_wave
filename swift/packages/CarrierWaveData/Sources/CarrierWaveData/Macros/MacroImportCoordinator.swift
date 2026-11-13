import Foundation

// MARK: - MacroImportProvenance

/// How a macro document arrived at the device — used to label the
/// install confirmation sheet and (post-Phase 1) to gate registry-only
/// affordances.
public enum MacroImportProvenance: Sendable, Equatable {
    case registry(slug: String)
    case airDrop
    case files
    case web(host: String)
    case other(label: String)
}

// MARK: - MacroImportOutcome

/// Result of validating an imported document before persistence. The
/// editor turns `.readyToInstall` into a confirmation sheet (with raw-bytes
/// emphasis when set) and `.rejected` into a refusal banner.
public enum MacroImportOutcome: Sendable {
    case readyToInstall(
        RadioMacroSpec,
        provenance: MacroImportProvenance,
        requiresRawBytesConfirmation: Bool
    )
    case rejected(reason: String)
}

// MARK: - MacroImportCoordinator

/// Validates an incoming `.cwmacro` document end-to-end before it touches
/// SwiftData. Runs the same `MacroVerifier` pass the editor and registry
/// use, plus a belt-and-suspenders capability-dominance check so a stripped
/// capabilities block can't smuggle a transmit-capable payload past the
/// gate. Provenance is carried through so the install sheet can name the
/// source ("from AirDrop", "from Carrier Wave Registry", etc.).
public actor MacroImportCoordinator {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public func evaluate(
        documentData: Data,
        provenance: MacroImportProvenance
    ) -> MacroImportOutcome {
        let document: RadioMacroDocument
        do {
            document = try JSONDecoder().decode(RadioMacroDocument.self, from: documentData)
        } catch let RadioMacroDocumentError.unsupportedFormat(format) {
            return .rejected(reason: "Macro requires a newer Carrier Wave (format \(format))")
        } catch RadioMacroDocumentError.unsupportedV1 {
            return .rejected(reason: "Macro is in the deprecated v1 format and cannot be installed")
        } catch {
            return .rejected(reason: "Invalid macro document JSON")
        }

        // Defense in depth: decode succeeded but format claims a higher
        // version. The decoder already enforces format == currentFormat
        // so this is unreachable today, but kept against the day someone
        // relaxes the decoder.
        if document.format > RadioMacroDocument.currentFormat {
            return .rejected(
                reason: "Macro requires a newer Carrier Wave (format \(document.format))"
            )
        }

        // Capability-dominance re-check. MacroVerifier.verify already
        // emits an error issue when declared capabilities don't dominate
        // the inferred set, but we run it explicitly so a future Verifier
        // refactor doesn't quietly relax the import gate.
        let inferred = MacroVerifier.inferCapabilities(from: document.macro.steps)
        if !document.macro.capabilities.dominates(inferred) {
            return .rejected(reason: "Capability declarations don't match steps")
        }

        let issues = MacroVerifier.verify(document.macro)
        if let firstError = issues.first(where: { $0.severity == .error }) {
            return .rejected(reason: firstError.message)
        }

        return .readyToInstall(
            document.macro,
            provenance: provenance,
            requiresRawBytesConfirmation: document.macro.capabilities.usesRawBytes
        )
    }

    /// Spec-level overload that skips the JSON round-trip. Used by the
    /// registry install flow where the document arrives over HTTP rather
    /// than as a `.cwmacro` blob.
    public func evaluate(
        spec: RadioMacroSpec,
        provenance: MacroImportProvenance
    ) -> MacroImportOutcome {
        let inferred = MacroVerifier.inferCapabilities(from: spec.steps)
        if !spec.capabilities.dominates(inferred) {
            return .rejected(reason: "Capability declarations don't match steps")
        }
        let issues = MacroVerifier.verify(spec)
        if let firstError = issues.first(where: { $0.severity == .error }) {
            return .rejected(reason: firstError.message)
        }
        return .readyToInstall(
            spec,
            provenance: provenance,
            requiresRawBytesConfirmation: spec.capabilities.usesRawBytes
        )
    }
}

// MARK: - RadioMacroDocumentError (forward-declared for actor scope)

// RadioMacroDocumentError is defined in RadioMacroDocument.swift; no
// re-declaration needed. This comment is here to make the intent obvious
// to anyone grepping for the error type the catch arms reference.
