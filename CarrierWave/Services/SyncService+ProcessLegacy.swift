import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - SyncService Legacy Synchronous Process Methods

extension SyncService {
    /// Synchronous version - prefer processDownloadedQSOsAsync for better UI responsiveness.
    func processDownloadedQSOs(_ fetched: [FetchedQSO]) throws -> ProcessResult {
        let debugLog = SyncDebugLog.shared

        // Group by deduplication key
        var byKey: [String: [FetchedQSO]] = [:]
        for qso in fetched {
            byKey[qso.deduplicationKey, default: []].append(qso)
        }

        // Count by source for diagnostics
        let breakdownStr = buildSourceBreakdown(fetched)
        debugLog.info("Processing \(fetched.count) QSOs: \(breakdownStr)")

        // Fetch existing QSOs
        let descriptor = FetchDescriptor<QSO>()
        let existingQSOs = try modelContext.fetch(descriptor)
        let existingByKey = Dictionary(grouping: existingQSOs) { $0.deduplicationKey }
        debugLog.info("Found \(existingQSOs.count) existing QSOs in database")

        var created = 0
        var merged = 0
        var createdQSOIds: [UUID] = []

        for (key, fetchedGroup) in byKey {
            if let existing = existingByKey[key]?.first {
                for fetchedQSO in fetchedGroup {
                    mergeIntoExisting(existing: existing, fetched: fetchedQSO)
                }
                merged += 1
            } else {
                let newQSO = createNewQSOFromGroup(fetchedGroup)
                createdQSOIds.append(newQSO.id)
                created += 1
            }
        }

        debugLog.info("Process result: created=\(created), merged=\(merged)")
        return ProcessResult(created: created, merged: merged, createdQSOIds: createdQSOIds)
    }

    private func buildSourceBreakdown(_ fetched: [FetchedQSO]) -> String {
        var sourceBreakdown: [ServiceType: Int] = [:]
        for qso in fetched {
            sourceBreakdown[qso.source, default: 0] += 1
        }
        return sourceBreakdown.map { "\($0.key.displayName)=\($0.value)" }.joined(separator: ", ")
    }

    @discardableResult
    private func createNewQSOFromGroup(_ fetchedGroup: [FetchedQSO]) -> QSO {
        let mergedFetched = mergeFetchedGroup(fetchedGroup)
        let newQSO = createQSO(from: mergedFetched)
        modelContext.insert(newQSO)

        // Create presence records for all sources that had this QSO
        let sources = Set(fetchedGroup.map(\.source))

        // Create presence record for ALL services
        for service in ServiceType.allCases {
            // POTA uploads only apply to QSOs where user was activating from a park
            let skipPOTAUpload = service == .pota && (newQSO.parkReference?.isEmpty ?? true)

            let presence =
                if sources.contains(service) {
                    // QSO came from this service - mark as present
                    ServicePresence.downloaded(from: service, qso: newQSO)
                } else if service.supportsUpload, !skipPOTAUpload {
                    // Bidirectional service without this QSO - needs upload
                    ServicePresence.needsUpload(to: service, qso: newQSO)
                } else {
                    // Download-only service without this QSO - not present, no upload needed
                    ServicePresence(serviceType: service, isPresent: false, qso: newQSO)
                }
            modelContext.insert(presence)
            newQSO.servicePresence.append(presence)
        }

        return newQSO
    }

    /// Reconcile QRZ presence records against what QRZ actually returned.
    /// Clears isPresent and sets needsUpload for QSOs that we thought were in QRZ but aren't.
    /// Uses callsign aliases to properly match QSOs logged under previous callsigns.
    func reconcileQRZPresence(downloadedKeys: Set<String>) async throws {
        let descriptor = FetchDescriptor<QSO>()
        let allQSOs = try modelContext.fetch(descriptor)

        // Get user's callsign aliases for matching
        let aliasService = await MainActor.run { CallsignAliasService.shared }
        let userCallsigns = await MainActor.run { aliasService.getAllUserCallsigns() }

        for qso in allQSOs {
            guard let presence = qso.presence(for: .qrz), presence.isPresent else {
                continue
            }

            // Check if QRZ returned this QSO or an equivalent one under a different user callsign
            let isPresent = isQSOPresentInDownloaded(
                qso: qso,
                downloadedKeys: downloadedKeys,
                userCallsigns: userCallsigns
            )

            if !isPresent {
                presence.isPresent = false
                presence.needsUpload = true
            }
        }
    }

    /// Check if a QSO is present in the downloaded set, considering callsign aliases.
    private func isQSOPresentInDownloaded(
        qso: QSO,
        downloadedKeys: Set<String>,
        userCallsigns: Set<String>
    ) -> Bool {
        // First, check exact match
        if downloadedKeys.contains(qso.deduplicationKey) {
            return true
        }

        // If the QSO's myCallsign is one of the user's callsigns, check if any variant exists
        let myCallsign = qso.myCallsign.uppercased()
        guard !myCallsign.isEmpty, userCallsigns.contains(myCallsign) else {
            return false
        }

        // The deduplication key already ignores MYCALLSIGN (it uses contacted station),
        // so if the exact key isn't found, the QSO truly isn't present
        return false
    }

    /// Merge fetched QSO data into existing QSO (richest data wins)
    func mergeIntoExisting(existing: QSO, fetched: FetchedQSO) {
        existing.frequency = existing.frequency ?? fetched.frequency
        existing.rstSent = existing.rstSent.nonEmpty ?? fetched.rstSent
        existing.rstReceived = existing.rstReceived.nonEmpty ?? fetched.rstReceived
        existing.myGrid = existing.myGrid.nonEmpty ?? fetched.myGrid
        existing.theirGrid = existing.theirGrid.nonEmpty ?? fetched.theirGrid
        existing.parkReference = FetchedQSO.combineParkReferences(
            existing.parkReference,
            fetched.parkReference.flatMap { ParkReference.sanitizeMulti($0) }
        )
        existing.theirParkReference =
            existing.theirParkReference.nonEmpty
                ?? fetched.theirParkReference.flatMap { ParkReference.sanitize($0) }
        existing.notes = existing.notes.nonEmpty ?? fetched.notes
        existing.rawADIF = existing.rawADIF.nonEmpty ?? fetched.rawADIF
        existing.name = existing.name.nonEmpty ?? fetched.name
        existing.qth = existing.qth.nonEmpty ?? fetched.qth
        existing.state = existing.state.nonEmpty ?? fetched.state
        existing.country = existing.country.nonEmpty ?? fetched.country
        existing.power = existing.power ?? fetched.power
        existing.myRig = existing.myRig.nonEmpty ?? fetched.myRig
        existing.sotaRef = existing.sotaRef.nonEmpty ?? fetched.sotaRef

        // QRZ-specific: only update from QRZ source
        if fetched.source == .qrz {
            existing.qrzLogId = existing.qrzLogId ?? fetched.qrzLogId
            existing.qrzConfirmed = existing.qrzConfirmed || fetched.qrzConfirmed
            existing.lotwConfirmedDate = existing.lotwConfirmedDate ?? fetched.lotwConfirmedDate
            // DXCC from QRZ if we don't have one yet
            existing.dxcc = existing.dxcc ?? fetched.dxcc
        }

        // LoTW-specific: update confirmation status and DXCC
        if fetched.source == .lotw {
            if fetched.lotwConfirmed {
                existing.lotwConfirmed = true
                existing.lotwConfirmedDate = existing.lotwConfirmedDate ?? fetched.lotwConfirmedDate
            }
            // DXCC from LoTW is authoritative
            existing.dxcc = existing.dxcc ?? fetched.dxcc
        }

        // Update or create ServicePresence
        existing.markPresent(in: fetched.source, context: modelContext)
    }

    /// Update existing QSO with all fields from fetched data (for force re-download)
    func updateExistingQSO(existing: QSO, from fetched: FetchedQSO) {
        existing.frequency = fetched.frequency
        existing.rstSent = fetched.rstSent
        existing.rstReceived = fetched.rstReceived
        existing.myGrid = fetched.myGrid
        existing.theirGrid = fetched.theirGrid
        existing.parkReference = fetched.parkReference
        existing.theirParkReference = fetched.theirParkReference
        existing.notes = fetched.notes
        existing.rawADIF = fetched.rawADIF
        existing.name = fetched.name
        existing.qth = fetched.qth
        existing.state = fetched.state
        existing.country = fetched.country
        existing.power = fetched.power
        existing.myRig = fetched.myRig
        existing.sotaRef = fetched.sotaRef

        // QRZ-specific
        if fetched.source == .qrz {
            existing.qrzLogId = fetched.qrzLogId
            existing.qrzConfirmed = fetched.qrzConfirmed
            existing.lotwConfirmedDate = fetched.lotwConfirmedDate
            existing.dxcc = existing.dxcc ?? fetched.dxcc
        }

        // LoTW-specific
        if fetched.source == .lotw {
            existing.lotwConfirmed = fetched.lotwConfirmed
            existing.lotwConfirmedDate = fetched.lotwConfirmedDate
            existing.dxcc = fetched.dxcc
        }

        existing.markPresent(in: fetched.source, context: modelContext)
    }

    /// Reprocess fetched QSOs, updating existing ones instead of skipping
    func reprocessQSOs(_ fetched: [FetchedQSO]) throws -> (updated: Int, created: Int) {
        let debugLog = SyncDebugLog.shared
        debugLog.info("Reprocessing \(fetched.count) QSOs (force re-download)")

        let descriptor = FetchDescriptor<QSO>()
        let existingQSOs = try modelContext.fetch(descriptor)
        let existingByKey = Dictionary(grouping: existingQSOs) { $0.deduplicationKey }

        var updated = 0
        var created = 0

        for fetchedQSO in fetched {
            let key = fetchedQSO.deduplicationKey
            if let existing = existingByKey[key]?.first {
                updateExistingQSO(existing: existing, from: fetchedQSO)
                updated += 1
            } else {
                let newQSO = createQSO(from: fetchedQSO)
                modelContext.insert(newQSO)
                createPresenceForNewQSO(newQSO, source: fetchedQSO.source)
                created += 1
            }
        }

        try modelContext.save()
        debugLog.info("Reprocess complete: updated=\(updated), created=\(created)")
        return (updated, created)
    }

    /// Create presence records for a newly created QSO
    private func createPresenceForNewQSO(_ qso: QSO, source: ServiceType) {
        for service in ServiceType.allCases {
            // POTA uploads only apply to QSOs where user was activating from a park
            let skipPOTAUpload = service == .pota && (qso.parkReference?.isEmpty ?? true)

            let presence =
                if service == source {
                    ServicePresence.downloaded(from: service, qso: qso)
                } else if service.supportsUpload, !skipPOTAUpload {
                    ServicePresence.needsUpload(to: service, qso: qso)
                } else {
                    ServicePresence(serviceType: service, isPresent: false, qso: qso)
                }
            modelContext.insert(presence)
            qso.servicePresence.append(presence)
        }
    }

    /// Merge multiple fetched QSOs into one (for new QSO creation)
    func mergeFetchedGroup(_ group: [FetchedQSO]) -> FetchedQSO {
        guard var merged = group.first else {
            fatalError("Empty group in mergeFetchedGroup")
        }

        for other in group.dropFirst() {
            merged = FetchedQSO(
                callsign: merged.callsign,
                band: merged.band,
                mode: merged.mode,
                frequency: merged.frequency ?? other.frequency,
                timestamp: merged.timestamp,
                rstSent: merged.rstSent.nonEmpty ?? other.rstSent,
                rstReceived: merged.rstReceived.nonEmpty ?? other.rstReceived,
                myCallsign: merged.myCallsign.isEmpty ? other.myCallsign : merged.myCallsign,
                myGrid: merged.myGrid.nonEmpty ?? other.myGrid,
                theirGrid: merged.theirGrid.nonEmpty ?? other.theirGrid,
                parkReference: FetchedQSO.combineParkReferences(merged.parkReference, other.parkReference),
                theirParkReference: merged.theirParkReference.nonEmpty ?? other.theirParkReference,
                notes: merged.notes.nonEmpty ?? other.notes,
                rawADIF: merged.rawADIF.nonEmpty ?? other.rawADIF,
                name: merged.name.nonEmpty ?? other.name,
                qth: merged.qth.nonEmpty ?? other.qth,
                state: merged.state.nonEmpty ?? other.state,
                country: merged.country.nonEmpty ?? other.country,
                power: merged.power ?? other.power,
                myRig: merged.myRig.nonEmpty ?? other.myRig,
                sotaRef: merged.sotaRef.nonEmpty ?? other.sotaRef,
                qrzLogId: merged.qrzLogId ?? other.qrzLogId,
                qrzConfirmed: merged.qrzConfirmed || other.qrzConfirmed,
                lotwConfirmedDate: merged.lotwConfirmedDate ?? other.lotwConfirmedDate,
                lotwConfirmed: merged.lotwConfirmed || other.lotwConfirmed,
                dxcc: merged.dxcc ?? other.dxcc,
                source: merged.source
            )
        }

        return merged
    }

    /// Create a QSO from merged fetched data
    func createQSO(from fetched: FetchedQSO) -> QSO {
        // Apply comment park action for park refs found in notes
        let notesRef = fetched.notes.flatMap { ParkReference.extractFromFreeText($0) }
        var parkReference = fetched.parkReference
        var theirParkReference = fetched.theirParkReference

        if let notesRef {
            switch CommentParkAction.current {
            case .ignore:
                break
            case .theirPark:
                theirParkReference = theirParkReference.nonEmpty ?? notesRef
            case .myPark:
                parkReference = FetchedQSO.combineParkReferences(parkReference, notesRef)
            }
        }

        return QSO(
            callsign: fetched.callsign,
            band: fetched.band,
            mode: fetched.mode,
            frequency: fetched.frequency,
            timestamp: fetched.timestamp,
            rstSent: fetched.rstSent,
            rstReceived: fetched.rstReceived,
            myCallsign: fetched.myCallsign,
            myGrid: fetched.myGrid,
            theirGrid: fetched.theirGrid,
            parkReference: parkReference,
            theirParkReference: theirParkReference,
            notes: fetched.notes,
            importSource: fetched.source.toImportSource,
            rawADIF: fetched.rawADIF,
            name: fetched.name,
            qth: fetched.qth,
            state: fetched.state,
            country: fetched.country,
            power: fetched.power,
            myRig: fetched.myRig,
            sotaRef: fetched.sotaRef,
            qrzLogId: fetched.qrzLogId,
            qrzConfirmed: fetched.qrzConfirmed,
            lotwConfirmedDate: fetched.lotwConfirmedDate,
            lotwConfirmed: fetched.lotwConfirmed,
            dxcc: fetched.dxcc
        )
    }
}
