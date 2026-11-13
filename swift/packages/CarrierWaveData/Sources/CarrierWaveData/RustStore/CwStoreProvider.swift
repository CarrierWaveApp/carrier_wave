import CarrierWaveCore
import Foundation
import Security

/// Single long-lived FieldStore for the on-disk cw-store (see `CwStoreLocation`). The importer,
/// mirror, and read source all use this one instance (the observer registry and
/// single-writer mutex must be shared). `opener` is injectable for tests.
public actor CwStoreProvider {
    // MARK: Lifecycle

    public init(opener: @escaping @Sendable () throws -> FieldStore = CwStoreProvider.appGroupOpener) {
        self.opener = opener
    }

    // MARK: Public

    public static let shared = CwStoreProvider()

    /// Opens the on-disk store with the device-local SQLCipher key.
    public static let appGroupOpener: @Sendable () throws -> FieldStore = {
        let url = try CwStoreLocation.storeURL()
        return try FieldStore.open(path: url.path, key: localEncryptionKey())
    }

    /// Whether `error` (from opening the store) means the file exists but cannot
    /// be decrypted with the current key — SQLCipher `file is not a database`
    /// (NOTADB). That is the orphaned-store signature (a lost/rotated at-rest
    /// key), distinct from a transient failure. Callers use it to offer recovery
    /// instead of silently degrading.
    public static func isUnopenableStoreError(_ error: Error) -> Bool {
        guard let cwError = error as? CwError, case let .Store(reason) = cwError else {
            return false
        }
        let lowered = reason.lowercased()
        // SQLCipher/SQLite signatures for "the file exists but can't be opened as
        // a valid decrypted database" — a lost/wrong key or on-disk corruption.
        // Match several so a wording change in one library version can't silently
        // hide the recovery path.
        let signatures = [
            "not a database", // SQLITE_NOTADB — wrong / lost key
            "file is encrypted", // some SQLCipher builds
            "malformed", // SQLITE_CORRUPT — "database disk image is malformed"
            "disk image is malformed",
            "database corruption",
        ]
        return signatures.contains { lowered.contains($0) }
    }

    public func store() throws -> FieldStore {
        if let opened {
            return opened
        }
        let instance = try opener()
        opened = instance
        return instance
    }

    /// Drop the cached instance so the next `store()` re-opens. Used after a
    /// rebuild swaps the underlying file, or to force a re-open attempt.
    public func reset() {
        opened = nil
    }

    /// Preserve an unopenable store by renaming it aside — **never deletes** —
    /// and drop the cached instance so the next `store()` creates a fresh store
    /// at the canonical path. Returns the archived URL (nil if no file existed).
    /// Any SQLite sidecars (`-wal`/`-shm`/`-journal`) are moved alongside so the
    /// fresh store starts clean.
    @discardableResult
    public func moveOrphanedStoreAside() throws -> URL? {
        opened = nil
        let url = try CwStoreLocation.storeURL()
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let directory = url.deletingLastPathComponent()
        let stamp = Int(Date().timeIntervalSince1970)
        // Never overwrite an earlier orphan — uniquify if the timestamp collides
        // (repeated rebuilds), so moveItem can't throw on an existing file.
        var archived = directory.appendingPathComponent("cw-store.orphaned-\(stamp).db")
        var counter = 1
        while fileManager.fileExists(atPath: archived.path) {
            archived = directory.appendingPathComponent("cw-store.orphaned-\(stamp)-\(counter).db")
            counter += 1
        }
        try fileManager.moveItem(at: url, to: archived)
        for suffix in ["-wal", "-shm", "-journal"] {
            let side = URL(fileURLWithPath: url.path + suffix)
            guard fileManager.fileExists(atPath: side.path) else {
                continue
            }
            try? fileManager.moveItem(at: side, to: URL(fileURLWithPath: archived.path + suffix))
        }
        // Preserved for recovery but re-derivable — keep orphaned copies out of
        // device / iCloud backups so they never bloat the user's backup.
        var mutableArchived = archived
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutableArchived.setResourceValues(values)
        return archived
    }

    // MARK: Internal

    static func localEncryptionKey() throws -> String {
        let keychain = KeychainHelper.shared

        // Read the existing key. CRITICAL: only "item not found" (genuine first
        // run) may fall through to generating a new key. Any OTHER keychain
        // error — notably errSecInteractionNotAllowed when the device is locked
        // on a background / pre-first-unlock launch — MUST propagate. Silently
        // regenerating the key on a transient read failure overwrites the good
        // key and permanently orphans the existing encrypted store, which then
        // fails to open with SQLCipher "file is not a database".
        let existing: String?
        do {
            existing = try keychain.readString(for: KeychainHelper.Keys.cwStoreEncryptionKey)
        } catch KeychainError.itemNotFound {
            existing = nil
        }
        if let existing, !existing.isEmpty {
            return existing
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw CwStoreImportError.keyGenerationFailed(status)
        }
        let key = Data(bytes).base64EncodedString()
        try keychain.save(key, for: KeychainHelper.Keys.cwStoreEncryptionKey)
        return key
    }

    // MARK: Private

    private let opener: @Sendable () throws -> FieldStore
    private var opened: FieldStore?
}
