import CarrierWaveData
import CoreSpotlight
import UIKit
import UniformTypeIdentifiers

// MARK: - QSOSpotlightSnapshot

/// Sendable snapshot of a QSO for CoreSpotlight indexing.
///
/// Extracted from the SwiftData model on a background actor so the snapshot
/// can be passed to the `@MainActor` indexer without crossing a managed
/// object across actor boundaries.
nonisolated struct QSOSpotlightSnapshot {
    // MARK: Lifecycle

    init(qso: QSO) {
        id = qso.id
        callsign = qso.callsign
        band = qso.band
        mode = qso.mode
        frequencyMHz = qso.frequency
        timestamp = qso.timestamp
        modifiedAt = qso.modifiedAt
        importedAt = qso.importedAt
        rstSent = qso.rstSent
        rstReceived = qso.rstReceived
        myCallsign = qso.myCallsign
        myGrid = qso.myGrid
        theirGrid = qso.theirGrid
        parkReference = qso.parkReference
        sotaRef = qso.sotaRef
        wwffRef = qso.wwffRef
        name = qso.name
        qth = qso.qth
        state = qso.state
        country = qso.country
        dxcc = qso.dxcc
        notes = qso.notes
    }

    // MARK: Internal

    let id: UUID
    let callsign: String
    let band: String
    let mode: String
    let frequencyMHz: Double?
    let timestamp: Date
    let modifiedAt: Date?
    let importedAt: Date
    let rstSent: String?
    let rstReceived: String?
    let myCallsign: String
    let myGrid: String?
    let theirGrid: String?
    let parkReference: String?
    let sotaRef: String?
    let wwffRef: String?
    let name: String?
    let qth: String?
    let state: String?
    let country: String?
    let dxcc: Int?
    let notes: String?

    /// Build the Spotlight attribute set shown in search results.
    func makeAttributeSet() -> CSSearchableItemAttributeSet {
        // `UTType.text` rather than `UTType.content` — `public.content` is
        // an abstract UTI and CoreSpotlight can silently drop items that
        // use abstract base types. `public.text` is concrete and appropriate
        // for a plain-text QSO record.
        let attributes = CSSearchableItemAttributeSet(contentType: UTType.text)
        // iOS 17+ requires both `title` and `displayName` to be set for an
        // item to surface in Spotlight search results — items with only
        // `title` are silently indexed but never displayed (Apple Developer
        // Forum thread 734996, FB12555541). Assign both from the same
        // local String so there's no chance of a mismatch.
        let displayTitle = SpotlightFormatter.qsoTitle(
            callsign: callsign, band: band, mode: mode
        )
        attributes.title = displayTitle
        attributes.displayName = displayTitle
        attributes.contentDescription = SpotlightFormatter.qsoDescription(snapshot: self)
        attributes.keywords = SpotlightFormatter.qsoKeywords(snapshot: self)
        attributes.contentCreationDate = timestamp
        attributes.contentModificationDate = modifiedAt ?? importedAt
        return attributes
    }
}

// MARK: - SessionSpotlightSnapshot

/// Sendable snapshot of a LoggingSession for CoreSpotlight indexing.
nonisolated struct SessionSpotlightSnapshot {
    // MARK: Lifecycle

    init(session: LoggingSession) {
        id = session.id
        myCallsign = session.myCallsign
        startedAt = session.startedAt
        endedAt = session.endedAt
        mode = session.mode
        activationTypeRaw = session.activationType.rawValue
        programDisplayName = session.programsDisplayName
        parkReference = session.parkReference
        sotaReference = session.sotaReference
        wwffReference = session.wwffReference
        missionReference = session.missionReference
        customTitle = session.customTitle
        qsoCount = session.qsoCount
        myRig = session.myRig
        myAntenna = session.myAntenna
        myKey = session.myKey
    }

    // MARK: Internal

    let id: UUID
    let myCallsign: String
    let startedAt: Date
    let endedAt: Date?
    let mode: String
    let activationTypeRaw: String
    let programDisplayName: String
    let parkReference: String?
    let sotaReference: String?
    let wwffReference: String?
    let missionReference: String?
    let customTitle: String?
    let qsoCount: Int
    let myRig: String?
    let myAntenna: String?
    let myKey: String?

    /// Build the Spotlight attribute set shown in search results.
    func makeAttributeSet() -> CSSearchableItemAttributeSet {
        // `UTType.text` rather than `UTType.content` — see QSO snapshot for
        // rationale; abstract UTIs can be silently dropped by CoreSpotlight.
        let attributes = CSSearchableItemAttributeSet(contentType: UTType.text)
        // iOS 17+ requires both `title` and `displayName`; see QSO snapshot
        // for context.
        let displayTitle = SpotlightFormatter.sessionTitle(
            programDisplayName: programDisplayName,
            parkReference: parkReference,
            sotaReference: sotaReference,
            customTitle: customTitle,
            startedAt: startedAt
        )
        attributes.title = displayTitle
        attributes.displayName = displayTitle
        attributes.contentDescription = SpotlightFormatter.sessionDescription(snapshot: self)
        attributes.keywords = SpotlightFormatter.sessionKeywords(snapshot: self)
        attributes.contentCreationDate = startedAt
        attributes.contentModificationDate = endedAt ?? startedAt
        return attributes
    }
}
