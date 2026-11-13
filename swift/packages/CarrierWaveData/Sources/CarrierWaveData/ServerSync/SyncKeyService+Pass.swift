import CarrierWaveCore
import Foundation

// MARK: - Sync pass driver, cursor + seeded + fingerprint persistence

public extension SyncKeyService {
    // MARK: Public

    /// Whether this install holds the E2E data key for the active server —
    /// the enrollment gate for background and timer-driven passes.
    nonisolated static var isEnrolledForActiveServer: Bool {
        (try? KeychainHelper.shared.read(for: dataKeyKeychainKey)) != nil
    }

    /// Whether this server has ever completed a sync pass from this install.
    /// Keyed per base URL (like the cursor): dirty flags are cleared by pushes
    /// to *any* server, so switching servers (staging → prod) must re-seed or
    /// the new server never receives the existing log.
    nonisolated static func isSeeded(base: String) -> Bool {
        UserDefaults.standard.bool(forKey: "syncSeeded.\(base)")
    }

    nonisolated static func loadCursor(base: String) -> Int64 {
        Int64(UserDefaults.standard.integer(forKey: cursorKey(base: base)))
    }

    nonisolated static func saveCursor(_ value: Int64, base: String) {
        UserDefaults.standard.set(Int(value), forKey: cursorKey(base: base))
    }

    /// Fingerprint of the server escrow blob this device's key was minted
    /// from (create) or recovered from (unlock). Compared against the
    /// server's current escrow before every push — see `SyncEscrowValidation`.
    nonisolated static func loadEscrowFingerprint(base: String) -> String? {
        UserDefaults.standard.string(forKey: "syncEscrowFingerprint.\(base)")
    }

    nonisolated static func saveEscrowFingerprint(_ fingerprint: String, base: String) {
        UserDefaults.standard.set(fingerprint, forKey: "syncEscrowFingerprint.\(base)")
    }

    nonisolated static func clearEscrowFingerprint(base: String) {
        UserDefaults.standard.removeObject(forKey: "syncEscrowFingerprint.\(base)")
    }

    /// One pull→push pass with no UI service instance: used by the iOS
    /// `BGAppRefreshTask`, the `CloudSyncJournalEngine` server-sync runner, and
    /// CW Sweep's timer. Deliberately conservative: runs only when this server
    /// has already been seeded by a user-initiated foreground sync (never kicks
    /// off a full-log seed in a background window) and re-validates the local
    /// key against the server escrow before pushing.
    @discardableResult
    static func runBackgroundPass(trigger: String) async -> Bool {
        guard !passInFlight else {
            return false
        }
        passInFlight = true
        defer { passInFlight = false }

        let base = ActivitiesServer.resolvedBaseURL
        guard Self.isSeeded(base: base),
              let keyData = try? KeychainHelper.shared.read(for: dataKeyKeychainKey)
        else {
            ServerSyncLog.info("Server sync (\(trigger)): skipped — not enrolled or not yet seeded for \(base)")
            return false
        }
        let client = SyncAccountClient()
        guard let bearer = await client.syncAuthToken() else {
            ServerSyncLog.info("Server sync (\(trigger)): skipped — no account session (email sign-in required)")
            return false
        }
        do {
            guard try await escrowAllowsPush(client: client, base: base, trigger: trigger) else {
                return false
            }
            let store = try await CwStoreProvider.shared.store()
            var cursor = loadCursor(base: base)
            let pull = try await pullOffMain(
                store: store, baseURL: base, bearer: bearer, dataKey: keyData, sinceSeq: cursor
            )
            cursor = max(cursor, pull.highWater)
            let push = try await pushOffMain(store: store, baseURL: base, bearer: bearer, dataKey: keyData)
            cursor = max(cursor, push.highWater)
            saveCursor(cursor, base: base)
            ServerSnapshotCoordinator.recordPushed(push.pushed, base: base)
            ServerSyncLog.info("Server sync (\(trigger)): pushed \(push.pushed), pulled \(pull.pulled)")
            return true
        } catch {
            ServerSyncLog.error("Server sync (\(trigger)) failed: \(error.localizedDescription)")
            return false
        }
    }

    /// After the user wipes the local logbook (CAR-264), drop every per-base
    /// cursor and seeded flag so the next pull replays the full journal from
    /// seq 0 (repopulating the emptied store) and no background pass pushes
    /// the emptied store as if it were still seeded. The escrow fingerprint
    /// stays — wiping the log does not change the data key.
    static func resetForLocalWipe() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix("syncCursor.") || key.hasPrefix("syncSeeded.")
        {
            defaults.removeObject(forKey: key)
        }
        ServerSyncLog.info("Server sync: local wipe — cursors + seeded flags reset for all servers")
    }

    // MARK: Internal

    /// Re-entrancy guard shared by every pass entry point: the journal-engine
    /// seam, the BG task, the Sweep timer, and the foreground `performSync` can
    /// all request passes; overlapping passes would race the shared cursor.
    internal static var passInFlight = false

    /// Outbound half — push dirty QSOs. Off-main (HTTP + crypto + store I/O).
    nonisolated internal static func pushOffMain(
        store: FieldStore,
        baseURL: String,
        bearer: String,
        dataKey: Data
    ) async throws -> (pushed: Int, highWater: Int64) {
        try await Task.detached(priority: .userInitiated) {
            let result = try syncRunPush(store: store, baseUrl: baseURL, bearer: bearer, dataKey: dataKey)
            return (Int(result.pushed), result.highWater)
        }.value
    }

    /// Inbound half — pull + merge remote QSOs from the persisted cursor.
    nonisolated internal static func pullOffMain(
        store: FieldStore,
        baseURL: String,
        bearer: String,
        dataKey: Data,
        sinceSeq: Int64
    ) async throws -> (pulled: Int, highWater: Int64) {
        // Detailed pull: the applied keys feed the host replica (CW Sweep's
        // SwiftData follower) so views that still read SwiftData see pulled rows.
        let (pulled, highWater, applied) = try await Task.detached(priority: .userInitiated) {
            let result = try syncRunPullDetailed(
                store: store, baseUrl: baseURL, bearer: bearer, dataKey: dataKey, sinceSeq: sinceSeq
            )
            return (Int(result.pulled), result.highWater, result.applied.map(SyncAppliedChange.init(ffi:)))
        }.value
        if !applied.isEmpty, let replica = ServerSyncReplicaRegistry.current {
            await replica.apply(applied)
        }
        return (pulled, highWater)
    }

    internal func performSync(fullUpload: Bool) async -> Bool {
        lastError = nil
        // Same re-entrancy guard as the headless passes — a manual sync
        // interleaving with a journal-engine/BG pass would race the cursor.
        guard !Self.passInFlight else {
            lastError = "A sync pass is already running."
            return false
        }
        Self.passInFlight = true
        defer { Self.passInFlight = false }
        guard let keyData = try? keychain.read(for: Self.dataKeyKeychainKey) else {
            lastError = "This device isn't set up for sync yet."
            return false
        }
        guard let bearer = await client.syncAuthToken() else {
            lastError = "Carrier Wave Sync requires a signed-in account. Verify your callsign and email first."
            return false
        }
        beginOperation()
        let started = Date()
        defer { endOperation() }
        let base = ActivitiesServer.resolvedBaseURL
        // First pass against this server → seed the whole log automatically.
        let seeding = fullUpload || !Self.isSeeded(base: base)
        // Keep the process alive if backgrounded mid-sync (iOS): a cw-store
        // commit holding the SQLite lock at suspension is a 0xdead10cc kill.
        let suspensionGuard = SuspensionGuardFactory.make(name: "SyncKeyService.performSync")
        defer { suspensionGuard?.release() }
        let work = Task {
            await self.runSyncPass(base: base, seeding: seeding, started: started, bearer: bearer, keyData: keyData)
        }
        suspensionGuard?.onExpiration = { work.cancel() }
        return await withTaskCancellationHandler(operation: {
            await work.value
        }, onCancel: {
            work.cancel()
        })
    }

    /// Apply the escrow-fingerprint verdict for the active server. On refusal,
    /// updates `status`/`lastError` and returns `false`. A legacy install that
    /// seeded before fingerprints existed adopts the server's fingerprint once.
    internal func applyEscrowVerdict(serverBlob: SyncKeyBlob?) -> Bool {
        let base = ActivitiesServer.resolvedBaseURL
        let verdict = SyncEscrowValidation.verdict(
            serverWrappedKeyB64: serverBlob?.wrappedKeyB64,
            localFingerprint: Self.loadEscrowFingerprint(base: base),
            isSeeded: Self.isSeeded(base: base)
        )
        switch verdict {
        case .allow:
            return true
        case let .adoptAndAllow(fingerprint):
            Self.saveEscrowFingerprint(fingerprint, base: base)
            ServerSyncLog.info("Server sync: adopted escrow fingerprint for legacy enrollment on \(base)")
            return true
        case .refuseNoEscrow:
            setStatus(.notConfigured)
            lastError = "The server has no sync passphrase escrow, but this device holds a "
                + "sync key. Syncing would upload data no other device could ever read. "
                + "Set up a new passphrase first (this replaces the key on this device)."
            ServerSyncLog.error("Server sync: refused — local key present but no escrow on \(base)")
            return false
        case .refuseMismatch:
            setStatus(.lockedNeedsPassphrase)
            lastError = "This device's sync key doesn't match the server's passphrase escrow. "
                + "Re-enter your sync passphrase — syncing with this key would corrupt your synced log."
            ServerSyncLog.error("Server sync: refused — escrow fingerprint mismatch on \(base)")
            return false
        }
    }

    // MARK: Private

    nonisolated private static func cursorKey(base: String) -> String {
        "syncCursor.\(base)"
    }

    nonisolated private static func markSeeded(base: String) {
        UserDefaults.standard.set(true, forKey: "syncSeeded.\(base)")
    }

    /// Mark every QSO dirty (seed the full log) off the main actor.
    nonisolated private static func markAllDirtyOffMain(store: FieldStore) async throws -> Int64 {
        try await Task.detached(priority: .userInitiated) {
            try store.markAllDirty(entityType: "qso")
        }.value
    }

    /// Escrow-fingerprint gate for a headless pass. Legacy enrollments (seeded
    /// before fingerprints existed) adopt the server's fingerprint once;
    /// anything else that doesn't match refuses the push.
    private static func escrowAllowsPush(
        client: SyncAccountClient, base: String, trigger: String
    ) async throws -> Bool {
        let blob = try await client.getSyncKey()
        switch SyncEscrowValidation.verdict(
            serverWrappedKeyB64: blob?.wrappedKeyB64,
            localFingerprint: loadEscrowFingerprint(base: base),
            isSeeded: true
        ) {
        case .allow:
            return true
        case let .adoptAndAllow(fingerprint):
            saveEscrowFingerprint(fingerprint, base: base)
            return true
        case .refuseNoEscrow,
             .refuseMismatch:
            ServerSyncLog.error("Server sync (\(trigger)): refused — local key doesn't match escrow on \(base)")
            return false
        }
    }

    /// Pull first (from the persisted cursor) so we never re-download the
    /// entries we're about to push; then push and persist the new cursor.
    private func runPass(store: FieldStore, base: String, bearer: String, keyData: Data) async throws -> PassResult {
        let cursorBefore = Self.loadCursor(base: base)
        var cursor = cursorBefore
        setPhase(.downloading)
        let downloadStart = Date()
        let pull = try await Self.pullOffMain(
            store: store, baseURL: base, bearer: bearer, dataKey: keyData, sinceSeq: cursor
        )
        let downloadSeconds = Date().timeIntervalSince(downloadStart)
        cursor = max(cursor, pull.highWater)
        setPhase(.uploading)
        let uploadStart = Date()
        let push = try await Self.pushOffMain(store: store, baseURL: base, bearer: bearer, dataKey: keyData)
        let uploadSeconds = Date().timeIntervalSince(uploadStart)
        cursor = max(cursor, push.highWater)
        Self.saveCursor(cursor, base: base)
        Self.markSeeded(base: base)
        return PassResult(
            cursorBefore: cursorBefore, cursorAfter: cursor, pulled: pull.pulled, pushed: push.pushed,
            downloadSeconds: downloadSeconds, uploadSeconds: uploadSeconds
        )
    }

    /// Network + cw-store write body of a manual sync; never throws.
    private func runSyncPass(
        base: String, seeding: Bool, started: Date, bearer: String, keyData: Data
    ) async -> Bool {
        do {
            // Validate the local key against the server escrow BEFORE any
            // push. A key the escrow can't recover must never upload — that's
            // how a stale key once seeded 2k undecryptable QSOs into prod.
            setPhase(.contactingServer)
            let escrowBlob = try await client.getSyncKey()
            guard applyEscrowVerdict(serverBlob: escrowBlob) else {
                return false
            }
            let store = try await CwStoreProvider.shared.store()
            var prepareSeconds = 0.0
            if seeding {
                setPhase(.preparing)
                let mark = Date()
                _ = try await Self.markAllDirtyOffMain(store: store)
                prepareSeconds = Date().timeIntervalSince(mark)
            }
            let pass = try await runPass(store: store, base: base, bearer: bearer, keyData: keyData)
            let profile = SyncProfile(
                startedAt: started, server: base, fullUpload: seeding,
                prepareSeconds: prepareSeconds, downloadSeconds: pass.downloadSeconds,
                uploadSeconds: pass.uploadSeconds, totalSeconds: Date().timeIntervalSince(started),
                pushed: pass.pushed, pulled: pass.pulled,
                cursorBefore: pass.cursorBefore, cursorAfter: pass.cursorAfter
            )
            recordProfile(profile)
            ServerSnapshotCoordinator.recordPushed(pass.pushed, base: base)
            setPhase(.done)
            return true
        } catch {
            lastError = Self.message(for: error)
            return false
        }
    }
}
