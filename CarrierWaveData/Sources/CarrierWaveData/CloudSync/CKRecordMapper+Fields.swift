import CarrierWaveCore
import Foundation

// MARK: - QSOFields

/// Sendable snapshot of QSO fields extracted from a CKRecord
public struct QSOFields: Sendable {
    // MARK: Lifecycle

    public init(
        id: UUID,
        callsign: String,
        band: String,
        mode: String,
        frequency: Double?,
        timestamp: Date,
        rstSent: String?,
        rstReceived: String?,
        myCallsign: String,
        myGrid: String?,
        theirGrid: String?,
        parkReference: String?,
        theirParkReference: String?,
        notes: String?,
        importSource: ImportSource,
        importedAt: Date,
        modifiedAt: Date?,
        rawADIF: String?,
        name: String?,
        qth: String?,
        state: String?,
        country: String?,
        power: Int?,
        myRig: String?,
        stationProfileName: String?,
        sotaRef: String?,
        wwffRef: String?,
        qrzLogId: String?,
        qrzConfirmed: Bool,
        lotwConfirmedDate: Date?,
        lotwConfirmed: Bool,
        dxcc: Int?,
        theirLicenseClass: String?,
        isHidden: Bool,
        isActivityLogQSO: Bool,
        loggingSessionId: UUID?
    ) {
        self.id = id
        self.callsign = callsign
        self.band = band
        self.mode = mode
        self.frequency = frequency
        self.timestamp = timestamp
        self.rstSent = rstSent
        self.rstReceived = rstReceived
        self.myCallsign = myCallsign
        self.myGrid = myGrid
        self.theirGrid = theirGrid
        self.parkReference = parkReference
        self.theirParkReference = theirParkReference
        self.notes = notes
        self.importSource = importSource
        self.importedAt = importedAt
        self.modifiedAt = modifiedAt
        self.rawADIF = rawADIF
        self.name = name
        self.qth = qth
        self.state = state
        self.country = country
        self.power = power
        self.myRig = myRig
        self.stationProfileName = stationProfileName
        self.sotaRef = sotaRef
        self.wwffRef = wwffRef
        self.qrzLogId = qrzLogId
        self.qrzConfirmed = qrzConfirmed
        self.lotwConfirmedDate = lotwConfirmedDate
        self.lotwConfirmed = lotwConfirmed
        self.dxcc = dxcc
        self.theirLicenseClass = theirLicenseClass
        self.isHidden = isHidden
        self.isActivityLogQSO = isActivityLogQSO
        self.loggingSessionId = loggingSessionId
    }

    // MARK: Public

    public let id: UUID
    public let callsign: String
    public let band: String
    public let mode: String
    public let frequency: Double?
    public let timestamp: Date
    public let rstSent: String?
    public let rstReceived: String?
    public let myCallsign: String
    public let myGrid: String?
    public let theirGrid: String?
    public let parkReference: String?
    public let theirParkReference: String?
    public let notes: String?
    public let importSource: ImportSource
    public let importedAt: Date
    public let modifiedAt: Date?
    public let rawADIF: String?
    public let name: String?
    public let qth: String?
    public let state: String?
    public let country: String?
    public let power: Int?
    public let myRig: String?
    public let stationProfileName: String?
    public let sotaRef: String?
    public let wwffRef: String?
    public let qrzLogId: String?
    public let qrzConfirmed: Bool
    public let lotwConfirmedDate: Date?
    public let lotwConfirmed: Bool
    public let dxcc: Int?
    public let theirLicenseClass: String?
    public let isHidden: Bool
    public let isActivityLogQSO: Bool
    public let loggingSessionId: UUID?

    nonisolated public var deduplicationKey: String {
        let roundedTimestamp = timestamp.timeIntervalSince1970
        let rounded = Int(roundedTimestamp / 120) * 120
        let trimmedCallsign = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        let canonicalMode = ModeEquivalence.canonicalName(mode).uppercased()
        return "\(trimmedCallsign)|\(band.uppercased())|\(canonicalMode)|\(rounded)"
    }
}

// MARK: - ServicePresenceFields

/// Sendable snapshot of ServicePresence fields
public struct ServicePresenceFields: Sendable {
    // MARK: Lifecycle

    public init(
        id: UUID,
        serviceType: ServiceType,
        isPresent: Bool,
        needsUpload: Bool,
        uploadRejected: Bool,
        isSubmitted: Bool,
        lastConfirmedAt: Date?,
        parkReference: String?,
        qsoUUID: UUID?
    ) {
        self.id = id
        self.serviceType = serviceType
        self.isPresent = isPresent
        self.needsUpload = needsUpload
        self.uploadRejected = uploadRejected
        self.isSubmitted = isSubmitted
        self.lastConfirmedAt = lastConfirmedAt
        self.parkReference = parkReference
        self.qsoUUID = qsoUUID
    }

    // MARK: Public

    public let id: UUID
    public let serviceType: ServiceType
    public let isPresent: Bool
    public let needsUpload: Bool
    public let uploadRejected: Bool
    public let isSubmitted: Bool
    public let lastConfirmedAt: Date?
    public let parkReference: String?
    public let qsoUUID: UUID?
}

// MARK: - LoggingSessionFields

/// Sendable snapshot of LoggingSession fields
public struct LoggingSessionFields: Sendable {
    // MARK: Lifecycle

    public init(
        id: UUID,
        myCallsign: String,
        startedAt: Date,
        endedAt: Date?,
        frequency: Double?,
        mode: String,
        activationTypeRawValue: String,
        statusRawValue: String,
        parkReference: String?,
        sotaReference: String?,
        wwffReference: String?,
        myGrid: String?,
        power: Int?,
        myRig: String?,
        notes: String?,
        customTitle: String?,
        qsoCount: Int,
        isRove: Bool,
        myAntenna: String?,
        myKey: String?,
        myMic: String?,
        extraEquipment: String?,
        attendees: String?,
        photoFilenames: [String],
        spotCommentsData: Data?,
        roveStopsData: Data?,
        solarKIndex: Double?,
        solarFlux: Double?,
        solarSunspots: Int?,
        solarPropagationRating: String?,
        solarAIndex: Int?,
        solarBandConditions: String?,
        solarTimestamp: Date?,
        solarConditions: String?,
        weatherTemperatureF: Double?,
        weatherTemperatureC: Double?,
        weatherHumidity: Int?,
        weatherWindSpeed: Double?,
        weatherWindDirection: String?,
        weatherDescription: String?,
        weatherTimestamp: Date?,
        weather: String?
    ) {
        self.id = id
        self.myCallsign = myCallsign
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.frequency = frequency
        self.mode = mode
        self.activationTypeRawValue = activationTypeRawValue
        self.statusRawValue = statusRawValue
        self.parkReference = parkReference
        self.sotaReference = sotaReference
        self.wwffReference = wwffReference
        self.myGrid = myGrid
        self.power = power
        self.myRig = myRig
        self.notes = notes
        self.customTitle = customTitle
        self.qsoCount = qsoCount
        self.isRove = isRove
        self.myAntenna = myAntenna
        self.myKey = myKey
        self.myMic = myMic
        self.extraEquipment = extraEquipment
        self.attendees = attendees
        self.photoFilenames = photoFilenames
        self.spotCommentsData = spotCommentsData
        self.roveStopsData = roveStopsData
        self.solarKIndex = solarKIndex
        self.solarFlux = solarFlux
        self.solarSunspots = solarSunspots
        self.solarPropagationRating = solarPropagationRating
        self.solarAIndex = solarAIndex
        self.solarBandConditions = solarBandConditions
        self.solarTimestamp = solarTimestamp
        self.solarConditions = solarConditions
        self.weatherTemperatureF = weatherTemperatureF
        self.weatherTemperatureC = weatherTemperatureC
        self.weatherHumidity = weatherHumidity
        self.weatherWindSpeed = weatherWindSpeed
        self.weatherWindDirection = weatherWindDirection
        self.weatherDescription = weatherDescription
        self.weatherTimestamp = weatherTimestamp
        self.weather = weather
    }

    // MARK: Public

    public let id: UUID
    public let myCallsign: String
    public let startedAt: Date
    public let endedAt: Date?
    public let frequency: Double?
    public let mode: String
    public let activationTypeRawValue: String
    public let statusRawValue: String
    public let parkReference: String?
    public let sotaReference: String?
    public let wwffReference: String?
    public let myGrid: String?
    public let power: Int?
    public let myRig: String?
    public let notes: String?
    public let customTitle: String?
    public let qsoCount: Int
    public let isRove: Bool
    public let myAntenna: String?
    public let myKey: String?
    public let myMic: String?
    public let extraEquipment: String?
    public let attendees: String?
    public let photoFilenames: [String]
    public let spotCommentsData: Data?
    public let roveStopsData: Data?
    public let solarKIndex: Double?
    public let solarFlux: Double?
    public let solarSunspots: Int?
    public let solarPropagationRating: String?
    public let solarAIndex: Int?
    public let solarBandConditions: String?
    public let solarTimestamp: Date?
    public let solarConditions: String?
    public let weatherTemperatureF: Double?
    public let weatherTemperatureC: Double?
    public let weatherHumidity: Int?
    public let weatherWindSpeed: Double?
    public let weatherWindDirection: String?
    public let weatherDescription: String?
    public let weatherTimestamp: Date?
    public let weather: String?
}

// MARK: - ActivationMetadataFields

/// Sendable snapshot of ActivationMetadata fields
public struct ActivationMetadataFields: Sendable {
    // MARK: Lifecycle

    public init(
        parkReference: String,
        date: Date,
        title: String?,
        watts: Int?,
        weather: String?,
        solarConditions: String?,
        averageWPM: Int?,
        solarKIndex: Double?,
        solarFlux: Double?,
        solarSunspots: Int?,
        solarPropagationRating: String?,
        solarAIndex: Int?,
        solarBandConditions: String?,
        solarTimestamp: Date?,
        weatherTemperatureF: Double?,
        weatherTemperatureC: Double?,
        weatherHumidity: Int?,
        weatherWindSpeed: Double?,
        weatherWindDirection: String?,
        weatherDescription: String?,
        weatherTimestamp: Date?
    ) {
        self.parkReference = parkReference
        self.date = date
        self.title = title
        self.watts = watts
        self.weather = weather
        self.solarConditions = solarConditions
        self.averageWPM = averageWPM
        self.solarKIndex = solarKIndex
        self.solarFlux = solarFlux
        self.solarSunspots = solarSunspots
        self.solarPropagationRating = solarPropagationRating
        self.solarAIndex = solarAIndex
        self.solarBandConditions = solarBandConditions
        self.solarTimestamp = solarTimestamp
        self.weatherTemperatureF = weatherTemperatureF
        self.weatherTemperatureC = weatherTemperatureC
        self.weatherHumidity = weatherHumidity
        self.weatherWindSpeed = weatherWindSpeed
        self.weatherWindDirection = weatherWindDirection
        self.weatherDescription = weatherDescription
        self.weatherTimestamp = weatherTimestamp
    }

    // MARK: Public

    public let parkReference: String
    public let date: Date
    public let title: String?
    public let watts: Int?
    public let weather: String?
    public let solarConditions: String?
    public let averageWPM: Int?
    public let solarKIndex: Double?
    public let solarFlux: Double?
    public let solarSunspots: Int?
    public let solarPropagationRating: String?
    public let solarAIndex: Int?
    public let solarBandConditions: String?
    public let solarTimestamp: Date?
    public let weatherTemperatureF: Double?
    public let weatherTemperatureC: Double?
    public let weatherHumidity: Int?
    public let weatherWindSpeed: Double?
    public let weatherWindDirection: String?
    public let weatherDescription: String?
    public let weatherTimestamp: Date?
}

// MARK: - SessionSpotFields

/// Sendable snapshot of SessionSpot fields
public struct SessionSpotFields: Sendable {
    // MARK: Lifecycle

    public init(
        id: UUID,
        loggingSessionId: UUID,
        callsign: String,
        frequencyKHz: Double,
        mode: String,
        timestamp: Date,
        source: String,
        snr: Int?,
        wpm: Int?,
        spotter: String?,
        spotterGrid: String?,
        parkRef: String?,
        parkName: String?,
        comments: String?,
        region: String,
        distanceMeters: Double?,
        bearingDegrees: Double?
    ) {
        self.id = id
        self.loggingSessionId = loggingSessionId
        self.callsign = callsign
        self.frequencyKHz = frequencyKHz
        self.mode = mode
        self.timestamp = timestamp
        self.source = source
        self.snr = snr
        self.wpm = wpm
        self.spotter = spotter
        self.spotterGrid = spotterGrid
        self.parkRef = parkRef
        self.parkName = parkName
        self.comments = comments
        self.region = region
        self.distanceMeters = distanceMeters
        self.bearingDegrees = bearingDegrees
    }

    // MARK: Public

    public let id: UUID
    public let loggingSessionId: UUID
    public let callsign: String
    public let frequencyKHz: Double
    public let mode: String
    public let timestamp: Date
    public let source: String
    public let snr: Int?
    public let wpm: Int?
    public let spotter: String?
    public let spotterGrid: String?
    public let parkRef: String?
    public let parkName: String?
    public let comments: String?
    public let region: String
    public let distanceMeters: Double?
    public let bearingDegrees: Double?
}

// MARK: - ActivityLogFields

/// Sendable snapshot of ActivityLog fields
public struct ActivityLogFields: Sendable {
    // MARK: Lifecycle

    public init(
        id: UUID,
        name: String,
        myCallsign: String,
        createdAt: Date,
        stationProfileId: UUID?,
        currentGrid: String?,
        locationLabel: String?,
        isActive: Bool
    ) {
        self.id = id
        self.name = name
        self.myCallsign = myCallsign
        self.createdAt = createdAt
        self.stationProfileId = stationProfileId
        self.currentGrid = currentGrid
        self.locationLabel = locationLabel
        self.isActive = isActive
    }

    // MARK: Public

    public let id: UUID
    public let name: String
    public let myCallsign: String
    public let createdAt: Date
    public let stationProfileId: UUID?
    public let currentGrid: String?
    public let locationLabel: String?
    public let isActive: Bool
}
