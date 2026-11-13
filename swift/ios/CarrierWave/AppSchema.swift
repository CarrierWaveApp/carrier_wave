import CarrierWaveData
import SwiftData

/// Single source of truth for the iOS app's SwiftData model list: the shared
/// package models (`CarrierWaveSchema.models`) plus the iOS-only models.
///
/// Used by both the app `ModelContainer` and the test container so the list
/// can't drift or list an entity twice. A duplicate registration makes SwiftData
/// build two dynamic subclasses for the same `@Model`; a later `context.fetch`
/// materializes one and fails to cast it to the other, crashing with
/// "Failed to cast model X to X" (`ModelContext.swift`). `AppSchemaTests`
/// guards against reintroducing a duplicate.
nonisolated enum AppSchema {
    /// iOS-only models, not part of the shared `CarrierWaveSchema`.
    static let appOnlyModels: [any PersistentModel.Type] = [
        POTAUploadAttempt.self,
        ActivityItem.self,
        CallsignNotesSource.self,
        SolarSnapshot.self,
        CustomNeed.self,
        PropagationCheck.self,
    ]

    /// Full model list for the iOS container.
    static let models: [any PersistentModel.Type] = CarrierWaveSchema.models + appOnlyModels
}
