import CarrierWaveCwFfi
import Foundation

// Bridge the Rust store's `StoreObserver` callback into Swift `AsyncStream`s —
// the replacement for SwiftData `@Query` reactivity (migration plan §5, the
// flagged risk; prototyped on the QSO path in `docs/plans/2026-06-13-rust-core-handoff.md`).
//
// Rust fires `onChange` from whichever thread performed the mutation, *after*
// releasing the store's DB lock, so an observer may re-fetch without deadlock
// (proven by `callback_can_reenter_store_without_deadlock` in cw-ffi). The
// `AsyncStream` further decouples notification from re-fetch: the consumer's
// `for await` runs on its own task, so the upsert's `notify` has fully returned
// before any re-fetch re-locks the store.

public extension FieldStore {
    /// A stream of store changes, optionally filtered to a single `table`.
    ///
    /// Replaces a SwiftData `@Query`: pair it with an explicit bounded fetch in
    /// a `.task`, re-fetching whenever the stream yields.
    ///
    ///     .task {
    ///         await reload()
    ///         for await _ in store.changes(for: .qso) {
    ///             await reload()
    ///         }
    ///     }
    ///
    /// The observer is registered for the stream's lifetime and removed when the
    /// consuming task is cancelled or the stream terminates. The buffering
    /// policy keeps only the newest change, so a burst of upserts collapses into
    /// a single refresh signal (the `@Query`-invalidation semantic — re-fetch
    /// latest, don't replay every row event).
    func changes(for table: FfiStoreTable? = nil) -> AsyncStream<FfiStoreChange> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let observer = ContinuationStoreObserver(continuation: continuation, table: table)
            let token = addObserver(observer: observer)
            continuation.onTermination = { @Sendable [weak self] _ in
                self?.removeObserver(token: token)
            }
        }
    }
}

// MARK: - ContinuationStoreObserver

/// Forwards Rust `onChange` callbacks into an `AsyncStream` continuation.
/// `@unchecked Sendable`: the only stored state is an `AsyncStream.Continuation`
/// (itself `Sendable`) and an immutable optional filter.
private final class ContinuationStoreObserver: StoreObserver, @unchecked Sendable {
    // MARK: Lifecycle

    init(continuation: AsyncStream<FfiStoreChange>.Continuation, table: FfiStoreTable?) {
        self.continuation = continuation
        self.table = table
    }

    // MARK: Internal

    func onChange(change: FfiStoreChange) {
        if let table, change.table != table {
            return
        }
        continuation.yield(change)
    }

    // MARK: Private

    private let continuation: AsyncStream<FfiStoreChange>.Continuation
    private let table: FfiStoreTable?
}
