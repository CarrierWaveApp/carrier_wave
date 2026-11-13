import Foundation

// MARK: - TombstoneStore

/// Persists the most recent tombstone watermark across launches so the
/// next `GET /v1/macros/tombstones?since=<lastSeen>` only returns deltas.
public protocol TombstoneStore: Sendable {
    var lastSeen: Date? { get }
    func setLastSeen(_ date: Date)
}

// MARK: - UserDefaultsTombstoneStore

/// `UserDefaults` is documented thread-safe; `@unchecked Sendable` is the
/// cleanest path until the SDK marks it `Sendable` explicitly.
public final class UserDefaultsTombstoneStore: TombstoneStore, @unchecked Sendable {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = .standard, key: String = "macrosRegistry.tombstones.lastSeen") {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    public var lastSeen: Date? {
        let raw = defaults.double(forKey: key)
        guard raw > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: raw)
    }

    public func setLastSeen(_ date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}

// MARK: - InMemoryTombstoneStore

/// Test-only in-memory store. Lives in the production target so the
/// `MacrosRegistryService` initializer can default to it in unit tests
/// without exposing internals.
public final class InMemoryTombstoneStore: TombstoneStore, @unchecked Sendable {
    // MARK: Lifecycle

    public init(initial: Date? = nil) {
        storage = initial
    }

    // MARK: Public

    public var lastSeen: Date? {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    public func setLastSeen(_ date: Date) {
        lock.lock(); defer { lock.unlock() }
        storage = date
    }

    // MARK: Private

    private let lock = NSLock()
    private var storage: Date?
}
