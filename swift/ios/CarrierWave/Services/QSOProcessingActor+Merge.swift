import CarrierWaveData
import Foundation
import SwiftData

// MARK: - QSOProcessingActor Merge & Creation

extension QSOProcessingActor {
    /// Merge fetched data into an existing QSO by ID. Returns the merged QSO (or
    /// `nil` if it no longer exists) so the caller can route it — with its presence
    /// rows — through the off-main seam before the batch save.
    @discardableResult
    func mergeIntoExisting(
        existingId: UUID,
        fetchedGroup: [FetchedQSO],
        context: ModelContext
    ) throws -> QSO? {
        // Fetch the existing QSO by ID
        let descriptor = BoundedDescriptor<QSO>(
            predicate: #Predicate { $0.id == existingId },
            limit: 1
        )
        guard let existing = try context.boundedFetch(descriptor).first else {
            return nil
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
        return existing
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
        existing.wwffRef = existing.wwffRef.nonEmpty ?? fetched.wwffRef

        mergeSourceSpecificFields(from: fetched, into: existing)
    }

    /// Merge source-specific fields (QRZ, LoTW) from fetched QSO into existing.
    private func mergeSourceSpecificFields(from fetched: FetchedQSO, into existing: QSO) {
        if fetched.source == .qrz {
            existing.qrzLogId = existing.qrzLogId ?? fetched.qrzLogId
            existing.qrzConfirmed = existing.qrzConfirmed || fetched.qrzConfirmed
            existing.lotwConfirmedDate = existing.lotwConfirmedDate ?? fetched.lotwConfirmedDate
            existing.lotwConfirmed = existing.lotwConfirmed || fetched.lotwConfirmed
            existing.dxcc = existing.dxcc ?? fetched.dxcc
        }

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
    /// Returns the inserted QSO so the caller can route it (with its presence rows)
    /// through the off-main seam before the batch save.
    func createNewQSOFromGroup(_ fetchedGroup: [FetchedQSO], context: ModelContext) throws
        -> QSO
    {
        let merged = try mergeFetchedGroup(fetchedGroup)
        warnIfShadowsEditedLocalQSO(merged: merged, context: context)
        let newQSO = createQSO(from: merged)
        context.insert(newQSO)

        // Create presence records for all sources that had this QSO
        let sources = Set(fetchedGroup.map(\.source))

        // CAR-278: PoLo marker rows (`QSOMode.metadataModes`) are not QSOs —
        // no uploader will ever send them, so never arm needsUpload.
        let isMetadata = QSOMode.isMetadata(newQSO.mode)

        for service in ServiceType.allCases {
            // POTA uploads only apply to QSOs where user was activating from a park
            let skipPOTAUpload = service == .pota && (newQSO.parkReference?.isEmpty ?? true)

            // Only mark needsUpload for services that are actually configured
            let isConfiguredUpload = service.supportsUpload
                && configuredUploadServices.contains(service) && !skipPOTAUpload
                && !isMetadata

            let presence =
                if sources.contains(service) {
                    ServicePresence.downloaded(from: service, qso: newQSO)
                } else if isConfiguredUpload {
                    ServicePresence.needsUpload(to: service, qso: newQSO)
                } else {
                    ServicePresence(serviceType: service, isPresent: false, qso: newQSO)
                }
            presence.cloudDirtyFlag = true
            context.insert(presence)
            newQSO.servicePresence.append(presence)
        }

        return newQSO
    }

    /// Mark QSO as present in a service.
    func markPresent(qso: QSO, service: ServiceType, context: ModelContext) {
        if let existing = qso.presence(for: service) {
            // CAR-244: only dirty for CloudKit when meaningful state actually
            // changes. `lastConfirmedAt` is a per-pass heartbeat — refreshing
            // it alone shouldn't trigger an outbound sync, otherwise every
            // upload pass churns presence and feeds the inbound→outbound echo.
            let stateChanged = !existing.isPresent || existing.needsUpload
            existing.isPresent = true
            existing.needsUpload = false
            existing.lastConfirmedAt = Date()
            if stateChanged {
                existing.cloudDirtyFlag = true
            }
        } else {
            let newPresence = ServicePresence.downloaded(from: service, qso: qso)
            newPresence.cloudDirtyFlag = true
            context.insert(newPresence)
            qso.servicePresence.append(newPresence)
        }
    }

    /// Merge multiple fetched QSOs into one.
    /// - Precondition: group must not be empty (caller ensures via Dictionary grouping)
    func mergeFetchedGroup(_ group: [FetchedQSO]) throws -> FetchedQSO {
        guard var merged = group.first else {
            throw QSOProcessingError.emptyGroup
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
                wwffRef: merged.wwffRef.nonEmpty ?? other.wwffRef,
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
            wwffRef: fetched.wwffRef,
            qrzLogId: fetched.qrzLogId,
            qrzConfirmed: fetched.qrzConfirmed,
            lotwConfirmedDate: fetched.lotwConfirmedDate,
            lotwConfirmed: fetched.lotwConfirmed,
            dxcc: fetched.dxcc
        )
    }

    /// Diagnostic for CAR-245: warn when a download is about to insert a new
    /// QSO that "looks like" an existing local QSO whose contact callsign was
    /// edited (same myCallsign + band + mode + 2-min timestamp bucket, but a
    /// different callsign). This pattern means the originalCallsign-based
    /// dedup did not catch the match — usually because the local edit
    /// happened before the originalCallsign field existed (data predates the
    /// CAR-245 fix), or because the edit went through a path that didn't set
    /// originalCallsign. Logs to the iOS internal sync log so the bug can be
    /// detected in user reports.
    private func warnIfShadowsEditedLocalQSO(
        merged: FetchedQSO, context: ModelContext
    ) {
        let bucketStart = Date(
            timeIntervalSince1970: TimeInterval(
                Int(merged.timestamp.timeIntervalSince1970 / 120) * 120
            )
        )
        let bucketEnd = bucketStart.addingTimeInterval(120)
        let myCall = merged.myCallsign.uppercased()
        let band = merged.band.uppercased()
        let descriptor = BoundedDescriptor<QSO>(
            predicate: #Predicate {
                $0.myCallsign == myCall
                    && $0.band == band
                    && $0.timestamp >= bucketStart
                    && $0.timestamp < bucketEnd
                    && !$0.isHidden
            },
            limit: 5
        )
        let candidates = (try? context.boundedFetch(descriptor)) ?? []
        let canonicalIncomingMode = ModeEquivalence.canonicalNameForDedup(merged.mode)
        let trimmedIncoming = merged.callsign
            .trimmingCharacters(in: .whitespaces).uppercased()
        for existing in candidates {
            let existingCanonicalMode = ModeEquivalence.canonicalNameForDedup(existing.mode)
            guard existingCanonicalMode == canonicalIncomingMode else {
                continue
            }
            let existingCall = existing.callsign
                .trimmingCharacters(in: .whitespaces).uppercased()
            guard existingCall != trimmedIncoming else {
                continue
            }
            let message = "CAR-245 shadow detected: download is inserting "
                + "new QSO with callsign=\(trimmedIncoming) but a local QSO "
                + "already exists at \(existing.timestamp) with callsign="
                + "\(existingCall) (myCallsign=\(myCall), band=\(band), "
                + "mode=\(canonicalIncomingMode), originalCallsign="
                + "\(existing.originalCallsign ?? "nil")). This will create "
                + "a duplicate that uploads to POTA twice."
            Task { @MainActor in
                SyncDebugLog.shared.warning(message, service: .qrz)
            }
            return
        }
    }
}
