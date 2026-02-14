import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - ActivationType

/// Type of logging activation
enum ActivationType: String, Codable, CaseIterable {
    case casual
    case pota
    case sota

    // MARK: Internal

    var displayName: String {
        switch self {
        case .casual: "Casual"
        case .pota: "POTA"
        case .sota: "SOTA"
        }
    }

    var icon: String {
        switch self {
        case .casual: "radio"
        case .pota: "tree"
        case .sota: "mountain.2"
        }
    }
}

// MARK: - LoggingSessionStatus

/// Status of a logging session
enum LoggingSessionStatus: String, Codable {
    case active
    case paused
    case completed
}

// MARK: - LoggingSession

/// A logging session represents a period of operating, optionally at a specific activation
@Model
final class LoggingSession {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        myCallsign: String,
        startedAt: Date = Date(),
        frequency: Double? = nil,
        mode: String = "CW",
        activationType: ActivationType = .casual,
        parkReference: String? = nil,
        sotaReference: String? = nil,
        myGrid: String? = nil,
        notes: String? = nil,
        power: Int? = nil,
        myRig: String? = nil,
        myAntenna: String? = nil,
        myKey: String? = nil,
        myMic: String? = nil,
        extraEquipment: String? = nil,
        attendees: String? = nil
    ) {
        self.id = id
        self.myCallsign = myCallsign
        self.startedAt = startedAt
        self.frequency = frequency
        self.mode = mode
        activationTypeRawValue = activationType.rawValue
        self.parkReference = parkReference
        self.sotaReference = sotaReference
        self.myGrid = myGrid
        self.notes = notes
        self.power = power
        self.myRig = myRig
        self.myAntenna = myAntenna
        self.myKey = myKey
        self.myMic = myMic
        self.extraEquipment = extraEquipment
        self.attendees = attendees
    }

    // MARK: Internal

    var id: UUID
    var myCallsign: String
    var startedAt: Date
    var endedAt: Date?

    /// Operating frequency in MHz (e.g., 14.060)
    var frequency: Double?

    /// Operating mode (CW, SSB, FT8, etc.)
    var mode: String

    /// Stored as raw value for SwiftData compatibility
    var activationTypeRawValue: String = ActivationType.casual.rawValue

    /// Session status stored as raw value
    var statusRawValue: String = LoggingSessionStatus.active.rawValue

    /// POTA park reference (e.g., "K-1234")
    var parkReference: String?

    /// SOTA summit reference (e.g., "W4C/CM-001")
    var sotaReference: String?

    /// Operator's grid square
    var myGrid: String?

    /// Transmit power in watts
    var power: Int?

    /// Radio/rig name (e.g., "Elecraft KX3")
    var myRig: String?

    /// Session notes
    var notes: String?

    /// Custom title set by user (overrides displayTitle)
    var customTitle: String?

    /// Number of QSOs logged in this session
    var qsoCount: Int = 0

    /// Serialized spot comments JSON (stored as Data for SwiftData compatibility)
    var spotCommentsData: Data?

    // MARK: - Equipment

    /// Antenna used (e.g., "EFHW", "Buddipole")
    var myAntenna: String?

    /// CW key used (e.g., "Begali Adventure")
    var myKey: String?

    /// Microphone used (e.g., "Heil Pro 7")
    var myMic: String?

    /// Additional equipment notes
    var extraEquipment: String?

    // MARK: - People

    /// Comma-separated attendees/operators
    var attendees: String?

    // MARK: - Photos

    /// Photo filenames relative to SessionPhotos/<sessionUUID>/
    var photoFilenames: [String] = []

    /// Activation type enum accessor
    var activationType: ActivationType {
        get { ActivationType(rawValue: activationTypeRawValue) ?? .casual }
        set { activationTypeRawValue = newValue.rawValue }
    }

    /// Session status enum accessor
    var status: LoggingSessionStatus {
        get { LoggingSessionStatus(rawValue: statusRawValue) ?? .active }
        set { statusRawValue = newValue.rawValue }
    }

    /// Spot comments from the session (decoded from JSON data)
    var spotComments: [POTASpotComment] {
        get {
            guard let data = spotCommentsData else {
                return []
            }
            return (try? JSONDecoder().decode([POTASpotComment].self, from: data)) ?? []
        }
        set {
            spotCommentsData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Whether the session is currently active
    var isActive: Bool {
        status == .active
    }

    /// Session duration
    var duration: TimeInterval {
        let end = endedAt ?? Date()
        return end.timeIntervalSince(startedAt)
    }

    // MARK: - Methods

    /// End the session
    func end() {
        endedAt = Date()
        status = .completed
    }

    /// Pause the session
    func pause() {
        status = .paused
    }

    /// Resume a paused session
    func resume() {
        status = .active
    }

    /// Increment QSO count
    func incrementQSOCount() {
        qsoCount += 1
    }

    /// Update operating frequency
    func updateFrequency(_ freq: Double) {
        frequency = freq
    }

    /// Update operating mode
    func updateMode(_ newMode: String) {
        mode = newMode.uppercased()
    }
}
