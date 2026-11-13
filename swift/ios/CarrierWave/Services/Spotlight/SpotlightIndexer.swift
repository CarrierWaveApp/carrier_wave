import CoreSpotlight
import OSLog
import UIKit

// MARK: - SpotlightConstants

/// Identifier constants shared between the indexer and the reindex actor.
nonisolated enum SpotlightConstants {
    /// Domain identifier applied to every QSO searchable item. Used for
    /// bulk deindex via `deleteSearchableItems(withDomainIdentifiers:)`.
    static let qsoDomainIdentifier = "carrierwave.qso"

    /// Domain identifier applied to every LoggingSession searchable item.
    static let sessionDomainIdentifier = "carrierwave.session"

    /// UserDefaults key storing the last-indexed schema version. Bump
    /// ``currentSchemaVersion`` to force a full rebuild on next launch.
    static let schemaVersionKey = "spotlight.indexedSchemaVersion"

    /// UserDefaults key storing the timestamp of the last incremental
    /// reindex pass. Records modified after this time are picked up.
    static let lastIncrementalKey = "spotlight.lastIncrementalReindex"

    /// Schema version for the shape of indexed items. Bump whenever
    /// ``QSOSpotlightSnapshot`` or ``SessionSpotlightSnapshot`` gains a
    /// new indexed field so existing users get a full rebuild.
    ///
    /// History:
    /// - 1: Initial schema.
    /// - 2: Forced rebuild for users whose initial indexing pass never
    ///   populated the index (bug where existing logs showed no results
    ///   in Spotlight search until reinstall).
    static let currentSchemaVersion = 2

    /// Build the unique identifier used for a QSO searchable item.
    static func qsoUniqueIdentifier(id: UUID) -> String {
        "\(qsoDomainIdentifier)/\(id.uuidString)"
    }

    /// Build the unique identifier used for a LoggingSession searchable item.
    static func sessionUniqueIdentifier(id: UUID) -> String {
        "\(sessionDomainIdentifier)/\(id.uuidString)"
    }

    /// Parse a unique identifier emitted by this indexer back into an
    /// entity kind and UUID. Returns `nil` for identifiers produced by
    /// other apps or older schema versions.
    static func parseUniqueIdentifier(_ value: String) -> SpotlightEntity? {
        let components = value.split(separator: "/", maxSplits: 1)
        guard components.count == 2, let uuid = UUID(uuidString: String(components[1])) else {
            return nil
        }
        switch String(components[0]) {
        case qsoDomainIdentifier: return .qso(id: uuid)
        case sessionDomainIdentifier: return .session(id: uuid)
        default: return nil
        }
    }
}

// MARK: - QueryCounter

/// Thread-safe integer accumulator used by
/// ``SpotlightIndexer/queryOwnIndexedItemCount()`` to collect batch
/// counts from `CSSearchQuery.foundItemsHandler` callbacks (which
/// may fire from a background queue) before the completion handler
/// reads the total.
///
/// Declared `nonisolated` because the iOS target has
/// `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`, which would otherwise
/// make every method of this class implicitly `@MainActor`-isolated.
/// CoreSpotlight invokes `foundItemsHandler` from a background
/// dispatch queue, and calling a `@MainActor` method from there
/// traps in Swift 6 runtime isolation checks
/// (`_swift_task_checkIsolatedSwift` → `dispatch_assert_queue_fail`).
nonisolated private final class QueryCounter: @unchecked Sendable {
    // MARK: Internal

    var total: Int {
        lock.withLock { stored }
    }

    func add(_ count: Int) {
        lock.withLock { stored += count }
    }

    // MARK: Private

    private let lock = NSLock()
    private var stored = 0
}

// MARK: - SpotlightEntity

/// Result of parsing a CoreSpotlight unique identifier back into an app entity.
enum SpotlightEntity: Equatable {
    case qso(id: UUID)
    case session(id: UUID)
}

// MARK: - SpotlightIndexer

/// Main-actor entry point for sending ``CSSearchableItem`` updates to
/// ``CSSearchableIndex/default()``.
///
/// All heavy work (SwiftData fetches, snapshot construction) happens in
/// ``SpotlightReindexActor``. This type is a thin wrapper that accepts
/// already-built ``Sendable`` snapshots and forwards them to CoreSpotlight.
@MainActor
final class SpotlightIndexer {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = SpotlightIndexer()

    /// Whether CoreSpotlight indexing is available on this device.
    var isAvailable: Bool {
        CSSearchableIndex.isIndexingAvailable()
    }

    /// Index (or re-index) a batch of QSOs. Safe to call with an empty array.
    /// Returns the error from `CSSearchableIndex.indexSearchableItems`
    /// if the callback reported one, otherwise `nil`.
    func indexQSOs(_ snapshots: [QSOSpotlightSnapshot]) async -> Error? {
        guard !snapshots.isEmpty, isAvailable else {
            return nil
        }
        let items = snapshots.map { snapshot -> CSSearchableItem in
            CSSearchableItem(
                uniqueIdentifier: SpotlightConstants.qsoUniqueIdentifier(id: snapshot.id),
                domainIdentifier: SpotlightConstants.qsoDomainIdentifier,
                attributeSet: snapshot.makeAttributeSet()
            )
        }
        return await indexItems(items)
    }

    /// Index (or re-index) a batch of logging sessions. Safe to call empty.
    /// Returns the error from `CSSearchableIndex.indexSearchableItems`
    /// if the callback reported one, otherwise `nil`.
    func indexSessions(_ snapshots: [SessionSpotlightSnapshot]) async -> Error? {
        guard !snapshots.isEmpty, isAvailable else {
            return nil
        }
        let items = snapshots.map { snapshot -> CSSearchableItem in
            CSSearchableItem(
                uniqueIdentifier: SpotlightConstants.sessionUniqueIdentifier(id: snapshot.id),
                domainIdentifier: SpotlightConstants.sessionDomainIdentifier,
                attributeSet: snapshot.makeAttributeSet()
            )
        }
        return await indexItems(items)
    }

    /// Remove a set of QSOs from the index by their identifiers.
    func deindexQSOs(ids: [UUID]) async {
        guard !ids.isEmpty, isAvailable else {
            return
        }
        let identifiers = ids.map(SpotlightConstants.qsoUniqueIdentifier(id:))
        await deleteItems(identifiers: identifiers)
    }

    /// Remove a set of logging sessions from the index by their identifiers.
    func deindexSessions(ids: [UUID]) async {
        guard !ids.isEmpty, isAvailable else {
            return
        }
        let identifiers = ids.map(SpotlightConstants.sessionUniqueIdentifier(id:))
        await deleteItems(identifiers: identifiers)
    }

    /// Remove every item this app has contributed to CoreSpotlight. Used
    /// when rebuilding the index after a schema version bump.
    func deindexAll() async {
        guard isAvailable else {
            return
        }
        await withCheckedContinuation { continuation in
            CSSearchableIndex.default().deleteSearchableItems(
                withDomainIdentifiers: [
                    SpotlightConstants.qsoDomainIdentifier,
                    SpotlightConstants.sessionDomainIdentifier,
                ]
            ) { error in
                if let error {
                    Self.logger.error("deindexAll failed: \(error.localizedDescription, privacy: .public)")
                }
                continuation.resume()
            }
        }
    }

    /// Diagnostic: run a `CSSearchQuery` against our own CoreSpotlight
    /// contributions and return how many items iOS actually has indexed
    /// under our QSO and session domains. Used by the debug view to
    /// answer the question "did our indexSearchableItems calls actually
    /// land?" when the callbacks all returned success but nothing shows
    /// up in Spotlight.
    ///
    /// Returns the match count on success, or an `Error` describing the
    /// query failure. A count of 0 when a full rebuild has completed is
    /// strong evidence the index is being rejected silently.
    func queryOwnIndexedItemCount() async -> Result<Int, Error> {
        guard isAvailable else {
            return .success(0)
        }
        let queryString =
            "(domainIdentifier == \"\(SpotlightConstants.qsoDomainIdentifier)\") || " +
            "(domainIdentifier == \"\(SpotlightConstants.sessionDomainIdentifier)\")"
        return await withCheckedContinuation { continuation in
            let context = CSSearchQueryContext()
            context.fetchAttributes = ["title"]
            let query = CSSearchQuery(queryString: queryString, queryContext: context)
            let counter = QueryCounter()
            // `@Sendable` on both closures prevents Swift from inferring
            // them as `@MainActor` (the iOS target default), which would
            // otherwise cause a runtime trap when CoreSpotlight calls
            // them from its background dispatch queue.
            query.foundItemsHandler = { @Sendable items in
                counter.add(items.count)
            }
            query.completionHandler = { @Sendable error in
                if let error {
                    continuation.resume(returning: .failure(error))
                } else {
                    continuation.resume(returning: .success(counter.total))
                }
            }
            query.start()
        }
    }

    // MARK: Private

    /// `nonisolated` because the CoreSpotlight completion handlers run
    /// off the main actor and log their outcome via this static.
    nonisolated private static let logger = Logger(
        subsystem: "app.carrierwave", category: "SpotlightIndexer"
    )

    private func indexItems(_ items: [CSSearchableItem]) async -> Error? {
        await withCheckedContinuation { continuation in
            CSSearchableIndex.default().indexSearchableItems(items) { error in
                if let error {
                    Self.logger.error(
                        "indexSearchableItems failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
                continuation.resume(returning: error)
            }
        }
    }

    private func deleteItems(identifiers: [String]) async {
        await withCheckedContinuation { continuation in
            CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: identifiers) { error in
                if let error {
                    Self.logger.error(
                        "deleteSearchableItems failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
                continuation.resume()
            }
        }
    }
}

// MARK: - SpotlightDebugState

/// Observable state snapshot of the most recent (or in-progress) Spotlight
/// reindex pass. Exposed to ``SpotlightDebugView`` so users without Console
/// access can see what the reindexer is actually doing.
///
/// Written exclusively from ``SpotlightReindexActor`` via ``MainActor/run(_:)``.
@MainActor
@Observable
final class SpotlightDebugState {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = SpotlightDebugState()

    var isRunning = false
    var currentPhase: String = "idle"
    var lastEntryAt: Date?
    var lastCompletedAt: Date?
    var lastAvailable: Bool?
    var lastPath: String = "none"
    var storedVersion: Int = -1
    var currentVersion: Int = SpotlightConstants.currentSchemaVersion
    var lastQSOIndexed: Int = 0
    var lastSessionIndexed: Int = 0
    var lastError: String?
    var lastElapsed: TimeInterval?

    /// Most recent error reported by `CSSearchableIndex.indexSearchableItems`
    /// via its completion callback, surfaced to the debug view so users
    /// without Console access can spot silent indexing failures.
    var lastIndexError: String?

    /// Number of per-batch `indexSearchableItems` callbacks that reported
    /// an error during the most recent pass. Useful to distinguish "one
    /// transient failure" from "every batch is failing".
    var indexErrorCount: Int = 0

    /// Result of the most recent "query own index" diagnostic: count of
    /// items iOS actually has indexed under our QSO + session domains.
    /// `nil` means the diagnostic has not been run yet. A value of 0
    /// after a completed full rebuild is strong evidence that
    /// `indexSearchableItems` callbacks are lying about success.
    var lastQueryCount: Int?

    /// Error from the most recent query, if the `CSSearchQuery`
    /// completion handler reported one.
    var lastQueryError: String?

    /// Timestamp of the most recent query diagnostic run.
    var lastQueryAt: Date?

    /// `true` while a query diagnostic is in flight.
    var isQueryRunning = false
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted from the CarrierWaveApp `.onContinueUserActivity` handler when
    /// a user taps a QSO Spotlight result. UserInfo contains `"qsoID": UUID`.
    static let didOpenSpotlightQSO = Notification.Name("didOpenSpotlightQSO")

    /// Posted from the CarrierWaveApp `.onContinueUserActivity` handler when
    /// a user taps a logging session Spotlight result. UserInfo contains
    /// `"sessionID": UUID`.
    static let didOpenSpotlightSession = Notification.Name("didOpenSpotlightSession")
}
