// cw-store Key Recovery (offline, passphrase-based)
//
// Makes the cw-store SQLCipher at-rest key recoverable by the user's sync
// passphrase WITHOUT changing the key or contacting the server. When the
// passphrase is captured (SyncKeyService create/unlock), we wrap the current
// at-rest key under an Argon2id KEK and cache the envelope locally in the App
// Group. If the Keychain key is later lost, the user re-enters the passphrase
// and we unwrap the key offline and restore it. See
// docs/plans/2026-07-08-cwstore-passphrase-recovery.md.

import CarrierWaveCore
import CarrierWaveData
import UIKit

// MARK: - CwStoreKeyRecovery

enum CwStoreKeyRecovery {
    // MARK: Internal

    /// Whether a local recovery envelope exists — i.e. offline passphrase
    /// recovery is available for this install.
    static var hasRecoveryBlob: Bool {
        guard let url = sidecarURL else {
            return false
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Provision (or refresh) the local recovery envelope: wrap the CURRENT
    /// cw-store at-rest key under `passphrase` and cache it in the App Group.
    /// No-op when the at-rest key isn't a 32-byte value in the Keychain. Runs
    /// off-main — Argon2id is deliberately CPU-heavy.
    static func provision(passphrase: String) async {
        // CRITICAL: only back up a key that actually OPENS the store. If the
        // store is already orphaned (Keychain holds a stale key), wrapping that
        // key would cache an envelope that "recovers" a key which still can't
        // decrypt the file — a false sense of recoverability. A successful
        // open() proves the current Keychain key is the store's real key.
        guard await (try? CwStoreProvider.shared.store()) != nil else {
            return
        }
        guard let url = sidecarURL,
              let keyString = try? KeychainHelper.shared.readString(
                  for: KeychainHelper.Keys.cwStoreEncryptionKey
              ),
              let keyData = Data(base64Encoded: keyString),
              keyData.count == 32
        else {
            return
        }
        await Task.detached(priority: .utility) {
            do {
                let envelope = try createKeyEscrow(passphrase: passphrase, key: keyData)
                let blob = Blob(
                    wrappedKeyB64: envelope.wrappedKeyB64,
                    kdfParamsJson: envelope.kdfParamsJson
                )
                let data = try JSONEncoder().encode(blob)
                try data.write(to: url, options: [.atomic, .completeFileProtection])
            } catch {
                await SyncDebugLog.shared.error(
                    "cw-store recovery: failed to provision envelope: \(error.localizedDescription)"
                )
            }
        }.value
    }

    /// OFFLINE recovery: unwrap the at-rest key from the local envelope using
    /// `passphrase`, restore it to the Keychain, and re-open the store. Returns
    /// true only if the store then opens (the recovered key matched the file).
    static func recover(passphrase: String) async -> Bool {
        guard let url = sidecarURL,
              let data = try? Data(contentsOf: url),
              let blob = try? JSONDecoder().decode(Blob.self, from: data)
        else {
            return false
        }
        guard let storePath = storeURL?.path else {
            return false
        }
        return await Task.detached(priority: .userInitiated) {
            do {
                let keyBytes = try openSyncEscrow(
                    passphrase: passphrase,
                    wrappedKeyB64: blob.wrappedKeyB64,
                    kdfParamsJson: blob.kdfParamsJson
                )
                let keyString = keyBytes.base64EncodedString()
                // Verify the recovered key actually decrypts the store BEFORE
                // persisting it — never overwrite the Keychain with a key that
                // doesn't open the file. FieldStore.open throws NOTADB on a wrong
                // key via its forced keyed read.
                _ = try FieldStore.open(path: storePath, key: keyString)
                try KeychainHelper.shared.save(
                    keyString, for: KeychainHelper.Keys.cwStoreEncryptionKey
                )
                await CwStoreProvider.shared.reset()
                return true
            } catch {
                return false
            }
        }.value
    }

    // MARK: Private

    nonisolated private struct Blob: Codable {
        let wrappedKeyB64: String
        let kdfParamsJson: String
    }

    /// The encrypted store (see `CwStoreLocation`).
    private static var storeURL: URL? {
        try? CwStoreLocation.storeURL()
    }

    /// Sidecar next to `cw-store.db`.
    private static var sidecarURL: URL? {
        try? CwStoreLocation.recoverySidecarURL()
    }
}
