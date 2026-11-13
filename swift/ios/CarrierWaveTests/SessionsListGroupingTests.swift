import XCTest
@testable import CarrierWave

/// Tests for the pure `SessionsListGroupingActor.monthGroups(_:)` half of the
/// Sessions list cache (CAR-154). The actor hop and the key-to-`ListItem`
/// resolution are exercised in the app; this suite pins ordering, UTC month
/// bucketing, and identity stability.
final class SessionsListGroupingTests: XCTestCase {
    // MARK: Internal

    // MARK: - Ordering

    func test_emptyInputProducesNoSections() {
        XCTAssertTrue(SessionsListGroupingActor.monthGroups([]).isEmpty)
    }

    func test_rowsSortNewestFirstAcrossSessionsAndOrphans() {
        let older = UUID()
        let newer = UUID()
        let entries = [
            entry(.session(older), "2026-03-02T10:00:00Z"),
            entry(.orphanActivation("K-0001|2026-03-15"), "2026-03-15T00:00:00Z"),
            entry(.session(newer), "2026-03-20T18:30:00Z"),
        ]

        let groups = SessionsListGroupingActor.monthGroups(entries)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].month, "March 2026")
        XCTAssertEqual(
            groups[0].keys,
            [.session(newer), .orphanActivation("K-0001|2026-03-15"), .session(older)]
        )
    }

    func test_sectionsOrderNewestMonthFirst() {
        let entries = [
            entry(.session(UUID()), "2025-11-05T12:00:00Z"),
            entry(.session(UUID()), "2026-01-10T12:00:00Z"),
            entry(.session(UUID()), "2025-12-25T12:00:00Z"),
        ]

        let months = SessionsListGroupingActor.monthGroups(entries).map(\.month)

        XCTAssertEqual(months, ["January 2026", "December 2025", "November 2025"])
    }

    func test_equalDatesKeepInputOrder() {
        // Sessions are appended before orphans by the view; a stable sort must
        // keep that relative order for identical timestamps.
        let session = UUID()
        let entries = [
            entry(.session(session), "2026-02-01T00:00:00Z"),
            entry(.orphanActivation("K-0002|2026-02-01"), "2026-02-01T00:00:00Z"),
        ]

        let groups = SessionsListGroupingActor.monthGroups(entries)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(
            groups[0].keys,
            [.session(session), .orphanActivation("K-0002|2026-02-01")]
        )
    }

    // MARK: - UTC bucketing

    func test_monthBoundaryIsEvaluatedInUTC() {
        // 23:30Z on Mar 31 is still March; 00:30Z on Apr 1 is April, regardless
        // of the simulator's local time zone.
        let march = UUID()
        let april = UUID()
        let entries = [
            entry(.session(march), "2026-03-31T23:30:00Z"),
            entry(.session(april), "2026-04-01T00:30:00Z"),
        ]

        let groups = SessionsListGroupingActor.monthGroups(entries)

        XCTAssertEqual(groups.map(\.month), ["April 2026", "March 2026"])
        XCTAssertEqual(groups[0].keys, [.session(april)])
        XCTAssertEqual(groups[1].keys, [.session(march)])
    }

    // MARK: - Identity

    func test_listItemIDMatchesLegacyFormat() {
        let id = UUID()
        XCTAssertEqual(SessionsListEntryKey.session(id).listItemID, "session-\(id)")
        XCTAssertEqual(
            SessionsListEntryKey.orphanActivation("K-1234|2026-05-01").listItemID,
            "orphan-K-1234|2026-05-01"
        )
    }

    // MARK: Private

    private func entry(_ key: SessionsListEntryKey, _ iso8601: String) -> SessionsListEntry {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return SessionsListEntry(key: key, date: formatter.date(from: iso8601)!)
    }
}
