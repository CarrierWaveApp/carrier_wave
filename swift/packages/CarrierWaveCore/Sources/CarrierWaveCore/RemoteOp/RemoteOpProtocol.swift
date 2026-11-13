import Foundation

// MARK: - RemoteOp

//
// One Codable namespace shared by the iOS client and the macOS server. Frames
// are sent as JSON-encoded `RemoteOpFrame` values over a WebSocket. Wire types
// are deliberately primitive (`UInt64` Hz, mode strings) so this module does
// not couple to evolving SwiftData / domain types — only `CarrierWaveCore` is
// allowed to import this from above.

public enum RemoteOp {
    /// Bonjour service type advertised by Sweep and browsed by Field.
    public static let bonjourServiceType = "_cwsweep-remote._tcp"

    /// Protocol version. Bump when the frame schema changes incompatibly.
    public static let protocolVersion = 1
}

// MARK: - RemoteOpFrame

public enum RemoteOpFrame: Codable, Sendable, Equatable {
    case hello(Hello)
    case helloAck(HelloAck)
    case pair(Pair)
    case paired(Paired)
    case ping(Ping)
    case pong(Pong)
    case subscribe(Subscribe)
    case unsubscribe(Unsubscribe)
    case eventRadioState(RadioStateEvent)
    case eventRadioMeters(RadioMetersEvent)
    case eventSpot(SpotEvent)
    case eventSpotsCleared(SpotsClearedEvent)
    case commandTune(TuneCommand)
    case commandSetQuerySelection(SetQuerySelectionCommand)
    case eventQueriesList(QueriesListEvent)
    case eventQuerySelection(QuerySelectionEvent)
    case commandSendCW(SendCWCommand)
    case commandStopCW(StopCWCommand)
    case commandSetCWSpeed(SetCWSpeedCommand)
    case commandPlayCWSlot(PlayCWSlotCommand)
    case commandSetCWSlot(SetCWSlotCommand)
    case eventCWStatus(CWStatusEvent)
    case eventCWSlots(CWSlotsEvent)
    case eventActiveSession(ActiveSessionEvent)
    case commandSetActiveSession(SetActiveSessionCommand)
    case commandSetWaterfallView(SetWaterfallViewCommand)
    case eventWaterfallLine(WaterfallLineEvent)
    case eventWaterfallCleared(WaterfallClearedEvent)
    case eventAudioFormat(AudioFormatEvent)
    case eventAudioFrame(AudioFrameEvent)
    case ack(Ack)
    case errorFrame(ErrorFrame)
}

// MARK: - Hello

public struct Hello: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        protocolVersion: Int = RemoteOp.protocolVersion,
        clientName: String,
        clientPlatform: String,
        token: String?
    ) {
        self.protocolVersion = protocolVersion
        self.clientName = clientName
        self.clientPlatform = clientPlatform
        self.token = token
    }

    // MARK: Public

    public let protocolVersion: Int
    public let clientName: String
    public let clientPlatform: String
    public let token: String?
}

// MARK: - HelloAck

public struct HelloAck: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        protocolVersion: Int = RemoteOp.protocolVersion,
        serverName: String,
        serverPlatform: String,
        serverVersion: String,
        authenticated: Bool,
        serverTimeUTC: Date
    ) {
        self.protocolVersion = protocolVersion
        self.serverName = serverName
        self.serverPlatform = serverPlatform
        self.serverVersion = serverVersion
        self.authenticated = authenticated
        self.serverTimeUTC = serverTimeUTC
    }

    // MARK: Public

    public let protocolVersion: Int
    public let serverName: String
    public let serverPlatform: String
    public let serverVersion: String
    /// True if the supplied token authenticated the session.
    public let authenticated: Bool
    /// Server's view of UTC time, ISO8601. Used by clients to compute clock skew.
    public let serverTimeUTC: Date
}

// MARK: - Pair

/// Client → server. Submit the operator-typed pairing code from Sweep's UI.
public struct Pair: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(code: String, deviceName: String) {
        self.code = code
        self.deviceName = deviceName
    }

    // MARK: Public

    public let code: String
    public let deviceName: String
}

// MARK: - Paired

/// Server → client. Returned token is opaque; client stores in Keychain.
public struct Paired: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(token: String, deviceID: UUID) {
        self.token = token
        self.deviceID = deviceID
    }

    // MARK: Public

    public let token: String
    public let deviceID: UUID
}

// MARK: - Ping

public struct Ping: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(nonce: UUID = UUID()) {
        self.nonce = nonce
    }

    // MARK: Public

    public let nonce: UUID
}

// MARK: - Pong

public struct Pong: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(nonce: UUID) {
        self.nonce = nonce
    }

    // MARK: Public

    public let nonce: UUID
}

// MARK: - RemoteOpTopic

public enum RemoteOpTopic: String, Codable, Sendable, Equatable, CaseIterable {
    case radioState = "radio.state"
    case radioMeters = "radio.meters"
    case spotsFeed = "spots.feed"
    case queriesList = "queries.list"
    case querySelection = "queries.selection"
    case cwKeyer = "cw.keyer"
    case cwSlots = "cw.slots"
    case activeSession = "session.active"
    case waterfall = "radio.waterfall"
    case audio = "radio.audio"
}

// MARK: - Subscribe

public struct Subscribe: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(topic: RemoteOpTopic, filter: SubscribeFilter? = nil) {
        self.topic = topic
        self.filter = filter
    }

    // MARK: Public

    public let topic: RemoteOpTopic
    public let filter: SubscribeFilter?
}

// MARK: - Unsubscribe

public struct Unsubscribe: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(topic: RemoteOpTopic) {
        self.topic = topic
    }

    // MARK: Public

    public let topic: RemoteOpTopic
}

// MARK: - SubscribeFilter

public struct SubscribeFilter: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        bands: [String]? = nil,
        modes: [String]? = nil,
        sources: [String]? = nil,
        neededOnly: Bool? = nil,
        minSNR: Int? = nil
    ) {
        self.bands = bands
        self.modes = modes
        self.sources = sources
        self.neededOnly = neededOnly
        self.minSNR = minSNR
    }

    // MARK: Public

    public let bands: [String]?
    public let modes: [String]?
    public let sources: [String]?
    public let neededOnly: Bool?
    public let minSNR: Int?
}

// MARK: - RadioStateEvent

public struct RadioStateEvent: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        radioID: String,
        radioName: String?,
        freqHz: UInt64,
        mode: String,
        vfo: String?,
        split: SplitState?,
        isTransmitting: Bool,
        timestamp: Date
    ) {
        self.radioID = radioID
        self.radioName = radioName
        self.freqHz = freqHz
        self.mode = mode
        self.vfo = vfo
        self.split = split
        self.isTransmitting = isTransmitting
        self.timestamp = timestamp
    }

    // MARK: Public

    public let radioID: String
    public let radioName: String?
    public let freqHz: UInt64
    public let mode: String
    public let vfo: String?
    public let split: SplitState?
    public let isTransmitting: Bool
    public let timestamp: Date
}

// MARK: - SplitState

public struct SplitState: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(enabled: Bool, txFreqHz: UInt64?) {
        self.enabled = enabled
        self.txFreqHz = txFreqHz
    }

    // MARK: Public

    public let enabled: Bool
    public let txFreqHz: UInt64?
}

// MARK: - RadioMetersEvent

public struct RadioMetersEvent: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        radioID: String,
        sMeter: Double?,
        swr: Double?,
        powerOut: Double?,
        alc: Double?,
        temperature: Double?,
        timestamp: Date
    ) {
        self.radioID = radioID
        self.sMeter = sMeter
        self.swr = swr
        self.powerOut = powerOut
        self.alc = alc
        self.temperature = temperature
        self.timestamp = timestamp
    }

    // MARK: Public

    public let radioID: String
    public let sMeter: Double?
    public let swr: Double?
    public let powerOut: Double?
    public let alc: Double?
    public let temperature: Double?
    public let timestamp: Date
}

// MARK: - RemoteSpot

/// Wire-format spot. Decoupled from CarrierWaveData's `EnrichedSpot` so the
/// protocol module stays free of SwiftData.
public struct RemoteSpot: Codable, Sendable, Equatable, Identifiable {
    // MARK: Lifecycle

    public init(
        id: String,
        callsign: String,
        freqHz: UInt64,
        mode: String?,
        band: String?,
        source: String,
        spotter: String?,
        comment: String?,
        snr: Int?,
        dxccEntity: String?,
        dxccPrefix: String?,
        region: String?,
        needed: Bool,
        workedBefore: Bool,
        spottedAt: Date,
        distanceMeters: Double? = nil,
        bearingDegrees: Double? = nil
    ) {
        self.id = id
        self.callsign = callsign
        self.freqHz = freqHz
        self.mode = mode
        self.band = band
        self.source = source
        self.spotter = spotter
        self.comment = comment
        self.snr = snr
        self.dxccEntity = dxccEntity
        self.dxccPrefix = dxccPrefix
        self.region = region
        self.needed = needed
        self.workedBefore = workedBefore
        self.spottedAt = spottedAt
        self.distanceMeters = distanceMeters
        self.bearingDegrees = bearingDegrees
    }

    // MARK: Public

    public let id: String
    public let callsign: String
    public let freqHz: UInt64
    public let mode: String?
    public let band: String?
    public let source: String
    public let spotter: String?
    public let comment: String?
    public let snr: Int?
    public let dxccEntity: String?
    public let dxccPrefix: String?
    public let region: String?
    public let needed: Bool
    public let workedBefore: Bool
    public let spottedAt: Date
    /// Great-circle distance from the user's QTH to the spot, when Sweep
    /// has been able to compute one (requires both ends to have a grid).
    public let distanceMeters: Double?
    /// Bearing from the user's QTH to the spot, in degrees true (0–360).
    public let bearingDegrees: Double?
}

// MARK: - SpotEvent

public struct SpotEvent: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(spot: RemoteSpot) {
        self.spot = spot
    }

    // MARK: Public

    public let spot: RemoteSpot
}

// MARK: - SpotsClearedEvent

public struct SpotsClearedEvent: Codable, Sendable, Equatable {
    public init() {}
}

// MARK: - TuneCommand

public struct TuneCommand: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        requestID: UUID = UUID(),
        radioID: String? = nil,
        freqHz: UInt64,
        mode: String? = nil
    ) {
        self.requestID = requestID
        self.radioID = radioID
        self.freqHz = freqHz
        self.mode = mode
    }

    // MARK: Public

    public let requestID: UUID
    public let radioID: String?
    public let freqHz: UInt64
    public let mode: String?
}

// MARK: - Ack

public struct Ack: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(requestID: UUID, success: Bool, detail: String? = nil) {
        self.requestID = requestID
        self.success = success
        self.detail = detail
    }

    // MARK: Public

    public let requestID: UUID
    public let success: Bool
    public let detail: String?
}

// MARK: - ErrorFrame

public struct ErrorFrame: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(code: ErrorCode, message: String, requestID: UUID? = nil) {
        self.code = code
        self.message = message
        self.requestID = requestID
    }

    // MARK: Public

    public let code: ErrorCode
    public let message: String
    public let requestID: UUID?
}

// MARK: - ErrorCode

public enum ErrorCode: String, Codable, Sendable, Equatable {
    case versionMismatch = "version_mismatch"
    case notAuthenticated = "not_authenticated"
    case pairingRefused = "pairing_refused"
    case invalidPayload = "invalid_payload"
    case unsupportedTopic = "unsupported_topic"
    case noActiveRadio = "no_active_radio"
    case commandFailed = "command_failed"
    case rateLimited = "rate_limited"
    case internalError = "internal_error"
}
