import Foundation
import Testing
@testable import CarrierWaveData

private func tracker(_ kind: TrackerKind, host: String, detail: String = "") -> DiscoveredTracker {
    DiscoveredTracker(endpoint: TrackerEndpoint(kind: kind, host: host), name: kind.displayName, detail: detail)
}

@Test func promptPrefersRealTrackersOverPCRotctld() {
    let discovered = [
        tracker(.hamlibRotctld, host: "192.168.1.10"),
        tracker(.psr100, host: "192.168.1.41"),
        tracker(.csnSAT, host: "192.168.1.40"),
    ]
    let pick = TrackerAutoDetector.promptCandidate(
        discovered: discovered, connectedHost: nil, savedHost: nil, ignored: [], dismissed: []
    )
    #expect(pick?.kind == .csnSAT)
}

@Test func promptSkipsConnectedSavedIgnoredAndDismissed() {
    let discovered = [
        tracker(.csnSAT, host: "10.0.0.1"),
        tracker(.csnSAT, host: "10.0.0.2"),
        tracker(.psr100, host: "10.0.0.3"),
        tracker(.psr100, host: "10.0.0.4"),
        tracker(.psr100, host: "10.0.0.5"),
    ]
    let pick = TrackerAutoDetector.promptCandidate(
        discovered: discovered,
        connectedHost: "10.0.0.1",
        savedHost: "10.0.0.2",
        ignored: ["10.0.0.3"],
        dismissed: ["10.0.0.4"]
    )
    #expect(pick?.host == "10.0.0.5")
    let none = TrackerAutoDetector.promptCandidate(
        discovered: discovered,
        connectedHost: "10.0.0.1",
        savedHost: "10.0.0.2",
        ignored: ["10.0.0.3", "10.0.0.5"],
        dismissed: ["10.0.0.4"]
    )
    #expect(none == nil)
}

@Test func autoConnectOnlyWhenSavedUnitIsSeenAndNotLinked() {
    let saved = TrackerEndpoint(kind: .csnSAT, host: "192.168.1.40")
    let seen = [tracker(.csnSAT, host: "192.168.1.40")]
    #expect(
        TrackerAutoDetector.autoConnectTarget(discovered: seen, saved: saved, rotatorConnected: false) == saved
    )
    #expect(TrackerAutoDetector.autoConnectTarget(discovered: seen, saved: saved, rotatorConnected: true) == nil)
    #expect(TrackerAutoDetector.autoConnectTarget(discovered: [], saved: saved, rotatorConnected: false) == nil)
    #expect(TrackerAutoDetector.autoConnectTarget(discovered: seen, saved: nil, rotatorConnected: false) == nil)
}

@Test func autoConnectAdoptsWhatDiscoveryActuallySawForAPSR100() {
    let saved = TrackerEndpoint(kind: .psr100, host: "192.168.1.41", protocolKind: .easycommII)
    let viaWeb = DiscoveredTracker(
        endpoint: TrackerEndpoint(kind: .psr100, host: "192.168.1.41"),
        name: "PSR-100 Mk2", detail: "192.168.1.41 · web UI :8080 · HTTP control"
    )
    // A stale UDP choice is upgraded to HTTP control, which crosses VLANs.
    #expect(
        TrackerAutoDetector.autoConnectTarget(discovered: [viaWeb], saved: saved, rotatorConnected: false)?
            .protocolKind == .psr100HTTP
    )
    let viaUDP = DiscoveredTracker(
        endpoint: TrackerEndpoint(kind: .psr100, host: "192.168.1.41", protocolKind: .gs232B),
        name: "PSR-100", detail: "192.168.1.41 · GS-232B (UDP) · UDP 2390"
    )
    #expect(
        TrackerAutoDetector.autoConnectTarget(discovered: [viaUDP], saved: saved, rotatorConnected: false)?
            .protocolKind == .gs232B
    )
}

@Test func detectedPromptCopyNamesVendorAndHost() {
    let sat = tracker(.csnSAT, host: "192.168.1.40")
    #expect(sat.detectedTitle == "CSN S.A.T. detected")
    #expect(sat.detectedMessage.contains("CSN Technologies"))
    #expect(sat.detectedMessage.contains("192.168.1.40"))
    #expect(sat.detectedMessage.contains("4533"))
    let psr = tracker(.psr100, host: "192.168.1.41")
    #expect(psr.detectedTitle == "WA4MCM PSR-100 detected")
    #expect(psr.detectedMessage.contains("web interface on port 8080"))
}
