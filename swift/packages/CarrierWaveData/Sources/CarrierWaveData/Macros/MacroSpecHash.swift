import CryptoKit
import Foundation

// MARK: - MacroSpecHash

/// Canonical SHA-256 of a macro's *steps* only.
///
/// Used as the acceptance key for raw-bytes opcodes: once a user has
/// approved a particular byte sequence for a particular protocol, the
/// safety gate can recognize the same sequence again on subsequent runs
/// or after import without re-prompting. Hashing only `spec.steps`
/// (with sorted JSON keys) means cosmetic edits to name, icon, tags,
/// etc. don't invalidate the acceptance, while any change to the actual
/// transmitted bytes does.
public enum MacroSpecHash {
    /// SHA-256 hex digest of the canonical JSON encoding of `spec.steps`.
    /// Returns an empty string if encoding fails; callers should treat
    /// an empty string as "no stable hash" rather than as a match.
    public static func canonical(_ spec: RadioMacroSpec) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(spec.steps) else {
            return ""
        }
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
