import CarrierWaveCore

// MARK: - ActivityLogApiRegistry

/// Main-actor handles to the stateless Rust `ActivityLogApi` / `SessionApi`, bound
/// to the shared app-group `FieldStore`. Built once by
/// `CarrierWaveApp.applyQSOMirrorMode` (alongside the write-seam registries) and
/// `nil` in `off` mode. The managers read these to delegate hunter/session logic to
/// the shared core, then reflect the returned records into SwiftData via
/// `FfiReflector`. Value/reference held directly — the APIs are `Sendable` and hold
/// only an `Arc<FieldStore>`, so there is no retain cycle with the manager.
@MainActor
enum ActivityLogApiRegistry {
    static var current: ActivityLogApi?
}

// MARK: - SessionApiRegistry

@MainActor
enum SessionApiRegistry {
    static var current: SessionApi?
}

// MARK: - LoggerCommandApiRegistry

/// Handle to the stateless Rust `LoggerCommandApi` — runs logger commands
/// (FREQ/MODE/NOTE/MYCALL/session-metadata + spot/panel intents) against the
/// shared store. Built alongside `SessionApiRegistry`; `nil` in `off` mode.
@MainActor
enum LoggerCommandApiRegistry {
    static var current: LoggerCommandApi?
}
