import Foundation
import Testing
@testable import CarrierWaveData

struct CloudSyncEventTests {
    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let event = CloudSyncEvent(
            category: .fetch,
            entityType: "QSO",
            detail: "Received 42 QSOs",
            recordCount: 42,
            duration: 1.234
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(CloudSyncEvent.self, from: data)
        #expect(decoded.id == event.id)
        #expect(decoded.category == .fetch)
        #expect(decoded.entityType == "QSO")
        #expect(decoded.detail == "Received 42 QSOs")
        #expect(decoded.recordCount == 42)
        #expect(decoded.duration == 1.234)
    }

    @Test("Codable round-trip with nil optional fields")
    func codableNilFields() throws {
        let event = CloudSyncEvent(
            category: .accountChange,
            detail: "Signed in"
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(CloudSyncEvent.self, from: data)
        #expect(decoded.entityType == nil)
        #expect(decoded.recordCount == nil)
        #expect(decoded.duration == nil)
    }

    @Test("Summary computes last fetch from events")
    func summaryLastFetch() {
        let events = [
            CloudSyncEvent(category: .fetch, detail: "Fetch 1", recordCount: 10, duration: 0.5),
            CloudSyncEvent(category: .fetch, detail: "Fetch 2", recordCount: 20, duration: 1.0),
            CloudSyncEvent(category: .upload, detail: "Upload 1", recordCount: 5, duration: 0.3),
        ]
        let summary = CloudSyncSummary.from(events: events)
        #expect(summary.lastFetchRecordCount == 20)
        #expect(summary.lastFetchDuration == 1.0)
        #expect(summary.lastUploadRecordCount == 5)
    }

    @Test("Summary counts today's conflicts and errors")
    func summaryTodayCounts() throws {
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: Date()))
        let events = [
            CloudSyncEvent(category: .conflict, detail: "Conflict 1"),
            CloudSyncEvent(category: .conflict, detail: "Conflict 2"),
            CloudSyncEvent(category: .error, detail: "Error 1"),
            CloudSyncEvent(timestamp: yesterday, category: .error, detail: "Old error"),
        ]
        let summary = CloudSyncSummary.from(events: events)
        #expect(summary.conflictsToday == 2)
        #expect(summary.errorsToday == 1)
    }

    @Test("Empty events produce empty summary")
    func summaryEmpty() {
        let summary = CloudSyncSummary.from(events: [])
        #expect(summary.lastFetchDate == nil)
        #expect(summary.lastUploadDate == nil)
        #expect(summary.conflictsToday == 0)
        #expect(summary.errorsToday == 0)
    }
}
