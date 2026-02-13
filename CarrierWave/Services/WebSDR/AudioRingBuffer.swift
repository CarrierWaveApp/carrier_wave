import Foundation
import os

// MARK: - AudioRingBuffer

/// Thread-safe circular buffer for audio samples.
/// Network thread pushes samples in, audio render thread pulls samples out.
/// Uses `OSAllocatedUnfairLock` for lock-based synchronization that is
/// safe on the real-time audio thread (no priority inversion).
final class AudioRingBuffer: Sendable {
    // MARK: Lifecycle

    /// Create a ring buffer with the given capacity in samples.
    /// Default is 3 seconds at 12 kHz.
    init(capacity: Int = 36_000) {
        let state = State(capacity: capacity)
        lockedState = OSAllocatedUnfairLock(initialState: state)
    }

    // MARK: Internal

    /// Current fill ratio (0.0 to 1.0). Safe to call from any thread.
    nonisolated var fillRatio: Double {
        lockedState.withLock { state in
            guard state.capacity > 0 else {
                return 0.0
            }
            return Double(state.count) / Double(state.capacity)
        }
    }

    /// Number of samples currently buffered.
    nonisolated var availableSamples: Int {
        lockedState.withLock { $0.count }
    }

    /// Write samples into the buffer (called from network thread).
    /// On overflow, drops oldest samples to make room.
    nonisolated func write(_ samples: [Int16]) {
        guard !samples.isEmpty else {
            return
        }

        lockedState.withLock { state in
            for sample in samples {
                state.buffer[state.writeIndex] = sample
                state.writeIndex = (state.writeIndex + 1) % state.capacity

                if state.count == state.capacity {
                    // Overflow: advance read index (drop oldest)
                    state.readIndex = (state.readIndex + 1) % state.capacity
                } else {
                    state.count += 1
                }
            }
        }
    }

    /// Read samples into a raw pointer (called from audio render thread).
    /// Returns the number of samples actually read. Fills remaining with silence.
    /// This method is real-time safe — no allocations.
    nonisolated func read(into buffer: UnsafeMutablePointer<Int16>, count: Int) -> Int {
        // The pointer is valid for the duration of this call and the lock
        // scope is synchronous, so this is safe despite the Sendable warning.
        nonisolated(unsafe) let buf = buffer
        return lockedState.withLock { state in
            let available = min(count, state.count)

            for i in 0 ..< available {
                buf[i] = state.buffer[state.readIndex]
                state.readIndex = (state.readIndex + 1) % state.capacity
            }
            state.count -= available

            // Fill remaining with silence
            for i in available ..< count {
                buf[i] = 0
            }

            return available
        }
    }

    /// Read samples as Float32, resampling from input rate to output rate.
    /// Uses nearest-neighbor interpolation — sufficient for narrowband
    /// ham radio audio. Converts Int16 → Float32 and resamples inside
    /// the lock with zero allocation on the real-time audio thread.
    /// `ratio` is outputRate / inputRate (e.g., 4.0 for 12kHz → 48kHz).
    nonisolated func readResampledAsFloat(
        into buffer: UnsafeMutablePointer<Float>,
        outputCount: Int,
        ratio: Double
    ) -> Int {
        nonisolated(unsafe) let buf = buffer
        let scale: Float = 1.0 / Float(Int16.max)

        return lockedState.withLock { state in
            let inputNeeded = Int(ceil(Double(outputCount) / ratio))
            let available = min(inputNeeded, state.count)

            guard available > 0 else {
                for i in 0 ..< outputCount {
                    buf[i] = 0
                }
                return 0
            }

            // How many output frames we can produce from available input
            let producible = min(outputCount, Int(Double(available) * ratio))

            for i in 0 ..< producible {
                let srcIdx = min(Int(Double(i) / ratio), available - 1)
                let ringIdx = (state.readIndex + srcIdx) % state.capacity
                buf[i] = Float(state.buffer[ringIdx]) * scale
            }

            // Fill remainder with silence
            for i in producible ..< outputCount {
                buf[i] = 0
            }

            // Consume the input samples we used
            state.readIndex = (state.readIndex + available) % state.capacity
            state.count -= available

            return available
        }
    }

    /// Reset the buffer, discarding all samples.
    nonisolated func reset() {
        lockedState.withLock { state in
            state.readIndex = 0
            state.writeIndex = 0
            state.count = 0
        }
    }

    // MARK: Private

    private let lockedState: OSAllocatedUnfairLock<State>
}

// MARK: AudioRingBuffer.State

extension AudioRingBuffer {
    /// Internal mutable state protected by the lock.
    struct State {
        // MARK: Lifecycle

        init(capacity: Int) {
            self.capacity = capacity
            buffer = [Int16](repeating: 0, count: capacity)
        }

        // MARK: Internal

        var buffer: [Int16]
        let capacity: Int
        var readIndex: Int = 0
        var writeIndex: Int = 0
        var count: Int = 0
    }
}
