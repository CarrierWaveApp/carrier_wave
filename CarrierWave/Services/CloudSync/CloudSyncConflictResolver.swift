import CarrierWaveCore
import Foundation

// MARK: - CloudSyncConflictResolver

/// Conflict resolution strategies for each synced model type.
/// Called when the same record is modified on two devices simultaneously.
enum CloudSyncConflictResolver {
    // MARK: - QSO: Field-Level Merge

    /// Merge two versions of a QSO, preferring the newer modificationDate for differing fields.
    nonisolated static func mergeQSO(
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

        let coreFields = mergeQSOCoreFields(
            local: local, remote: remote, preferRemote: preferRemote
        )
        let extraFields = mergeQSOExtraFields(
            local: local, remote: remote, preferRemote: preferRemote
        )

        return QSOFields(
            id: local.id,
            callsign: coreFields.callsign,
            band: coreFields.band,
            mode: coreFields.mode,
            frequency: coreFields.frequency,
            timestamp: coreFields.timestamp,
            rstSent: coreFields.rstSent,
            rstReceived: coreFields.rstReceived,
            myCallsign: coreFields.myCallsign,
            myGrid: coreFields.myGrid,
            theirGrid: coreFields.theirGrid,
            parkReference: coreFields.parkReference,
            theirParkReference: coreFields.theirParkReference,
            notes: mergeNotes(local: local.notes, remote: remote.notes),
            importSource: local.importSource,
            importedAt: min(local.importedAt, remote.importedAt),
            modifiedAt: extraFields.modifiedAt,
            rawADIF: local.rawADIF ?? remote.rawADIF,
            name: extraFields.name,
            qth: extraFields.qth,
            state: extraFields.state,
            country: extraFields.country,
            power: extraFields.power,
            myRig: extraFields.myRig,
            stationProfileName: extraFields.stationProfileName,
            sotaRef: extraFields.sotaRef,
            qrzLogId: extraFields.qrzLogId,
            qrzConfirmed: local.qrzConfirmed || remote.qrzConfirmed,
            lotwConfirmedDate: extraFields.lotwConfirmedDate,
            lotwConfirmed: local.lotwConfirmed || remote.lotwConfirmed,
            dxcc: extraFields.dxcc,
            theirLicenseClass: extraFields.theirLicenseClass,
            isHidden: local.isHidden || remote.isHidden,
            isActivityLogQSO: local.isActivityLogQSO || remote.isActivityLogQSO,
            loggingSessionId: extraFields.loggingSessionId
        )
    }

    // MARK: - ServicePresence: Union Merge

    /// Merge service presence using union semantics.
    /// Upload status propagates in one direction: once present, stays present.
    nonisolated static func mergeServicePresence(
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
    nonisolated static func mergeLoggingSession(
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

    nonisolated static func mergeActivationMetadata(
        local: ActivationMetadataFields,
        remote: ActivationMetadataFields,
        localModDate: Date,
        remoteModDate: Date
    ) -> ActivationMetadataFields {
        remoteModDate > localModDate ? remote : local
    }

    // MARK: - SessionSpot: Last-Writer-Wins

    /// Merge session spot using LWW. Spots are immutable once recorded,
    /// so we simply take the remote version on conflict.
    nonisolated static func mergeSessionSpot(
        local _: SessionSpotFields,
        remote: SessionSpotFields,
        localModDate _: Date,
        remoteModDate _: Date
    ) -> SessionSpotFields {
        remote
    }

    // MARK: - ActivityLog: Last-Writer-Wins

    /// Merge activity log using LWW — prefer the newer modification date.
    nonisolated static func mergeActivityLog(
        local: ActivityLogFields,
        remote: ActivityLogFields,
        localModDate: Date,
        remoteModDate: Date
    ) -> ActivityLogFields {
        remoteModDate > localModDate ? remote : local
    }
}

// MARK: - CloudSyncConflictResolver + QSO Merge Helpers

extension CloudSyncConflictResolver {
    struct QSOCoreFieldsMerge {
        let callsign: String
        let band: String
        let mode: String
        let frequency: Double?
        let timestamp: Date
        let rstSent: String?
        let rstReceived: String?
        let myCallsign: String
        let myGrid: String?
        let theirGrid: String?
        let parkReference: String?
        let theirParkReference: String?
    }

    struct QSOExtraFieldsMerge {
        let modifiedAt: Date?
        let name: String?
        let qth: String?
        let state: String?
        let country: String?
        let power: Int?
        let myRig: String?
        let stationProfileName: String?
        let sotaRef: String?
        let qrzLogId: String?
        let lotwConfirmedDate: Date?
        let dxcc: Int?
        let theirLicenseClass: String?
        let loggingSessionId: UUID?
    }

    nonisolated static func mergeQSOCoreFields(
        local: QSOFields, remote: QSOFields, preferRemote: Bool
    ) -> QSOCoreFieldsMerge {
        QSOCoreFieldsMerge(
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
            )
        )
    }

    nonisolated static func mergeQSOExtraFields(
        local: QSOFields, remote: QSOFields, preferRemote: Bool
    ) -> QSOExtraFieldsMerge {
        QSOExtraFieldsMerge(
            modifiedAt: pickOptional(
                local.modifiedAt, remote.modifiedAt, preferRemote: preferRemote
            ),
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
            lotwConfirmedDate: pickOptional(
                local.lotwConfirmedDate, remote.lotwConfirmedDate, preferRemote: preferRemote
            ),
            dxcc: pickOptional(local.dxcc, remote.dxcc, preferRemote: preferRemote),
            theirLicenseClass: pickOptional(
                local.theirLicenseClass, remote.theirLicenseClass, preferRemote: preferRemote
            ),
            loggingSessionId: pickOptional(
                local.loggingSessionId, remote.loggingSessionId, preferRemote: preferRemote
            )
        )
    }

    nonisolated static func pickString(
        _ local: String, _ remote: String, preferRemote: Bool
    ) -> String {
        local == remote ? local : (preferRemote ? remote : local)
    }

    nonisolated static func pickValue<T: Equatable>(
        _ local: T, _ remote: T, preferRemote: Bool
    ) -> T {
        local == remote ? local : (preferRemote ? remote : local)
    }

    nonisolated static func pickOptional<T: Equatable>(
        _ local: T?, _ remote: T?, preferRemote: Bool
    ) -> T? {
        if local == remote {
            return local
        }
        if local == nil {
            return remote
        }
        if remote == nil {
            return local
        }
        return preferRemote ? remote : local
    }

    nonisolated static func mergeNotes(local: String?, remote: String?) -> String? {
        if local == remote {
            return local
        }
        if local == nil {
            return remote
        }
        if remote == nil {
            return local
        }
        let localStr = local!
        let remoteStr = remote!
        if localStr.contains(remoteStr) {
            return localStr
        }
        if remoteStr.contains(localStr) {
            return remoteStr
        }
        let separator = "\n---\n"
        let localBlocks = localStr.components(separatedBy: separator)
        let remoteBlocks = remoteStr.components(separatedBy: separator)
        var seen = Set<String>()
        var merged: [String] = []
        for block in localBlocks + remoteBlocks {
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else {
                continue
            }
            seen.insert(trimmed)
            merged.append(trimmed)
        }
        let result = merged.joined(separator: separator)
        return result.count > 10_000 ? String(result.prefix(10_000)) : result
    }

    nonisolated static func newerOptionalDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (.some(dateA), .some(dateB)):
            dateA > dateB ? dateA : dateB
        case (.some, .none): lhs
        case (.none, .some): rhs
        case (.none, .none): nil
        }
    }
}
