import CarrierWaveCore
import Foundation
import SwiftData

@Model
final class QSO {
    // MARK: Lifecycle

    init(
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
        sotaRef: String? = nil,
        qrzLogId: String? = nil,
        qrzConfirmed: Bool = false,
        lotwConfirmedDate: Date? = nil,
        lotwConfirmed: Bool = false,
        dxcc: Int? = nil,
        theirLicenseClass: String? = nil
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
        self.importSource = importSource
        self.importedAt = importedAt
        self.rawADIF = rawADIF
        self.name = name
        self.qth = qth
        self.state = state
        self.country = country
        self.power = power
        self.myRig = myRig
        self.sotaRef = sotaRef
        self.qrzLogId = qrzLogId
        self.qrzConfirmed = qrzConfirmed
        self.lotwConfirmedDate = lotwConfirmedDate
        self.lotwConfirmed = lotwConfirmed
        self.dxcc = dxcc
        self.theirLicenseClass = theirLicenseClass
    }

    // MARK: Internal

    var id: UUID
    var callsign: String
    var band: String
    var mode: String
    var frequency: Double?
    var timestamp: Date
    var rstSent: String?
    var rstReceived: String?
    var myCallsign: String
    var myGrid: String?
    var theirGrid: String?
    var parkReference: String?
    var theirParkReference: String?
    var notes: String?
    var importSource: ImportSource
    var importedAt: Date
    var rawADIF: String?

    // Contact info (from HAMRS and other sources)
    var name: String?
    var qth: String?
    var state: String?
    var country: String?
    var power: Int?
    var myRig: String?
    var sotaRef: String?

    // QRZ sync tracking
    var qrzLogId: String?
    var qrzConfirmed: Bool = false
    var lotwConfirmedDate: Date?
    var lotwConfirmed: Bool = false

    /// DXCC entity (from LoTW)
    var dxcc: Int?

    /// Their license class (e.g., "Extra", "General") - from QRZ lookup at time of logging
    var theirLicenseClass: String?

    /// Soft delete flag - QSOs are never truly deleted, only hidden
    var isHidden: Bool = false

    /// Logging session this QSO belongs to (optional - older QSOs won't have this)
    var loggingSessionId: UUID?

    @Relationship(deleteRule: .cascade, inverse: \ServicePresence.qso)
    var servicePresence: [ServicePresence] = []

    /// Deduplication key: callsign + band + mode + timestamp (rounded to 2 min)
    nonisolated var deduplicationKey: String {
        let roundedTimestamp = timestamp.timeIntervalSince1970
        let rounded = Int(roundedTimestamp / 120) * 120 // 2 minute buckets
        return "\(callsign.uppercased())|\(band.uppercased())|\(mode.uppercased())|\(rounded)"
    }

    /// Extract callsign prefix (for display/grouping)
    var callsignPrefix: String {
        let upper = callsign.uppercased()
        // Simple prefix extraction - takes letters/numbers before any /
        let base = upper.components(separatedBy: "/").first ?? upper
        // Extract prefix (first 1-3 chars that form entity)
        var prefix = ""
        for char in base {
            if char.isLetter || char.isNumber {
                prefix.append(char)
                // Most prefixes are 1-3 characters
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

    /// DXCC entity for this QSO (from LoTW when available)
    var dxccEntity: DXCCEntity? {
        if let dxcc {
            return DescriptionLookup.dxccEntity(forNumber: dxcc)
        }
        return nil
    }

    /// Check if this is likely a US station (for state counting)
    var isUSStation: Bool {
        dxccEntity?.number == 291 // United States DXCC number
    }

    /// Convenience property - QSO is visible (not hidden)
    var isVisible: Bool {
        !isHidden
    }

    /// Whether this QSO has the required fields for upload to external services.
    /// QSOs missing band (or with "Unknown" band) and no frequency cannot be uploaded.
    var hasRequiredFieldsForUpload: Bool {
        // Must have a valid band, or a frequency we can derive band from
        let hasValidBand = !band.isEmpty && band.uppercased() != "UNKNOWN"
        let hasFrequency = frequency != nil

        // At minimum we need either a valid band or a frequency
        return hasValidBand || hasFrequency
    }

    /// Count of populated optional fields (for deduplication tiebreaker)
    var fieldRichnessScore: Int {
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
        if theirLicenseClass != nil {
            score += 1
        }
        return score
    }

    /// Count of services where this QSO is confirmed present
    var syncedServicesCount: Int {
        servicePresence.filter(\.isPresent).count
    }

    /// Date only in local timezone (for activity tracking)
    var dateOnly: Date {
        Calendar.current.startOfDay(for: timestamp)
    }

    /// Date only in UTC (for POTA activation grouping - activations are defined by UTC date)
    var utcDateOnly: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.startOfDay(for: timestamp)
    }

    // MARK: - Service Presence Helpers

    /// Get presence record for a specific service
    func presence(for service: ServiceType) -> ServicePresence? {
        servicePresence.first { $0.serviceType == service }
    }

    /// Check if QSO is present in a service
    func isPresent(in service: ServiceType) -> Bool {
        presence(for: service)?.isPresent ?? false
    }

    /// Check if QSO needs upload to a service
    func needsUpload(to service: ServiceType) -> Bool {
        presence(for: service)?.needsUpload ?? false
    }

    /// Mark QSO as present in a service
    func markPresent(in service: ServiceType, context: ModelContext) {
        if let existing = presence(for: service) {
            existing.isPresent = true
            existing.needsUpload = false
            existing.lastConfirmedAt = Date()
        } else {
            let newPresence = ServicePresence.downloaded(from: service, qso: self)
            context.insert(newPresence)
            servicePresence.append(newPresence)
        }
    }

    /// Mark QSO as needing upload to a service (if it supports upload)
    func markNeedsUpload(to service: ServiceType, context: ModelContext) {
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

    /// Check if upload to a service was rejected by the user
    func isUploadRejected(for service: ServiceType) -> Bool {
        presence(for: service)?.uploadRejected ?? false
    }

    /// Mark QSO upload as rejected for a service
    func markUploadRejected(for service: ServiceType, context: ModelContext) {
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

    /// Check if QSO is present in POTA (uploaded or downloaded from POTA)
    func isPresentInPOTA() -> Bool {
        // Downloaded from POTA
        if importSource == .pota {
            return true
        }
        // Has ServicePresence indicating present
        if isPresent(in: .pota) {
            return true
        }
        return false
    }

    // MARK: - Per-Park POTA Presence (Two-fer Support)

    /// Get all POTA presence records for this QSO (may have multiple for two-fers)
    func potaPresenceRecords() -> [ServicePresence] {
        servicePresence.filter { $0.serviceType == .pota }
    }
}
