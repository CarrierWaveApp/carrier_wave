import CarrierWaveCore
import Foundation

// Faithful `@Model` → `Ffi*` projections for the seed importer. Each is a plain
// field copy with the store's representation conventions: `Date` → unix seconds,
// `UUID` → lowercase string, `Int` → `Int64`, JSON-backed array columns encoded
// to text, `Data` blobs copied verbatim.
//
// `function_body_length` is disabled here: these are wide, inherent field maps
// (QSO and LoggingSession each carry 40–75 columns); splitting a single
// initializer call would obscure, not clarify.
// swiftlint:disable function_body_length

public extension SwiftDataStoreImporter {
    /// `frequency` is MHz in the `@Model`; the store column is kHz.
    /// `band`/`mode`/`myCallsign` widen `String` → `String?` unchanged (the
    /// `@Model` stores "" not nil, preserved as-is).
    /// `nonisolated` so the mirror can project on a background context's thread
    /// (the save notification fires synchronously on the saving context's executor).
    nonisolated static func project(_ qso: QSO) -> FfiQso {
        FfiQso(
            id: uuid(qso.id),
            callsign: qso.callsign,
            band: qso.band,
            mode: qso.mode,
            freqKhz: qso.frequency.map { $0 * 1_000 },
            qsoDate: unix(qso.timestamp),
            myGrid: qso.myGrid,
            theirGrid: qso.theirGrid,
            rstSent: qso.rstSent,
            rstRcvd: qso.rstReceived,
            myCallsign: qso.myCallsign,
            park: qso.parkReference,
            theirPark: qso.theirParkReference,
            notes: qso.notes,
            notesUserAuthored: qso.notesUserAuthored,
            spotCommentsData: qso.spotCommentsData,
            callsignChangeNote: qso.callsignChangeNote,
            originalCallsign: qso.originalCallsign,
            importSourceRawValue: qso.importSourceRawValue,
            importedAt: unix(qso.importedAt),
            modifiedAt: qso.modifiedAt.map(unix),
            rawAdif: qso.rawADIF,
            name: qso.name,
            qth: qso.qth,
            state: qso.state,
            country: qso.country,
            power: qso.power.map(Int64.init),
            myRig: qso.myRig,
            stationProfileName: qso.stationProfileName,
            sotaRef: qso.sotaRef,
            wwffRef: qso.wwffRef,
            aoaCode: qso.aoaCode,
            qrzLogId: qso.qrzLogId,
            qrzConfirmed: qso.qrzConfirmed,
            lotwConfirmedDate: qso.lotwConfirmedDate.map(unix),
            lotwConfirmed: qso.lotwConfirmed,
            dxcc: qso.dxcc.map(Int64.init),
            theirLicenseClass: qso.theirLicenseClass,
            contestName: qso.contestName,
            contestSerialSent: qso.contestSerialSent.map(Int64.init),
            contestSerialReceived: qso.contestSerialReceived.map(Int64.init),
            contestExchangeSent: qso.contestExchangeSent,
            contestExchangeReceived: qso.contestExchangeReceived,
            isHidden: qso.isHidden,
            isActivityLogQso: qso.isActivityLogQSO,
            stationCallsign: qso.stationCallsign,
            loggingSessionId: qso.loggingSessionId.map(uuid),
            dirty: qso.cloudDirtyFlag,
            satName: qso.satName,
            propMode: qso.propMode,
            // Presence is mirrored as separate service_presence rows, never via the
            // QSO upsert; the Logbook query path projects it back on read.
            presence: []
        )
    }

    nonisolated static func project(_ session: LoggingSession) -> FfiLoggingSession {
        FfiLoggingSession(
            id: uuid(session.id),
            myCallsign: session.myCallsign,
            startedAt: unix(session.startedAt),
            endedAt: session.endedAt.map(unix),
            frequency: session.frequency,
            mode: session.mode,
            activationTypeRawValue: session.activationTypeRawValue,
            programsRawValue: session.programsRawValue,
            statusRawValue: session.statusRawValue,
            parkReference: session.parkReference,
            sotaReference: session.sotaReference,
            missionReference: session.missionReference,
            wwffReference: session.wwffReference,
            myGrid: session.myGrid,
            power: session.power.map(Int64.init),
            myRig: session.myRig,
            notes: session.notes,
            qsoComment: session.qsoComment,
            customTitle: session.customTitle,
            qsoCount: Int64(session.qsoCount),
            spotCommentsData: session.spotCommentsData,
            isRove: session.isRove,
            roveStopsData: session.roveStopsData,
            myAntenna: session.myAntenna,
            myKey: session.myKey,
            myMic: session.myMic,
            extraEquipment: session.extraEquipment,
            attendees: session.attendees,
            photoFilenames: jsonStringArray(session.photoFilenames),
            radioItemId: session.radioItemID.map(uuid),
            stationCallsign: session.stationCallsign,
            operatorCallsignsRawValue: session.operatorCallsignsRawValue,
            solarKIndex: session.solarKIndex,
            solarFlux: session.solarFlux,
            solarSunspots: session.solarSunspots.map(Int64.init),
            solarPropagationRating: session.solarPropagationRating,
            solarAIndex: session.solarAIndex.map(Int64.init),
            solarBandConditions: session.solarBandConditions,
            solarTimestamp: session.solarTimestamp.map(unix),
            solarConditions: session.solarConditions,
            weatherTemperatureF: session.weatherTemperatureF,
            weatherTemperatureC: session.weatherTemperatureC,
            weatherHumidity: session.weatherHumidity.map(Int64.init),
            weatherWindSpeed: session.weatherWindSpeed,
            weatherWindDirection: session.weatherWindDirection,
            weatherDescription: session.weatherDescription,
            weatherTimestamp: session.weatherTimestamp.map(unix),
            weather: session.weather,
            cloudDirtyFlag: session.cloudDirtyFlag,
            contestId: session.contestId,
            contestCategory: session.contestCategory,
            contestOverlayCategory: session.contestOverlayCategory,
            contestPower: session.contestPower,
            contestBands: session.contestBands,
            contestOperator: session.contestOperator,
            activationLatitude: session.activationLatitude,
            activationLongitude: session.activationLongitude,
            activationDistanceMiles: session.activationDistanceMiles,
            activationElevationGainFeet: session.activationElevationGainFeet,
            ruckWeightPounds: session.ruckWeightPounds,
            qrpActivation: session.qrpActivation,
            withPets: session.withPets,
            withKids: session.withKids,
            winlinkSent: session.winlinkSent,
            aprsSent: session.aprsSent,
            varacSent: session.varacSent,
            adaptiveSport: session.adaptiveSport,
            trackPointsData: session.trackPointsData,
            totaCategoryRawValue: session.totaCategoryRawValue,
            personalEffortFactor: session.personalEffortFactor.map(Int64.init),
            firstActivationOfTileEver: session.firstActivationOfTileEver,
            winterActivationOverride: session.winterActivationOverride.map { $0 ? 1 : 0 },
            tilesActivatedData: session.tilesActivatedData,
            totaT3CandidatesData: session.totaT3CandidatesData,
            totaT3SnapshotAt: session.totaT3SnapshotAt.map(unix),
            totaOfficialPoints: session.totaOfficialPoints
        )
    }

    nonisolated static func project(_ presence: ServicePresence) -> FfiServicePresence {
        FfiServicePresence(
            id: uuid(presence.id),
            serviceTypeRawValue: presence.serviceTypeRawValue,
            isPresent: presence.isPresent,
            needsUpload: presence.needsUpload,
            uploadRejected: presence.uploadRejected,
            rejectedAtBuild: presence.rejectedAtBuild,
            isSubmitted: presence.isSubmitted,
            lastConfirmedAt: presence.lastConfirmedAt.map(unix),
            parkReference: presence.parkReference,
            cloudDirtyFlag: presence.cloudDirtyFlag,
            qsoId: presence.qso.map { uuid($0.id) }
        )
    }

    nonisolated static func project(_ spot: SessionSpot) -> FfiSessionSpot {
        FfiSessionSpot(
            id: uuid(spot.id),
            loggingSessionId: uuid(spot.loggingSessionId),
            callsign: spot.callsign,
            frequencyKHz: spot.frequencyKHz,
            mode: spot.mode,
            timestamp: unix(spot.timestamp),
            source: spot.source,
            snr: spot.snr.map(Int64.init),
            wpm: spot.wpm.map(Int64.init),
            spotter: spot.spotter,
            spotterGrid: spot.spotterGrid,
            parkRef: spot.parkRef,
            parkName: spot.parkName,
            comments: spot.comments,
            region: spot.region,
            distanceMeters: spot.distanceMeters,
            bearingDegrees: spot.bearingDegrees,
            cloudDirtyFlag: spot.cloudDirtyFlag
        )
    }

    nonisolated static func project(_ metadata: ActivationMetadata) -> FfiActivationMetadata {
        FfiActivationMetadata(
            parkReference: metadata.parkReference,
            date: unix(metadata.date),
            title: metadata.title,
            watts: metadata.watts.map(Int64.init),
            weather: metadata.weather,
            solarConditions: metadata.solarConditions,
            averageWpm: metadata.averageWPM.map(Int64.init),
            solarKIndex: metadata.solarKIndex,
            solarFlux: metadata.solarFlux,
            solarSunspots: metadata.solarSunspots.map(Int64.init),
            solarPropagationRating: metadata.solarPropagationRating,
            solarAIndex: metadata.solarAIndex.map(Int64.init),
            solarBandConditions: metadata.solarBandConditions,
            solarTimestamp: metadata.solarTimestamp.map(unix),
            weatherTemperatureF: metadata.weatherTemperatureF,
            weatherTemperatureC: metadata.weatherTemperatureC,
            weatherHumidity: metadata.weatherHumidity.map(Int64.init),
            weatherWindSpeed: metadata.weatherWindSpeed,
            weatherWindDirection: metadata.weatherWindDirection,
            weatherDescription: metadata.weatherDescription,
            weatherTimestamp: metadata.weatherTimestamp.map(unix),
            cloudDirtyFlag: metadata.cloudDirtyFlag
        )
    }

    nonisolated static func project(_ log: ActivityLog) -> FfiActivityLog {
        FfiActivityLog(
            id: uuid(log.id),
            name: log.name,
            myCallsign: log.myCallsign,
            createdAt: unix(log.createdAt),
            stationProfileId: log.stationProfileId.map(uuid),
            currentGrid: log.currentGrid,
            locationLabel: log.locationLabel,
            isActive: log.isActive,
            cloudDirtyFlag: log.cloudDirtyFlag
        )
    }

    nonisolated static func project(_ item: EquipmentItem) -> FfiEquipmentItem {
        FfiEquipmentItem(
            id: uuid(item.id),
            catalogId: item.catalogId,
            catalogName: item.catalogName,
            categoryRawValue: item.categoryRawValue,
            nickname: item.nickname,
            notes: item.notes,
            acquiredDate: item.acquiredDate.map(unix),
            isRetired: item.isRetired,
            bandsJson: item.bandsJSON,
            modesJson: item.modesJSON,
            maxPowerWatts: item.maxPowerWatts.map(Int64.init),
            portabilityRawValue: item.portabilityRawValue,
            manufacturer: item.manufacturer,
            createdAt: unix(item.createdAt),
            weightOunces: item.weightOunces.map(Int64.init),
            connectionProfileJson: item.connectionProfileJSON
        )
    }

    nonisolated static func project(_ macro: RadioMacro) -> FfiRadioMacro {
        FfiRadioMacro(
            id: uuid(macro.id),
            name: macro.name,
            icon: macro.icon,
            macroDescription: macro.macroDescription,
            tagsCsv: macro.tagsCSV,
            appliesToCsv: macro.appliesToCSV,
            author: macro.author,
            argsJson: macro.argsJSON,
            stepsJson: macro.stepsJSON,
            capabilitiesJson: macro.capabilitiesJSON,
            registryJson: macro.registryJSON,
            format: Int64(macro.format),
            sortOrder: Int64(macro.sortOrder),
            createdAt: unix(macro.createdAt),
            updatedAt: unix(macro.updatedAt),
            tombstoned: macro.tombstoned,
            tombstoneReason: macro.tombstoneReason,
            cloudDirtyFlag: macro.cloudDirtyFlag
        )
    }

    nonisolated static func project(_ recording: WebSDRRecording) -> FfiWebSdrRecording {
        FfiWebSdrRecording(
            id: uuid(recording.id),
            loggingSessionId: uuid(recording.loggingSessionId),
            kiwisdrHost: recording.kiwisdrHost,
            kiwisdrName: recording.kiwisdrName,
            startedAt: unix(recording.startedAt),
            endedAt: recording.endedAt.map(unix),
            frequencyKHz: recording.frequencyKHz,
            mode: recording.mode,
            relativeFilePath: recording.relativeFilePath,
            fileSizeBytes: recording.fileSizeBytes,
            durationSeconds: recording.durationSeconds,
            isComplete: recording.isComplete,
            spotCallsign: recording.spotCallsign,
            spotParkRef: recording.spotParkRef,
            spotParkName: recording.spotParkName,
            spotSummitCode: recording.spotSummitCode,
            spotBand: recording.spotBand,
            isTuneInRecording: recording.isTuneInRecording,
            clipBookmarksData: recording.clipBookmarksData,
            parameterChangesData: recording.parameterChangesData
        )
    }

    nonisolated static func project(_ favorite: WebSDRFavorite) -> FfiWebSdrFavorite {
        FfiWebSdrFavorite(
            hostPort: favorite.hostPort,
            displayName: favorite.displayName,
            location: favorite.location,
            antenna: favorite.antenna,
            addedDate: unix(favorite.addedDate)
        )
    }

    nonisolated static func project(_ destination: UploadDestination) -> FfiUploadDestination {
        FfiUploadDestination(
            id: uuid(destination.id),
            typeRawValue: destination.typeRawValue,
            isEnabled: destination.isEnabled,
            lastSyncAt: destination.lastSyncAt.map(unix)
        )
    }

    nonisolated static func project(_ metadata: CloudSyncMetadata) -> FfiCloudSyncMetadata {
        FfiCloudSyncMetadata(
            entityType: metadata.entityType,
            localId: uuid(metadata.localId),
            recordName: metadata.recordName,
            encodedSystemFields: metadata.encodedSystemFields,
            lastSyncedAt: metadata.lastSyncedAt.map(unix)
        )
    }

    /// Structured `rove_stop` rows decoded from the session's transitional
    /// `roveStopsData` blob — the write-through that keeps the cw-store table
    /// (which the Rust split reads) in lockstep with the blob the iOS UI still
    /// uses. Inverse: `FfiReflector.hydrateRoveStops`.
    nonisolated static func projectRoveStops(_ session: LoggingSession) -> [FfiRoveStop] {
        let sessionId = uuid(session.id)
        return session.roveStops.map { stop in
            FfiRoveStop(
                id: uuid(stop.id),
                loggingSessionId: sessionId,
                parkReference: stop.parkReference,
                startedAt: unix(stop.startedAt),
                endedAt: stop.endedAt.map(unix),
                myGrid: stop.myGrid,
                qsoCount: Int64(stop.qsoCount),
                notes: stop.notes,
                cloudDirtyFlag: session.cloudDirtyFlag
            )
        }
    }
}

// swiftlint:enable function_body_length
