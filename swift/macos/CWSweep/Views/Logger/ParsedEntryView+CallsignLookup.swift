import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - ParsedEntryView + Callsign Lookup

extension ParsedEntryView {
    /// Re-parses the entry text and mirrors the result into shared state so
    /// the Remote CW keyer can read live macros from Sweep instead of needing
    /// its own entry UI on iOS. Lives here because the bulk of what it does
    /// is feed the callsign-info lookup; keeping it next to that code keeps
    /// the main view body under SwiftLint's type_body_length cap.
    func parseEntry(_ text: String) {
        selectionState.entryInProgress = !text.isEmpty
        selectionState.entryCallsignGrid = nil

        guard !text.isEmpty else {
            parsedResult = nil
            selectionState.parsedQuickEntry = nil
            selectionState.entryCallsign = nil
            selectionState.entryCallsignName = nil
            clearCallsignLookup()
            return
        }
        let result = QuickEntryParser.parse(text)
        parsedResult = result

        let detectedCallsign: String? = if let result {
            result.callsign
        } else {
            extractLeadingCallsign(text)
        }

        selectionState.parsedQuickEntry = result
        selectionState.entryCallsign = detectedCallsign

        updateCallsignLookup(callsign: detectedCallsign, band: result?.band)
        contestParseIfNeeded(text: text, leadingCallsign: detectedCallsign)
    }

    func updateCallsignLookup(callsign: String?, band: String?) {
        if let callsign {
            let entity = dxccLookup.lookup(callsign)
            entryDXCCEntity = entity?.name
            if let entityName = entity?.name {
                let resolvedBand = band ?? BandUtilities.deriveBand(
                    from: radioManager.frequency * 1_000
                ) ?? ""
                entryNeededStatus = neededChecker.check(
                    entityName: entityName, band: resolvedBand
                )
            } else {
                entryNeededStatus = .unknown
            }
            lookupCallsignInfo(callsign)
        } else {
            clearCallsignLookup()
        }
    }

    func lookupCallsignInfo(_ callsign: String) {
        callsignLookupTask?.cancel()
        callsignLookupTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else {
                return
            }

            let upperCallsign = callsign.uppercased()
            let summaries = fetchPreviousQSOSummaries(callsign: upperCallsign)

            let info = await CallsignInfoCache.shared.lookup(
                callsign: upperCallsign,
                qsoSummaries: summaries
            )
            guard !Task.isCancelled else {
                return
            }
            callsignInfo = info
            selectionState.entryCallsignGrid = info.grid
            // Operator's first name only — keeps `{NAME}` short on the air.
            selectionState.entryCallsignName = info.operatorName?
                .components(separatedBy: .whitespaces)
                .first
            selectionState.entryCallsignState = info.qrzResult?.state ?? info.license?.state

            let store = PoloNotesStore.shared
            await store.ensureLoaded()
            guard !Task.isCancelled else {
                return
            }
            poloEntry = await store.info(for: upperCallsign)
            combinedEmoji = await store.combinedEmoji(for: upperCallsign)
        }
    }

    func extractLeadingCallsign(_ text: String) -> String? {
        let firstToken = text.trimmingCharacters(in: .whitespaces)
            .split(separator: " ", maxSplits: 1).first.map(String.init)
        guard let token = firstToken, QuickEntryParser.isCallsign(token.uppercased()) else {
            return nil
        }
        return token.uppercased()
    }

    func clearCallsignLookup() {
        entryDXCCEntity = nil
        entryNeededStatus = .unknown
        callsignInfo = nil
        poloEntry = nil
        combinedEmoji = nil
        selectionState.entryCallsignGrid = nil
        selectionState.entryCallsignName = nil
        selectionState.entryCallsignState = nil
        callsignLookupTask?.cancel()
    }

    /// Enrich a QSO with QRZ/HamDB data in the background after logging.
    func enrichQSOInBackground(_ qso: QSO) {
        let qsoId = qso.id
        let callsign = qso.callsign.uppercased()
        Task {
            let summaries = fetchPreviousQSOSummaries(callsign: callsign)
            let info = await CallsignInfoCache.shared.lookup(
                callsign: callsign, qsoSummaries: summaries
            )
            guard info.qrzResult != nil || info.license != nil else {
                return
            }

            let descriptor = BoundedDescriptor<QSO>(
                predicate: #Predicate { $0.id == qsoId }, limit: 1
            )
            guard let freshQSO = try? modelContext.boundedFetch(descriptor).first else {
                return
            }

            var changed = false
            if let qrzResult = info.qrzResult {
                changed = applyQRZData(to: freshQSO, from: qrzResult)
            }
            // Fill remaining nil fields from HamDB
            if let license = info.license {
                if applyHamDBData(to: freshQSO, from: license) {
                    changed = true
                }
            }
            if changed {
                freshQSO.modifiedAt = Date()
                try? CwStoreSeams.save(modelContext, qsos: [freshQSO])
                selectionState.logUpdatedQSORow = QSOTableRow(from: freshQSO)
            }
        }
    }

    /// Apply QRZ lookup data to a QSO, filling in nil fields. Returns true if any field changed.
    @discardableResult
    func applyQRZData(to qso: QSO, from qrz: QRZCallbookResult) -> Bool {
        var changed = false
        if qso.name == nil, let val = qrz.name {
            qso.name = val; changed = true
        }
        if qso.qth == nil, let val = qrz.city {
            qso.qth = val; changed = true
        }
        if qso.state == nil, let val = qrz.state {
            qso.state = val; changed = true
        }
        if qso.country == nil, let val = qrz.country {
            qso.country = val; changed = true
        }
        if qso.theirGrid == nil, let val = qrz.grid {
            qso.theirGrid = val; changed = true
        }
        if qso.theirLicenseClass == nil, let val = qrz.licenseClass {
            qso.theirLicenseClass = val; changed = true
        }
        if qso.callsignChangeNote == nil,
           let val = qrz.callsignChangeNote
        {
            qso.callsignChangeNote = val; changed = true
        }
        return changed
    }

    /// Apply HamDB lookup data to a QSO, filling in nil fields. Returns true if any field changed.
    @discardableResult
    func applyHamDBData(to qso: QSO, from license: HamDBLicense) -> Bool {
        var changed = false
        if qso.name == nil, let val = license.fullName, !val.isEmpty {
            qso.name = val; changed = true
        }
        if qso.qth == nil, let val = license.city, !val.isEmpty {
            qso.qth = val; changed = true
        }
        if qso.state == nil, let val = license.state, !val.isEmpty {
            qso.state = val; changed = true
        }
        if qso.country == nil, let val = license.country, !val.isEmpty {
            qso.country = val; changed = true
        }
        if qso.theirGrid == nil, let val = license.grid, !val.isEmpty {
            qso.theirGrid = val; changed = true
        }
        return changed
    }

    @MainActor
    func fetchPreviousQSOSummaries(callsign: String) -> [PreviousQSOSummary] {
        let descriptor = BoundedDescriptor<QSO>(
            predicate: #Predicate<QSO> { qso in
                qso.callsign == callsign && !qso.isHidden
            },
            sortBy: [SortDescriptor(\QSO.timestamp, order: .reverse)],
            limit: 10
        )

        guard let qsos = try? modelContext.boundedFetch(descriptor) else {
            return []
        }
        return qsos.map { qso in
            PreviousQSOSummary(
                timestamp: qso.timestamp,
                band: qso.band,
                mode: qso.mode,
                notes: qso.notes
            )
        }
    }
}
