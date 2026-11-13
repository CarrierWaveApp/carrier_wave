import Testing
import UIKit
@testable import CarrierWave

@Suite("Satellite pass-recording store")
struct SatellitePassRecordingStoreTests {
    // MARK: Internal

    @Test("sidecar round-trips and loads newest-first")
    func roundTripNewestFirst() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let older = recording(norad: 1, startedAt: now.addingTimeInterval(-3_600))
        let newer = recording(norad: 2, startedAt: now, marks: [12.5, 90])
        try SatellitePassRecordingStore.save(older, in: directory)
        try SatellitePassRecordingStore.save(newer, in: directory)

        let loaded = SatellitePassRecordingStore.loadAll(in: directory)
        #expect(loaded == [newer, older])
        #expect(loaded[0].markOffsets == [12.5, 90])
        #expect(loaded[0].markDates == [
            newer.startedAt.addingTimeInterval(12.5),
            newer.startedAt.addingTimeInterval(90),
        ])
    }

    @Test("latest() matches the bird and the 45-minute recency window")
    func latestFiltersByBirdAndAge() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fresh = recording(
            norad: 7, startedAt: now.addingTimeInterval(-1_800),
            endedAt: now.addingTimeInterval(-600)
        )
        let stale = recording(
            norad: 7, startedAt: now.addingTimeInterval(-7_200),
            endedAt: now.addingTimeInterval(-3_600)
        )
        let otherBird = recording(
            norad: 8, startedAt: now.addingTimeInterval(-900),
            endedAt: now.addingTimeInterval(-300)
        )
        let unfinished = recording(norad: 7, startedAt: now.addingTimeInterval(-300))
        for item in [fresh, stale, otherBird, unfinished] {
            try SatellitePassRecordingStore.save(item, in: directory)
        }

        #expect(SatellitePassRecordingStore.latest(noradID: 7, in: directory, now: now) == fresh)
        #expect(SatellitePassRecordingStore.latest(noradID: 9, in: directory, now: now) == nil)
    }

    @Test("prune deletes sidecar + audio past the 7-day retention")
    func pruneDeletesOldRecordings() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let old = recording(norad: 1, startedAt: now.addingTimeInterval(-8 * 24 * 3_600))
        let recent = recording(norad: 2, startedAt: now.addingTimeInterval(-1 * 24 * 3_600))
        try SatellitePassRecordingStore.save(old, in: directory)
        try SatellitePassRecordingStore.save(recent, in: directory)
        let oldAudio = SatellitePassRecordingStore.audioURL(for: old, in: directory)
        try Data("audio".utf8).write(to: oldAudio)

        SatellitePassRecordingStore.prune(in: directory, now: now)

        #expect(SatellitePassRecordingStore.loadAll(in: directory) == [recent])
        #expect(!FileManager.default.fileExists(atPath: oldAudio.path))
    }

    // MARK: Private

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("satpass-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func recording(
        norad: Int,
        startedAt: Date,
        endedAt: Date? = nil,
        marks: [TimeInterval] = []
    ) -> SatellitePassRecording {
        let id = UUID()
        return SatellitePassRecording(
            id: id,
            noradID: norad,
            satelliteName: "SAT-\(norad)",
            startedAt: startedAt,
            endedAt: endedAt,
            markOffsets: marks,
            audioFileName: "\(id.uuidString.lowercased()).m4a"
        )
    }
}
