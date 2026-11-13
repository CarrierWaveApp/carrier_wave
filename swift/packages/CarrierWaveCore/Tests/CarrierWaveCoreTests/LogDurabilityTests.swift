//
//  LogDurabilityTests.swift
//  CarrierWaveCoreTests
//
//  Swift durability tests — proves that the UniFFI/FieldStore path
//  does not buffer or drop writes even under process abort and
//  concurrent access.
//
//  Two tests:
//    1. appCrashAfterAckPreservesQso — spawns LogDurabilityCrasher, asserts the
//       acked QSO survived the abort().
//    2. concurrentUpsertsAllPersist — 4 concurrent Tasks × 50 upserts = 200 rows.
//

import CarrierWaveCore
import Foundation
import Testing

// MARK: - Crasher path helper

private func crasherURL() -> URL {
    // Tests/CarrierWaveCoreTests/LogDurabilityTests.swift → pkg root (3 dirs up)
    let pkg = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return pkg.appendingPathComponent(".build/debug/LogDurabilityCrasher")
}

// MARK: - FfiQso minimal builder (mirrors LogDurabilityCrasher/main.swift)

private extension FfiQso {
    // swiftlint:disable:next function_body_length
    static func minimal(id: String) -> FfiQso {
        FfiQso(
            id: id,
            callsign: "W1AW",
            band: nil,
            mode: nil,
            freqKhz: nil,
            qsoDate: 1_000,
            myGrid: nil,
            theirGrid: nil,
            rstSent: nil,
            rstRcvd: nil,
            myCallsign: nil,
            park: nil,
            theirPark: nil,
            notes: nil,
            notesUserAuthored: false,
            spotCommentsData: nil,
            callsignChangeNote: nil,
            originalCallsign: nil,
            importSourceRawValue: "logger",
            importedAt: 1_000,
            modifiedAt: nil,
            rawAdif: nil,
            name: nil,
            qth: nil,
            state: nil,
            country: nil,
            power: nil,
            myRig: nil,
            stationProfileName: nil,
            sotaRef: nil,
            wwffRef: nil,
            aoaCode: nil,
            qrzLogId: nil,
            qrzConfirmed: false,
            lotwConfirmedDate: nil,
            lotwConfirmed: false,
            dxcc: nil,
            theirLicenseClass: nil,
            contestName: nil,
            contestSerialSent: nil,
            contestSerialReceived: nil,
            contestExchangeSent: nil,
            contestExchangeReceived: nil,
            isHidden: false,
            isActivityLogQso: false,
            stationCallsign: nil,
            loggingSessionId: nil,
            dirty: true,
            satName: nil,
            propMode: nil,
            presence: []
        )
    }
}

// MARK: - LogDurabilityTests

struct LogDurabilityTests {
    @Test func appCrashAfterAckPreservesQso() throws {
        let crasher = crasherURL()
        guard FileManager.default.fileExists(atPath: crasher.path) else {
            // swiftlint:disable:next line_length
            let msg = "LogDurabilityCrasher not found at \(crasher.path) — run: swift build --product LogDurabilityCrasher"
            Issue.record(Comment(rawValue: msg))
            return
        }

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let db = tmp.appendingPathComponent("log.db").path

        let proc = Process()
        proc.executableURL = crasher
        proc.arguments = [db, "k", "swiftcrash"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try proc.run()
        proc.waitUntilExit()

        let raw = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: raw, encoding: .utf8) ?? ""
        #expect(out.contains("ACK swiftcrash"))
        #expect(proc.terminationReason == .uncaughtSignal)

        let store = try FieldStore.open(path: db, key: "k")
        let filter = FfiQsoFilter(callsignPrefix: nil, band: nil, mode: nil, since: nil, dirtyOnly: false)
        let rows = try store.fetchQsos(filter: filter, limit: 10, offset: 0)
        #expect(rows.contains(where: { $0.id == "swiftcrash" }))
    }

    @Test func concurrentUpsertsAllPersist() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let db = tmp.appendingPathComponent("log.db").path

        // FieldStore is @unchecked Sendable and internally serialized in Rust —
        // sharing one instance across tasks is safe and exercises busy_timeout.
        let store = try FieldStore.open(path: db, key: "k")

        try await withThrowingTaskGroup(of: Void.self, body: { group in
            for taskIdx in 0 ..< 4 {
                group.addTask {
                    for i in 0 ..< 50 {
                        try store.upsertQso(qso: .minimal(id: "\(taskIdx)-\(i)"))
                    }
                }
            }
            try await group.waitForAll()
        })

        #expect(try store.qsoCount() == 200)
    }
}
