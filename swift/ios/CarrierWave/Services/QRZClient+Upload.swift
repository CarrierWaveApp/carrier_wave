import CarrierWaveData
import Foundation
import SwiftData

// MARK: - QRZUploadSnapshot

/// Pre-captured QSO data for upload. Snapshots model properties before the async
/// upload loop to avoid accessing SwiftData models after they may be invalidated
/// by concurrent operations (iCloud sync, background tasks, user edits).
struct QRZUploadSnapshot {
    let index: Int
    let persistentID: PersistentIdentifier
    let adifContent: String
    let myCallsign: String
    /// For failure logging only
    let callsign: String
    let band: String
    let mode: String
    let timestamp: Date
    /// True when we can safely REPLACE an existing QRZ record (we have QRZ's own data).
    /// False for QSOs from other sources where REPLACE could blank fields QRZ already has.
    let useReplace: Bool
}

// MARK: - QRZUploadResponse

/// Result of a single QRZ upload request
struct QRZUploadResponse {
    let uploaded: Int
    let duplicates: Int
    let logId: String?
}

// MARK: - QRZClient Upload Entry Point

extension QRZClient {
    /// Upload QSOs to QRZ logbook one at a time.
    /// QRZ INSERT only processes one ADIF record per request, so we send each QSO
    /// individually with a 200ms delay between requests.
    ///
    /// Snapshots all QSO data before the async loop to avoid accessing SwiftData
    /// models that may be invalidated by concurrent operations during the upload.
    func uploadQSOs(_ qsos: [QSO]) async throws -> QRZUploadResult {
        guard !qsos.isEmpty else {
            return QRZUploadResult(
                uploaded: 0, duplicates: 0, failed: 0, skipped: 0,
                confirmedIDs: [], logIdsByPersistentID: [:]
            )
        }

        let mappings = getCallsignMappings()

        // Snapshot all QSO data upfront while models are guaranteed valid.
        // The upload loop below yields between requests (200ms sleeps),
        // during which iCloud sync or user edits can invalidate models.
        let snapshots = snapshotQSOsForUpload(qsos)

        return await uploadSnapshotsWithMappings(snapshots, mappings: mappings)
    }

    /// Capture ADIF content and metadata from live QSO models before the async loop.
    func snapshotQSOsForUpload(_ qsos: [QSO]) -> [QRZUploadSnapshot] {
        qsos.enumerated().map { index, qso in
            var adif = qso.rawADIF ?? generateADIF(for: qso)
            // CAR-243: When the rawADIF round-trip path is used, the ADIF may still
            // contain a <COMMENT:…> field from QRZ's own copy (or a prior auto-fill
            // of `notes`). Strip it when the user didn't author the notes — same
            // gate as `generateADIF(for:)` applies above.
            if qso.rawADIF != nil, !qso.notesUserAuthored {
                adif = Self.stripCommentField(from: adif)
            }
            if !adif.lowercased().contains("<eor>") {
                adif += " <eor>"
            }
            // Only REPLACE when we have a qrzLogId — meaning this QSO was downloaded
            // from QRZ and our copy includes QRZ's own data (possibly enriched).
            // Without qrzLogId, the QSO may exist on QRZ from a manual ADIF upload
            // and REPLACE would blank fields (frequency, grid) we don't have.
            let canReplace = qso.qrzLogId != nil
            return QRZUploadSnapshot(
                index: index,
                persistentID: qso.persistentModelID,
                adifContent: adif,
                myCallsign: qso.myCallsign,
                callsign: qso.callsign,
                band: qso.band,
                mode: qso.mode,
                timestamp: qso.timestamp,
                useReplace: canReplace
            )
        }
    }

    /// Remove the `<comment:N>VALUE` field from an ADIF record string. ADIF
    /// fields have a length-prefixed length; we parse just the COMMENT tag and
    /// drop exactly that many bytes from the value. Case-insensitive on the tag.
    /// Used by the rawADIF upload path so QRZ doesn't see leftover auto-filled
    /// comment content when the user didn't author the notes locally. CAR-243.
    nonisolated static func stripCommentField(from adif: String) -> String {
        let lower = adif.lowercased()
        guard let tagStart = lower.range(of: "<comment:") else {
            return adif
        }
        // Find the closing `>` of the length tag (skip any optional type suffix)
        guard let tagEnd = adif.range(
            of: ">", range: tagStart.upperBound ..< adif.endIndex
        ) else {
            return adif
        }
        let lengthSpec = adif[tagStart.upperBound ..< tagEnd.lowerBound]
        // Length spec is "N" or "N:T" (the T is an optional type indicator)
        let lengthStr = lengthSpec.split(separator: ":").first.map(String.init) ?? ""
        guard let length = Int(lengthStr), length >= 0 else {
            return adif
        }
        let valueStart = tagEnd.upperBound
        guard let valueEnd = adif.index(
            valueStart, offsetBy: length, limitedBy: adif.endIndex
        ) else {
            return adif
        }
        var stripped = adif
        stripped.removeSubrange(tagStart.lowerBound ..< valueEnd)
        // Collapse any leftover double spaces from the removal
        while stripped.contains("  ") {
            stripped = stripped.replacingOccurrences(of: "  ", with: " ")
        }
        return stripped.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - QRZClient Upload Loop

extension QRZClient {
    /// Upload pre-snapshotted QSOs one at a time, routing each to the correct
    /// API key based on its myCallsign. QSOs with no matching mapping are skipped.
    ///
    /// `nonisolated` so the request building, response parsing, and inter-request
    /// sleeps run on a background executor instead of the main actor — the upload
    /// loop is invoked from `@MainActor` UI contexts (e.g. the Sessions list) and
    /// would otherwise compete with scrolling and other rendering work.
    nonisolated func uploadSnapshotsWithMappings(
        _ snapshots: [QRZUploadSnapshot],
        mappings: [QRZCallsignMapping]
    ) async -> QRZUploadResult {
        var totalUploaded = 0
        var totalDuplicates = 0
        var totalFailed = 0
        var totalSkipped = 0
        var confirmedIDs = Set<PersistentIdentifier>()
        var logIdsByPersistentID: [PersistentIdentifier: String] = [:]

        let mappingsByCallsign = Dictionary(
            uniqueKeysWithValues: mappings.map { ($0.callsign, $0) }
        )

        for (position, snapshot) in snapshots.enumerated() {
            let mapping = resolveMapping(
                for: snapshot.myCallsign, lookupMap: mappingsByCallsign
            )
            guard let mapping else {
                totalSkipped += 1
                continue
            }

            let outcome = await uploadSingleSnapshot(
                snapshot, apiKey: mapping.apiKey, bookId: mapping.bookId
            )
            totalUploaded += outcome.uploaded
            totalDuplicates += outcome.duplicates
            totalFailed += outcome.failed
            if outcome.confirmed {
                confirmedIDs.insert(snapshot.persistentID)
            }
            if let logId = outcome.logId {
                logIdsByPersistentID[snapshot.persistentID] = logId
            }

            if position < snapshots.count - 1 {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        return QRZUploadResult(
            uploaded: totalUploaded, duplicates: totalDuplicates,
            failed: totalFailed, skipped: totalSkipped,
            confirmedIDs: confirmedIDs,
            logIdsByPersistentID: logIdsByPersistentID
        )
    }

    /// Resolve which mapping to use for a QSO's myCallsign.
    nonisolated private func resolveMapping(
        for myCallsign: String,
        lookupMap: [String: QRZCallsignMapping]
    ) -> QRZCallsignMapping? {
        let upper = myCallsign.uppercased()
        guard !upper.isEmpty else {
            // Empty myCallsign: fall back to primary mapping
            return lookupMap.values.first(where: \.isPrimary)
        }

        // Direct match
        if let direct = lookupMap[upper] {
            return direct
        }

        // Try base callsign (strips /P, /M, etc.)
        let base = CallsignAliasService.extractBaseCallsign(upper)
        return lookupMap[base]
    }

    /// Upload a single snapshot and return the outcome.
    nonisolated private func uploadSingleSnapshot(
        _ snapshot: QRZUploadSnapshot, apiKey: String, bookId: String?
    ) async -> QRZSingleUploadOutcome {
        do {
            let request = try buildUploadRequest(
                apiKey: apiKey, adifContent: snapshot.adifContent,
                bookId: bookId, useReplace: snapshot.useReplace
            )
            let result = try await executeQRZUpload(
                request: request, adifChars: snapshot.adifContent.count,
                qsoCount: 1, bookId: bookId
            )
            if result.uploaded >= 1 || result.duplicates >= 1 {
                return QRZSingleUploadOutcome(
                    uploaded: result.uploaded, duplicates: result.duplicates,
                    failed: 0, confirmed: true, logId: result.logId
                )
            }
            logSnapshotUploadFailure(snapshot, reason: "COUNT=0")
            return QRZSingleUploadOutcome(
                uploaded: 0, duplicates: 0, failed: 1, confirmed: false, logId: nil
            )
        } catch {
            logSnapshotUploadFailure(snapshot, reason: error.localizedDescription)
            return QRZSingleUploadOutcome(
                uploaded: 0, duplicates: 0, failed: 1, confirmed: false, logId: nil
            )
        }
    }

    /// Log a per-QSO upload failure using snapshot data (no model access needed).
    nonisolated private func logSnapshotUploadFailure(
        _ snapshot: QRZUploadSnapshot, reason: String
    ) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let dateStr = dateFormatter.string(from: snapshot.timestamp)
        let message = "QRZ per-QSO upload failed: \(snapshot.callsign) @ \(dateStr) "
            + "| \(snapshot.band) \(snapshot.mode) - \(reason)"
        Task { @MainActor in
            SyncDebugLog.shared.warning(message, service: .qrz)
        }
    }
}

// MARK: - QRZClient Upload Helpers

extension QRZClient {
    /// Execute QRZ upload request with response logging
    nonisolated func executeQRZUpload(
        request: URLRequest, adifChars: Int, qsoCount: Int, bookId: String?
    ) async throws -> QRZUploadResponse {
        await MainActor.run {
            SyncDebugLog.shared.debug(
                "QRZ upload request: \(qsoCount) QSO(s), "
                    + "ADIF \(adifChars) chars, bookId=\(bookId ?? "nil")",
                service: .qrz
            )
        }

        let uploadStart = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let durationMs = Int(Date().timeIntervalSince(uploadStart) * 1_000)
        let httpStatus = (response as? HTTPURLResponse)?.statusCode

        guard let responseString = String(data: data, encoding: .utf8) else {
            let dataCount = data.count
            await MainActor.run {
                SyncDebugLog.shared.error(
                    "QRZ response: HTTP \(httpStatus ?? 0) (\(durationMs)ms) "
                        + "- cannot decode \(dataCount) bytes as UTF-8",
                    service: .qrz
                )
            }
            throw QRZError.invalidResponse(
                "Cannot decode response as UTF-8, \(dataCount) bytes"
            )
        }

        await MainActor.run {
            let level: SyncDebugLog.LogEntry.Level =
                httpStatus.map { (200 ... 299).contains($0) } == true ? .debug : .error
            SyncDebugLog.shared.log(
                "QRZ response: HTTP \(httpStatus ?? 0) (\(durationMs)ms) "
                    + "\(responseString.prefix(500))",
                level: level, service: .qrz
            )
        }

        return try parseUploadResponse(responseString)
    }

    /// Filter QSOs to only those with a matching callsign mapping.
    func filterQSOsForUpload(
        _ qsos: [QSO], mappings: [QRZCallsignMapping]
    ) -> (matching: [QSO], skippedCount: Int) {
        guard !mappings.isEmpty else {
            return ([], qsos.count)
        }

        let mappedCallsigns = Set(mappings.map(\.callsign))
        let primaryCallsign = mappings.first(where: \.isPrimary)?.callsign
        var matching: [QSO] = []
        var skipped = 0

        for qso in qsos {
            let upper = qso.myCallsign.uppercased()
            if upper.isEmpty {
                // Empty myCallsign: include if we have a primary mapping
                if primaryCallsign != nil {
                    matching.append(qso)
                } else {
                    skipped += 1
                }
            } else if mappedCallsigns.contains(upper) {
                matching.append(qso)
            } else {
                let base = CallsignAliasService.extractBaseCallsign(upper)
                if mappedCallsigns.contains(base) {
                    matching.append(qso)
                } else {
                    skipped += 1
                }
            }
        }

        return (matching, skipped)
    }

    /// Build the upload request with proper headers and form data.
    /// - Parameter useReplace: When true, includes OPTION=REPLACE so QRZ overwrites
    ///   matching records. Only safe when our data is known to be at least as rich as QRZ's
    ///   (i.e., the QSO was previously downloaded from QRZ).
    nonisolated func buildUploadRequest(
        apiKey: String, adifContent: String, bookId: String?,
        useReplace: Bool = true
    ) throws -> URLRequest {
        guard let url = URL(string: baseURL) else {
            throw QRZError.invalidResponse("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var formData = [
            "KEY": apiKey, "ACTION": "INSERT", "ADIF": adifContent,
        ]
        if useReplace {
            formData["OPTION"] = "REPLACE"
        }
        if let bookId {
            formData["BOOKID"] = bookId
        }
        request.httpBody = formEncode(formData).data(using: .utf8)
        return request
    }

    /// Parse the upload response and return counts or throw appropriate error
    nonisolated func parseUploadResponse(_ responseString: String) throws -> QRZUploadResponse {
        let parsed = Self.parseResponse(responseString)

        if parsed["RESULT"] == "AUTH" {
            throw QRZError.sessionExpired
        }

        let result = parsed["RESULT"] ?? ""
        let reason = parsed["REASON"] ?? ""
        let reasonLower = reason.lowercased()

        // Handle duplicate responses (INSERT without REPLACE when QSO already exists).
        // QRZ may return FAIL/DUPE with a reason mentioning "duplicate" — treat as a
        // successful no-op rather than an error, since the QSO is already on QRZ.
        let isDuplicate = result == "DUPE"
            || (result == "FAIL" && reasonLower.contains("duplic"))
        if isDuplicate {
            let logId = parsed["LOGID"]
            return QRZUploadResponse(uploaded: 0, duplicates: 1, logId: logId)
        }

        guard result == "OK" || result == "REPLACE" || result == "PARTIAL" else {
            let displayReason = reason.isEmpty
                ? "Response: \(responseString.prefix(200))"
                : reason
            throw QRZError.uploadFailed(displayReason)
        }

        let count = Int(parsed["COUNT"] ?? "0") ?? 0
        let dupes = Int(parsed["DUPES"] ?? "0") ?? 0
        let logId = parsed["LOGID"]

        if result == "PARTIAL" {
            Task { @MainActor in
                SyncDebugLog.shared.warning(
                    "QRZ PARTIAL upload: \(count) accepted, \(dupes) dupes"
                        + (reason.isEmpty ? "" : ", reason=\(reason)"),
                    service: .qrz
                )
            }
        }

        return QRZUploadResponse(
            uploaded: count, duplicates: dupes, logId: logId
        )
    }
}
