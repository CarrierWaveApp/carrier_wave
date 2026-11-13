import CarrierWaveData
import Foundation
import OSLog

// MARK: - BandScopeQueryRunner

/// Drives the SQL-backed band scope filter mode. Owns a `QueryReader`,
/// validates that the picked saved query has the required `spot_id`
/// column, and exposes a `Set<String>` of allowed spot IDs that
/// `BandMapView` filters on.
///
/// Re-runs the query every second. Polling is coarse on purpose: spot
/// observations land at the SpotAggregator's poll cadence (~30s) and a
/// 1s tick is more than fast enough to feel live without putting load
/// on SQLite. We can switch to GRDB `ValueObservation` later if it
/// becomes a bottleneck.
@MainActor
@Observable
final class BandScopeQueryRunner {
    // MARK: Lifecycle

    init() {}

    // MARK: Internal

    /// Outcome of validating a saved query for use as a band-scope
    /// filter. Carries the actual error so the picker UI can show it
    /// alongside the query name instead of greying out silently.
    enum SpotIDValidation: Equatable {
        case valid
        case missingColumn
        case executionFailed(String)
    }

    /// `nil` means "no filter active" — either widgets mode, no query
    /// picked, or query failed validation. `BandMapView` treats `nil`
    /// as "show all spots" and falls back to widget filters.
    private(set) var allowedSpotIDs: Set<String>?

    /// Surfaced to the UI as a red banner when non-nil. Cleared when the
    /// query starts running successfully again.
    private(set) var error: String?

    /// Validates that `sql` actually executes and emits a `spot_id`
    /// column. We RUN the statement (with rowLimit 1) rather than
    /// just preparing it — preparing catches syntax and structural
    /// errors but misses some SQLite quirks, and "did it run?" is the
    /// most honest signal for whether the query will work as a
    /// scope filter.
    func validate(sql: String) async -> SpotIDValidation {
        await ensureReader()
        guard let reader else {
            return .executionFailed("Query database not ready.")
        }
        do {
            let result = try await reader.run(sql: sql, rowLimit: 1)
            if result.columns.contains(where: { $0.name == "spot_id" }) {
                return .valid
            }
            return .missingColumn
        } catch let queryError as SQLQueryError {
            return .executionFailed(queryError.message)
        } catch {
            return .executionFailed(error.localizedDescription)
        }
    }

    /// Convenience wrapper for callers that only care about validity.
    func hasSpotIDColumn(sql: String) async -> Bool {
        await validate(sql: sql) == .valid
    }

    /// Set the active query. `nil` switches off the SQL filter (widgets
    /// mode). On failure the previous filter set is cleared and `error`
    /// is populated. Validation runs before the polling loop starts so
    /// the user sees the rejection synchronously after picking.
    func setQuery(_ query: SavedQuery?) {
        loopTask?.cancel()
        loopTask = nil

        guard let query else {
            currentSQL = nil
            allowedSpotIDs = nil
            error = nil
            return
        }

        Task {
            await ensureReader()
            guard let reader else {
                error = "Query database not ready."
                allowedSpotIDs = nil
                return
            }

            // Validate shape: the query must select a `spot_id` column.
            // We need spot_id to know which `EnrichedSpot`s to draw.
            // Reject loudly here rather than silently rendering empty.
            do {
                let columns = try await reader.columnNames(sql: query.sql)
                guard columns.contains("spot_id") else {
                    error = """
                    This query can't drive the band scope: it doesn't \
                    return a `spot_id` column. The band scope needs \
                    `spot_id` to know which spots to highlight. Add \
                    `spot_id` to your SELECT (e.g. \
                    `SELECT spot_id, callsign FROM scope.spots`).
                    """
                    allowedSpotIDs = nil
                    return
                }
            } catch let queryError as SQLQueryError {
                self.error = "Query failed to prepare: \(queryError.message)"
                allowedSpotIDs = nil
                return
            } catch let other as Error {
                self.error = "Query failed to prepare: \(other.localizedDescription)"
                allowedSpotIDs = nil
                return
            }

            currentSQL = query.sql
            error = nil
            startLoop()
        }
    }

    // MARK: Private

    private static let pollInterval: Duration = .seconds(1)
    private static let logger = Logger(
        subsystem: "com.jsvana.CWSweep",
        category: "BandScopeQueryRunner"
    )

    private var reader: QueryReader?
    private var currentSQL: String?
    private var loopTask: Task<Void, Never>?

    private func ensureReader() async {
        if reader != nil {
            return
        }
        guard let store = QueryFacade.current else {
            return
        }
        do {
            let queue = try await store.openReader()
            reader = QueryReader(reader: queue)
        } catch {
            Self.logger.error(
                "openReader failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func startLoop() {
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runOnce()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    private func runOnce() async {
        guard let sql = currentSQL, let reader else {
            return
        }
        do {
            let result = try await reader.run(sql: sql)
            // `spot_id` was validated to exist in setQuery; find its
            // column index and gather every value.
            guard let idx = result.columns.firstIndex(where: { $0.name == "spot_id" }) else {
                error = "Query no longer returns spot_id."
                allowedSpotIDs = nil
                return
            }
            var ids = Set<String>()
            ids.reserveCapacity(result.rows.count)
            for row in result.rows where idx < row.count {
                if case let .text(value) = row[idx] {
                    ids.insert(value)
                }
            }
            allowedSpotIDs = ids
            error = nil
        } catch let queryError as SQLQueryError {
            error = "Query failed: \(queryError.message)"
            allowedSpotIDs = nil
        } catch let other as Error {
            self.error = "Query failed: \(other.localizedDescription)"
            allowedSpotIDs = nil
        }
    }
}
