// Off-main-thread sort + month grouping for the Sessions list (CAR-154).
//
// `SessionsView` snapshots its rows into `SessionsListEntry` values (identity
// and date only — no SwiftData objects cross the actor boundary), hands them to
// `SessionsListGroupingActor`, and resolves the returned keys back to
// `ListItem`s on the main actor. The pure `monthGroups(_:)` static is what the
// unit tests exercise.

import CarrierWaveData
import UIKit

// MARK: - SessionsListEntryKey

/// Stable identity for a Sessions list row. `listItemID` reproduces the
/// pre-existing `SessionsView.ListItem.id` strings exactly so `List` diffing is
/// unaffected by the move to a cached, precomputed list.
nonisolated enum SessionsListEntryKey: Hashable, Sendable {
    case session(UUID)
    case orphanActivation(String)

    // MARK: Internal

    var listItemID: String {
        switch self {
        case let .session(id): "session-\(id)"
        case let .orphanActivation(id): "orphan-\(id)"
        }
    }
}

// MARK: - SessionsListEntry

/// Sendable snapshot of the two fields the grouping needs.
nonisolated struct SessionsListEntry: Hashable, Sendable {
    let key: SessionsListEntryKey
    let date: Date
}

// MARK: - SessionsListMonthGroup

/// One "MMMM yyyy" (UTC) section with its row keys in display order
/// (newest first). Sections themselves are returned newest first.
nonisolated struct SessionsListMonthGroup: Hashable, Sendable {
    let month: String
    let keys: [SessionsListEntryKey]
}

// MARK: - SessionsListGroupingActor

/// Background actor that sorts and buckets Sessions list rows by UTC month.
actor SessionsListGroupingActor {
    // MARK: Internal

    /// Sort newest first, then bucket by UTC month, sections newest first.
    ///
    /// Semantics match the former `SessionsView.allItems` / `itemsByMonth`
    /// computed properties one-for-one: a stable descending sort by date,
    /// `Dictionary(grouping:)` on the month label, and sections ordered by
    /// their first (newest) row.
    nonisolated static func monthGroups(
        _ entries: [SessionsListEntry]
    ) -> [SessionsListMonthGroup] {
        let sorted = entries.sorted { $0.date > $1.date }
        let grouped = Dictionary(grouping: sorted) { entry in
            monthYearFormatter.string(from: entry.date)
        }
        return grouped
            .sorted { $0.value[0].date > $1.value[0].date }
            .map { SessionsListMonthGroup(month: $0.key, keys: $0.value.map(\.key)) }
    }

    func monthGroups(for entries: [SessionsListEntry]) -> [SessionsListMonthGroup] {
        Self.monthGroups(entries)
    }

    // MARK: Private

    private static let monthYearFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()
}

// MARK: - SessionsView + Cached Sections

extension SessionsView {
    /// Called from `.onChange(of: listEntries)`. Prunes rows whose backing
    /// model has gone (e.g. a just-deleted session) synchronously so the stale
    /// cache is never rendered, then regroups on `SessionsListGroupingActor`.
    func scheduleListRebuild(_ entries: [SessionsListEntry]) {
        listRebuildTask?.cancel()

        let live = Set(entries.map(\.key))
        itemsByMonth = itemsByMonth.compactMap { section in
            let kept = section.items.filter { live.contains($0.key) }
            return kept.isEmpty ? nil : MonthSection(month: section.month, items: kept)
        }

        listRebuildTask = Task {
            let groups = await listGrouping.monthGroups(for: entries)
            guard !Task.isCancelled else {
                return
            }
            applyMonthGroups(groups)
        }
    }

    /// Resolve grouped keys back to `ListItem`s against the current state.
    /// Keys with no live model (data changed under the task) are dropped; the
    /// follow-up `onChange` rebuild picks up the new state.
    func applyMonthGroups(_ groups: [SessionsListMonthGroup]) {
        var itemsByKey: [SessionsListEntryKey: ListItem] = [:]
        itemsByKey.reserveCapacity(sessions.count + orphanActivations.count)
        for session in sessions {
            itemsByKey[.session(session.id)] = .session(session)
        }
        for activation in orphanActivations {
            itemsByKey[.orphanActivation(activation.id)] = .orphanActivation(activation)
        }

        itemsByMonth = groups.compactMap { group in
            let items = group.keys.compactMap { itemsByKey[$0] }
            return items.isEmpty ? nil : MonthSection(month: group.month, items: items)
        }
    }
}
