import CarrierWaveCore
import Foundation

// MARK: - FfiLoggingSession + LoggingSessionFields

extension FfiLoggingSession {
    // swiftlint:disable function_body_length
    /// Recover the journal wire fields from a stored session row, so the same
    /// `LoggingSession.fromFields` / `LoggingSessionFields.apply(to:)` path the
    /// CloudKit inbound seam uses can replicate a server-synced session into
    /// SwiftData. Reverse of `SwiftDataStoreImporter.project(_ session:)`.
    /// Returns `nil` only if the stored id is not a valid UUID.
    func toLoggingSessionFields() -> LoggingSessionFields? {
        guard let sessionId = UUID(uuidString: id) else {
            return nil
        }
        let date: (Int64) -> Date = { Date(timeIntervalSince1970: TimeInterval($0)) }
        let photos = (try? JSONDecoder().decode([String].self, from: Data(photoFilenames.utf8))) ?? []
        return LoggingSessionFields(
            id: sessionId,
            myCallsign: myCallsign,
            startedAt: date(startedAt),
            endedAt: endedAt.map(date),
            frequency: frequency,
            mode: mode,
            activationTypeRawValue: activationTypeRawValue,
            statusRawValue: statusRawValue,
            parkReference: parkReference,
            sotaReference: sotaReference,
            wwffReference: wwffReference,
            myGrid: myGrid,
            power: power.map(Int.init),
            myRig: myRig,
            notes: notes,
            qsoComment: qsoComment,
            customTitle: customTitle,
            qsoCount: Int(qsoCount),
            isRove: isRove,
            myAntenna: myAntenna,
            myKey: myKey,
            myMic: myMic,
            extraEquipment: extraEquipment,
            attendees: attendees,
            photoFilenames: photos,
            spotCommentsData: spotCommentsData,
            roveStopsData: roveStopsData,
            solarKIndex: solarKIndex,
            solarFlux: solarFlux,
            solarSunspots: solarSunspots.map(Int.init),
            solarPropagationRating: solarPropagationRating,
            solarAIndex: solarAIndex.map(Int.init),
            solarBandConditions: solarBandConditions,
            solarTimestamp: solarTimestamp.map(date),
            solarConditions: solarConditions,
            weatherTemperatureF: weatherTemperatureF,
            weatherTemperatureC: weatherTemperatureC,
            weatherHumidity: weatherHumidity.map(Int.init),
            weatherWindSpeed: weatherWindSpeed,
            weatherWindDirection: weatherWindDirection,
            weatherDescription: weatherDescription,
            weatherTimestamp: weatherTimestamp.map(date),
            weather: weather,
            stationCallsign: stationCallsign,
            operatorCallsignsRawValue: operatorCallsignsRawValue
        )
    }

    // swiftlint:enable function_body_length
}
