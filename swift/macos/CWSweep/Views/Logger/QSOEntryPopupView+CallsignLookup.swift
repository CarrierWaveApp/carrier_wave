import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - QSOEntryPopupView + Callsign Lookup

extension QSOEntryPopupView {
    func updateCallsignLookup(callsign: String?, band: String?) {
        if let callsign {
            let entity = dxccLookup.lookup(callsign)
            entryDXCCEntity = entity?.name
            if let entityName = entity?.name {
                let resolvedBand = band ?? ""
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
        lookupStatus = "Looking up \(callsign.uppercased())..."
        callsignLookupTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else {
                lookupStatus = nil
                return
            }

            let upperCallsign = callsign.uppercased()
            let summaries = fetchPreviousQSOSummaries(
                callsign: upperCallsign
            )

            let info = await CallsignInfoCache.shared.lookup(
                callsign: upperCallsign,
                qsoSummaries: summaries
            )
            guard !Task.isCancelled else {
                lookupStatus = nil
                return
            }
            callsignInfo = info
            autoFillFromLookup(info)

            let store = PoloNotesStore.shared
            await store.ensureLoaded()
            guard !Task.isCancelled else {
                return
            }
            poloEntry = await store.info(for: upperCallsign)
            combinedEmoji = await store.combinedEmoji(for: upperCallsign)

            updateLookupStatus(info: info, callsign: upperCallsign)
        }
    }

    /// Auto-fill empty form fields from callsign lookup data
    func autoFillFromLookup(_ info: CallsignInfo) {
        if name.isEmpty, let opName = info.operatorName {
            name = opName
        }
        if theirGrid.isEmpty, let grid = info.grid {
            theirGrid = grid
        }
        if qth.isEmpty, let loc = info.location {
            qth = loc
        }
        if state.isEmpty {
            let st = info.qrzResult?.state ?? info.license?.state
            if let st, !st.isEmpty {
                state = st
            }
        }
    }

    /// Update lookup status text based on available sources
    func updateLookupStatus(info: CallsignInfo, callsign: String) {
        var sources: [String] = []
        if info.qrzResult != nil {
            sources.append("QRZ")
        }
        if info.license != nil {
            sources.append("HamDB")
        }
        if poloEntry != nil {
            sources.append("Notes")
        }
        if info.previousQSOCount > 0 {
            sources.append("\(info.previousQSOCount) prev")
        }
        lookupStatus = sources.isEmpty
            ? "No data found for \(callsign)" : nil
    }

    func extractLeadingCallsign(_ text: String) -> String? {
        let firstToken = text.trimmingCharacters(in: .whitespaces)
            .split(separator: " ", maxSplits: 1).first.map(String.init)
        guard let token = firstToken,
              QuickEntryParser.isCallsign(token.uppercased())
        else {
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
        lookupStatus = nil
        callsignLookupTask?.cancel()
    }

    @MainActor
    func fetchPreviousQSOSummaries(
        callsign: String
    ) -> [PreviousQSOSummary] {
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
