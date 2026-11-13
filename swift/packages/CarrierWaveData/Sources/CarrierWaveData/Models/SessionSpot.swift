import CarrierWaveCore
import Foundation
import SwiftData

@Model
nonisolated public final class SessionSpot {
    // MARK: Lifecycle

    public init(
        loggingSessionId: UUID,
        callsign: String,
        frequencyKHz: Double,
        mode: String,
        timestamp: Date,
        source: String,
        snr: Int? = nil,
        wpm: Int? = nil,
        spotter: String? = nil,
        spotterGrid: String? = nil,
        parkRef: String? = nil,
        parkName: String? = nil,
        comments: String? = nil,
        region: String = "Other",
        distanceMeters: Double? = nil,
        bearingDegrees: Double? = nil
    ) {
        id = UUID()
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

    public var id = UUID()
    public var loggingSessionId = UUID()
    public var callsign = ""
    public var frequencyKHz: Double = 0
    public var mode = ""
    public var timestamp = Date()
    public var source = ""
    public var snr: Int?
    public var wpm: Int?
    public var spotter: String?
    public var spotterGrid: String?
    public var parkRef: String?
    public var parkName: String?
    public var comments: String?
    public var region = "Other"
    public var distanceMeters: Double?
    public var bearingDegrees: Double?
    public var cloudDirtyFlag = false

    public var dedupKey: String {
        "\(source)-\(callsign)-\(Int(frequencyKHz))-\(Int(timestamp.timeIntervalSince1970))"
    }

    public var isPOTA: Bool {
        source == "pota" && !isRBNRelay
    }

    public var isSelfSpot: Bool {
        isPOTA && spotter?.uppercased() == callsign.uppercased()
    }

    public var isRBN: Bool {
        source == "rbn" || isRBNRelay
    }

    public var isRBNRelay: Bool {
        source == "pota" && (comments?.hasPrefix("RBN") ?? false)
    }

    public var band: String? {
        BandUtilities.deriveBand(from: frequencyKHz)
    }

    public var frequencyMHz: Double {
        frequencyKHz / 1_000.0
    }
}
