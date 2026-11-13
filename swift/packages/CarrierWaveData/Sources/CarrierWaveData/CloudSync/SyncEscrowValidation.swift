import CryptoKit
import Foundation

// MARK: - SyncEscrowValidation

/// Pure decision logic for validating a locally-held E2E sync data key against
/// the server's key escrow before pushing (Phase 7.1 of the sync-server plan).
///
/// A device must never push blobs encrypted with a key the server's escrow
/// cannot recover: that is exactly the 2026-07-03 poisoned-tenant incident,
/// where a stale local key seed-uploaded ~2k undecryptable QSOs after the
/// staging→prod switch. Because the escrow blob is passphrase-wrapped, the
/// client cannot cryptographically verify its key against it without the
/// passphrase — instead we fingerprint the escrow blob the local key was
/// derived from (at create/unlock time) and require the server's current
/// escrow to match that fingerprint before any push.
public enum SyncEscrowValidation {
    /// The outcome of comparing the server escrow against the locally-recorded
    /// escrow fingerprint.
    public enum Verdict: Equatable, Sendable {
        /// Fingerprints match — safe to push.
        case allow
        /// Legacy enrolled device (seeded before fingerprints existed) —
        /// adopt the server's current escrow fingerprint and allow.
        case adoptAndAllow(fingerprint: String)
        /// The server has no escrow at all. Pushing would seed the tenant
        /// with blobs no future device can ever recover — refuse.
        case refuseNoEscrow
        /// The server escrow does not correspond to the local key (or the
        /// local key was never validated against this server). Refuse and
        /// require the passphrase flow.
        case refuseMismatch
    }

    /// Stable fingerprint of an escrow blob: SHA-256 of the wrapped-key
    /// base64 string, hex-encoded. Recorded locally when the data key is
    /// minted (create) or recovered (unlock).
    public static func fingerprint(wrappedKeyB64: String) -> String {
        let digest = SHA256.hash(data: Data(wrappedKeyB64.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Decide whether a push against this server is safe.
    ///
    /// - Parameters:
    ///   - serverWrappedKeyB64: the escrow blob currently on the server, or
    ///     `nil` when the server has none (404).
    ///   - localFingerprint: the escrow fingerprint recorded for this base
    ///     URL at create/unlock time, or `nil` if never recorded.
    ///   - isSeeded: whether this install has already completed a sync pass
    ///     against this base URL (legacy enrollments predate fingerprints).
    public static func verdict(
        serverWrappedKeyB64: String?,
        localFingerprint: String?,
        isSeeded: Bool
    ) -> Verdict {
        guard let serverWrappedKeyB64 else {
            return .refuseNoEscrow
        }
        let serverFingerprint = fingerprint(wrappedKeyB64: serverWrappedKeyB64)
        guard let localFingerprint else {
            // Seeded before fingerprints existed → grandfather in once.
            // Unseeded → the key has never been validated against this
            // server; require the passphrase flow (which records it).
            return isSeeded
                ? .adoptAndAllow(fingerprint: serverFingerprint)
                : .refuseMismatch
        }
        return localFingerprint == serverFingerprint ? .allow : .refuseMismatch
    }
}
