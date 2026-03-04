// POTA upload job status types
//
// Models the job status responses from the POTA API /user/jobs endpoint.
// Status codes: 0=pending, 1=processing, 2=complete, 3+=various error states.

import CarrierWaveData
import Foundation

// MARK: - POTAJobStatus

enum POTAJobStatus: Int, Codable {
    case pending = 0
    case processing = 1
    case completed = 2
    case failed = 3
    case duplicate = 7
    case error = -1

    // MARK: Internal

    var displayName: String {
        switch self {
        case .pending: "Pending"
        case .processing: "Processing"
        case .completed: "Completed"
        case .failed: "Failed"
        case .duplicate: "Duplicate"
        case .error: "Error"
        }
    }

    var color: String {
        switch self {
        case .pending,
             .processing:
            "orange"
        case .completed: "green"
        case .failed,
             .error:
            "red"
        case .duplicate: "yellow"
        }
    }

    var isFailure: Bool {
        switch self {
        case .failed,
             .error:
            true
        default: false
        }
    }
}

// MARK: - POTAJob

struct POTAJob: Identifiable, Codable {
    // MARK: Lifecycle

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobId = try container.decode(Int.self, forKey: .jobId)
        let statusInt = try container.decode(Int.self, forKey: .status)
        status = POTAJobStatus(rawValue: statusInt) ?? .error
        reference = try container.decode(String.self, forKey: .reference)
        parkName = try container.decodeIfPresent(String.self, forKey: .parkName)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        totalQsos = try container.decodeIfPresent(Int.self, forKey: .totalQsos) ?? -1
        insertedQsos = try container.decodeIfPresent(Int.self, forKey: .insertedQsos) ?? -1
        callsignUsed = try container.decodeIfPresent(String.self, forKey: .callsignUsed)
        userComment = try container.decodeIfPresent(String.self, forKey: .userComment)

        // Parse dates - POTA API returns dates without timezone suffix (assumed UTC)
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        // Simple formatter for dates without timezone (e.g., "2026-02-04T17:06:41")
        let simpleFormatter = DateFormatter()
        simpleFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        simpleFormatter.timeZone = TimeZone(identifier: "UTC")

        let submittedStr = try container.decode(String.self, forKey: .submitted)
        submitted =
            dateFormatter.date(from: submittedStr)
                ?? fallbackFormatter.date(from: submittedStr)
                ?? simpleFormatter.date(from: submittedStr)
                ?? Date()

        if let processedStr = try container.decodeIfPresent(String.self, forKey: .processed) {
            processed =
                dateFormatter.date(from: processedStr)
                    ?? fallbackFormatter.date(from: processedStr)
                    ?? simpleFormatter.date(from: processedStr)
        } else {
            processed = nil
        }

        // Parse firstQSO/lastQSO for activation matching
        if let firstQSOStr = try container.decodeIfPresent(String.self, forKey: .firstQSO) {
            firstQSO =
                dateFormatter.date(from: firstQSOStr)
                    ?? fallbackFormatter.date(from: firstQSOStr)
                    ?? simpleFormatter.date(from: firstQSOStr)
        } else {
            firstQSO = nil
        }

        if let lastQSOStr = try container.decodeIfPresent(String.self, forKey: .lastQSO) {
            lastQSO =
                dateFormatter.date(from: lastQSOStr)
                    ?? fallbackFormatter.date(from: lastQSOStr)
                    ?? simpleFormatter.date(from: lastQSOStr)
        } else {
            lastQSO = nil
        }
    }

    /// For testing/previews
    init(
        jobId: Int, status: POTAJobStatus, submitted: Date, processed: Date?,
        reference: String, parkName: String?, location: String?,
        totalQsos: Int, insertedQsos: Int, callsignUsed: String?, userComment: String?,
        firstQSO: Date? = nil, lastQSO: Date? = nil
    ) {
        self.jobId = jobId
        self.status = status
        self.submitted = submitted
        self.processed = processed
        self.reference = reference
        self.parkName = parkName
        self.location = location
        self.totalQsos = totalQsos
        self.insertedQsos = insertedQsos
        self.callsignUsed = callsignUsed
        self.userComment = userComment
        self.firstQSO = firstQSO
        self.lastQSO = lastQSO
    }

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case jobId
        case status
        case submitted
        case processed
        case reference
        case location
        case parkName
        case totalQsos = "total"
        case insertedQsos = "inserted"
        case callsignUsed
        case userComment
        case firstQSO
        case lastQSO
    }

    let jobId: Int
    let status: POTAJobStatus
    let submitted: Date
    let processed: Date?
    let reference: String
    let parkName: String?
    let location: String?
    let totalQsos: Int
    let insertedQsos: Int
    let callsignUsed: String?
    let userComment: String?
    /// Timestamp of the first QSO in this job (used for activation matching)
    let firstQSO: Date?
    /// Timestamp of the last QSO in this job
    let lastQSO: Date?

    var id: Int {
        jobId
    }

    /// UTC date string for the first QSO (for activation matching)
    var utcDateString: String? {
        guard let firstQSO else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: firstQSO)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jobId, forKey: .jobId)
        try container.encode(status.rawValue, forKey: .status)
        try container.encode(reference, forKey: .reference)
        try container.encodeIfPresent(parkName, forKey: .parkName)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encode(totalQsos, forKey: .totalQsos)
        try container.encode(insertedQsos, forKey: .insertedQsos)
        try container.encodeIfPresent(callsignUsed, forKey: .callsignUsed)
        try container.encodeIfPresent(userComment, forKey: .userComment)

        let dateFormatter = ISO8601DateFormatter()
        try container.encode(dateFormatter.string(from: submitted), forKey: .submitted)
        if let processed {
            try container.encode(dateFormatter.string(from: processed), forKey: .processed)
        }
        if let firstQSO {
            try container.encode(dateFormatter.string(from: firstQSO), forKey: .firstQSO)
        }
        if let lastQSO {
            try container.encode(dateFormatter.string(from: lastQSO), forKey: .lastQSO)
        }
    }
}

// MARK: - Job Matching

extension POTAJob {
    /// Check if this job matches a given activation by (park, UTC date, callsign).
    /// Only matches when firstQSO is available for exact date matching.
    /// Jobs with nil firstQSO are handled separately via fuzzy matching in rebuildJobIndex.
    func matches(parkReference: String, utcDate: String, callsign: String) -> Bool {
        guard matchesParkAndCallsign(parkReference: parkReference, callsign: callsign) else {
            return false
        }
        // Match UTC date of first QSO (requires firstQSO to be present)
        guard let jobDate = utcDateString else {
            return false
        }
        return jobDate == utcDate
    }

    /// Check if this job matches a park + callsign (ignoring date).
    /// Used for fuzzy matching nil-date jobs to unmatched activations.
    func matchesParkAndCallsign(parkReference: String, callsign: String) -> Bool {
        guard reference.uppercased() == parkReference.uppercased() else {
            return false
        }
        guard let jobCallsign = callsignUsed,
              jobCallsign.uppercased() == callsign.uppercased()
        else {
            return false
        }
        return true
    }
}

// MARK: - POTAJobDetails

/// Detailed job information from /user/jobs/details/{jobId}
struct POTAJobDetails: Codable {
    // MARK: Lifecycle

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        filename = try container.decodeIfPresent(String.self, forKey: .filename)
        stationCallsign = try container.decodeIfPresent(String.self, forKey: .stationCallsign)
        operatorCallsign = try container.decodeIfPresent(String.self, forKey: .operatorCallsign)
        mySigInfo = try container.decodeIfPresent(String.self, forKey: .mySigInfo)
        totals = try container.decodeIfPresent([String: POTAJobTotals].self, forKey: .totals)
        errors = try container.decodeIfPresent([String].self, forKey: .errors) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        header = try container.decodeIfPresent(POTAJobHeader.self, forKey: .header)
    }

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case filename
        case stationCallsign = "station_callsign"
        case operatorCallsign = "operator"
        case mySigInfo = "my_sig_info"
        case totals
        case errors
        case warnings
        case header
    }

    let filename: String?
    let stationCallsign: String?
    let operatorCallsign: String?
    let mySigInfo: String?
    let totals: [String: POTAJobTotals]?
    let errors: [String]
    let warnings: [String]
    let header: POTAJobHeader?
}

// MARK: - POTAJobTotals

/// QSO totals breakdown by activation date/park
struct POTAJobTotals: Codable {
    enum CodingKeys: String, CodingKey {
        case activationDate = "activation_date"
        case activationPark = "activation_park"
        case cw = "CW"
        case data = "DATA"
        case phone = "PHONE"
        case total = "TOTAL"
    }

    let activationDate: String?
    let activationPark: String?
    let cw: Int
    let data: Int
    let phone: Int
    let total: Int
}

// MARK: - POTAJobHeader

/// ADIF header information from job details
struct POTAJobHeader: Codable {
    // MARK: Lifecycle

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        raw = try container.decodeIfPresent(String.self, forKey: .raw)
        errors = try container.decodeIfPresent([String].self, forKey: .errors) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        infos = try container.decodeIfPresent([String].self, forKey: .infos) ?? []
        headerText = try container.decodeIfPresent(String.self, forKey: .headerText)
        adifVer = try container.decodeIfPresent(String.self, forKey: .adifVer)
        programid = try container.decodeIfPresent(String.self, forKey: .programid)
        programversion = try container.decodeIfPresent(String.self, forKey: .programversion)
    }

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case raw
        case errors
        case warnings
        case infos
        case headerText = "header_text"
        case adifVer = "adif_ver"
        case programid
        case programversion
    }

    let raw: String?
    let errors: [String]
    let warnings: [String]
    let infos: [String]
    let headerText: String?
    let adifVer: String?
    let programid: String?
    let programversion: String?
}
