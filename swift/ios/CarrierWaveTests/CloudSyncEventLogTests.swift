import Foundation
import Testing
@testable import CarrierWaveData

struct CloudSyncEventLogTests {
    // MARK: Internal

    @Test("Append and retrieve events")
    func appendAndRetrieve() async {
        let log = CloudSyncEventLog(
            fileURL: tempFileURL()
        )
        let event = CloudSyncEvent(
            category: .fetch, detail: "Test fetch"
        )
        await log.append(event)
        let events = await log.allEvents()
        #expect(events.count == 1)
        #expect(events[0].detail == "Test fetch")
    }

    @Test("Events persist to disk and reload")
    func persistAndReload() async {
        let url = tempFileURL()
        let log1 = CloudSyncEventLog(fileURL: url)
        await log1.append(
            CloudSyncEvent(category: .fetch, detail: "Persisted")
        )

        let log2 = CloudSyncEventLog(fileURL: url)
        await log2.load()
        let events = await log2.allEvents()
        #expect(events.count == 1)
        #expect(events[0].detail == "Persisted")
    }

    @Test("Prunes to maxEvents FIFO")
    func pruning() async {
        let log = CloudSyncEventLog(
            fileURL: tempFileURL(), maxEvents: 5
        )
        for idx in 0 ..< 8 {
            await log.append(
                CloudSyncEvent(
                    category: .fetch, detail: "Event \(idx)"
                )
            )
        }
        let events = await log.allEvents()
        #expect(events.count == 5)
        #expect(events[0].detail == "Event 3")
        #expect(events[4].detail == "Event 7")
    }

    @Test("Load with missing file returns empty")
    func loadMissingFile() async {
        let log = CloudSyncEventLog(
            fileURL: URL(fileURLWithPath: "/tmp/nonexistent_\(UUID()).json")
        )
        await log.load()
        let events = await log.allEvents()
        #expect(events.isEmpty)
    }

    // MARK: Private

    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("test_sync_events_\(UUID()).json")
    }
}
