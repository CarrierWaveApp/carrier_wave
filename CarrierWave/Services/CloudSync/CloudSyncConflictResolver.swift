import CarrierWaveCore
import Foundation

/// Conflict resolution strategies for each synced model type.
/// Called when the same record is modified on two devices simultaneously.
enum CloudSyncConflictResolver {
    // MARK: - QSO: Field-Level Merge

    /// Merge two versions of a QSO, preferring the version with the newer modificationDate
    /// for fields changed on both sides.
    /// - Parameters:
    ///   - local: The local QSO's current field values
    ///   - remote: The incoming CKRecord field values
    ///   - base: The base version (last known synced state), if available
    /// - Returns: Merged field values to apply to the local QSO
    static func mergeQSO(
        local: QSOFields,
        remote: QSOFields,
        localModDate: Date,
        remoteModDate: Date
    ) -> QSOFields {
        // For each field, if only one side changed from the common ancestor,
        // take that change. If both changed, prefer newer modificationDate.
        // Since we don't store field-level base versions, we use a simpler approach:
        // prefer the newer modification date for differing fields.
        let preferRemote = remoteModDate > localModDate

        return QSOFields(
            id: local.id,
            callsign: pickString(local.callsign, remote.callsign, preferRemote: preferRemote),
            band: pickString(local.band, remote.band, preferRemote: preferRemote),
            mode: pickString(local.mode, remote.mode, preferRemote: preferRemote),
            frequency: pickOptional(local.frequency, remote.frequency, preferRemote: preferRemote),
            timestamp: pickValue(local.timestamp, remote.timestamp, preferRemote: preferRemote),
            rstSent: pickOptional(local.rstSent, remote.rstSent, preferRemote: preferRemote),
            rstReceived: pickOptional(
                local.rstReceived, remote.rstReceived, preferRemote: preferRemote
            ),
            myCallsign: pickString(
                local.myCallsign, remote.myCallsign, preferRemote: preferRemote
            ),
            myGrid: pickOptional(local.myGrid, remote.myGrid, preferRemote: preferRemote),
            theirGrid: pickOptional(local.theirGrid, remote.theirGrid, preferRemote: preferRemote),
            parkReference: pickOptional(
                local.parkReference, remote.parkReference, preferRemote: preferRemote
            ),
            theirParkReference: pickOptional(
                local.theirParkReference, remote.theirParkReference, preferRemote: preferRemote
            ),
            // Notes: concatenate if both changed to different values
            notes: mergeNotes(local: local.notes, remote: remote.notes),
            importSource: local.importSource, // keep local
            importedAt: min(local.importedAt, remote.importedAt), // earliest
            // rawADIF: never overwrite non-nil with nil
            rawADIF: local.rawADIF ?? remote.rawADIF,
            name: pickOptional(local.name, remote.name, preferRemote: preferRemote),
            qth: pickOptional(local.qth, remote.qth, preferRemote: preferRemote),
            state: pickOptional(local.state, remote.state, preferRemote: preferRemote),
            country: pickOptional(local.country, remote.country, preferRemote: preferRemote),
            power: pickOptional(local.power, remote.power, preferRemote: preferRemote),
            myRig: pickOptional(local.myRig, remote.myRig, preferRemote: preferRemote),
            stationProfileName: pickOptional(
                local.stationProfileName, remote.stationProfileName, preferRemote: preferRemote
            ),
            sotaRef: pickOptional(local.sotaRef, remote.sotaRef, preferRemote: preferRemote),
            qrzLogId: pickOptional(local.qrzLogId, remote.qrzLogId, preferRemote: preferRemote),
            qrzConfirmed: local.qrzConfirmed || remote.qrzConfirmed,
            lotwConfirmedDate: pickOptional(
                local.lotwConfirmedDate, remote.lotwConfirmedDate, preferRemote: preferRemote
            ),
            lotwConfirmed: local.lotwConfirmed || remote.lotwConfirmed,
            dxcc: pickOptional(local.dxcc, remote.dxcc, preferRemote: preferRemote),
            theirLicenseClass: pickOptional(
                local.theirLicenseClass, remote.theirLicenseClass, preferRemote: preferRemote
            ),
            // isHidden: delete wins (if either is hidden, stay hidden)
            isHidden: local.isHidden || remote.isHidden,
            isActivityLogQSO: local.isActivityLogQSO || remote.isActivityLogQSO,
            loggingSessionId: pickOptional(
                local.loggingSessionId, remote.loggingSessionId, preferRemote: preferRemote
            )
        )
    }

    // MARK: - ServicePresence: Union Merge

    /// Merge service presence using union semantics.
    /// Upload status propagates in one direction: once present, stays present.
    static func mergeServicePresence(
        local: ServicePresenceFields,
        remote: ServicePresenceFields
    ) -> ServicePresenceFields {
        ServicePresenceFields(
            id: local.id,
            serviceType: local.serviceType,
            isPresent: local.isPresent || remote.isPresent,
            needsUpload: local.needsUpload && remote.needsUpload,
            uploadRejected: local.uploadRejected || remote.uploadRejected,
            isSubmitted: local.isSubmitted || remote.isSubmitted,
            lastConfirmedAt: newerOptionalDate(local.lastConfirmedAt, remote.lastConfirmedAt),
            parkReference: local.parkReference ?? remote.parkReference,
            qsoUUID: local.qsoUUID ?? remote.qsoUUID
        )
    }

    // MARK: - LoggingSession: Last-Writer-Wins (with qsoCount max)

    /// Merge logging session using last-writer-wins.
    /// Exception: qsoCount takes the maximum of both values.
    static func mergeLoggingSession(
        local: LoggingSessionFields,
        remote: LoggingSessionFields,
        localModDate: Date,
        remoteModDate: Date
    ) -> LoggingSessionFields {
        let winner = remoteModDate > localModDate ? remote : local

        return LoggingSessionFields(
            id: local.id,
            myCallsign: winner.myCallsign,
            startedAt: winner.startedAt,
            endedAt: winner.endedAt,
            frequency: winner.frequency,
            mode: winner.mode,
            activationTypeRawValue: winner.activationTypeRawValue,
            statusRawValue: winner.statusRawValue,
            parkReference: winner.parkReference,
            sotaReference: winner.sotaReference,
            myGrid: winner.myGrid,
            power: winner.power,
            myRig: winner.myRig,
            notes: winner.notes,
            customTitle: winner.customTitle,
            qsoCount: max(local.qsoCount, remote.qsoCount), // always take max
            isRove: winner.isRove,
            myAntenna: winner.myAntenna,
            myKey: winner.myKey,
            myMic: winner.myMic,
            extraEquipment: winner.extraEquipment,
            attendees: winner.attendees,
            photoFilenames: winner.photoFilenames,
            spotCommentsData: winner.spotCommentsData,
            roveStopsData: winner.roveStopsData,
            solarKIndex: winner.solarKIndex,
            solarFlux: winner.solarFlux,
            solarSunspots: winner.solarSunspots,
            solarPropagationRating: winner.solarPropagationRating,
            solarAIndex: winner.solarAIndex,
            solarBandConditions: winner.solarBandConditions,
            solarTimestamp: winner.solarTimestamp,
            solarConditions: winner.solarConditions,
            weatherTemperatureF: winner.weatherTemperatureF,
            weatherTemperatureC: winner.weatherTemperatureC,
            weatherHumidity: winner.weatherHumidity,
            weatherWindSpeed: winner.weatherWindSpeed,
            weatherWindDirection: winner.weatherWindDirection,
            weatherDescription: winner.weatherDescription,
            weatherTimestamp: winner.weatherTimestamp,
            weather: winner.weather
        )
    }

    // MARK: - ActivationMetadata: Last-Writer-Wins

    static func mergeActivationMetadata(
        local: ActivationMetadataFields,
        remote: ActivationMetadataFields,
        localModDate: Date,
        remoteModDate: Date
    ) -> ActivationMetadataFields {
        remoteModDate > localModDate ? remote : local
    }

    // MARK: - Private Helpers

    private static func pickString(
        _ local: String,
        _ remote: String,
        preferRemote: Bool
    ) -> String {
        if local == remote { return local }
        return preferRemote ? remote : local
    }

    private static func pickValue<T: Equatable>(
        _ local: T,
        _ remote: T,
        preferRemote: Bool
    ) -> T {
        if local == remote { return local }
        return preferRemote ? remote : local
    }

    private static func pickOptional<T: Equatable>(
        _ local: T?,
        _ remote: T?,
        preferRemote: Bool
    ) -> T? {
        if local == remote { return local }
        // If one side has data and the other doesn't, prefer the one with data
        if local == nil { return remote }
        if remote == nil { return local }
        // Both have different values — prefer by timestamp
        return preferRemote ? remote : local
    }

    private static func mergeNotes(local: String?, remote: String?) -> String? {
        if local == remote { return local }
        if local == nil { return remote }
        if remote == nil { return local }
        // Both have different values — concatenate
        return "\(local!)\n---\n\(remote!)"
    }

    private static func newerOptionalDate(_ a: Date?, _ b: Date?) -> Date? {
        switch (a, b) {
        case (.some(let dateA), .some(let dateB)):
            return dateA > dateB ? dateA : dateB
        case (.some, .none):
            return a
        case (.none, .some):
            return b
        case (.none, .none):
            return nil
        }
    }
}
