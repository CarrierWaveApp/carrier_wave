import Testing
@testable import CWSweep

/// Pins the Swift view of jtty-sidecar's `JttyShm` to the C layout in
/// `src/protocol.h` (protocol v1). The C side static-asserts the same sizes.
struct JttyShmLayoutTests {
    @Test("Struct sizes match the C static asserts")
    func sizes() {
        #expect(JttyShmLayout.resultStride == 120)
        #expect(JttyShmLayout.txResponseSeqDoneOffset - JttyShmLayout.txRequestSeqOffset == 112)
        #expect(JttyShmLayout.resultsOffset - JttyShmLayout.txResponseSeqDoneOffset == 96)
        let expected = 64 + 48 + 112 + 96 + 120 * JttyShmLayout.resultRing
            + 2 * JttyShmLayout.txMaxSamples + 2 * JttyShmLayout.rxRingSamples
        #expect(JttyShmLayout.totalSize == expected)
        #expect(JttyShmLayout.totalSize == 4_374_080)
    }

    @Test("Field offsets follow the C declaration order and alignment")
    func offsets() {
        #expect(JttyShmLayout.headerSize == 64)
        #expect(JttyShmLayout.rxWrittenOffset == 64)
        #expect(JttyShmLayout.resultsWrittenOffset == 88)
        #expect(JttyShmLayout.txRequestSeqOffset == 112)
        #expect(JttyShmLayout.txRequestTextOffset == 144)
        #expect(JttyShmLayout.txResponseTextOffset == 240)
        #expect(JttyShmLayout.resultsOffset == 320)
        #expect(JttyShmLayout.txPcmOffset == 31_040)
        #expect(JttyShmLayout.rxPcmOffset == 2_934_080)
        // int64 fields stay 8-byte aligned in every ring slot.
        #expect(JttyShmLayout.resultsOffset % 8 == 0)
        #expect(JttyShmLayout.resultStride % 8 == 0)
        #expect(JttyShmLayout.magic == 0x3159_5454)
    }
}
