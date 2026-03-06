import Foundation

/// Assembles raw byte streams into protocol-specific frames.
/// CI-V frames: FE FE ... FD
/// Kenwood frames: terminated by ';'
actor FrameAssembler {
    // MARK: Lifecycle

    init(frameType: FrameType) {
        self.frameType = frameType
    }

    // MARK: Internal

    enum FrameType {
        case civ // Icom CI-V: FE FE <to> <from> <cmd> ... FD
        case kenwood // Kenwood/Elecraft: command;
    }

    /// Feed raw bytes, returns any complete frames found
    func feed(_ data: Data) -> [Data] {
        buffer.append(data)

        switch frameType {
        case .civ:
            return extractCIVFrames()
        case .kenwood:
            return extractKenwoodFrames()
        }
    }

    func reset() {
        buffer.removeAll()
    }

    // MARK: Private

    private let frameType: FrameType
    private var buffer = Data()

    // MARK: - CI-V Frame Extraction

    private func extractCIVFrames() -> [Data] {
        var frames: [Data] = []

        while let startIndex = findCIVStart() {
            // Drop bytes before the frame start
            if startIndex > 0 {
                buffer.removeFirst(startIndex)
            }

            // Look for FD terminator
            guard let endIndex = buffer.firstIndex(of: 0xFD) else {
                // Incomplete frame, wait for more data
                break
            }

            let frameEnd = buffer.index(after: endIndex)
            let frame = Data(buffer[buffer.startIndex ..< frameEnd])
            frames.append(frame)
            buffer.removeFirst(frameEnd - buffer.startIndex)
        }

        // Prevent unbounded buffer growth
        if buffer.count > 4_096 {
            buffer.removeAll()
        }

        return frames
    }

    private func findCIVStart() -> Int? {
        guard buffer.count >= 2 else {
            return nil
        }
        for i in 0 ..< buffer.count - 1 {
            if buffer[buffer.startIndex + i] == 0xFE,
               buffer[buffer.startIndex + i + 1] == 0xFE
            {
                return i
            }
        }
        return nil
    }

    // MARK: - Kenwood Frame Extraction

    private func extractKenwoodFrames() -> [Data] {
        var frames: [Data] = []

        while let semicolonIndex = buffer.firstIndex(of: UInt8(ascii: ";")) {
            let frameEnd = buffer.index(after: semicolonIndex)
            let frame = Data(buffer[buffer.startIndex ..< frameEnd])
            frames.append(frame)
            buffer.removeFirst(frameEnd - buffer.startIndex)
        }

        // Prevent unbounded buffer growth
        if buffer.count > 4_096 {
            buffer.removeAll()
        }

        return frames
    }
}
