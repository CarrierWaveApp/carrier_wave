import Foundation

// MARK: - MacroVerifierSeverity

public enum MacroVerifierSeverity: Sendable, Equatable {
    case error
    case warning
}

// MARK: - MacroVerifierIssue

public struct MacroVerifierIssue: Sendable, Equatable {
    // MARK: Lifecycle

    public init(severity: MacroVerifierSeverity, stepIndex: Int?, message: String) {
        self.severity = severity
        self.stepIndex = stepIndex
        self.message = message
    }

    // MARK: Public

    public let severity: MacroVerifierSeverity
    public let stepIndex: Int?
    public let message: String
}

// MARK: - MacroVerifier

/// Static analysis pass over a `RadioMacroSpec`. Produces a flat list of
/// `MacroVerifierIssue`s — errors and warnings — that the editor surfaces
/// inline and the server uses to gate publication of macros to the
/// registry.
public enum MacroVerifier {
    // MARK: Public

    public static func verify(_ spec: RadioMacroSpec) -> [MacroVerifierIssue] {
        var issues: [MacroVerifierIssue] = []
        let inferred = inferCapabilities(from: spec.steps)
        if !spec.capabilities.dominates(inferred) {
            let parts = [
                "transmits=\(inferred.transmits)",
                "changesFrequency=\(inferred.changesFrequency)",
                "changesMode=\(inferred.changesMode)",
                "changesPower=\(inferred.changesPower)",
                "usesRawBytes=\(inferred.usesRawBytes)",
            ].joined(separator: ", ")
            issues.append(.init(
                severity: .error,
                stepIndex: nil,
                message: "Declared capabilities do not cover inferred: \(parts)"
            ))
        }
        for (index, step) in spec.steps.enumerated() {
            issues.append(contentsOf: verifyStep(step, index: index, args: spec.args))
        }
        for arg in spec.args where arg.type == .frequency {
            if arg.min == nil || arg.max == nil {
                issues.append(.init(
                    severity: .error,
                    stepIndex: nil,
                    message: "Frequency arg '\(arg.name)' must declare min/max bounds"
                ))
            }
        }
        return issues
    }

    public static func inferCapabilities(
        from steps: [RadioMacroStep]
    ) -> RadioMacroCapabilities {
        var caps = RadioMacroCapabilities()
        for step in steps {
            let bits = step.capabilityContribution()
            caps = caps.union(bits.asCapabilities())
            // T6: decode `.rawBytes` payloads against the per-protocol
            // opcode table. Recognised opcodes contribute their capability
            // bits; payloads that match no known opcode are treated as
            // hostile and floor capabilities at `transmits: true,
            // usesRawBytes: true` regardless of declaration.
            if case let .rawBytes(protocolName, bytes) = step {
                let table = RadioMacroOpcodeTable.load(for: protocolName)
                caps = caps.union(table.capabilities(forBytesHex: bytes))
                if !table.allRecognized(forBytesHex: bytes) {
                    caps.transmits = true
                    caps.usesRawBytes = true
                }
            }
        }
        return caps
    }

    // MARK: Private

    private static func verifyStep(
        _ step: RadioMacroStep,
        index: Int,
        args _: [RadioMacroArg]
    ) -> [MacroVerifierIssue] {
        switch step {
        case let .delay(durationMs):
            if durationMs > 30_000 {
                return [.init(
                    severity: .error,
                    stepIndex: index,
                    message: "Delay exceeds 30000 ms cap"
                )]
            }
        case let .waitUntil(_, timeoutMs):
            if timeoutMs > 30_000 {
                return [.init(
                    severity: .error,
                    stepIndex: index,
                    message: "waitUntil timeout exceeds 30000 ms cap"
                )]
            }
        case let .sendCW(text):
            if !text.allSatisfy(\.isASCII) {
                return [.init(
                    severity: .error,
                    stepIndex: index,
                    message: "sendCW requires ASCII text"
                )]
            }
        default:
            break
        }
        return []
    }
}

// MARK: - CapabilityBits bridge

/// Bridge between the codegen `CapabilityBits` shape (struct with bool
/// fields, no `regions`) and the public `RadioMacroCapabilities` type.
extension CapabilityBits {
    func asCapabilities() -> RadioMacroCapabilities {
        RadioMacroCapabilities(
            transmits: transmits,
            changesFrequency: changesFrequency,
            changesMode: changesMode,
            changesPower: changesPower,
            usesRawBytes: usesRawBytes
        )
    }
}
