import Foundation

// MARK: - CwStoreLocation

/// Where `cw-store.db` lives, plus the one-time move out of the App Group.
///
/// On iOS the store lives in the app's private Application Support directory,
/// NOT the shared App Group container. RunningBoard kills a suspended app that
/// holds a file lock inside an App Group container (`0xdead10cc`); a cw-store
/// SQLite read or commit in flight when the user switches apps was the source
/// of nearly every TestFlight crash. Locks on files in the app's own container
/// don't trigger that kill, so moving the file removes the whole crash class
/// instead of guarding each call site with a background-task assertion. No
/// extension opens cw-store (the widget reads SwiftData; the watch can't see
/// the phone's App Group), so nothing relied on the shared location.
///
/// macOS keeps the App Group location: there is no suspension kill there.
/// The macOS group ID is the team-prefixed form Apple requires there: macOS 15+
/// verifies a `<TeamID>.` group from the code signature, whereas an iOS-style
/// `group.` ID needs a provisioning profile that carries the entitlement and
/// otherwise raises the "would like to access data from other apps" prompt on
/// every launch. `MacGroupContainerMigration` moves existing data across once.
public enum CwStoreLocation {
    // MARK: Public

    #if os(macOS)
        public static let defaultAppGroupID = "7UE4RDLUSX.com.jsvana.FullDuplex"
        /// The iOS-style container CW Sweep used before the team-prefixed one.
        public static let legacyMacAppGroupID = "group.com.jsvana.FullDuplex"
    #else
        public static let defaultAppGroupID = "group.com.jsvana.FullDuplex"
    #endif
    public static let storeFileName = "cw-store.db"
    public static let recoverySidecarName = "cw-store.recovery.json"

    /// Canonical store URL. On iOS this performs the one-time migration out of
    /// the App Group on first call in the process (before anything can open
    /// the store), and caches the answer.
    public static func storeURL(appGroupID: String = defaultAppGroupID) throws -> URL {
        #if os(iOS)
            try resolvedURL.resolve {
                let legacyDirectory = try appGroupDirectory(appGroupID)
                let privateDirectory = try FileManager.default
                    .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    .appendingPathComponent("CwStore", isDirectory: true)
                return try migrate(from: legacyDirectory, to: privateDirectory)
                    .appendingPathComponent(storeFileName)
            }
        #else
            return try appGroupDirectory(appGroupID).appendingPathComponent(storeFileName)
        #endif
    }

    /// The recovery-envelope sidecar, always next to the store.
    public static func recoverySidecarURL(appGroupID: String = defaultAppGroupID) throws -> URL {
        try storeURL(appGroupID: appGroupID)
            .deletingLastPathComponent()
            .appendingPathComponent(recoverySidecarName)
    }

    // MARK: Internal

    enum MigrationError: Error {
        /// A file exists at both locations; refusing to overwrite either.
        case conflict(String)
        /// Some files moved and others didn't. The store is split across both
        /// directories, so neither may be opened until a later launch finishes
        /// the move (a hot rollback journal must stay with its database).
        case incomplete(underlying: Error)
    }

    /// Move every cw-store file (database, SQLite sidecars, recovery sidecar,
    /// orphaned copies) from `legacy` to `destination` and return the directory
    /// the store should be opened from.
    ///
    /// - Nothing to move → `destination`.
    /// - Everything moved → `destination`.
    /// - The first move fails and no earlier attempt moved anything (e.g. a
    ///   pre-first-unlock background launch) → `legacy`: the old location is
    ///   still whole; the next launch retries.
    /// - A later move fails → throws `.incomplete`; the next launch moves the
    ///   remainder (already-moved files are gone from `legacy`).
    static func migrate(
        from legacy: URL,
        to destination: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let names = try storeFiles(in: legacy, fileManager: fileManager)
        guard !names.isEmpty else {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            return destination
        }
        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            return legacy
        }

        // An earlier interrupted attempt may already have moved some files; if
        // so the legacy directory is no longer whole and must not be opened.
        var movedAny = try !storeFiles(in: destination, fileManager: fileManager).isEmpty
        for name in names {
            let source = legacy.appendingPathComponent(name)
            let target = destination.appendingPathComponent(name)
            do {
                if fileManager.fileExists(atPath: target.path) {
                    throw MigrationError.conflict(name)
                }
                try fileManager.moveItem(at: source, to: target)
                movedAny = true
            } catch {
                guard movedAny else {
                    return legacy
                }
                throw MigrationError.incomplete(underlying: error)
            }
        }
        return destination
    }

    // MARK: Private

    #if os(iOS)
        /// Resolved once per process: the migration must run before the first
        /// open, and every later caller must see the same answer.
        private static let resolvedURL = ResolvedURL()
    #endif

    private static func appGroupDirectory(_ appGroupID: String) throws -> URL {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else {
            throw CwStoreImportError.appGroupUnavailable(appGroupID)
        }
        return container
    }

    /// cw-store files present in `directory`, SQLite sidecars before their
    /// databases. Matches `cw-store.db`, `cw-store.db-journal|-wal|-shm`,
    /// `cw-store.recovery.json`, and `cw-store.orphaned-*.db` (+ sidecars).
    private static func storeFiles(in directory: URL, fileManager: FileManager) throws -> [String] {
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }
        let names = try fileManager.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("cw-store.") }
        let sidecarSuffixes = ["-journal", "-wal", "-shm"]
        let sidecars = names.filter { name in sidecarSuffixes.contains { name.hasSuffix($0) } }
        let rest = names.filter { !sidecars.contains($0) }
        return sidecars.sorted() + rest.sorted()
    }
}

// MARK: - ResolvedURL

/// Lock-protected memo. A failed resolve is not cached, so a later call retries.
private final class ResolvedURL: @unchecked Sendable {
    // MARK: Internal

    func resolve(_ compute: () throws -> URL) throws -> URL {
        try lock.withLock {
            if let value {
                return value
            }
            let computed = try compute()
            value = computed
            return computed
        }
    }

    // MARK: Private

    private let lock = NSLock()
    private var value: URL?
}
