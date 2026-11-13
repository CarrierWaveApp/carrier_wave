import CarrierWaveData

// iOS conformance to the cross-platform session lifecycle vocabulary.
//
// The iOS manager already implements `activeSession`, `pauseSession()`,
// `resumeSession(_:)`, and `finishSession(_:)` with the right signatures —
// this extension just declares conformance so shared code in CarrierWaveData
// (and future cross-platform tests) can speak to either implementation
// polymorphically.
//
// `startSession` is platform-specific and lives outside the protocol; see
// `SessionLifecycleAPI`'s doc comment for the reasoning.
extension LoggingSessionManager: SessionLifecycleAPI {}
