import CarrierWaveCore
import Foundation
import SwiftData

// `function_body_length` is disabled here for the same reason as
// `SwiftDataStoreImporter+Projections`: these are wide, inherent field maps (QSO
// carries ~50 columns); splitting one initializer call would obscure, not clarify.
// swiftlint:disable function_body_length

// MARK: - FfiReflector

/// Reverse of `SwiftDataStoreImporter.project(_:)` — hydrates a SwiftData `@Model`
/// from an `Ffi<Entity>` record.
///
/// This is the **pre-Phase-5 bridge** for delegating writes to the shared Rust
/// `SessionApi` / `ActivityLogApi`. Those APIs write cw-store (canonical under
/// `CwStoreQSOMode.on`) and return the persisted `Ffi<Entity>`. While SwiftData is
/// still the CloudKit sync replica, the host must reflect that record back into
/// SwiftData — mirror-suppressed, so CloudKit still syncs it and `@Observable`
/// UI updates — instead of hand-mutating the model. **Delete this layer once
/// Phase 5 server-sync retires the SwiftData CloudKit replica.**
///
/// Hydrators are pure (`Ffi -> @Model`); persisting the model (the
/// mirror-suppressed upsert into a `ModelContext`) is the caller's job — the
/// existing write seam already owns suppression. Round-trip parity
/// (`project(hydrate(ffi)) == ffi`) is the acceptance bar, mirroring the read-source
/// snapshot tests.
///
/// This file holds the hunter-side entities (`ActivityLog`, `QSO`,
/// `ServicePresence`); the session-side entities (`LoggingSession`,
/// `SessionSpot`, `ActivationMetadata`) live in `FfiReflector+Sessions.swift`.
public enum FfiReflector {
    // MARK: Public

    /// `ActivityLog` (hunter log). Inverse of `project(_ log: ActivityLog)`.
    /// `cloudDirtyFlag` is outside the model initializer, so it is set after.
    nonisolated public static func hydrate(_ ffi: FfiActivityLog) -> ActivityLog {
        let log = ActivityLog(
            id: UUID(uuidString: ffi.id) ?? UUID(),
            name: ffi.name,
            myCallsign: ffi.myCallsign,
            createdAt: Date(timeIntervalSince1970: TimeInterval(ffi.createdAt)),
            stationProfileId: ffi.stationProfileId.flatMap { UUID(uuidString: $0) },
            currentGrid: ffi.currentGrid,
            locationLabel: ffi.locationLabel,
            isActive: ffi.isActive
        )
        log.cloudDirtyFlag = ffi.cloudDirtyFlag
        return log
    }

    /// Reflect an `ActivityLog` record into the SwiftData replica: update the
    /// existing row in place (preserving `@Observable` identity) or insert a
    /// hydrated one, then save **mirror-suppressed** so the write reaches CloudKit
    /// + the UI but is not re-projected into cw-store (the Rust `ActivityLogApi`
    /// already wrote it). The caller re-points its held reference to the returned
    /// model. Pass `mirror = nil` for the `.off`/test path (a plain save).
    @MainActor
    public static func reflect(
        _ ffi: FfiActivityLog,
        into context: ModelContext,
        mirror: CwStoreMirror?
    ) throws -> ActivityLog {
        let model: ActivityLog
        if let id = UUID(uuidString: ffi.id), let existing = fetchActivityLog(id: id, in: context) {
            applyFields(ffi, to: existing)
            model = existing
        } else {
            model = hydrate(ffi)
            context.insert(model)
        }
        mirror?.beginSeamWrite(for: context)
        defer { mirror?.endSeamWrite(for: context) }
        try context.save()
        return model
    }

    /// `QSO`. Inverse of `project(_ qso: QSO)`.
    ///
    /// - `freqKhz` (store) → `frequency` MHz (`@Model`): divide by 1000.
    /// - `band`/`mode`/`myCallsign` narrow `String?` → the `@Model`'s non-optional
    ///   `String` (the projection widened them; the model stores "" not nil).
    /// - `importSourceRawValue` → the `ImportSource` init parameter (defaults to
    ///   `.logger`, the model's own default, if the raw value is unrecognised).
    /// - Fields outside the initializer (`modifiedAt`, `spotCommentsData`,
    ///   `originalCallsign`, `isHidden`, `isActivityLogQSO`, `stationCallsign`,
    ///   `loggingSessionId`, `cloudDirtyFlag`) are set after.
    nonisolated public static func hydrate(_ ffi: FfiQso) -> QSO {
        let qso = QSO(
            id: UUID(uuidString: ffi.id) ?? UUID(),
            callsign: ffi.callsign,
            band: ffi.band ?? "",
            mode: ffi.mode ?? "",
            frequency: ffi.freqKhz.map { $0 / 1_000 },
            timestamp: Date(timeIntervalSince1970: TimeInterval(ffi.qsoDate)),
            rstSent: ffi.rstSent,
            rstReceived: ffi.rstRcvd,
            myCallsign: ffi.myCallsign ?? "",
            myGrid: ffi.myGrid,
            theirGrid: ffi.theirGrid,
            parkReference: ffi.park,
            theirParkReference: ffi.theirPark,
            notes: ffi.notes,
            notesUserAuthored: ffi.notesUserAuthored,
            importSource: ImportSource(rawValue: ffi.importSourceRawValue) ?? .logger,
            importedAt: Date(timeIntervalSince1970: TimeInterval(ffi.importedAt)),
            rawADIF: ffi.rawAdif,
            name: ffi.name,
            qth: ffi.qth,
            state: ffi.state,
            country: ffi.country,
            power: ffi.power.map(Int.init),
            myRig: ffi.myRig,
            stationProfileName: ffi.stationProfileName,
            sotaRef: ffi.sotaRef,
            wwffRef: ffi.wwffRef,
            aoaCode: ffi.aoaCode,
            qrzLogId: ffi.qrzLogId,
            qrzConfirmed: ffi.qrzConfirmed,
            lotwConfirmedDate: ffi.lotwConfirmedDate.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            lotwConfirmed: ffi.lotwConfirmed,
            dxcc: ffi.dxcc.map(Int.init),
            theirLicenseClass: ffi.theirLicenseClass,
            contestName: ffi.contestName,
            contestSerialSent: ffi.contestSerialSent.map(Int.init),
            contestSerialReceived: ffi.contestSerialReceived.map(Int.init),
            contestExchangeSent: ffi.contestExchangeSent,
            contestExchangeReceived: ffi.contestExchangeReceived,
            callsignChangeNote: ffi.callsignChangeNote,
            satName: ffi.satName,
            propMode: ffi.propMode
        )
        qso.originalCallsign = ffi.originalCallsign
        qso.importSourceRawValue = ffi.importSourceRawValue
        qso.modifiedAt = ffi.modifiedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        qso.spotCommentsData = ffi.spotCommentsData
        qso.isHidden = ffi.isHidden
        qso.isActivityLogQSO = ffi.isActivityLogQso
        qso.stationCallsign = ffi.stationCallsign
        qso.loggingSessionId = ffi.loggingSessionId.flatMap { UUID(uuidString: $0) }
        qso.cloudDirtyFlag = ffi.dirty
        return qso
    }

    /// Reflect a `QSO` record into the SwiftData replica. Uses **in-place update**
    /// (never delete+insert) so the QSO's `ServicePresence` relationship survives.
    /// Saved mirror-suppressed. Returns the persisted model.
    @MainActor
    public static func reflect(
        _ ffi: FfiQso,
        into context: ModelContext,
        mirror: CwStoreMirror?
    ) throws -> QSO {
        let model: QSO
        if let id = UUID(uuidString: ffi.id), let existing = fetchQso(id: id, in: context) {
            applyFields(ffi, to: existing)
            model = existing
        } else {
            model = hydrate(ffi)
            context.insert(model)
        }
        mirror?.beginSeamWrite(for: context)
        defer { mirror?.endSeamWrite(for: context) }
        try context.save()
        return model
    }

    /// Reflect a `ServicePresence` record into the SwiftData replica, linking its
    /// `qso` relationship to `linkedTo` (the Ffi record carries only a `qsoId`).
    /// Saved mirror-suppressed.
    @MainActor
    public static func reflect(
        _ ffi: FfiServicePresence,
        into context: ModelContext,
        mirror: CwStoreMirror?,
        linkedTo qso: QSO?
    ) throws -> ServicePresence {
        let model: ServicePresence
        if let id = UUID(uuidString: ffi.id), let existing = fetchServicePresence(id: id, in: context) {
            applyFields(ffi, to: existing)
            model = existing
        } else {
            model = hydrate(ffi)
            context.insert(model)
        }
        model.qso = qso
        mirror?.beginSeamWrite(for: context)
        defer { mirror?.endSeamWrite(for: context) }
        try context.save()
        return model
    }

    /// `ServicePresence`. Inverse of `project(_ presence: ServicePresence)`. The
    /// `qso` relationship is **not** set here (the Ffi record carries only a
    /// `qsoId`); the context-upsert reflector links it by fetching the QSO.
    nonisolated public static func hydrate(_ ffi: FfiServicePresence) -> ServicePresence {
        let presence = ServicePresence(
            id: UUID(uuidString: ffi.id) ?? UUID(),
            serviceType: ServiceType(rawValue: ffi.serviceTypeRawValue) ?? .qrz,
            isPresent: ffi.isPresent,
            needsUpload: ffi.needsUpload,
            uploadRejected: ffi.uploadRejected,
            isSubmitted: ffi.isSubmitted,
            lastConfirmedAt: ffi.lastConfirmedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            qso: nil,
            parkReference: ffi.parkReference
        )
        presence.serviceTypeRawValue = ffi.serviceTypeRawValue
        presence.rejectedAtBuild = ffi.rejectedAtBuild
        presence.cloudDirtyFlag = ffi.cloudDirtyFlag
        return presence
    }

    // MARK: Private

    /// The existing `ActivityLog` with this id in `context`, or nil.
    @MainActor
    private static func fetchActivityLog(id: UUID, in context: ModelContext) -> ActivityLog? {
        var descriptor = FetchDescriptor<ActivityLog>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Copy every non-key `FfiActivityLog` field onto an existing model (in-place
    /// update path of `reflect`). `id` is the key and stays put.
    nonisolated private static func applyFields(_ ffi: FfiActivityLog, to log: ActivityLog) {
        log.name = ffi.name
        log.myCallsign = ffi.myCallsign
        log.createdAt = Date(timeIntervalSince1970: TimeInterval(ffi.createdAt))
        log.stationProfileId = ffi.stationProfileId.flatMap { UUID(uuidString: $0) }
        log.currentGrid = ffi.currentGrid
        log.locationLabel = ffi.locationLabel
        log.isActive = ffi.isActive
        log.cloudDirtyFlag = ffi.cloudDirtyFlag
    }

    /// The existing `QSO` with this id in `context`, or nil.
    @MainActor
    private static func fetchQso(id: UUID, in context: ModelContext) -> QSO? {
        var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// The existing `ServicePresence` with this id in `context`, or nil.
    @MainActor
    private static func fetchServicePresence(id: UUID, in context: ModelContext) -> ServicePresence? {
        var descriptor = FetchDescriptor<ServicePresence>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// In-place field copy for `QSO` (the update path; `id`, and the `qso`-side of
    /// relationships, stay put). Mirrors `hydrate(_ ffi: FfiQso)`.
    nonisolated private static func applyFields(_ ffi: FfiQso, to qso: QSO) {
        qso.callsign = ffi.callsign
        qso.band = ffi.band ?? ""
        qso.mode = ffi.mode ?? ""
        qso.frequency = ffi.freqKhz.map { $0 / 1_000 }
        qso.timestamp = Date(timeIntervalSince1970: TimeInterval(ffi.qsoDate))
        qso.rstSent = ffi.rstSent
        qso.rstReceived = ffi.rstRcvd
        qso.myCallsign = ffi.myCallsign ?? ""
        qso.myGrid = ffi.myGrid
        qso.theirGrid = ffi.theirGrid
        qso.parkReference = ffi.park
        qso.theirParkReference = ffi.theirPark
        qso.notes = ffi.notes
        qso.notesUserAuthored = ffi.notesUserAuthored
        qso.importSourceRawValue = ffi.importSourceRawValue
        qso.importedAt = Date(timeIntervalSince1970: TimeInterval(ffi.importedAt))
        qso.rawADIF = ffi.rawAdif
        qso.name = ffi.name
        qso.qth = ffi.qth
        qso.state = ffi.state
        qso.country = ffi.country
        qso.power = ffi.power.map(Int.init)
        qso.myRig = ffi.myRig
        qso.stationProfileName = ffi.stationProfileName
        qso.sotaRef = ffi.sotaRef
        qso.wwffRef = ffi.wwffRef
        qso.aoaCode = ffi.aoaCode
        qso.qrzLogId = ffi.qrzLogId
        qso.qrzConfirmed = ffi.qrzConfirmed
        qso.lotwConfirmedDate = ffi.lotwConfirmedDate.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        qso.lotwConfirmed = ffi.lotwConfirmed
        qso.dxcc = ffi.dxcc.map(Int.init)
        qso.theirLicenseClass = ffi.theirLicenseClass
        qso.contestName = ffi.contestName
        qso.contestSerialSent = ffi.contestSerialSent.map(Int.init)
        qso.contestSerialReceived = ffi.contestSerialReceived.map(Int.init)
        qso.contestExchangeSent = ffi.contestExchangeSent
        qso.contestExchangeReceived = ffi.contestExchangeReceived
        qso.callsignChangeNote = ffi.callsignChangeNote
        qso.originalCallsign = ffi.originalCallsign
        qso.modifiedAt = ffi.modifiedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        qso.spotCommentsData = ffi.spotCommentsData
        qso.isHidden = ffi.isHidden
        qso.isActivityLogQSO = ffi.isActivityLogQso
        qso.stationCallsign = ffi.stationCallsign
        qso.loggingSessionId = ffi.loggingSessionId.flatMap { UUID(uuidString: $0) }
        qso.cloudDirtyFlag = ffi.dirty
        qso.satName = ffi.satName
        qso.propMode = ffi.propMode
    }

    /// In-place field copy for `ServicePresence` (the `qso` relationship is set by
    /// the caller). Mirrors `hydrate(_ ffi: FfiServicePresence)`.
    nonisolated private static func applyFields(_ ffi: FfiServicePresence, to presence: ServicePresence) {
        presence.serviceTypeRawValue = ffi.serviceTypeRawValue
        presence.isPresent = ffi.isPresent
        presence.needsUpload = ffi.needsUpload
        presence.uploadRejected = ffi.uploadRejected
        presence.rejectedAtBuild = ffi.rejectedAtBuild
        presence.isSubmitted = ffi.isSubmitted
        presence.lastConfirmedAt = ffi.lastConfirmedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        presence.parkReference = ffi.parkReference
        presence.cloudDirtyFlag = ffi.cloudDirtyFlag
    }
}
