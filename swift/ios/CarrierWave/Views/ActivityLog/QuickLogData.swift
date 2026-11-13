import Foundation

// MARK: - QuickLogData

/// Data collected from the quick log form
struct QuickLogData {
    var callsign: String = ""
    var band: String = "Unknown"
    var mode: String = "CW"
    var frequency: Double?
    var rstSent: String = "599"
    var rstReceived: String = "599"
    var theirParkReference: String?
    var theirGrid: String?
    var state: String?
    var notes: String?
    var name: String?
    var country: String?
}
