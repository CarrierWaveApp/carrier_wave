// Full QSON Export Actor
//
// Background actor that batch-fetches all QSOs from SwiftData and streams
// QSON (QSO Object Notation) records to a temporary file. Mirrors the
// FullADIFExportActor pattern for large logs without loading everything
// into memory at once.

import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - FullQSONExportActor

public actor FullQSONExportActor {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public func exportAllQSOs(
        container: ModelContainer,
        onProgress: @escaping @Sendable (FullExportProgressInfo) -> Void
    ) async throws -> FullExportResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let totalCount = try context.boundedCount(
            QSO.self,
            predicate: #Predicate { !$0.isHidden }
        )

        let (fileURL, filename) = createTempFile()
        try? FileManager.default.removeItem(at: fileURL)
        FileManager.default.createFile(
            atPath: fileURL.path, contents: nil
        )
        let fileHandle = try FileHandle(forWritingTo: fileURL)
        defer { try? fileHandle.close() }

        // Write opening: {"version":"0.5","source":"carrierwave","qsos":[
        fileHandle.write(Data(buildPreamble().utf8))

        let exportedCount = try await writeBatches(
            context: context,
            totalCount: totalCount,
            fileHandle: fileHandle,
            onProgress: onProgress
        )

        // Close the array and object: ]}
        fileHandle.write(Data("\n]}\n".utf8))

        try fileHandle.synchronize()
        let attrs = try FileManager.default.attributesOfItem(
            atPath: fileURL.path
        )
        let fileSize = attrs[.size] as? Int64 ?? 0

        return FullExportResult(
            fileURL: fileURL,
            filename: filename,
            qsoCount: exportedCount,
            fileSizeBytes: fileSize
        )
    }

    // MARK: Private

    private static let fetchBatchSize = 1_000

    private var isFirstRecord = true

    private func createTempFile() -> (url: URL, filename: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let dateStr = dateFormatter.string(from: Date())
        let filename = "carrierwave_full_export_\(dateStr).qson"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
        return (url, filename)
    }

    private func buildPreamble() -> String {
        "{\"version\":\"0.5\",\"source\":\"carrierwave\",\"qsos\":[\n"
    }

    private func writeBatches(
        context: ModelContext,
        totalCount: Int,
        fileHandle: FileHandle,
        onProgress: @escaping @Sendable (FullExportProgressInfo) -> Void
    ) async throws -> Int {
        var offset = 0
        var exportedCount = 0
        isFirstRecord = true

        while offset < totalCount {
            let descriptor = BoundedDescriptor<QSO>(
                predicate: #Predicate { !$0.isHidden },
                sortBy: [SortDescriptor(\.timestamp, order: .forward)],
                limit: Self.fetchBatchSize,
                offset: offset
            )

            let batch = try context.boundedFetch(descriptor)
            if batch.isEmpty {
                break
            }

            let snapshots = batch
                .filter { !QSOMode.isMetadata($0.mode) }
                .map { FullExportQSOSnapshot(from: $0) }

            var batchText = ""
            batchText.reserveCapacity(snapshots.count * 400)
            for snapshot in snapshots {
                if isFirstRecord {
                    isFirstRecord = false
                } else {
                    batchText.append(",\n")
                }
                batchText.append(QSONRecordBuilder.build(from: snapshot))
            }

            fileHandle.write(Data(batchText.utf8))
            exportedCount += snapshots.count
            offset += batch.count

            onProgress(FullExportProgressInfo(
                processed: offset,
                total: totalCount
            ))
            await Task.yield()
        }

        return exportedCount
    }
}

// MARK: - QSONRecordBuilder

/// Builds QSON JSON objects from QSO export snapshots.
enum QSONRecordBuilder {
    // MARK: Internal

    static func build(from snapshot: FullExportQSOSnapshot) -> String {
        var parts: [String] = []

        appendCoreParts(to: &parts, snapshot: snapshot)
        appendOurStation(to: &parts, snapshot: snapshot)
        appendTheirStation(to: &parts, snapshot: snapshot)
        appendRefs(to: &parts, snapshot: snapshot)
        appendQSL(to: &parts, snapshot: snapshot)

        if let notes = snapshot.notes, !notes.isEmpty {
            parts.append(jsonPair("notes", notes))
        }

        return "{\(parts.joined(separator: ","))}"
    }

    /// Build a QSON record from a raw QSO model (for the safety ledger).
    static func build(from qso: QSO) -> String {
        var parts: [String] = []

        appendQSOCoreParts(to: &parts, qso: qso)
        appendQSOOurStation(to: &parts, qso: qso)
        appendQSOTheirStation(to: &parts, qso: qso)

        var refs: [String] = []
        appendRefObject(to: &refs, qso: qso)
        if !refs.isEmpty {
            parts.append("\"refs\":[\(refs.joined(separator: ","))]")
        }

        if let notes = qso.notes, !notes.isEmpty {
            parts.append(jsonPair("notes", notes))
        }

        return "{\(parts.joined(separator: ","))}"
    }

    // MARK: Private

    private static let isoFormatter: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt
    }()

    private static func isoString(from date: Date) -> String {
        isoFormatter.string(from: date)
    }

    private static func formatNumber(_ value: Double) -> String {
        if value == value.rounded(.towardZero), value < 1e15 {
            return String(Int64(value))
        }
        return String(value)
    }

    private static func jsonPair(
        _ key: String, _ value: String
    ) -> String {
        "\"\(key)\":\"\(jsonEscape(value))\""
    }

    private static func jsonEscape(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.count)
        for char in string {
            switch char {
            case "\"": result.append("\\\"")
            case "\\": result.append("\\\\")
            case "\n": result.append("\\n")
            case "\r": result.append("\\r")
            case "\t": result.append("\\t")
            default:
                if char.asciiValue ?? 0x20 < 0x20 {
                    let code = char.asciiValue ?? 0
                    result.append(
                        String(format: "\\u%04x", code)
                    )
                } else {
                    result.append(char)
                }
            }
        }
        return result
    }

    // MARK: - Snapshot-based builders

    private static func appendCoreParts(
        to parts: inout [String],
        snapshot: FullExportQSOSnapshot
    ) {
        if let freq = snapshot.frequency {
            let khz = freq * 1_000
            parts.append("\"freq\":\(formatNumber(khz))")
        }
        parts.append(jsonPair("band", snapshot.band))
        parts.append(jsonPair("mode", snapshot.mode))

        let millis = Int64(
            snapshot.timestamp.timeIntervalSince1970 * 1_000
        )
        parts.append(
            jsonPair("startAt", isoString(from: snapshot.timestamp))
        )
        parts.append("\"startAtMillis\":\(millis)")
    }

    private static func appendOurStation(
        to parts: inout [String],
        snapshot: FullExportQSOSnapshot
    ) {
        var ourParts: [String] = []
        ourParts.append(jsonPair("call", snapshot.myCallsign))
        if let grid = snapshot.myGrid, !grid.isEmpty {
            ourParts.append(jsonPair("grid", grid))
        }
        if let rst = snapshot.rstSent, !rst.isEmpty {
            ourParts.append(jsonPair("sent", rst))
        }
        if let power = snapshot.power {
            ourParts.append("\"power\":\(power)")
        }
        if let myRig = snapshot.myRig, !myRig.isEmpty {
            ourParts.append(jsonPair("rig", myRig))
        }
        parts.append("\"our\":{\(ourParts.joined(separator: ","))}")
    }

    private static func appendTheirStation(
        to parts: inout [String],
        snapshot: FullExportQSOSnapshot
    ) {
        var theirParts: [String] = []
        theirParts.append(jsonPair("call", snapshot.callsign))
        if let grid = snapshot.theirGrid, !grid.isEmpty {
            theirParts.append(jsonPair("grid", grid))
        }
        if let rst = snapshot.rstReceived, !rst.isEmpty {
            theirParts.append(jsonPair("sent", rst))
        }
        if let name = snapshot.name, !name.isEmpty {
            theirParts.append(jsonPair("name", name))
        }
        if let qth = snapshot.qth, !qth.isEmpty {
            theirParts.append(jsonPair("city", qth))
        }
        if let state = snapshot.state, !state.isEmpty {
            theirParts.append(jsonPair("state", state))
        }
        if let country = snapshot.country, !country.isEmpty {
            theirParts.append(jsonPair("country", country))
        }
        if let dxcc = snapshot.dxcc {
            theirParts.append("\"dxccCode\":\(dxcc)")
        }
        parts.append(
            "\"their\":{\(theirParts.joined(separator: ","))}"
        )
    }

    private static func appendRefs(
        to parts: inout [String],
        snapshot: FullExportQSOSnapshot
    ) {
        var refs: [String] = []

        if let park = snapshot.theirParkReference, !park.isEmpty {
            refs.append(
                "{\"type\":\"pota\",\"ref\":\"\(jsonEscape(park))\"}"
            )
        }
        if let park = snapshot.parkReference, !park.isEmpty {
            refs.append(
                "{\"type\":\"potaActivation\","
                    + "\"ref\":\"\(jsonEscape(park))\"}"
            )
        }
        if let sota = snapshot.sotaRef, !sota.isEmpty {
            refs.append(
                "{\"type\":\"sotaActivation\","
                    + "\"ref\":\"\(jsonEscape(sota))\"}"
            )
        }
        if let wwff = snapshot.wwffRef, !wwff.isEmpty {
            refs.append(
                "{\"type\":\"wwffActivation\","
                    + "\"ref\":\"\(jsonEscape(wwff))\"}"
            )
        }
        if let contest = snapshot.contestName, !contest.isEmpty {
            refs.append(
                "{\"type\":\"contest\","
                    + "\"ref\":\"\(jsonEscape(contest))\"}"
            )
        }

        if !refs.isEmpty {
            parts.append("\"refs\":[\(refs.joined(separator: ","))]")
        }
    }

    private static func appendQSL(
        to parts: inout [String],
        snapshot: FullExportQSOSnapshot
    ) {
        var sources: [String] = []
        let received = snapshot.qrzConfirmed || snapshot.lotwConfirmed

        if snapshot.qrzConfirmed {
            sources.append("\"qrz\":{\"received\":true}")
        }
        if snapshot.lotwConfirmed {
            var lotwParts = "\"received\":true"
            if let lotwDate = snapshot.lotwConfirmedDate {
                let dateStr = isoString(from: lotwDate)
                let millis = Int64(
                    lotwDate.timeIntervalSince1970 * 1_000
                )
                lotwParts += ",\"receivedOn\":\"\(dateStr)\""
                lotwParts += ",\"receivedOnMillis\":\(millis)"
            }
            sources.append("\"lotw\":{\(lotwParts)}")
        }

        if received || !sources.isEmpty {
            var qslParts = "\"received\":\(received)"
            for source in sources {
                qslParts += ",\(source)"
            }
            parts.append("\"qsl\":{\(qslParts)}")
        }
    }

    // MARK: - Raw QSO builders (for ledger)

    private static func appendQSOCoreParts(
        to parts: inout [String], qso: QSO
    ) {
        if let freq = qso.frequency {
            let khz = freq * 1_000
            parts.append("\"freq\":\(formatNumber(khz))")
        }
        parts.append(jsonPair("band", qso.band))
        parts.append(jsonPair("mode", qso.mode))

        let millis = Int64(
            qso.timestamp.timeIntervalSince1970 * 1_000
        )
        parts.append(
            jsonPair("startAt", isoString(from: qso.timestamp))
        )
        parts.append("\"startAtMillis\":\(millis)")
    }

    private static func appendQSOOurStation(
        to parts: inout [String], qso: QSO
    ) {
        var ourParts: [String] = []
        ourParts.append(jsonPair("call", qso.myCallsign))
        if let grid = qso.myGrid, !grid.isEmpty {
            ourParts.append(jsonPair("grid", grid))
        }
        if let rst = qso.rstSent, !rst.isEmpty {
            ourParts.append(jsonPair("sent", rst))
        }
        if let power = qso.power {
            ourParts.append("\"power\":\(power)")
        }
        parts.append("\"our\":{\(ourParts.joined(separator: ","))}")
    }

    private static func appendQSOTheirStation(
        to parts: inout [String], qso: QSO
    ) {
        var theirParts: [String] = []
        theirParts.append(jsonPair("call", qso.callsign))
        if let grid = qso.theirGrid, !grid.isEmpty {
            theirParts.append(jsonPair("grid", grid))
        }
        if let rst = qso.rstReceived, !rst.isEmpty {
            theirParts.append(jsonPair("sent", rst))
        }
        if let name = qso.name, !name.isEmpty {
            theirParts.append(jsonPair("name", name))
        }
        if let state = qso.state, !state.isEmpty {
            theirParts.append(jsonPair("state", state))
        }
        if let country = qso.country, !country.isEmpty {
            theirParts.append(jsonPair("country", country))
        }
        if let dxcc = qso.dxcc {
            theirParts.append("\"dxccCode\":\(dxcc)")
        }
        parts.append(
            "\"their\":{\(theirParts.joined(separator: ","))}"
        )
    }

    private static func appendRefObject(
        to refs: inout [String], qso: QSO
    ) {
        if let park = qso.theirParkReference, !park.isEmpty {
            refs.append(
                "{\"type\":\"pota\",\"ref\":\"\(jsonEscape(park))\"}"
            )
        }
        if let park = qso.parkReference, !park.isEmpty {
            refs.append(
                "{\"type\":\"potaActivation\","
                    + "\"ref\":\"\(jsonEscape(park))\"}"
            )
        }
        if let sota = qso.sotaRef, !sota.isEmpty {
            refs.append(
                "{\"type\":\"sotaActivation\","
                    + "\"ref\":\"\(jsonEscape(sota))\"}"
            )
        }
        if let wwff = qso.wwffRef, !wwff.isEmpty {
            refs.append(
                "{\"type\":\"wwffActivation\","
                    + "\"ref\":\"\(jsonEscape(wwff))\"}"
            )
        }
        if let contest = qso.contestName, !contest.isEmpty {
            refs.append(
                "{\"type\":\"contest\","
                    + "\"ref\":\"\(jsonEscape(contest))\"}"
            )
        }
    }
}
