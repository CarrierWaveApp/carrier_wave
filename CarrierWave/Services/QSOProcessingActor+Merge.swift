import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - QSOProcessingActor Merge & Creation

extension QSOProcessingActor {
    /// Merge fetched data into an existing QSO by ID.
    func mergeIntoExisting(
        existingId: UUID,
        fetchedGroup: [FetchedQSO],
        context: ModelContext
    ) throws {
        // Fetch the existing QSO by ID
        var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { $0.id == existingId })
        descriptor.fetchLimit = 1
        guard let existing = try context.fetch(descriptor).first else {
            return
        }

        for fetched in fetchedGroup {
            mergeFields(from: fetched, into: existing)
            markPresent(qso: existing, service: fetched.source, context: context)
        }

        // After merging all sources, apply comment park action for notes-extracted refs
        if let notes = existing.notes,
           let extracted = ParkReference.extractFromFreeText(notes)
        {
            switch commentParkAction {
            case .ignore:
                break
            case .theirPark:
                if existing.theirParkReference?.isEmpty ?? true {
                    existing.theirParkReference = extracted
                }
            case .myPark:
                if !existing.isActivityLogQSO, existing.parkReference?.isEmpty ?? true {
                    existing.parkReference = extracted
                }
            }
        }
    }

    /// Merge fields from a fetched QSO into an existing QSO (richest data wins).
    private func mergeFields(from fetched: FetchedQSO, into existing: QSO) {
        existing.frequency = existing.frequency ?? fetched.frequency
        existing.rstSent = existing.rstSent.nonEmpty ?? fetched.rstSent
        existing.rstReceived = existing.rstReceived.nonEmpty ?? fetched.rstReceived
        existing.myGrid = existing.myGrid.nonEmpty ?? fetched.myGrid
        existing.theirGrid = existing.theirGrid.nonEmpty ?? fetched.theirGrid

        // Combine explicit park references (only from MY_SIG_INFO / MY_POTA_REF)
        // Skip for activity log QSOs — they are hunter QSOs and should never get parkReference
        if !existing.isActivityLogQSO {
            let fetchedPark = fetched.parkReference.flatMap { ParkReference.sanitizeMulti($0) }
            existing.parkReference = FetchedQSO.combineParkReferences(
                existing.parkReference,
                fetchedPark
            )
        }

        // Apply comment park action for notes-extracted park refs
        let notesRef = fetched.notes.flatMap { ParkReference.extractFromFreeText($0) }
        switch commentParkAction {
        case .ignore:
            existing.theirParkReference =
                existing.theirParkReference.nonEmpty
                    ?? fetched.theirParkReference.flatMap { ParkReference.sanitize($0) }
        case .theirPark:
            existing.theirParkReference =
                existing.theirParkReference.nonEmpty
                    ?? fetched.theirParkReference.flatMap { ParkReference.sanitize($0) }
                    ?? notesRef
        case .myPark:
            existing.theirParkReference =
                existing.theirParkReference.nonEmpty
                    ?? fetched.theirParkReference.flatMap { ParkReference.sanitize($0) }
            if !existing.isActivityLogQSO, let notesRef {
                existing.parkReference = FetchedQSO.combineParkReferences(
                    existing.parkReference, notesRef
                )
            }
        }
        existing.notes = existing.notes.nonEmpty ?? fetched.notes
        existing.rawADIF = existing.rawADIF.nonEmpty ?? fetched.rawADIF
        existing.name = existing.name.nonEmpty ?? fetched.name
        existing.qth = existing.qth.nonEmpty ?? fetched.qth
        existing.state = existing.state.nonEmpty ?? fetched.state
        existing.country = existing.country.nonEmpty ?? fetched.country
        existing.power = existing.power ?? fetched.power
        existing.sotaRef = existing.sotaRef.nonEmpty ?? fetched.sotaRef

        // QRZ-specific
        if fetched.source == .qrz {
            existing.qrzLogId = existing.qrzLogId ?? fetched.qrzLogId
            existing.qrzConfirmed = existing.qrzConfirmed || fetched.qrzConfirmed
            existing.lotwConfirmedDate = existing.lotwConfirmedDate ?? fetched.lotwConfirmedDate
            existing.dxcc = existing.dxcc ?? fetched.dxcc
        }

        // LoTW-specific
        if fetched.source == .lotw {
            if fetched.lotwConfirmed {
                existing.lotwConfirmed = true
                existing.lotwConfirmedDate =
                    existing.lotwConfirmedDate ?? fetched.lotwConfirmedDate
            }
            existing.dxcc = existing.dxcc ?? fetched.dxcc
        }
    }

    /// Create a new QSO from a group of fetched QSOs (merges all sources).
    func createNewQSOFromGroup(_ fetchedGroup: [FetchedQSO], context: ModelContext) throws
        -> UUID
    {
        let merged = mergeFetchedGroup(fetchedGroup)
        let newQSO = createQSO(from: merged)
        context.insert(newQSO)

        // Create presence records for all sources that had this QSO
        let sources = Set(fetchedGroup.map(\.source))

        for service in ServiceType.allCases {
            // POTA uploads only apply to QSOs where user was activating from a park
            let skipPOTAUpload = service == .pota && (newQSO.parkReference?.isEmpty ?? true)

            let presence =
                if sources.contains(service) {
                    ServicePresence.downloaded(from: service, qso: newQSO)
                } else if service.supportsUpload, !skipPOTAUpload {
                    ServicePresence.needsUpload(to: service, qso: newQSO)
                } else {
                    ServicePresence(serviceType: service, isPresent: false, qso: newQSO)
                }
            context.insert(presence)
            newQSO.servicePresence.append(presence)
        }

        return newQSO.id
    }

    /// Mark QSO as present in a service.
    func markPresent(qso: QSO, service: ServiceType, context: ModelContext) {
        if let existing = qso.presence(for: service) {
            existing.isPresent = true
            existing.needsUpload = false
            existing.lastConfirmedAt = Date()
        } else {
            let newPresence = ServicePresence.downloaded(from: service, qso: qso)
            context.insert(newPresence)
            qso.servicePresence.append(newPresence)
        }
    }

    /// Merge multiple fetched QSOs into one.
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

    /// Create a QSO from merged fetched data.
    func createQSO(from fetched: FetchedQSO) -> QSO {
        // Apply comment park action for park refs found in notes
        let notesRef = fetched.notes.flatMap { ParkReference.extractFromFreeText($0) }
        var parkReference = fetched.parkReference
        var theirParkReference = fetched.theirParkReference

        if let notesRef {
            switch commentParkAction {
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
