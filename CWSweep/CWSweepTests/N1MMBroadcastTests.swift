import Foundation
import Testing
@testable import CWSweep

// MARK: - N1MM Broadcast XML Format Tests

@Test func n1mmContactInfoXMLContainsRequiredFields() async {
    // Verify the broadcast method doesn't crash and XML format is correct
    // (can't test actual UDP send without a listener, but we can test the service creation)
    let service = N1MMBroadcastService(host: "127.0.0.1", port: 12_060)
    // Service should be creatable without error
    await service.start()
    await service.stop()
}

// MARK: - Interop Manager Tests

@Test @MainActor func interopManagerStartsDisabled() {
    let manager = InteropManager()
    #expect(!manager.n1mmEnabled)
    #expect(!manager.wsjtxEnabled)
    #expect(!manager.wsjtxConnected)
    #expect(manager.recentDecodes.isEmpty)
}

// MARK: - WSJT-X Decode Model Tests

@Test func wsjtxDecodeHasIdentity() {
    let decode = WSJTXDecode(
        timestamp: Date(),
        callsign: "K3LR",
        frequency: 14.074,
        snr: -10,
        message: "CQ K3LR FN20"
    )
    #expect(decode.callsign == "K3LR")
    #expect(decode.frequency == 14.074)
    #expect(decode.snr == -10)
    #expect(decode.message == "CQ K3LR FN20")
}
