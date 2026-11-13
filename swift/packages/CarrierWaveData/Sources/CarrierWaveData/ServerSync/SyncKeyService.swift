import CarrierWaveCore
import Foundation

// MARK: - SyncKeyService

/// Drives the E2E sync passphrase lifecycle: create a passphrase (mint + escrow
/// the data key), unlock a device (recover the key from the server escrow), and
/// track whether this device holds the data key. Shared by Carrier Wave (iOS)
/// and CW Sweep (macOS).
///
/// The 32-byte data key lives only in the device Keychain, scoped per server
/// (never iCloud-synced). The server holds only the Argon2id-wrapped copy,
/// which it cannot read.
///
/// Host hooks: diagnostics go to `ServerSyncLog`, long passes take a
/// `SuspensionGuardFactory` guard when the platform installs one, and
/// `passphraseProvisioner` lets iOS back up the cw-store at-rest key under the
/// passphrase after create/unlock.
@MainActor
@Observable
public final class SyncKeyService {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public enum Status: Equatable, Sendable {
        /// Haven't checked yet, or the server was unreachable.
        case unknown
        /// No escrow on the server and no local key — ready to create one.
        case notConfigured
        /// The server has an escrow but this device lacks the key — needs the passphrase.
        case lockedNeedsPassphrase
        /// This device holds the data key.
        case ready
    }

    /// A step within a create/unlock operation, surfaced live in the UI.
    public enum Phase: Equatable, Sendable {
        case idle
        case derivingKey
        case contactingServer
        case preparing
        case uploading
        case downloading
        case saving
        case done

        // MARK: Public

        public var label: String {
            switch self {
            case .idle: ""
            case .derivingKey: "Deriving encryption key…"
            case .contactingServer: "Contacting server…"
            case .preparing: "Preparing your log…"
            case .uploading: "Uploading…"
            case .downloading: "Downloading…"
            case .saving: "Saving…"
            case .done: "Done"
            }
        }
    }

    /// Installed by the host to run after a passphrase is created or entered
    /// (iOS: `CwStoreKeyRecovery.provision`). Best-effort; never blocks sync.
    public static var passphraseProvisioner: (@MainActor (String) async -> Void)?

    /// Keychain slot for the data key, scoped per server (like the cursor and
    /// seeded flag). A key recovered from one server's escrow must never be
    /// silently trusted against another server: that's how the iPhone once
    /// uploaded a whole log to prod under a staging-era key the prod escrow
    /// couldn't decrypt. Legacy unscoped keys are intentionally ignored.
    nonisolated public static var dataKeyKeychainKey: String {
        "\(KeychainHelper.Keys.syncDataKey).\(ActivitiesServer.resolvedBaseURL)"
    }

    public private(set) var status: Status = .unknown
    public private(set) var phase: Phase = .idle
    /// When the in-flight operation started, for the elapsed-time readout.
    public private(set) var operationStart: Date?
    public private(set) var lastSyncSummary: SyncRunSummary?
    public private(set) var lastProfile: SyncProfile?
    public var lastError: String?

    public var hasLocalKey: Bool {
        (try? keychain.read(for: Self.dataKeyKeychainKey)) != nil
    }

    /// Determine the current state. A local key is only `.ready` if it still
    /// corresponds to the server's escrow (fingerprint check) — a stale key
    /// must never look usable against a server whose escrow it can't match
    /// (the 2026-07-03 poisoned-tenant incident). If the server is
    /// unreachable, a locally-held key stays `.ready` for offline use; the
    /// push path re-validates before any upload.
    public func refreshStatus() async {
        lastError = nil
        do {
            let blob = try await client.getSyncKey()
            if hasLocalKey {
                if applyEscrowVerdict(serverBlob: blob) {
                    status = .ready
                }
            } else {
                status = blob == nil ? .notConfigured : .lockedNeedsPassphrase
            }
        } catch {
            if hasLocalKey {
                status = .ready
            } else {
                status = .unknown
                lastError = Self.message(for: error)
            }
        }
    }

    /// Create a brand-new sync passphrase. Only valid from `.notConfigured` —
    /// the UI gates this, and the server is re-checked here at creation time
    /// so a stale status can never silently overwrite an existing escrow
    /// (old blobs would become permanently undecryptable; there is no
    /// key-rotation path).
    public func createPassphrase(_ passphrase: String) async -> Bool {
        lastError = nil
        beginOperation()
        defer { operationStart = nil }
        do {
            phase = .contactingServer
            if try await client.getSyncKey() != nil {
                status = .lockedNeedsPassphrase
                lastError = "A sync passphrase already exists for this account on this server. "
                    + "Enter it to unlock this device instead — creating a new one would make "
                    + "your existing synced data unreadable."
                ServerSyncLog.error(
                    "Server sync: refused to create a passphrase — escrow already exists on server"
                )
                return false
            }
            phase = .derivingKey
            let escrow = try await Self.deriveEscrow(passphrase: passphrase)
            // Escrow to the server FIRST; only persist the local key once the
            // wrapped copy is safely stored, so we never end up "ready" locally
            // with nothing recoverable elsewhere.
            phase = .contactingServer
            try await client.putSyncKey(
                wrappedKeyB64: escrow.wrappedKeyB64,
                kdfParamsJSON: escrow.kdfParamsJson
            )
            phase = .saving
            try keychain.save(escrow.dataKey, for: Self.dataKeyKeychainKey)
            Self.saveEscrowFingerprint(
                SyncEscrowValidation.fingerprint(wrappedKeyB64: escrow.wrappedKeyB64),
                base: ActivitiesServer.resolvedBaseURL
            )
            phase = .done
            status = .ready
            provision(passphrase)
            return true
        } catch {
            lastError = Self.message(for: error)
            return false
        }
    }

    /// Unlock this device using an existing passphrase. Valid from
    /// `.lockedNeedsPassphrase`.
    public func unlock(_ passphrase: String) async -> Bool {
        lastError = nil
        beginOperation()
        defer { operationStart = nil }
        do {
            phase = .contactingServer
            guard let blob = try await client.getSyncKey() else {
                lastError = "No sync passphrase is set up yet. Create one first."
                return false
            }
            phase = .derivingKey
            let dataKey = try await Self.recoverKey(
                passphrase: passphrase,
                wrappedKeyB64: blob.wrappedKeyB64,
                kdfParamsJson: blob.kdfParamsJSON
            )
            phase = .saving
            try keychain.save(dataKey, for: Self.dataKeyKeychainKey)
            Self.saveEscrowFingerprint(
                SyncEscrowValidation.fingerprint(wrappedKeyB64: blob.wrappedKeyB64),
                base: ActivitiesServer.resolvedBaseURL
            )
            phase = .done
            status = .ready
            provision(passphrase)
            return true
        } catch is CwError {
            // The only CwError on this path is a failed unwrap.
            lastError = "Incorrect passphrase."
            return false
        } catch {
            lastError = Self.message(for: error)
            return false
        }
    }

    /// Manually run one sync pass: push this device's dirty QSOs (E2E-encrypted)
    /// and pull + merge any remote ones. The first pass against a given server
    /// automatically seeds the full log (see `performSync`). Valid from `.ready`.
    public func runSyncOnce() async -> Bool {
        await performSync(fullUpload: false)
    }

    /// Manual repair: mark every QSO dirty, then sync. First-time seeding now
    /// happens automatically per server, so this is only needed to force a
    /// re-upload (the server dedups unchanged batches by content hash).
    public func uploadFullLog() async -> Bool {
        await performSync(fullUpload: true)
    }

    /// Remove the data key from this device only. The server escrow is
    /// untouched, so the passphrase still unlocks it again later.
    public func forgetOnThisDevice() async {
        try? keychain.delete(for: Self.dataKeyKeychainKey)
        try? keychain.delete(for: KeychainHelper.Keys.syncDataKey) // sweep the legacy unscoped slot
        Self.clearEscrowFingerprint(base: ActivitiesServer.resolvedBaseURL)
        await refreshStatus()
    }

    // MARK: Internal

    /// Timings + counts from the pull→push core of one pass.
    struct PassResult {
        let cursorBefore: Int64
        let cursorAfter: Int64
        let pulled: Int
        let pushed: Int
        let downloadSeconds: Double
        let uploadSeconds: Double
    }

    let keychain = KeychainHelper.shared

    /// Account client for the *currently resolved* server. Rebuilt whenever the
    /// developer override changes the base URL, so the bearer, escrow calls,
    /// data-key slot, cursor and fingerprint always refer to the same server —
    /// a client captured at init once sent a staging token to prod after the
    /// override moved (2026-10-05).
    var client: SyncAccountClient {
        let base = ActivitiesServer.resolvedBaseURL
        if let cached = clientCache, cached.base == base {
            return cached.client
        }
        let fresh = SyncAccountClient()
        clientCache = (base, fresh)
        return fresh
    }

    static func message(for error: Error) -> String {
        if let accountError = error as? SyncAccountError {
            return accountError.errorDescription ?? "Something went wrong."
        }
        if let cwError = error as? CwError {
            return cwError.errorDescription ?? "Encryption error."
        }
        return error.localizedDescription
    }

    func recordProfile(_ profile: SyncProfile) {
        lastProfile = profile
        lastSyncSummary = SyncRunSummary(
            pushed: profile.pushed, pulled: profile.pulled, seconds: profile.totalSeconds
        )
    }

    func setPhase(_ newPhase: Phase) {
        phase = newPhase
    }

    func setStatus(_ newStatus: Status) {
        status = newStatus
    }

    func beginOperation() {
        phase = .idle
        operationStart = Date()
    }

    func endOperation() {
        operationStart = nil
    }

    // MARK: Private

    /// Sendable snapshot of a fresh escrow, safe to return across the actor.
    private struct EscrowMaterial: Sendable {
        let wrappedKeyB64: String
        let kdfParamsJson: String
        let dataKey: Data
    }

    private var clientCache: (base: String, client: SyncAccountClient)?

    /// Mint + wrap a fresh data key off the main actor. Argon2id is CPU-heavy
    /// by design, so running it on `@MainActor` would freeze the UI.
    nonisolated private static func deriveEscrow(passphrase: String) async throws -> EscrowMaterial {
        try await Task.detached(priority: .userInitiated) {
            let escrow = try createSyncEscrow(passphrase: passphrase)
            return EscrowMaterial(
                wrappedKeyB64: escrow.wrappedKeyB64,
                kdfParamsJson: escrow.kdfParamsJson,
                dataKey: escrow.dataKey
            )
        }.value
    }

    /// Recover the data key from the escrow off the main actor (Argon2id).
    nonisolated private static func recoverKey(
        passphrase: String,
        wrappedKeyB64: String,
        kdfParamsJson: String
    ) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try openSyncEscrow(
                passphrase: passphrase,
                wrappedKeyB64: wrappedKeyB64,
                kdfParamsJson: kdfParamsJson
            )
        }.value
    }

    /// Back up the cw-store at-rest key under this passphrase for offline
    /// recovery when the host provides a provisioner (best-effort).
    private func provision(_ passphrase: String) {
        guard let provisioner = Self.passphraseProvisioner else {
            return
        }
        Task { await provisioner(passphrase) }
    }
}
