// POTA Activation view model
//
// Groups QSOs by park reference, UTC date, and callsign for display
// in the POTA Activations view. Not persisted - computed from QSOs.

import Foundation

// MARK: - POTAActivationStatus

enum POTAActivationStatus {
    case uploaded // All QSOs present in POTA
    case partial // Some QSOs present
    case pending // No QSOs present

    // MARK: Internal

    var iconName: String {
        switch self {
        case .uploaded: "checkmark.circle.fill"
        case .partial: "circle.lefthalf.filled"
        case .pending: "arrow.up.circle"
        }
    }

    var color: String {
        switch self {
        case .uploaded: "green"
        case .partial: "orange"
        case .pending: "gray"
        }
    }
}

// MARK: - POTAActivation

struct POTAActivation: Identifiable {
    // MARK: Internal

    /// Modes that represent activation metadata, not actual QSOs (from Ham2K PoLo)
    /// These should never be uploaded to POTA or counted as QSOs
    static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

    let parkReference: String
    let utcDate: Date
    let callsign: String
    let qsos: [QSO]

    var id: String {
        let dateString = Self.utcDateFormatter.string(from: utcDate)
        return "\(parkReference)|\(callsign)|\(dateString)"
    }

    var utcDateString: String {
        Self.utcDateFormatter.string(from: utcDate)
    }

    var displayDate: String {
        Self.displayDateFormatter.string(from: utcDate)
    }

    var qsoCount: Int {
        qsos.count
    }

    var uploadedCount: Int {
        uploadedQSOs().count
    }

    var pendingCount: Int {
        pendingQSOs().count
    }

    var status: POTAActivationStatus {
        let uploaded = uploadedCount
        if uploaded == qsoCount {
            return .uploaded
        } else if uploaded > 0 {
            return .partial
        } else {
            return .pending
        }
    }

    var hasQSOsToUpload: Bool {
        pendingCount > 0
    }

    // MARK: - Stats for Sharing

    /// Duration of the activation (first QSO to last QSO)
    var duration: TimeInterval {
        guard let first = qsos.min(by: { $0.timestamp < $1.timestamp }),
              let last = qsos.max(by: { $0.timestamp < $1.timestamp })
        else {
            return 0
        }
        return last.timestamp.timeIntervalSince(first.timestamp)
    }

    /// Formatted duration string (e.g., "2h 15m" or "45m")
    var formattedDuration: String {
        let totalMinutes = Int(duration) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// Unique bands worked during this activation
    var uniqueBands: Set<String> {
        Set(qsos.map(\.band))
    }

    /// Unique modes used during this activation
    var uniqueModes: Set<String> {
        Set(qsos.map(\.mode))
    }

    /// QSOs that have valid grid squares for mapping
    var mappableQSOs: [QSO] {
        qsos.filter { qso in
            guard let grid = qso.theirGrid, grid.count >= 4 else {
                return false
            }
            return true
        }
    }

    /// Whether this activation has been rejected (all non-uploaded QSOs are rejected)
    var isRejected: Bool {
        let notUploaded = qsos.filter { !$0.isPresentInPOTA() }
        guard !notUploaded.isEmpty else {
            return false
        }
        return notUploaded.allSatisfy { $0.isUploadRejected(for: .pota) }
    }

    // MARK: - Grouping

    /// Group QSOs into activations by (parkReference, UTC date, callsign)
    static func groupQSOs(_ qsos: [QSO]) -> [POTAActivation] {
        let calendar = Calendar(identifier: .gregorian)
        let utc = TimeZone(identifier: "UTC")!

        // Filter to QSOs with park references, excluding metadata modes (WEATHER, SOLAR, NOTE)
        let parkQSOs = qsos.filter {
            $0.parkReference?.isEmpty == false
                && !metadataModes.contains($0.mode.uppercased())
        }

        // Group by (park, utcDate, callsign)
        var groups: [String: [QSO]] = [:]
        for qso in parkQSOs {
            let parkRef = qso.parkReference!.uppercased()
            let utcDate = calendar.startOfDay(for: qso.timestamp, in: utc)
            let callsign = qso.myCallsign.uppercased()
            let key = "\(parkRef)|\(callsign)|\(utcDateFormatter.string(from: utcDate))"
            groups[key, default: []].append(qso)
        }

        // Convert to POTAActivation structs
        return groups.map { key, qsos in
            // Use omittingEmptySubsequences: false to preserve empty callsign between pipes
            let parts = key.split(separator: "|", omittingEmptySubsequences: false)
            let parkRef = String(parts[0])
            let callsign = String(parts[1])
            let dateStr = String(parts[2])
            let utcDate = utcDateFormatter.date(from: dateStr) ?? Date()
            return POTAActivation(
                parkReference: parkRef,
                utcDate: utcDate,
                callsign: callsign,
                qsos: qsos.sorted { $0.timestamp < $1.timestamp }
            )
        }.sorted { $0.utcDate > $1.utcDate }
    }

    /// Group activations by park reference for sectioning
    static func groupByPark(_ activations: [POTAActivation]) -> [(
        park: String, activations: [POTAActivation]
    )] {
        let grouped = Dictionary(grouping: activations) { $0.parkReference }
        return
            grouped
                .map { (park: $0.key, activations: $0.value.sorted { $0.utcDate > $1.utcDate }) }
                .sorted { $0.park < $1.park }
    }

    /// QSOs that are present in POTA (uploaded or downloaded from POTA)
    func uploadedQSOs() -> [QSO] {
        qsos.filter { $0.isPresentInPOTA() }
    }

    /// QSOs where upload was rejected by the user
    func rejectedQSOs() -> [QSO] {
        qsos.filter { $0.isUploadRejected(for: .pota) }
    }

    /// QSOs that need to be uploaded to POTA (not uploaded and not rejected)
    func pendingQSOs() -> [QSO] {
        qsos.filter { !$0.isPresentInPOTA() && !$0.isUploadRejected(for: .pota) }
    }

    // MARK: Private

    // MARK: - Date Formatters

    private static let utcDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}

// MARK: - Calendar Extension

private extension Calendar {
    func startOfDay(for date: Date, in timeZone: TimeZone) -> Date {
        var cal = self
        cal.timeZone = timeZone
        return cal.startOfDay(for: date)
    }
}
