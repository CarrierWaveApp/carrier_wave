import Foundation

// MARK: - LoggedQSO

/// A `Sendable` value-type snapshot returned by the logging entry points
/// (`LoggingSessionManager.logQSO`, `ActivityLogManager.logQSO`/`logFT8QSO`) in
/// place of a live SwiftData `@Model QSO`. Callers get the fields they read off a
/// freshly-logged contact without holding a live model; when a caller genuinely
/// needs the live `QSO` again (edit / metadata enrich / hide), it re-fetches via
/// `LogbookIDBridge.fetchQSO(id:in:)` using `id`.
///
/// `id` uses the same lowercase-UUID convention as the Rust store
/// (`SwiftDataStoreImporter.uuid`) so it round-trips through the id-bridge
/// identically across backends, matching `QSORowSnapshot`.
///
/// This is deliberately distinct from `QSORowSnapshot`: that type is for Logbook
/// row rendering (presence badges, confirmation flags) which are empty/false for a
/// just-logged QSO. `LoggedQSO` carries the caller-return field set instead.
public struct LoggedQSO: Sendable, Identifiable, Equatable {
    // MARK: Lifecycle

    public init(
        id: String,
        callsign: String,
        timestamp: Date,
        band: String,
        mode: String,
        frequency: Double? = nil,
        myCallsign: String,
        myGrid: String? = nil,
        theirGrid: String? = nil,
        rstSent: String? = nil,
        rstReceived: String? = nil,
        parkReference: String? = nil,
        theirParkReference: String? = nil,
        notes: String? = nil,
        importSource: ImportSource,
        loggingSessionId: UUID? = nil,
        isHidden: Bool = false
    ) {
        self.id = id
        self.callsign = callsign
        self.timestamp = timestamp
        self.band = band
        self.mode = mode
        self.frequency = frequency
        self.myCallsign = myCallsign
        self.myGrid = myGrid
        self.theirGrid = theirGrid
        self.rstSent = rstSent
        self.rstReceived = rstReceived
        self.parkReference = parkReference
        self.theirParkReference = theirParkReference
        self.notes = notes
        self.importSource = importSource
        self.loggingSessionId = loggingSessionId
        self.isHidden = isHidden
    }

    /// Snapshot a live `QSO`. Lives in the same module as the `@Model`, so callers
    /// need no `import SwiftData` to obtain a `LoggedQSO`.
    public init(qso: QSO) {
        self.init(
            id: SwiftDataStoreImporter.uuid(qso.id),
            callsign: qso.callsign,
            timestamp: qso.timestamp,
            band: qso.band,
            mode: qso.mode,
            frequency: qso.frequency,
            myCallsign: qso.myCallsign,
            myGrid: qso.myGrid,
            theirGrid: qso.theirGrid,
            rstSent: qso.rstSent,
            rstReceived: qso.rstReceived,
            parkReference: qso.parkReference,
            theirParkReference: qso.theirParkReference,
            notes: qso.notes,
            importSource: qso.importSource,
            loggingSessionId: qso.loggingSessionId,
            isHidden: qso.isHidden
        )
    }

    // MARK: Public

    public let id: String
    public let callsign: String
    public let timestamp: Date
    public let band: String
    public let mode: String
    public let frequency: Double?
    public let myCallsign: String
    public let myGrid: String?
    public let theirGrid: String?
    public let rstSent: String?
    public let rstReceived: String?
    public let parkReference: String?
    public let theirParkReference: String?
    public let notes: String?
    public let importSource: ImportSource
    public let loggingSessionId: UUID?
    public let isHidden: Bool
}
