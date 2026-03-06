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
        callsignChangeNote: String? = nil
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
    /// Note about callsign owner change detected during lookup
    public var callsignChangeNote: String?
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

    /// Soft delete flag
    public var isHidden: Bool = false

    /// Whether this QSO was created via the activity log (hunter workflow)
    public var isActivityLogQSO: Bool = false

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

    // MARK: - Service Presence Helpers

    /// Get presence record for a specific service
    public func presence(for service: ServiceType) -> ServicePresence? {
        servicePresence.first { !$0.isDeleted && $0.serviceType == service }
    }

    /// Check if QSO is present in a service
    public func isPresent(in service: ServiceType) -> Bool {
        presence(for: service)?.isPresent ?? false
    }

    /// Check if QSO needs upload to a service
    public func needsUpload(to service: ServiceType) -> Bool {
        servicePresence.contains { !$0.isDeleted && $0.serviceType == service && $0.needsUpload }
    }

    /// Mark QSO as present in a service
    public func markPresent(in service: ServiceType, context: ModelContext) {
        if let existing = presence(for: service) {
            existing.isPresent = true
            existing.needsUpload = false
            existing.isSubmitted = false
            existing.lastConfirmedAt = Date()
        } else {
            let newPresence = ServicePresence.downloaded(from: service, qso: self)
            context.insert(newPresence)
            servicePresence.append(newPresence)
        }
    }

    /// Mark QSO as needing upload to a service
    public func markNeedsUpload(to service: ServiceType, context: ModelContext) {
        guard service.supportsUpload else {
            return
        }

        if let existing = presence(for: service) {
            if !existing.isPresent {
                existing.needsUpload = true
            }
        } else {
            let newPresence = ServicePresence.needsUpload(to: service, qso: self)
            context.insert(newPresence)
            servicePresence.append(newPresence)
        }
    }

    /// Check if upload to a service was rejected
    public func isUploadRejected(for service: ServiceType) -> Bool {
        presence(for: service)?.uploadRejected ?? false
    }

    /// Mark QSO upload as rejected for a service
    public func markUploadRejected(for service: ServiceType, context: ModelContext) {
        if let existing = presence(for: service) {
            existing.uploadRejected = true
            existing.needsUpload = false
        } else {
            let newPresence = ServicePresence(
                serviceType: service,
                isPresent: false,
                needsUpload: false,
                uploadRejected: true,
                qso: self
            )
            context.insert(newPresence)
            servicePresence.append(newPresence)
        }
    }

    /// Check if QSO is present in POTA
    public func isPresentInPOTA() -> Bool {
        if importSource == .pota {
            return true
        }
        if isPresent(in: .pota) {
            return true
        }
        return false
    }

    /// Get all POTA presence records (may have multiple for two-fers)
    public func potaPresenceRecords() -> [ServicePresence] {
        servicePresence.filter { !$0.isDeleted && $0.serviceType == .pota }
    }

    // MARK: Private

    @Relationship(deleteRule: .cascade, inverse: \ServicePresence.qso)
    private var servicePresenceRelation: [ServicePresence]?
}
