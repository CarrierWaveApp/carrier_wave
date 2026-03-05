import Foundation

/// Data from a qsy://log URI, held for user confirmation before logging.
struct QSYLogConfirmation: Identifiable, Equatable, Sendable {
    let id = UUID()
    let callsign: String
    let frequencyMHz: Double
    let mode: String
    var rstSent: String?
    var rstReceived: String?
    var grid: String?
    var ref: String?
    var refType: String?
    var time: Date?
    var contest: String?
    var srx: String?
    var stx: String?
    var source: String?
    var comment: String?

    static func == (lhs: QSYLogConfirmation, rhs: QSYLogConfirmation) -> Bool {
        lhs.id == rhs.id
    }
}
