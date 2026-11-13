import Foundation

/// Assembles raw byte streams into protocol-specific frames.
/// CI-V frames: FE FE ... FD
/// Kenwood frames: terminated by ';'
/// SmartSDR frames: newline-terminated ASCII lines
public actor FrameAssembler {
    // MARK: Lifecycle

    public init(frameType: FrameType) {
        self.frameType = frameType
    }

    // MARK: Public

    public enum FrameType: Sendable {
        case civ
        case kenwood
        case smartsdr
    }

    /// Feed raw bytes, returns any complete frames found
    public func feed(_ data: Data) -> [Data] {
        buffer.append(data)

        switch frameType {
        case .civ:
            return extractCIVFrames()
        case .kenwood:
            return extractKenwoodFrames()
        case .smartsdr:
            return extractSmartSDRFrames()
        }
    }

    public func reset() {
        buffer.removeAll()
    }

    // MARK: Private

    private let frameType: FrameType
    private var buffer = Data()

    private func extractCIVFrames() -> [Data] {
        var frames: [Data] = []

        while let startIndex = findCIVStart() {
            if startIndex > 0 {
                buffer.removeFirst(startIndex)
            }

            guard let endIndex = buffer.firstIndex(of: 0xFD) else {
                break
            }

            let frameEnd = buffer.index(after: endIndex)
            let frame = Data(buffer[buffer.startIndex ..< frameEnd])
            frames.append(frame)
            buffer.removeFirst(frameEnd - buffer.startIndex)
        }

        if buffer.count > 4_096 {
            buffer.removeAll()
        }

        return frames
    }

    private func findCIVStart() -> Int? {
        guard buffer.count >= 2 else {
            return nil
        }
        for idx in 0 ..< buffer.count - 1 {
            if buffer[buffer.startIndex + idx] == 0xFE,
               buffer[buffer.startIndex + idx + 1] == 0xFE
            {
                return idx
            }
        }
        return nil
    }

    private func extractKenwoodFrames() -> [Data] {
        var frames: [Data] = []

        while let semicolonIndex = buffer.firstIndex(of: UInt8(ascii: ";")) {
            let frameEnd = buffer.index(after: semicolonIndex)
            let frame = Data(buffer[buffer.startIndex ..< frameEnd])
            frames.append(frame)
            buffer.removeFirst(frameEnd - buffer.startIndex)
        }

        if buffer.count > 4_096 {
            buffer.removeAll()
        }

        return frames
    }

    private func extractSmartSDRFrames() -> [Data] {
        var frames: [Data] = []
        let newline = UInt8(ascii: "\n")

        while let nlIndex = buffer.firstIndex(of: newline) {
            var frame = Data(buffer[buffer.startIndex ..< nlIndex])
            if let last = frame.last, last == UInt8(ascii: "\r") {
                frame = frame.dropLast()
            }
            if !frame.isEmpty {
                frames.append(Data(frame))
            }
            buffer.removeFirst(nlIndex - buffer.startIndex + 1)
        }

        if buffer.count > 8_192 {
            buffer.removeAll()
        }

        return frames
    }
}
