import Foundation
import Testing
@testable import CWSweep

// MARK: - AudioRingBuffer Tests

@Test func ringBufferInitialState() {
    let buffer = AudioRingBuffer(capacity: 100)
    #expect(buffer.availableSamples == 0)
    #expect(buffer.fillRatio == 0.0)
}

@Test func ringBufferWriteAndRead() {
    let buffer = AudioRingBuffer(capacity: 100)
    let samples: [Int16] = [100, 200, 300, 400, 500]
    buffer.write(samples)

    #expect(buffer.availableSamples == 5)

    let output = UnsafeMutablePointer<Int16>.allocate(capacity: 5)
    defer { output.deallocate() }
    let read = buffer.read(into: output, count: 5)

    #expect(read == 5)
    #expect(output[0] == 100)
    #expect(output[1] == 200)
    #expect(output[2] == 300)
    #expect(output[3] == 400)
    #expect(output[4] == 500)
    #expect(buffer.availableSamples == 0)
}

@Test func ringBufferFillRatio() {
    let buffer = AudioRingBuffer(capacity: 100)
    let samples = [Int16](repeating: 42, count: 50)
    buffer.write(samples)

    #expect(buffer.fillRatio == 0.5)
}

@Test func ringBufferOverflow() {
    let buffer = AudioRingBuffer(capacity: 10)

    // Write more than capacity — oldest should be dropped
    let samples = [Int16](1 ... 15)
    buffer.write(samples)

    #expect(buffer.availableSamples == 10)

    let output = UnsafeMutablePointer<Int16>.allocate(capacity: 10)
    defer { output.deallocate() }
    let read = buffer.read(into: output, count: 10)

    #expect(read == 10)
    // Should have kept the last 10 samples (6-15)
    #expect(output[0] == 6)
    #expect(output[9] == 15)
}

@Test func ringBufferPartialRead() {
    let buffer = AudioRingBuffer(capacity: 100)
    let samples: [Int16] = [10, 20, 30]
    buffer.write(samples)

    // Request more than available — remainder should be silence (0)
    let output = UnsafeMutablePointer<Int16>.allocate(capacity: 6)
    defer { output.deallocate() }
    let read = buffer.read(into: output, count: 6)

    #expect(read == 3)
    #expect(output[0] == 10)
    #expect(output[1] == 20)
    #expect(output[2] == 30)
    #expect(output[3] == 0) // silence
    #expect(output[4] == 0) // silence
    #expect(output[5] == 0) // silence
}

@Test func ringBufferReset() {
    let buffer = AudioRingBuffer(capacity: 100)
    let samples: [Int16] = [10, 20, 30]
    buffer.write(samples)

    #expect(buffer.availableSamples == 3)

    buffer.reset()

    #expect(buffer.availableSamples == 0)
    #expect(buffer.fillRatio == 0.0)
}

@Test func ringBufferWrap() {
    let buffer = AudioRingBuffer(capacity: 4)

    // Write and read to advance indices past capacity
    buffer.write([1, 2, 3])
    let out1 = UnsafeMutablePointer<Int16>.allocate(capacity: 3)
    defer { out1.deallocate() }
    _ = buffer.read(into: out1, count: 3)

    // Now write more — should wrap around
    buffer.write([10, 20, 30])
    let out2 = UnsafeMutablePointer<Int16>.allocate(capacity: 3)
    defer { out2.deallocate() }
    let read = buffer.read(into: out2, count: 3)

    #expect(read == 3)
    #expect(out2[0] == 10)
    #expect(out2[1] == 20)
    #expect(out2[2] == 30)
}

@Test func ringBufferWriteEmpty() {
    let buffer = AudioRingBuffer(capacity: 100)
    buffer.write([])
    #expect(buffer.availableSamples == 0)
}

@Test func ringBufferReadResampledAsFloat() {
    let buffer = AudioRingBuffer(capacity: 100)
    let samples: [Int16] = [Int16.max, 0, Int16.min]
    buffer.write(samples)

    let output = UnsafeMutablePointer<Float>.allocate(capacity: 6)
    defer { output.deallocate() }
    // 2:1 upsample
    let consumed = buffer.readResampledAsFloat(into: output, outputCount: 6, ratio: 2.0)

    #expect(consumed == 3)
    // First output sample should be close to 1.0 (Int16.max / Int16.max)
    #expect(output[0] > 0.9, "First sample should be near 1.0")
}
