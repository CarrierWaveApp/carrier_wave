import CarrierWaveData
import XCTest
@testable import CarrierWave

/// Tests for the pure `buildSnapshot` half of `DaySummaryDataActor`.
/// The paging halves are exercised in integration; this suite covers
/// slicing, virtual cards, badge derivation, and aggregates.
@MainActor
final class DaySummaryDataActorTests: XCTestCase {
    // MARK: Internal

    /// UTC May 22 2026 00:00:00.
    let dayStart = Date(timeIntervalSince1970: 1_779_667_200)

    var dayEnd: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(byAdding: .day, value: 1, to: dayStart)!
    }

    // MARK: - Tests

    func test_includesOverlappingSessionsWithSlicedQSOs() {
        let sess = session(start: 3_600, end: 7_200, programs: ["pota"], parkReference: "K-4561")
        let qsos = [qsoSnap(sessionId: sess.id, offset: 4_000)]
        let snap = build(
            dayQSOs: qsos,
            sessions: [sess]
        )
        XCTAssertEqual(snap.sessions.count, 1)
        XCTAssertEqual(snap.sessions.first?.kind, .session(sess.id))
        XCTAssertEqual(snap.sessions.first?.title, "K-4561")
        XCTAssertEqual(snap.sessions.first?.typeIcon, .pota)
        XCTAssertEqual(snap.sessions.first?.slicedQSOs.count, 1)
    }

    func test_dropsSessionsWithNoSlicedQSOs() {
        let sess = session(start: 3_600, end: 7_200, programs: ["pota"])
        let snap = build(
            dayQSOs: [],
            sessions: [sess]
        )
        XCTAssertTrue(snap.sessions.isEmpty)
    }

    func test_continuedBadgeWhenSessionStartedBefore() {
        let sess = session(start: -3_600, end: 3_600)
        let qsos = [qsoSnap(sessionId: sess.id, offset: 1_800)]
        let snap = build(
            dayQSOs: qsos,
            sessions: [sess]
        )
        XCTAssertEqual(snap.sessions.first?.continuationBadge, .continued)
    }

    func test_continuesBadgeWhenSessionEndsAfter() {
        let sess = session(start: 3_600, end: 90_000)
        let qsos = [qsoSnap(sessionId: sess.id, offset: 4_000)]
        let snap = build(
            dayQSOs: qsos,
            sessions: [sess]
        )
        XCTAssertEqual(snap.sessions.first?.continuationBadge, .continues)
    }

    func test_bothBadgeWhenSessionSpansMultipleDays() {
        let sess = session(start: -3_600, end: 90_000)
        let qsos = [qsoSnap(sessionId: sess.id, offset: 1_000)]
        let snap = build(
            dayQSOs: qsos,
            sessions: [sess]
        )
        XCTAssertEqual(snap.sessions.first?.continuationBadge, .both)
    }

    func test_hunterCardBuiltFromActivityLogQSOs() {
        let logId = UUID()
        let qsos = [
            qsoSnap(sessionId: logId, offset: 1_800),
            qsoSnap(sessionId: logId, offset: 3_600),
        ]
        let snap = build(
            dayQSOs: qsos,
            activityLogId: logId
        )
        XCTAssertEqual(snap.hunterCard?.kind, .hunter)
        XCTAssertEqual(snap.hunterCard?.slicedQSOs.count, 2)
    }

    func test_looseCardCollectsOrphanQSOs() {
        let qsos = [qsoSnap(sessionId: nil, offset: 1_800)]
        let snap = build(
            dayQSOs: qsos
        )
        XCTAssertEqual(snap.looseCard?.kind, .loose)
        XCTAssertEqual(snap.looseCard?.slicedQSOs.count, 1)
    }

    func test_looseCardIncludesQSOsForUnloadedSessions() {
        let unloadedId = UUID()
        let qsos = [qsoSnap(sessionId: unloadedId, offset: 1_800)]
        let snap = build(
            dayQSOs: qsos
        )
        XCTAssertEqual(snap.looseCard?.slicedQSOs.count, 1)
    }

    func test_sessionCardsSortByFirstSlicedQSO() {
        let sessA = session(start: 3_600, end: 7_200)
        let sessB = session(start: 1_800, end: 9_000)
        let qsos = [
            qsoSnap(sessionId: sessA.id, offset: 4_000),
            qsoSnap(sessionId: sessB.id, offset: 2_000),
        ]
        let snap = build(
            dayQSOs: qsos,
            sessions: [sessA, sessB]
        )
        XCTAssertEqual(snap.sessions.map(\.kind), [.session(sessB.id), .session(sessA.id)])
    }

    func test_dxccAndStateAggregation() {
        let qsos = [
            qsoSnap(sessionId: nil, offset: 100, state: "CA", dxcc: 291),
            qsoSnap(sessionId: nil, offset: 200, state: "WA", dxcc: 291),
            qsoSnap(sessionId: nil, offset: 300, state: nil, dxcc: 339),
        ]
        let snap = build(
            dayQSOs: qsos
        )
        XCTAssertEqual(snap.dxccCount, 2)
        XCTAssertEqual(snap.stateAbbreviations, ["CA", "WA"])
    }

    func test_bandAndModeAggregationsSorted() {
        let qsos = [
            qsoSnap(sessionId: nil, offset: 100, band: "40m", mode: "CW"),
            qsoSnap(sessionId: nil, offset: 200, band: "20m", mode: "SSB"),
            qsoSnap(sessionId: nil, offset: 300, band: "20m", mode: "SSB"),
        ]
        let snap = build(
            dayQSOs: qsos
        )
        XCTAssertEqual(snap.bandCounts, [
            DayBandCount(band: "20m", count: 2),
            DayBandCount(band: "40m", count: 1),
        ])
        XCTAssertEqual(snap.modeCounts, [
            DayModeCount(mode: "CW", count: 1),
            DayModeCount(mode: "SSB", count: 2),
        ])
    }

    func test_liveSessionWhenEndedAtIsNil() {
        let sess = session(start: 3_600, end: nil)
        let qsos = [qsoSnap(sessionId: sess.id, offset: 4_000)]
        let snap = build(
            dayQSOs: qsos,
            sessions: [sess],
            now: dayStart.addingTimeInterval(5_000)
        )
        XCTAssertEqual(snap.sessions.first?.isLive, true)
    }

    // MARK: Private

    // MARK: - Helpers

    private func qsoSnap(
        sessionId: UUID?,
        offset: TimeInterval,
        band: String = "20m",
        mode: String = "SSB",
        callsign: String = "TEST",
        state: String? = "CA",
        dxcc: Int? = 291
    ) -> DaySummaryQSO {
        DaySummaryQSO(
            id: UUID(),
            timestamp: dayStart.addingTimeInterval(offset),
            callsign: callsign,
            band: band,
            mode: mode,
            frequency: 14_250_000,
            loggingSessionId: sessionId,
            dxcc: dxcc,
            state: state,
            myGrid: "CM87",
            theirGrid: nil,
            stationProfileName: "Home"
        )
    }

    private func session(
        start: TimeInterval,
        end: TimeInterval?,
        programs: Set<String> = [],
        mode: String = "SSB",
        parkReference: String? = nil,
        customTitle: String? = nil
    ) -> SessionFacts {
        SessionFacts(
            id: UUID(),
            startedAt: dayStart.addingTimeInterval(start),
            endedAt: end.map { dayStart.addingTimeInterval($0) },
            mode: mode,
            programs: programs,
            parkReference: parkReference,
            sotaReference: nil,
            wwffReference: nil,
            customTitle: customTitle,
            activationTypeDisplay: programs.first?.uppercased() ?? "Casual"
        )
    }

    private func build(
        dayQSOs: [DaySummaryQSO],
        sessions: [SessionFacts] = [],
        activityLogId: UUID? = nil,
        now: Date? = nil
    ) -> DaySummarySnapshot {
        DaySummaryDataActor.buildSnapshot(.init(
            date: dayStart,
            endOfDay: dayEnd,
            dayQSOs: dayQSOs,
            sessions: sessions,
            activityLogId: activityLogId,
            now: now ?? dayStart
        ))
    }
}
