// ADIF Import Actor
//
// Background actor that imports ADIF files into SwiftData.
// Uses ADIFParser from CarrierWaveCore for parsing, deduplicates
// against existing QSOs, and creates ServicePresence records. QSO
// construction is shared with the S.A.T. listener via ADIFRecordQSOFactory.

import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData

// MARK: - ADIFImportResult

struct ADIFImportResult {
    let totalRecords: Int
    let imported: Int
    let duplicates: Int
    let errors: Int
}

// MARK: - ADIFImportProgressInfo

struct ADIFImportProgressInfo {
    let processed: Int
    let total: Int
}

// MARK: - ADIFImportActor

actor ADIFImportActor {
    // MARK: Internal

    func importADIF(
        from url: URL,
        myCallsign: String,
        container: ModelContainer,
        onProgress: @escaping @Sendable (ADIFImportProgressInfo) -> Void
    ) async throws -> ADIFImportResult {
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw ADIFImportError.invalidFile
        }
        return try await importADIF(
            content: content,
            myCallsign: myCallsign,
            container: container,
            onProgress: onProgress
        )
    }

    func importADIF(
        content: String,
        myCallsign: String,
        container: ModelContainer,
        onProgress: @escaping @Sendable (ADIFImportProgressInfo) -> Void
    ) async throws -> ADIFImportResult {
        let parser = ADIFParser()
        let records = try parser.parse(content)

        let context = ModelContext(container)
        context.autosaveEnabled = false

        let existingKeys = try fetchExistingKeys(context: context)

        var imported = 0
        var duplicates = 0
        var errors = 0
        var pending: [QSO] = []

        for (index, record) in records.enumerated() {
            // Skip metadata pseudo-modes
            if QSOMode.isMetadata(record.mode) {
                continue
            }

            do {
                let qso = try ADIFRecordQSOFactory.makeQSO(
                    from: record,
                    myCallsign: myCallsign,
                    importSource: .adifFile
                )

                if existingKeys.contains(qso.deduplicationKey) {
                    duplicates += 1
                    continue
                }

                context.insert(qso)
                ADIFRecordQSOFactory.attachServicePresence(
                    for: qso,
                    context: context,
                    myCallsign: myCallsign
                )
                imported += 1
                pending.append(qso)
            } catch {
                errors += 1
            }

            Self.reportProgress(index: index, total: records.count, onProgress)

            // Save in batches (cw-store first under `.on`, then SwiftData).
            if imported.isMultiple(of: Self.insertBatchSize), imported > 0 {
                try Self.flush(&pending, in: context)
                await Task.yield()
            }
        }

        try Self.flush(&pending, in: context)

        return ADIFImportResult(
            totalRecords: records.count,
            imported: imported,
            duplicates: duplicates,
            errors: errors
        )
    }

    // MARK: Private

    private static let insertBatchSize = 500

    private static func reportProgress(
        index: Int, total: Int, _ onProgress: @Sendable (ADIFImportProgressInfo) -> Void
    ) {
        if (index + 1).isMultiple(of: 100) || index == total - 1 {
            onProgress(ADIFImportProgressInfo(processed: index + 1, total: total))
        }
    }

    private static func flush(_ pending: inout [QSO], in context: ModelContext) throws {
        try OffMainStoreSeam.commitQSOsWithPresence(pending, in: context)
        pending.removeAll(keepingCapacity: true)
    }

    private func fetchExistingKeys(
        context: ModelContext
    ) throws -> Set<String> {
        var keys = Set<String>()
        var offset = 0

        while true {
            let descriptor = BoundedDescriptor<QSO>(
                limit: BoundedDescriptor<QSO>.maxLimit,
                offset: offset
            )
            let batch = try context.boundedFetch(descriptor)
            if batch.isEmpty {
                break
            }
            for qso in batch {
                keys.insert(qso.deduplicationKey)
            }
            offset += batch.count
        }
        return keys
    }
}

// MARK: - ADIFImportError

enum ADIFImportError: Error, LocalizedError {
    case invalidFile
    case missingTimestamp
    case parseError(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidFile:
            "Could not read the ADIF file"
        case .missingTimestamp:
            "QSO record missing date/time"
        case let .parseError(message):
            "Parse error: \(message)"
        }
    }
}
