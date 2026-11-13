// POTA Activation view model
//
// Groups QSOs by park reference, UTC date, and callsign for display
// in the POTA Activations view. Not persisted - computed from QSOs.

import CarrierWaveData
import Foundation

// MARK: - POTAActivationStatus

enum POTAActivationStatus {
    case uploaded // All QSOs confirmed in POTA job log
    case partial // Some QSOs confirmed
    case submitted // All QSOs submitted, awaiting POTA job confirmation
    case pending // No QSOs submitted or confirmed

    // MARK: Internal

    var iconName: String {
        switch self {
        case .uploaded: "checkmark.circle.fill"
        case .partial: "circle.lefthalf.filled"
        case .submitted: "clock.arrow.circlepath"
        case .pending: "arrow.up.circle"
        }
    }

    var color: String {
        switch self {
        case .uploaded: "green"
        case .partial: "orange"
        case .submitted: "blue"
        case .pending: "gray"
        }
    }
}

// MARK: - POTAActivation

struct POTAActivation: Identifiable, Equatable, Hashable {
    // MARK: Lifecycle

    init(
        parkReference: String,
        utcDate: Date,
        callsign: String,
        qsos: [QSO]
    ) {
        self.parkReference = parkReference
        self.utcDate = utcDate
        self.callsign = callsign
        self.qsos = qsos
        let parkList = POTAClient.splitParkReferences(parkReference)
        parks = parkList
        // Resolve the SwiftData servicePresence relationship exactly once, here, into
        // pure value snapshots. Subsequent reads of pendingCount/isRejected/etc. are
        // O(1) and never touch SwiftData — preventing the EXC_BREAKPOINT crash where
        // body rendering on the main thread races with CKSyncEngine merging on a
        // background thread and finds a `_InvalidFutureBackingData` placeholder.
        let snap = Self.computeUploadSnapshot(qsos: qsos, parks: parkList)
        pendingCount = snap.pendingCount
        submittedCount = snap.submittedCount
        uploadedCount = snap.uploadedCount
        isFullyUploaded = snap.isFullyUploaded
        isRejected = snap.isRejected
        parksNeedingUpload = snap.parksNeedingUpload
        uploadStatusSummary = snap.uploadStatusSummary
    }

    // MARK: Internal

    let parkReference: String
    let utcDate: Date
    let callsign: String
    let qsos: [QSO]

    /// Individual parks in this activation (splits comma-separated refs like
    /// "US-1044, US-3791"). Cached so consumers don't re-parse on every read.
    let parks: [String]

    /// Pre-computed upload status. Populated at init time by walking each QSO's
    /// servicePresence relationship once. Reads are pure value lookups — never
    /// touch SwiftData — so they are safe to call from a SwiftUI view body.
    let pendingCount: Int
    let submittedCount: Int
    let uploadedCount: Int
    let isFullyUploaded: Bool
    let isRejected: Bool
    let parksNeedingUpload: [String]
    let uploadStatusSummary: String?

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

    /// Count of unique QSOs (deduplicated by callsign + band + mode + park).
    /// POTA only credits one QSO per callsign/band/mode/park combination per activation.
    var uniqueQSOCount: Int {
        var seen = Set<String>()
        let park = parkReference.uppercased()
        for qso in qsos {
            let key = "\(qso.callsign.uppercased())|\(qso.band)|\(qso.mode)|\(park)"
            seen.insert(key)
        }
        return seen.count
    }

    var status: POTAActivationStatus {
        let uploaded = uploadedCount
        if uploaded == qsoCount {
            return .uploaded
        } else if uploaded > 0 {
            return .partial
        }
        // No confirmed uploads — check if submitted
        let submitted = submittedCount
        if submitted > 0 {
            return .submitted
        }
        return .pending
    }

    /// Whether there are QSOs that haven't been submitted or confirmed yet
    var hasQSOsToUpload: Bool {
        pendingCount > 0
    }

    // MARK: - Stats for Sharing

    /// Duration of the activation, summing individual session durations
    /// Groups QSOs by logging session and sums each session's span (first to last QSO),
    /// so gaps between sessions don't inflate the total.
    var duration: TimeInterval {
        guard !qsos.isEmpty else {
            return 0
        }

        // Group QSOs by logging session ID (nil = no session)
        var sessionGroups: [UUID?: [QSO]] = [:]
        for qso in qsos {
            sessionGroups[qso.loggingSessionId, default: []].append(qso)
        }

        // Sum the duration of each session group
        var total: TimeInterval = 0
        for (_, groupQSOs) in sessionGroups {
            guard let first = groupQSOs.min(by: { $0.timestamp < $1.timestamp }),
                  let last = groupQSOs.max(by: { $0.timestamp < $1.timestamp })
            else {
                continue
            }
            total += last.timestamp.timeIntervalSince(first.timestamp)
        }

        return total
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

    /// Unique modes used during this activation (deduped by mode family)
    var uniqueModes: [String] {
        ModeEquivalence.deduplicatedModes(qsos.map(\.mode))
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

    // MARK: - Two-fer Support

    /// Whether this is a multi-park activation (two-fer, three-fer, etc.)
    var isMultiPark: Bool {
        parks.count > 1
    }

    /// Upload status for each park in this activation
    /// Returns dict of park reference -> (uploaded count, total count)
    var uploadStatusByPark: [String: (uploaded: Int, total: Int)] {
        var status: [String: (uploaded: Int, total: Int)] = [:]
        for park in parks {
            let uploaded = qsos.filter { $0.isUploadedToPark(park) }.count
            status[park] = (uploaded: uploaded, total: qsos.count)
        }
        return status
    }

    /// Parks that have no uploads or submissions at all
    /// Used to show error indicators in the UI
    var failedParks: [String] {
        parks.filter { park in
            let uploaded = qsos.filter { $0.isUploadedToPark(park) }.count
            let submitted = qsos.filter { $0.isSubmittedToPark(park) }.count
            return uploaded == 0 && submitted == 0
        }
    }

    static func == (lhs: POTAActivation, rhs: POTAActivation) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Grouping

    /// Group QSOs into activations by (parkReference, UTC date, callsign)
    static func groupQSOs(_ qsos: [QSO]) -> [POTAActivation] {
        let calendar = Calendar(identifier: .gregorian)
        let utc = TimeZone(identifier: "UTC")!

        // Filter to QSOs with park references, excluding metadata modes (WEATHER, SOLAR, NOTE)
        let parkQSOs = qsos.filter {
            $0.parkReference?.isEmpty == false
                && !QSOMode.isMetadata($0.mode)
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
        return groups.compactMap { key, qsos in
            // Use omittingEmptySubsequences: false to preserve empty callsign between pipes
            let parts = key.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count >= 3 else {
                return nil
            }
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

    /// Group activations by UTC date for sectioning
    static func groupByDate(_ activations: [POTAActivation]) -> [(
        date: String, activations: [POTAActivation]
    )] {
        let grouped = Dictionary(grouping: activations) { $0.utcDateString }
        return
            grouped
                .map {
                    (date: $0.key, activations: $0.value.sorted { $0.parkReference < $1.parkReference })
                }
                .sorted { $0.date > $1.date }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// QSOs that are fully confirmed in POTA job log for all parks
    func uploadedQSOs() -> [QSO] {
        // A QSO is "uploaded" only if confirmed for ALL parks
        qsos.filter { qso in
            parks.allSatisfy { qso.isUploadedToPark($0) }
        }
    }

    /// QSOs that have been submitted but not yet confirmed by POTA job log
    func submittedQSOs() -> [QSO] {
        qsos.filter { qso in
            !qso.isUploadRejected(for: .pota)
                && !parks.allSatisfy { qso.isUploadedToPark($0) }
                && parks.contains { qso.isSubmittedToPark($0) }
        }
    }

    /// QSOs where upload was rejected by the user
    func rejectedQSOs() -> [QSO] {
        qsos.filter { $0.isUploadRejected(for: .pota) }
    }

    /// QSOs that need to be uploaded to POTA (not submitted, not confirmed, not rejected)
    func pendingQSOs() -> [QSO] {
        // A QSO is "pending" if ANY park hasn't been uploaded or submitted
        qsos.filter { qso in
            !qso.isUploadRejected(for: .pota)
                && parks.contains { !qso.isUploadedToPark($0) && !qso.isSubmittedToPark($0) }
        }
    }

    /// QSOs that need upload to a specific park (not submitted or confirmed)
    func pendingQSOs(forPark park: String) -> [QSO] {
        qsos.filter { qso in
            !qso.isUploadRejected(for: .pota) && !qso.isUploadedToPark(park)
                && !qso.isSubmittedToPark(park)
        }
    }

    // MARK: - Job Matching

    /// Find all POTA jobs that match this activation by (park, UTC date, callsign)
    /// Returns jobs sorted by submitted date descending (most recent first)
    func matchingJobs(from jobs: [POTAJob]) -> [POTAJob] {
        jobs.filter { job in
            job.matches(parkReference: parkReference, utcDate: utcDateString, callsign: callsign)
        }.sorted { $0.submitted > $1.submitted }
    }

    /// Check if any matching job has a failure status
    func hasFailedJob(in jobs: [POTAJob]) -> Bool {
        matchingJobs(from: jobs).contains { $0.status.isFailure }
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
