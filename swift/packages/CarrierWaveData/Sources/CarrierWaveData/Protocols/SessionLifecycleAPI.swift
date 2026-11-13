import Foundation
import SwiftData

/// Cross-platform session lifecycle vocabulary.
///
/// iOS (`Carrier Wave: Field`) and macOS (`CW Sweep`) each provide a concrete
/// implementation. This protocol formalizes the verbs both platforms share so
/// shared code (and shared tests) can reason about session lifecycle
/// polymorphically.
///
/// `startSession` is intentionally excluded — start parameters diverge enough
/// between the two platforms (POTA/TOTA/WebSDR auto-start on iOS, role-preset
/// wiring on macOS) that a single shared signature would either expose
/// iOS-only knobs to macOS callers or buy nothing by being lowest-common-
/// denominator. Each platform's concrete type exposes its own `startSession`.
@MainActor
public protocol SessionLifecycleAPI: AnyObject {
    /// The currently-foregrounded session, if any.
    var activeSession: LoggingSession? { get }

    /// Pause the active session. Sets `activeSession` to `nil`; the paused
    /// session can be resumed later via `resumeSession(_:)`.
    func pauseSession()

    /// Make a previously paused session active. Pauses the current active
    /// session first if one exists.
    func resumeSession(_ session: LoggingSession)

    /// Permanently close a session. If the session is currently active, also
    /// clears `activeSession`.
    func finishSession(_ session: LoggingSession)
}
