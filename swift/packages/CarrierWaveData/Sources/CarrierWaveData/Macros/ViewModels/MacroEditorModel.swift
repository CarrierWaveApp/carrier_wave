import Foundation

// MARK: - MacroEditorModel

/// View-model wrapping a working `RadioMacroSpec` for `MacroEditorView`.
/// Mutations are made directly against `spec`; callers must call
/// `reverify()` after each change to refresh `issues`. The view's save
/// affordance reads `canSave`.
@Observable
@MainActor
public final class MacroEditorModel {
    // MARK: Lifecycle

    public init(spec: RadioMacroSpec) {
        self.spec = spec
        issues = MacroVerifier.verify(spec)
    }

    // MARK: Public

    public var spec: RadioMacroSpec
    public var issues: [MacroVerifierIssue] = []
    public var dirty: Bool = false

    /// Verifier errors block save; warnings do not.
    public var canSave: Bool {
        !issues.contains(where: { $0.severity == .error })
    }

    public var errorIssues: [MacroVerifierIssue] {
        issues.filter { $0.severity == .error }
    }

    public var warningIssues: [MacroVerifierIssue] {
        issues.filter { $0.severity == .warning }
    }

    /// Re-run `MacroVerifier.verify` against the current spec. Cheap; safe
    /// to call from `onChange` of every editable field.
    public func reverify() {
        issues = MacroVerifier.verify(spec)
    }

    /// Convenience hook for callers that mutate `spec.steps` (or any nested
    /// field) and need both the dirty flag and verifier issues kept in sync.
    public func markDirty() {
        dirty = true
        reverify()
    }
}
