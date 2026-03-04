import CarrierWaveData
import Foundation

// MARK: - HAMRSAuthResponse

/// Response from HAMRS /api/v1/couchdb_url endpoint
struct HAMRSAuthResponse: Codable, @unchecked Sendable {
    let subscribed: Bool
    let url: String?
}

// MARK: - HAMRSLogbook

/// HAMRS Logbook document from CouchDB
/// Contains activation info that applies to all QSOs in the logbook
struct HAMRSLogbook: Codable, @unchecked Sendable {
    // MARK: Lifecycle

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        rev = try container.decodeIfPresent(String.self, forKey: .rev)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        template = try container.decodeIfPresent(String.self, forKey: .template)
        myPark = try container.decodeIfPresent(String.self, forKey: .myPark)
        myGridsquare = try container.decodeIfPresent(String.self, forKey: .myGridsquare)
        operatorCall = try container.decodeIfPresent(String.self, forKey: .operatorCall)
    }

    init(
        id: String,
        rev: String?,
        title: String?,
        createdAt: String?,
        updatedAt: String?,
        template: String?,
        myPark: String?,
        myGridsquare: String?,
        operatorCall: String?
    ) {
        self.id = id
        self.rev = rev
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.template = template
        self.myPark = myPark
        self.myGridsquare = myGridsquare
        self.operatorCall = operatorCall
    }

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case rev = "_rev"
        case title
        case createdAt
        case updatedAt
        case template
        case myPark
        case myGridsquare
        case operatorCall = "operator"
    }

    let id: String
    let rev: String?
    let title: String?
    let createdAt: String?
    let updatedAt: String?
    let template: String?
    let myPark: String?
    let myGridsquare: String?
    let operatorCall: String?

    /// Logbook ID without the "LOGBOOK:" prefix
    var logbookId: String {
        if id.hasPrefix("LOGBOOK:") {
            return String(id.dropFirst(8))
        }
        return id
    }
}

// MARK: - HAMRSQSO

/// HAMRS QSO document from CouchDB
struct HAMRSQSO: Codable, @unchecked Sendable {
    // MARK: Lifecycle

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        rev = try container.decodeIfPresent(String.self, forKey: .rev)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        call = try container.decodeIfPresent(String.self, forKey: .call)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        qth = try container.decodeIfPresent(String.self, forKey: .qth)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        gridsquare = try container.decodeIfPresent(String.self, forKey: .gridsquare)
        freq = try container.decodeIfPresent(FrequencyValue.self, forKey: .freq)
        band = try container.decodeIfPresent(String.self, forKey: .band)
        mode = try container.decodeIfPresent(String.self, forKey: .mode)
        rstSent = try container.decodeIfPresent(String.self, forKey: .rstSent)
        rstRcvd = try container.decodeIfPresent(String.self, forKey: .rstRcvd)
        qsoDate = try container.decodeIfPresent(String.self, forKey: .qsoDate)
        timeOn = try container.decodeIfPresent(String.self, forKey: .timeOn)
        qsoDateTime = try container.decodeIfPresent(String.self, forKey: .qsoDateTime)
        txPwr = try container.decodeIfPresent(PowerValue.self, forKey: .txPwr)
        potaRef = try container.decodeIfPresent(String.self, forKey: .potaRef)
        sotaRef = try container.decodeIfPresent(String.self, forKey: .sotaRef)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case rev = "_rev"
        case createdAt
        case call
        case name
        case qth
        case state
        case country
        case gridsquare
        case freq
        case band
        case mode
        case rstSent
        case rstRcvd
        case qsoDate
        case timeOn
        case qsoDateTime
        case txPwr
        case potaRef
        case sotaRef
        case notes
    }

    let id: String
    let rev: String?
    let createdAt: String?

    // Contact info
    let call: String?
    let name: String?
    let qth: String?
    let state: String?
    let country: String?
    let gridsquare: String?

    // QSO details
    let freq: FrequencyValue?
    let band: String?
    let mode: String?
    let rstSent: String?
    let rstRcvd: String?
    let qsoDate: String?
    let timeOn: String?
    let qsoDateTime: String?
    let txPwr: PowerValue?

    // Program references
    let potaRef: String?
    let sotaRef: String?

    /// Other
    let notes: String?

    /// Extract logbook ID from QSO ID
    /// Format: QSO:LOGBOOK:{logbook-uuid}:{qso-uuid}
    var logbookId: String? {
        let parts = id.split(separator: ":")
        guard parts.count >= 3, parts[0] == "QSO", parts[1] == "LOGBOOK" else {
            return nil
        }
        return String(parts[2])
    }

    /// Parse timestamp from qsoDateTime (ISO 8601) or fall back to qsoDate + timeOn
    var timestamp: Date? {
        // Try ISO 8601 first
        if let dateTimeStr = qsoDateTime {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateTimeStr) {
                return date
            }
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateTimeStr) {
                return date
            }
        }

        // Fall back to qsoDate + timeOn
        guard let dateStr = qsoDate else {
            return nil
        }

        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        if let timeStr = timeOn {
            // Try with time
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            if let date = dateFormatter.date(from: "\(dateStr) \(timeStr)") {
                return date
            }
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
            if let date = dateFormatter.date(from: "\(dateStr) \(timeStr.prefix(5))") {
                return date
            }
        }

        // Date only
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.date(from: dateStr)
    }
}

// MARK: - FrequencyValue

/// Handles frequency that can be either a number or string in JSON
enum FrequencyValue: Codable, @unchecked Sendable {
    case double(Double)
    case string(String)

    // MARK: Lifecycle

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.typeMismatch(
                FrequencyValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected Double or String for frequency"
                )
            )
        }
    }

    // MARK: Internal

    var doubleValue: Double? {
        switch self {
        case let .double(value):
            value
        case let .string(value):
            Double(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .double(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        }
    }
}

// MARK: - PowerValue

/// Handles power that can be either a number or string in JSON
enum PowerValue: Codable, @unchecked Sendable {
    case int(Int)
    case string(String)

    // MARK: Lifecycle

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.typeMismatch(
                PowerValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected Int or String for power"
                )
            )
        }
    }

    // MARK: Internal

    var intValue: Int? {
        switch self {
        case let .int(value):
            value
        case let .string(value):
            Int(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .int(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        }
    }
}

// MARK: - CouchDBAllDocsResponse

/// CouchDB _all_docs response
struct CouchDBAllDocsResponse<T: Codable>: Codable, @unchecked Sendable {
    enum CodingKeys: String, CodingKey {
        case totalRows = "total_rows"
        case offset
        case rows
    }

    let totalRows: Int
    let offset: Int
    let rows: [CouchDBRow<T>]
}

// MARK: - CouchDBRow

/// Single row in CouchDB _all_docs response
struct CouchDBRow<T: Codable>: Codable, @unchecked Sendable {
    let id: String
    let key: String
    let doc: T?
}
