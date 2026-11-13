import CarrierWaveData
import Foundation
import Testing
@testable import CWSweep

// MARK: - WaterfallStore

@MainActor
@Test func waterfallStoreAppendsLinesNewestFirst() {
    let store = WaterfallStore()
    store.append(line: [0.1, 0.2, 0.3], centerMHz: 14.1, spanKHz: 100, source: .sculan10)
    store.append(line: [0.4, 0.5, 0.6], centerMHz: 14.1, spanKHz: 100, source: .sculan10)

    #expect(store.magnitudes.count == 2)
    #expect(store.magnitudes.first == [0.4, 0.5, 0.6])
    #expect(store.activeBinCount == 3)
    #expect(store.source == .sculan10)
    #expect(store.lineSequence == 2)
}

@MainActor
@Test func waterfallStoreCapsAtMaxLines() {
    let store = WaterfallStore()
    store.maxLines = 3
    for idx in 0 ..< 6 {
        store.append(line: [Float(idx)], centerMHz: 14, spanKHz: 100, source: .flex)
    }
    #expect(store.magnitudes.count == 3)
    // Newest three: 5, 4, 3
    #expect(store.magnitudes.map(\.first) == [5, 4, 3])
}

@MainActor
@Test func waterfallStoreClearResetsState() {
    let store = WaterfallStore()
    store.append(line: [0.5], centerMHz: 14, spanKHz: 100, source: .sculan10)
    store.setReceiving(true, source: .sculan10)
    store.clear()

    #expect(store.magnitudes.isEmpty)
    #expect(store.activeBinCount == 0)
    #expect(store.source == .none)
    #expect(store.isReceiving == false)
}

@MainActor
@Test func waterfallStoreSetReceivingOnlyClearsOwnSource() {
    let store = WaterfallStore()
    store.setReceiving(true, source: .sculan10)
    // Flex producer asks to stop — should not clobber the SCU-LAN10 source.
    store.setReceiving(false, source: .flex)
    #expect(store.source == .sculan10)

    // SCU-LAN10 producer stops — clears.
    store.setReceiving(false, source: .sculan10)
    #expect(store.source == .none)
}

// MARK: - VITA-49 parser

@Test func vita49ParseExtractsStreamID() throws {
    // Build a minimal signal-data packet (type 1) with stream ID 0x40000123,
    // no class id, no timestamps, no trailer. Header word: type=1, packet
    // size = 3 32-bit words = 12 bytes total. Payload word = 0xCAFEBABE.
    let bytes: [UInt8] = [
        0x10, 0x00, 0x00, 0x03, // header
        0x40, 0x00, 0x01, 0x23, // stream ID
        0xCA, 0xFE, 0xBA, 0xBE, // payload
    ]
    let frame = try Vita49.parse(Data(bytes))
    #expect(frame.streamID == 0x4000_0123)
    #expect(frame.payload == Data([0xCA, 0xFE, 0xBA, 0xBE]))
}

@Test func vita49ParseRejectsShortHeader() {
    let data = Data([0x10, 0x00])
    #expect(throws: Vita49.ParseError.shortHeader) {
        try Vita49.parse(data)
    }
}

@Test func vita49ParseRejectsBadPacketSize() {
    // packet_size_words = 99 but only 12 bytes available
    let bytes: [UInt8] = [
        0x10, 0x00, 0x00, 0x63,
        0x40, 0x00, 0x01, 0x23,
        0xCA, 0xFE, 0xBA, 0xBE,
    ]
    #expect(throws: Vita49.ParseError.invalidPacketSize) {
        try Vita49.parse(Data(bytes))
    }
}

// MARK: - Flex stream-handle decoding

@Test func flexDecodeStreamHandleParsesHexPayload() {
    let value1 = FlexProtocolHandler.decodeStreamHandle(from: "0x40000001")
    #expect(value1 == 0x4000_0001)

    let value2 = FlexProtocolHandler.decodeStreamHandle(from: "40000001")
    #expect(value2 == 0x4000_0001)

    let value3 = FlexProtocolHandler.decodeStreamHandle(from: "0x42000010 0x44000010")
    #expect(value3 == 0x4200_0010)

    let value4 = FlexProtocolHandler.decodeStreamHandle(from: "not a number")
    #expect(value4 == nil)
}
