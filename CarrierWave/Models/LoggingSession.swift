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
        notes: String? = nil
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
    }

    // MARK: Internal

    /// Common CW frequencies by band
    static let cwFrequencies: [String: Double] = [
        "160m": 1.810,
        "80m": 3.530,
        "60m": 5.332,
        "40m": 7.030,
        "30m": 10.106,
        "20m": 14.060,
        "17m": 18.080,
        "15m": 21.060,
        "12m": 24.910,
        "10m": 28.060,
    ]

    /// Common SSB frequencies by band
    static let ssbFrequencies: [String: Double] = [
        "160m": 1.900,
        "80m": 3.850,
        "40m": 7.200,
        "20m": 14.250,
        "17m": 18.140,
        "15m": 21.300,
        "12m": 24.950,
        "10m": 28.400,
    ]

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

    /// Session notes
    var notes: String?

    /// Custom title set by user (overrides displayTitle)
    var customTitle: String?

    /// Number of QSOs logged in this session
    var qsoCount: Int = 0

    /// Serialized spot comments JSON (stored as Data for SwiftData compatibility)
    var spotCommentsData: Data?

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

    /// Formatted duration string (e.g., "1h 23m")
    var formattedDuration: String {
        let hours = Int(duration) / 3_600
        let minutes = (Int(duration) % 3_600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    /// Band derived from frequency
    var band: String? {
        guard let freq = frequency else {
            return nil
        }
        return Self.bandForFrequency(freq)
    }

    /// Display title for the session (uses customTitle if set)
    var displayTitle: String {
        if let custom = customTitle, !custom.isEmpty {
            return custom
        }
        return defaultTitle
    }

    /// Default generated title based on activation type
    var defaultTitle: String {
        switch activationType {
        case .pota:
            if let park = parkReference {
                return "\(myCallsign) at \(park)"
            }
            return "\(myCallsign) POTA"
        case .sota:
            if let summit = sotaReference {
                return "\(myCallsign) at \(summit)"
            }
            return "\(myCallsign) SOTA"
        case .casual:
            return "\(myCallsign) Casual"
        }
    }

    /// Reference for the activation (park or summit)
    var activationReference: String? {
        switch activationType {
        case .pota: parkReference
        case .sota: sotaReference
        case .casual: nil
        }
    }

    // MARK: - Static Helpers

    /// Get band name for a frequency in MHz
    static func bandForFrequency(_ freq: Double) -> String {
        switch freq {
        case 1.8 ..< 2.0: "160m"
        case 3.5 ..< 4.0: "80m"
        case 5.3 ..< 5.4: "60m"
        case 7.0 ..< 7.3: "40m"
        case 10.1 ..< 10.15: "30m"
        case 14.0 ..< 14.35: "20m"
        case 18.068 ..< 18.168: "17m"
        case 21.0 ..< 21.45: "15m"
        case 24.89 ..< 24.99: "12m"
        case 28.0 ..< 29.7: "10m"
        case 50.0 ..< 54.0: "6m"
        case 144.0 ..< 148.0: "2m"
        case 420.0 ..< 450.0: "70cm"
        default: "Unknown"
        }
    }

    /// Get suggested frequencies for a mode
    static func suggestedFrequencies(for mode: String) -> [String: Double] {
        switch mode.uppercased() {
        case "CW": cwFrequencies
        case "SSB",
             "USB",
             "LSB":
            ssbFrequencies
        default: cwFrequencies // Default to CW
        }
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
