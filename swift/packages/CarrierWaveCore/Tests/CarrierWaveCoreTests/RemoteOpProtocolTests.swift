import Foundation
import Testing
@testable import CarrierWaveCore

struct RemoteOpProtocolTests {
    // MARK: Internal

    @Test("Frame round-trips for hello")
    func helloRoundTrip() throws {
        let original = RemoteOpFrame.hello(.init(
            clientName: "Field on iPhone",
            clientPlatform: "iOS",
            token: nil
        ))
        let encoded = try RemoteOpFraming.encodeText(original)
        let decoded = try RemoteOpFraming.decode(text: encoded)
        #expect(decoded == original)
    }

    @Test("Frame round-trips for radio.state")
    func radioStateRoundTrip() throws {
        let original = RemoteOpFrame.eventRadioState(.init(
            radioID: "radio-1",
            radioName: "IC-705",
            freqHz: 14_074_000,
            mode: "USB",
            vfo: "A",
            split: nil,
            isTransmitting: false,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000.123)
        ))
        let encoded = try RemoteOpFraming.encodeText(original)
        let decoded = try RemoteOpFraming.decode(text: encoded)
        #expect(decoded == original)
    }

    @Test("Frame round-trips for spot event")
    func spotRoundTrip() throws {
        let spot = RemoteSpot(
            id: "rbn:W1AW:14074",
            callsign: "W1AW",
            freqHz: 14_074_000,
            mode: "FT8",
            band: "20m",
            source: "rbn",
            spotter: "K1JT",
            comment: "FT8",
            snr: -7,
            dxccEntity: "United States",
            dxccPrefix: "K",
            region: "NA",
            needed: true,
            workedBefore: false,
            spottedAt: Date(timeIntervalSince1970: 1_700_000_000.456)
        )
        let original = RemoteOpFrame.eventSpot(.init(spot: spot))
        let encoded = try RemoteOpFraming.encodeText(original)
        let decoded = try RemoteOpFraming.decode(text: encoded)
        #expect(decoded == original)
    }

    @Test("Tune command round-trips with deterministic request id")
    func tuneCommandRoundTrip() throws {
        let id = UUID()
        let original = RemoteOpFrame.commandTune(.init(
            requestID: id,
            radioID: "radio-1",
            freqHz: 14_200_000,
            mode: "USB"
        ))
        let encoded = try RemoteOpFraming.encodeText(original)
        let decoded = try RemoteOpFraming.decode(text: encoded)
        #expect(decoded == original)
        if case let .commandTune(cmd) = decoded {
            #expect(cmd.requestID == id)
        } else {
            Issue.record("Expected commandTune, got \(decoded)")
        }
    }

    @Test("CW send/stop/speed/slot commands round-trip")
    func cwCommandsRoundTrip() throws {
        let sendID = UUID()
        let send = RemoteOpFrame.commandSendCW(.init(
            requestID: sendID,
            text: "CQ CQ DE K1JT",
            radioID: "radio-1"
        ))
        try roundTrip(send)

        let stopID = UUID()
        let stop = RemoteOpFrame.commandStopCW(.init(requestID: stopID, radioID: "radio-1"))
        try roundTrip(stop)

        let speedID = UUID()
        let speed = RemoteOpFrame.commandSetCWSpeed(.init(requestID: speedID, wpm: 28))
        try roundTrip(speed)

        let slotID = UUID()
        let slot = RemoteOpFrame.commandPlayCWSlot(.init(
            requestID: slotID,
            slot: 3,
            context: ["call": "K1JT", "rst": "599"]
        ))
        try roundTrip(slot)
    }

    @Test("CW status event round-trips")
    func cwStatusEventRoundTrip() throws {
        let original = RemoteOpFrame.eventCWStatus(.init(
            radioID: "radio-1",
            keyerAvailable: true,
            wpm: 24,
            bufferDepth: 5,
            sendingSlot: 2,
            isSending: true,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000.789)
        ))
        try roundTrip(original)
    }

    @Test("cw.keyer is in the topic set so the server can route it")
    func cwKeyerTopicListed() {
        #expect(RemoteOpTopic.allCases.contains(.cwKeyer))
    }

    @Test("cw.slots is in the topic set")
    func cwSlotsTopicListed() {
        #expect(RemoteOpTopic.allCases.contains(.cwSlots))
    }

    @Test("RemoteCWMacros detects required tokens and rejects missing context")
    func cwMacroRequirements() {
        let template = "BR RR TU {NAME} ES 73 EE DE {MYCALL}"
        let required = RemoteCWMacros.requiredMacros(in: template)
        #expect(required == ["NAME", "MYCALL"])

        // Empty context → both missing
        let allMissing = RemoteCWMacros.missingMacros(in: template, context: [:])
        #expect(allMissing == ["MYCALL", "NAME"])

        // Whitespace-only counts as missing
        let blank = RemoteCWMacros.missingMacros(
            in: template,
            context: ["NAME": "  ", "MYCALL": "K6JY"]
        )
        #expect(blank == ["NAME"])

        // Fully satisfied
        let satisfied = RemoteCWMacros.missingMacros(
            in: template,
            context: ["NAME": "JOE", "MYCALL": "K6JY"]
        )
        #expect(satisfied.isEmpty)

        // Unknown braces are ignored
        let unknown = RemoteCWMacros.requiredMacros(in: "73 {FOO} {NAME}")
        #expect(unknown == ["NAME"])
    }

    @Test("RemoteCWMacros expands every known token, leaves unknowns alone")
    func cwMacroExpansion() {
        let template = "TU {NAME} {NR} {RST} ES 73 DE {MYCALL} {FOO}"
        let context: [String: String] = [
            "NAME": "JOE",
            "NR": "042",
            "RST": "599",
            "MYCALL": "K6JY",
        ]
        let out = RemoteCWMacros.expand(template, context: context)
        #expect(out == "TU JOE 042 599 ES 73 DE K6JY {FOO}")
    }

    @Test("setCWSlot command and slots event round-trip")
    func cwSlotProgrammingRoundTrip() throws {
        let setID = UUID()
        let setCmd = RemoteOpFrame.commandSetCWSlot(.init(
            requestID: setID,
            slot: 3,
            label: "73",
            text: "73 ES TU DE {MYCALL}"
        ))
        try roundTrip(setCmd)

        let slots = (UInt8(1) ... UInt8(8)).map { id in
            RemoteCWSlot(
                id: id,
                label: id == 3 ? "73" : "",
                text: id == 3 ? "73 ES TU DE {MYCALL}" : ""
            )
        }
        let event = RemoteOpFrame.eventCWSlots(.init(slots: slots))
        try roundTrip(event)
        if case let .eventCWSlots(payload) = event {
            #expect(payload.slots.count == 8)
            #expect(payload.slots[2].isEmpty == false)
            #expect(payload.slots[0].isEmpty)
        } else {
            Issue.record("Expected eventCWSlots, got \(event)")
        }
    }

    // MARK: Private

    private func roundTrip(_ frame: RemoteOpFrame) throws {
        let encoded = try RemoteOpFraming.encodeText(frame)
        let decoded = try RemoteOpFraming.decode(text: encoded)
        #expect(decoded == frame)
    }
}
