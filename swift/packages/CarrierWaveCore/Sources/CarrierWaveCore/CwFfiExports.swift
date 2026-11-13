// Re-export the UniFFI surface so downstream packages (notably CarrierWaveData,
// which depends on CarrierWaveCore but not on CarrierWaveCwFfi directly) can use
// `FieldStore`, the `Ffi*` DTOs, and `StoreObserver` via `import CarrierWaveCore`.
// CarrierWaveCore is the Swift-facing facade over the Rust core; this keeps the
// generated binding module an implementation detail callers don't import by name.
@_exported import CarrierWaveCwFfi
