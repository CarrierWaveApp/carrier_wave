import Foundation
import SwiftData

@Model
nonisolated public final class QSO {
    // MARK: Lifecycle

    public init(
        id: UUID = UUID(),
        callsign: String,
        band: String,
        mode: String,
        frequency: Double? = nil,
        timestamp: Date,
        rstSent: String? = nil,
        rstReceived: String? = nil,
        myCallsign: String,
        myGrid: String? = nil,
        theirGrid: String? = nil,
        parkReference: String? = nil,
        theirParkReference: String? = nil,
        notes: String? = nil,
        notesUserAuthored: Bool = false,
        importSource: ImportSource,
        importedAt: Date = Date(),
        rawADIF: String? = nil,
        name: String? = nil,
        qth: String? = nil,
        state: String? = nil,
        country: String? = nil,
        power: Int? = nil,
        myRig: String? = nil,
        stationProfileName: String? = nil,
        sotaRef: String? = nil,
        wwffRef: String? = nil,
        aoaCode: String? = nil,
        qrzLogId: String? = nil,
        qrzConfirmed: Bool = false,
        lotwConfirmedDate: Date? = nil,
        lotwConfirmed: Bool = false,
        dxcc: Int? = nil,
        theirLicenseClass: String? = nil,
        contestName: String? = nil,
        contestSerialSent: Int? = nil,
        contestSerialReceived: Int? = nil,
        contestExchangeSent: String? = nil,
        contestExchangeReceived: String? = nil,
        callsignChangeNote: String? = nil,
        satName: String? = nil,
        propMode: String? = nil
    ) {
        self.id = id
        self.callsign = callsign
        self.band = band
        self.mode = mode
        self.frequency = frequency
        self.timestamp = timestamp
        self.rstSent = rstSent
        self.rstReceived = rstReceived
        self.myCallsign = myCallsign
        self.myGrid = myGrid
        self.theirGrid = theirGrid
        self.parkReference = parkReference
        self.theirParkReference = theirParkReference
        self.notes = notes
        self.notesUserAuthored = notesUserAuthored
        importSourceRawValue = importSource.rawValue
        self.importedAt = importedAt
        self.rawADIF = rawADIF
        self.name = name
        self.qth = qth
        self.state = state
        self.country = country
        self.power = power
        self.myRig = myRig
        self.stationProfileName = stationProfileName
        self.sotaRef = sotaRef
        self.wwffRef = wwffRef
        self.aoaCode = aoaCode
        self.qrzLogId = qrzLogId
        self.qrzConfirmed = qrzConfirmed
        self.lotwConfirmedDate = lotwConfirmedDate
        self.lotwConfirmed = lotwConfirmed
        self.dxcc = dxcc
        self.theirLicenseClass = theirLicenseClass
        self.contestName = contestName
        self.contestSerialSent = contestSerialSent
        self.contestSerialReceived = contestSerialReceived
        self.contestExchangeSent = contestExchangeSent
        self.contestExchangeReceived = contestExchangeReceived
        self.callsignChangeNote = callsignChangeNote
        self.satName = satName
        self.propMode = propMode
    }

    // MARK: Public

    public var id = UUID()
    public var callsign = ""
    public var band = ""
    public var mode = ""
    public var frequency: Double?
    public var timestamp = Date()
    public var rstSent: String?
    public var rstReceived: String?
    public var myCallsign = ""
    public var myGrid: String?
    public var theirGrid: String?
    public var parkReference: String?
    public var theirParkReference: String?
    public var notes: String?
    /// Whether `notes` was authored by the user inside Carrier Wave (vs. arrived
    /// from an external source like LoFi/ADIF import/QRZ round-trip). Gates
    /// whether the COMMENT field is uploaded to QRZ. CAR-243.
    /// Default false: assume external until a user-edit site flips it true.
    public var notesUserAuthored: Bool = false
    /// JSON-encoded list of POTA spot comments attached to this QSO.
    /// Stored as Data so the array round-trips through CloudKit unchanged;
    /// access via `spotComments` for typed reads/writes.
    public var spotCommentsData: Data?
    /// Note about callsign owner change detected during lookup
    public var callsignChangeNote: String?
    /// First-known contact callsign for this QSO. nil until the user edits
    /// `callsign`; on first edit, set to the pre-edit value. Used by the
    /// download-merge dedup so that a remote service still holding the
    /// original callsign re-merges into this QSO instead of duplicating.
    /// See CAR-245.
    public var originalCallsign: String?
    @Attribute(originalName: "importSource")
    public var importSourceRawValue = ImportSource.logger.rawValue
    public var importedAt = Date()
    public var rawADIF: String?

    // Contact info
    public var name: String?
    public var qth: String?
    public var state: String?
    public var country: String?
    public var power: Int?
    public var myRig: String?
    public var stationProfileName: String?
    public var sotaRef: String?
    public var wwffRef: String?
    public var aoaCode: String?

    // QRZ sync tracking
    public var qrzLogId: String?
    public var qrzConfirmed: Bool = false
    public var lotwConfirmedDate: Date?
    public var lotwConfirmed: Bool = false

    /// DXCC entity (from LoTW)
    public var dxcc: Int?

    /// Their license class (e.g., "Extra", "General")
    public var theirLicenseClass: String?

    /// Contest fields
    /// Contest identifier (matches ContestDefinition.id)
    public var contestName: String?
    /// Serial number sent in this QSO
    public var contestSerialSent: Int?
    /// Serial number received in this QSO
    public var contestSerialReceived: Int?
    /// Exchange sent (state, zone, section, etc.)
    public var contestExchangeSent: String?
    /// Exchange received
    public var contestExchangeReceived: String?

    /// Satellite fields (ADIF SAT_NAME / PROP_MODE)
    /// Satellite short name worked through (e.g. "AO-91"); nil for terrestrial QSOs
    public var satName: String?
    /// Propagation mode; "SAT" when this QSO came through a satellite
    public var propMode: String?

    /// Soft delete flag
    public var isHidden: Bool = false

    /// Whether this QSO was created via the activity log (hunter workflow)
    public var isActivityLogQSO: Bool = false

    /// Club/alternate callsign used over the air (nil = operator is the station)
    public var stationCallsign: String?

    /// Whether this record has local changes not yet synced to iCloud
    public var cloudDirtyFlag: Bool = false

    /// When this QSO was last edited locally
    public var modifiedAt: Date?

    /// Logging session this QSO belongs to
    public var loggingSessionId: UUID?

    /// Whether this QSO is part of a contest
    public var isContestQSO: Bool {
        contestName != nil
    }

    /// Non-optional wrapper for CloudKit-required optional relationship
    public var servicePresence: [ServicePresence] {
        get { servicePresenceRelation ?? [] }
        set { servicePresenceRelation = newValue }
    }

    /// Import source enum accessor
    public var importSource: ImportSource {
        get { ImportSource(rawValue: importSourceRawValue) ?? .logger }
        set { importSourceRawValue = newValue.rawValue }
    }

    /// Extract callsign prefix (for display/grouping)
    public var callsignPrefix: String {
        let upper = callsign.uppercased()
        let base = upper.components(separatedBy: "/").first ?? upper
        var prefix = ""
        for char in base {
            if char.isLetter || char.isNumber {
                prefix.append(char)
                if prefix.count >= 2, char.isNumber {
                    break
                }
                if prefix.count >= 3 {
                    break
                }
            }
        }
        return prefix
    }

    /// Convenience property - QSO is visible (not hidden)
    public var isVisible: Bool {
        !isHidden
    }

    /// Whether this QSO has the required fields for upload
    public var hasRequiredFieldsForUpload: Bool {
        let hasValidBand = !band.isEmpty && band.uppercased() != "UNKNOWN"
        let hasFrequency = frequency != nil
        return hasValidBand || hasFrequency
    }

    /// Count of populated optional fields (for deduplication tiebreaker)
    public var fieldRichnessScore: Int {
        var score = 0
        if rstSent != nil {
            score += 1
        }
        if rstReceived != nil {
            score += 1
        }
        if myGrid != nil {
            score += 1
        }
        if theirGrid != nil {
            score += 1
        }
        if parkReference != nil {
            score += 1
        }
        if theirParkReference != nil {
            score += 1
        }
        if notes != nil {
            score += 1
        }
        if qrzLogId != nil {
            score += 1
        }
        if rawADIF != nil {
            score += 1
        }
        if frequency != nil {
            score += 1
        }
        if name != nil {
            score += 1
        }
        if qth != nil {
            score += 1
        }
        if state != nil {
            score += 1
        }
        if country != nil {
            score += 1
        }
        if power != nil {
            score += 1
        }
        if sotaRef != nil {
            score += 1
        }
        if wwffRef != nil {
            score += 1
        }
        if theirLicenseClass != nil {
            score += 1
        }
        if aoaCode != nil {
            score += 1
        }
        if satName != nil {
            score += 1
        }
        if propMode != nil {
            score += 1
        }
        return score
    }

    /// Count of services where this QSO is confirmed present
    public var syncedServicesCount: Int {
        servicePresence.filter(\.isPresent).count
    }

    /// Date only in local timezone
    public var dateOnly: Date {
        Calendar.current.startOfDay(for: timestamp)
    }

    /// Date only in UTC (for POTA activation grouping)
    public var utcDateOnly: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.startOfDay(for: timestamp)
    }

    /// POTA spot comments attached to this QSO by the live spot poller.
    /// Backed by `spotCommentsData` so the array survives CloudKit sync.
    public var spotComments: [POTASpotComment] {
        get {
            guard let data = spotCommentsData else {
                return []
            }
            return (try? JSONDecoder().decode([POTASpotComment].self, from: data)) ?? []
        }
        set { spotCommentsData = try? JSONEncoder().encode(newValue) }
    }

    // MARK: Private

    @Relationship(deleteRule: .cascade, inverse: \ServicePresence.qso)
    private var servicePresenceRelation: [ServicePresence]?
}
