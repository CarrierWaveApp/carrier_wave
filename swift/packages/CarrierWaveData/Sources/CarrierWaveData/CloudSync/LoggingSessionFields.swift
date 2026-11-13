import Foundation

// MARK: - LoggingSessionFields

/// Sendable snapshot of LoggingSession fields
public struct LoggingSessionFields: Sendable, Codable {
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
        qsoComment: String?,
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
        weather: String?,
        stationCallsign: String? = nil,
        operatorCallsignsRawValue: String = "[]"
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
        self.qsoComment = qsoComment
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
        self.stationCallsign = stationCallsign
        self.operatorCallsignsRawValue = operatorCallsignsRawValue
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
    public let qsoComment: String?
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
    public let stationCallsign: String?
    public let operatorCallsignsRawValue: String
}
