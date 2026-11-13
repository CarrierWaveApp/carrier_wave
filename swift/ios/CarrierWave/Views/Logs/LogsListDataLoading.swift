import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - Data Loading & Query Execution

extension LogsListContentView {
    /// Trimmed current query string. Empty means "all non-hidden, newest first".
    var currentQuery: String {
        debouncedQueryText.trimmingCharacters(in: .whitespaces)
    }

    /// The logbook snapshot source. The shared Rust store is now the only backend
    /// (the Swift query engine was retired); if it can't be opened there is nothing
    /// to show — in normal operation the store is populated by the QSO mirror.
    func currentSource() async -> any LogbookSnapshotSource {
        if let store = try? await CwStoreProvider.shared.store() {
            return RustLogbookSource(rustSource: RustQSOReadSource(store: store))
        }
        return EmptyLogbookSource()
    }

    /// One-time initial load (guarded against tab-switch re-fetch). Sets up service
    /// config + whole-log count, then loads the first page of the empty query.
    func loadInitialQSOs() async {
        guard !didInitialLoad else {
            isLoadingInitial = false
            return
        }
        isLoadingInitial = true
        loadServiceConfiguration()
        await refreshQSOCount()
        await reload(firstPageLimit: Self.initialBatchSize)
        didInitialLoad = true
        isLoadingInitial = false
    }

    func refreshAfterNewQSO() async {
        // In `.on` the mirror applies the SwiftData write to cw-store asynchronously;
        // drain it before re-paging so the list never shows a stale row.
        if qsoMode == .on {
            await CwStoreMirrorRegistry.current?.drain()
        }
        await refreshQSOCount()
        let limit = min(max(snapshots.count, Self.initialBatchSize), BoundedDescriptor<QSO>.maxLimit)
        await reload(firstPageLimit: limit)
    }

    func loadMoreQSOs() async {
        guard !isLoadingMore, hasMoreRows else {
            return
        }
        isLoadingMore = true
        let query = currentQuery
        let source = await currentSource()
        if let page = try? await source.page(
            query: query,
            limit: Self.loadMoreBatchSize,
            offset: snapshots.count
        ) {
            snapshots.append(contentsOf: page)
        }
        isLoadingMore = false
    }

    func refreshQSOCount() async {
        totalQSOCount = (try? modelContext.boundedCount(
            QSO.self,
            predicate: #Predicate { !$0.isHidden }
        )) ?? 0
    }

    /// Parse + analyze the query (for errors / slow-query warnings), gate on
    /// confirmation, then load the first page. Runs on every debounced query change.
    func executeQuery() async {
        // The first empty invocation is handled by `loadInitialQSOs`.
        guard didInitialLoad else {
            return
        }
        let trimmed = currentQuery

        // Already showing this query's results (redundant fire / tab switch).
        if trimmed == lastLoadedQuery {
            return
        }

        if trimmed.isEmpty {
            queryAnalysis = nil
            proceedWithSlowQuery = false
            await reload(firstPageLimit: Self.initialBatchSize)
            return
        }

        // Parse + analyze in the shared Rust core. `analyzeViaRust` throws on a
        // parse error, which we treat like the old `.failure` case (keep current
        // results). The Rust store backend re-parses the same string when it runs
        // the query — one parser everywhere.
        do {
            let analysis = try QueryAnalyzer.analyzeViaRust(trimmed, qsoCount: totalQSOCount)
            queryAnalysis = analysis

            // Hold for confirmation on expensive queries over a large log.
            if analysis.requiresConfirmation, !proceedWithSlowQuery, totalQSOCount > 5_000 {
                snapshots = []
                return
            }

            isSearching = true
            await reload(firstPageLimit: Self.searchBatchSize)
            isSearching = false
        } catch {
            // Parse error — keep showing current results, as before.
            queryAnalysis = nil
        }
    }

    /// Reset the list to the first page of the current query and refresh the
    /// match count that drives "Load More".
    func reload(firstPageLimit: Int) async {
        let query = currentQuery
        let source = await currentSource()
        do {
            snapshots = try await source.page(query: query, limit: firstPageLimit, offset: 0)
            currentMatchCount = try await source.count(query: query)
            lastLoadedQuery = query
        } catch {
            snapshots = []
            currentMatchCount = 0
            lastLoadedQuery = query
        }
    }

    /// Soft-delete the QSOs behind the given snapshots, bridging from the snapshot
    /// id to the live `QSO` (SwiftData is still the system of record).
    func deleteSnapshots(_ toDelete: [QSORowSnapshot]) {
        let ids = Set(toDelete.map(\.id))
        softDeleteQSOs(LogbookIDBridge.fetchQSOs(ids: ids, in: modelContext))
    }

    /// Append a suggested filter to the search field (from the slow-query banner).
    func addSuggestedFilter(_ suggestion: String) {
        if queryText.isEmpty {
            queryText = suggestion
        } else {
            queryText = "\(queryText) \(suggestion)"
        }
    }
}
