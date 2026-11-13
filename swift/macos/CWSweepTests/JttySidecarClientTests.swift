import Foundation
import Testing
@testable import CWSweep

// MARK: - JttySidecarClientTests

/// Drives `JttySidecarClient` against a caller-owned buffer laid out like the
/// helper's segment, playing the server's side of the protocol by hand.
struct JttySidecarClientTests {
    @Test("Header checks: not ready until magic, version, size and state agree")
    func readiness() {
        let segment = FakeSegment()
        let client = segment.client()
        #expect(!client.isReady)
        segment.writeHeader(state: .starting)
        #expect(!client.isReady)
        segment.store(Int32(1), at: JttyShmLayout.serverStateOffset)
        #expect(client.isReady)
        segment.store(UInt32(2), at: JttyShmLayout.versionOffset)
        #expect(!client.isReady)
    }

    @Test("Decode results are drained in order, text trimmed, once each")
    func drainResults() {
        let segment = FakeSegment()
        segment.writeHeader(state: .running)
        let client = segment.client()
        #expect(client.drainResults().isEmpty)

        segment.publishResult(slot: 0, id: 7, start: 12_000, frequency: 1_501.2, eom: false, text: "CQ K1")
        segment.publishResult(slot: 1, id: 7, start: 12_000, frequency: 1_501.2, eom: true, text: "CQ K1JT CQ")
        let results = client.drainResults()
        #expect(results.count == 2)
        #expect(results[0] == JttyDecodeResult(
            messageId: 7, startSample: 12_000, frequency: 1_501.2, isComplete: false, text: "CQ K1"
        ))
        #expect(results[1].isComplete)
        #expect(results[1].text == "CQ K1JT CQ")
        #expect(client.drainResults().isEmpty)
    }

    @Test("Falling more than a ring behind skips the overwritten entries")
    func drainSkipsLostEntries() {
        let segment = FakeSegment()
        segment.writeHeader(state: .running)
        let client = segment.client()
        for index in 0 ..< (JttyShmLayout.resultRing + 10) {
            segment.publishResult(
                slot: index % JttyShmLayout.resultRing,
                id: Int64(index), start: 0, frequency: 1_500, eom: true, text: "M\(index)"
            )
        }
        let results = client.drainResults()
        #expect(results.count == JttyShmLayout.resultRing)
        #expect(results.first?.messageId == 10)
        #expect(results.last?.messageId == Int64(JttyShmLayout.resultRing + 9))
    }

    @Test("Receive audio wraps around the ring and publishes the total count")
    func receiveRing() {
        let segment = FakeSegment()
        segment.writeHeader(state: .running)
        let client = segment.client()
        let ring = JttyShmLayout.rxRingSamples

        // Advance to 100 samples before the wrap point, then write 300.
        let prefix = [Int16](repeating: 1, count: ring - 100)
        prefix.withUnsafeBufferPointer { client.writeReceiveAudio($0) }
        let block = (0 ..< 300).map { Int16($0) }
        block.withUnsafeBufferPointer { client.writeReceiveAudio($0) }

        #expect(client.totalSamplesWritten == Int64(ring + 200))
        #expect(segment.load(Int64.self, at: JttyShmLayout.rxWrittenOffset) == Int64(ring + 200))
        // Last 100 slots of the ring hold block[0..<100]; the first 200 hold block[100..<300].
        #expect(segment.sample(at: ring - 1) == 99)
        #expect(segment.sample(at: 0) == 100)
        #expect(segment.sample(at: 199) == 299)
    }

    @Test("Transmit writes the request, waits for the matching seq, and copies the audio")
    func transmitRoundTrip() async throws {
        let segment = FakeSegment()
        segment.writeHeader(state: .running)
        let client = segment.client()

        let server = Task.detached {
            // Wait for the request to appear, then answer like the helper would.
            while segment.load(Int32.self, at: JttyShmLayout.txRequestSeqOffset) == 0 {
                try? await Task.sleep(for: .milliseconds(2))
            }
            let seq = segment.load(Int32.self, at: JttyShmLayout.txRequestSeqOffset)
            let text = segment.string(at: JttyShmLayout.txRequestTextOffset)
            #expect(text == "CQ K1ABC CQ")
            #expect(segment.load(Int32.self, at: JttyShmLayout.txRequestProfileOffset) == 2)
            #expect(segment.load(Int32.self, at: JttyShmLayout.txRequestSampleRateOffset) == 48_000)
            #expect(segment.load(Int32.self, at: JttyShmLayout.txRequestChainedOffset) == 1)
            #expect(segment.load(Float.self, at: JttyShmLayout.txRequestF0Offset) == 1_200)
            for index in 0 ..< 5 {
                segment.store(Int16(index * 100), at: JttyShmLayout.txPcmOffset + index * 2)
            }
            segment.store(Int32(0), at: JttyShmLayout.txResponseStatusOffset)
            segment.store(Int32(5), at: JttyShmLayout.txResponseSamplesOffset)
            segment.store(Int32(1), at: JttyShmLayout.txResponseFramesOffset)
            segment.writeText("CQ K1ABC CQ", at: JttyShmLayout.txResponseTextOffset)
            segment.store(seq, at: JttyShmLayout.txResponseSeqDoneOffset)
        }

        let rendering = try await client.transmit(
            text: "CQ K1ABC CQ", profile: .rttyRoundup, sampleRate: 48_000, f0: 1_200, chained: true
        )
        await server.value
        #expect(rendering.canonicalText == "CQ K1ABC CQ")
        #expect(rendering.frames == 1)
        #expect(rendering.samples == [0, 100, 200, 300, 400])
    }

    @Test("A rejected render surfaces the helper's status")
    func transmitRejected() async {
        let segment = FakeSegment()
        segment.writeHeader(state: .running)
        let client = segment.client()
        let server = Task.detached {
            while segment.load(Int32.self, at: JttyShmLayout.txRequestSeqOffset) == 0 {
                try? await Task.sleep(for: .milliseconds(2))
            }
            segment.store(Int32(5), at: JttyShmLayout.txResponseStatusOffset)
            segment.store(
                segment.load(Int32.self, at: JttyShmLayout.txRequestSeqOffset),
                at: JttyShmLayout.txResponseSeqDoneOffset
            )
        }
        await #expect(throws: JttySidecarClient.ClientError.self) {
            try await client.transmit(text: "X", profile: .serial, sampleRate: 12_000, f0: 1_500, chained: false)
        }
        await server.value
    }

    @Test("Transmit times out when the helper never answers")
    func transmitTimeout() async {
        let segment = FakeSegment()
        segment.writeHeader(state: .running)
        let client = segment.client()
        await #expect(throws: JttySidecarClient.ClientError.self) {
            try await client.transmit(
                text: "X", profile: .serial, sampleRate: 12_000, f0: 1_500, chained: false,
                timeout: .milliseconds(50)
            )
        }
    }
}

// MARK: - FakeSegment

/// A heap buffer with the segment's layout; the tests play the server.
private final class FakeSegment: @unchecked Sendable {
    // MARK: Lifecycle

    init() {
        base = UnsafeMutableRawPointer.allocate(byteCount: JttyShmLayout.totalSize, alignment: 8)
        base.initializeMemory(as: UInt8.self, repeating: 0, count: JttyShmLayout.totalSize)
    }

    deinit {
        base.deallocate()
    }

    // MARK: Internal

    let base: UnsafeMutableRawPointer

    func client() -> JttySidecarClient {
        JttySidecarClient(name: "test", base: base, mappedSize: JttyShmLayout.totalSize, unmapOnClose: false)
    }

    func writeHeader(state: JttyShmLayout.ServerState) {
        store(JttyShmLayout.version, at: JttyShmLayout.versionOffset)
        store(UInt32(JttyShmLayout.totalSize), at: JttyShmLayout.structSizeOffset)
        store(UInt32(JttyShmLayout.headerSize), at: JttyShmLayout.headerSizeOffset)
        store(state.rawValue, at: JttyShmLayout.serverStateOffset)
        store(JttyShmLayout.magic, at: JttyShmLayout.magicOffset)
    }

    func publishResult(slot: Int, id: Int64, start: Int64, frequency: Float, eom: Bool, text: String) {
        let offset = JttyShmLayout.resultsOffset + slot * JttyShmLayout.resultStride
        store(id, at: offset + JttyShmLayout.resultMessageIdOffset)
        store(start, at: offset + JttyShmLayout.resultStartSampleOffset)
        store(frequency, at: offset + JttyShmLayout.resultFrequencyOffset)
        store(Int32(eom ? 1 : 0), at: offset + JttyShmLayout.resultEomOffset)
        writeText(text, at: offset + JttyShmLayout.resultTextOffset, padding: 0x20)
        let written = load(Int64.self, at: JttyShmLayout.resultsWrittenOffset)
        store(written + 1, at: JttyShmLayout.resultsWrittenOffset)
    }

    func writeText(_ text: String, at offset: Int, padding: UInt8 = 0) {
        var bytes = [UInt8](repeating: padding, count: JttyShmLayout.textLength)
        for (index, byte) in text.utf8.prefix(JttyShmLayout.textLength).enumerated() {
            bytes[index] = byte
        }
        bytes.withUnsafeBytes { (base + offset).copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
    }

    func string(at offset: Int) -> String {
        let bytes = UnsafeRawBufferPointer(start: base + offset, count: JttyShmLayout.textLength)
        let end = bytes.firstIndex(of: 0) ?? JttyShmLayout.textLength
        return String(decoding: bytes[..<end], as: UTF8.self)
    }

    func sample(at index: Int) -> Int16 {
        load(Int16.self, at: JttyShmLayout.rxPcmOffset + index * 2)
    }

    func load<T>(_: T.Type, at offset: Int) -> T {
        base.loadUnaligned(fromByteOffset: offset, as: T.self)
    }

    func store<T>(_ value: T, at offset: Int) {
        base.storeBytes(of: value, toByteOffset: offset, as: T.self)
    }
}
