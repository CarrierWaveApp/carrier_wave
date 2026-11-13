// S.A.T. ADIF record buffer
//
// Accumulates bytes arriving from the CSN Technologies S.A.T. tracker (one UDP
// datagram or one TCP stream chunk at a time) and yields complete ADIF records
// for `ADIFParser`.

import Foundation

/// Tolerant record splitter for ADIF pushed over the network.
///
/// The S.A.T. wire format is not formally documented, so this accepts:
/// - bare records, records preceded by an ADIF header (`<eoh>`), and several
///   records in a single payload;
/// - `<eor>` / `<eoh>` in any letter case;
/// - a TCP record split across chunks (buffered until its `<eor>` arrives);
/// - trailing content with no `<eor>` at all — `flush()` emits it as a record
///   when it contains at least one `<name:length>` field, for senders that omit
///   the terminator or just close the socket.
struct SatLogRecordBuffer: Sendable {
    // MARK: Internal

    /// Pending bytes are discarded past this size so a sender that never
    /// terminates a record cannot grow memory without bound.
    static let maxPendingBytes = 64 * 1_024

    var isEmpty: Bool {
        pending.isEmpty
    }

    /// Split a self-contained payload (a UDP datagram) into records, treating
    /// an unterminated tail as a record too.
    static func records(inDatagram data: Data) -> [String] {
        var buffer = SatLogRecordBuffer()
        var records = buffer.append(data)
        records.append(contentsOf: buffer.flush())
        return records
    }

    /// Append a chunk and return every record it completed. Each returned
    /// string is header-free and ends with `<eor>`.
    mutating func append(_ data: Data) -> [String] {
        pending.append(contentsOf: data)
        if pending.count > Self.maxPendingBytes {
            pending.removeAll(keepingCapacity: false)
            return []
        }
        var records: [String] = []
        while let eor = Self.firstRange(of: Self.eorToken, in: pending) {
            if let record = Self.makeRecord(from: pending[0 ..< eor.lowerBound]) {
                records.append(record)
            }
            pending.removeSubrange(0 ..< eor.upperBound)
        }
        return records
    }

    /// Emit whatever is pending as a record (if it looks like one) and reset.
    mutating func flush() -> [String] {
        defer { pending.removeAll(keepingCapacity: false) }
        guard let record = Self.makeRecord(from: pending[...]) else {
            return []
        }
        return [record]
    }

    // MARK: Private

    private static let eorToken = Array("<eor>".utf8)
    private static let eohToken = Array("<eoh>".utf8)

    private var pending: [UInt8] = []

    /// Strip any header (everything through the last `<eoh>`), trim
    /// whitespace, and require at least one `<name:length>` field.
    private static func makeRecord(from bytes: ArraySlice<UInt8>) -> String? {
        var body = Array(bytes)
        if let eoh = lastRange(of: eohToken, in: body) {
            body.removeSubrange(0 ..< eoh.upperBound)
        }
        let decoded = String(bytes: body, encoding: .utf8)
            ?? String(bytes: body, encoding: .isoLatin1)
            ?? ""
        let text = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeRecord(text) else {
            return nil
        }
        return text + "<eor>"
    }

    /// True when the text contains a `<name:length…>` tag (a data specifier,
    /// not just a sentinel like `<eor>` or an XML-ish wrapper).
    private static func looksLikeRecord(_ text: String) -> Bool {
        var searchStart = text.startIndex
        while let open = text[searchStart...].firstIndex(of: "<") {
            guard let close = text[open...].firstIndex(of: ">") else {
                return false
            }
            if text[open ..< close].contains(":") {
                return true
            }
            searchStart = text.index(after: close)
        }
        return false
    }

    private static func firstRange(of token: [UInt8], in bytes: [UInt8]) -> Range<Int>? {
        guard bytes.count >= token.count else {
            return nil
        }
        for offset in 0 ... (bytes.count - token.count) where matches(token, in: bytes, at: offset) {
            return offset ..< offset + token.count
        }
        return nil
    }

    private static func lastRange(of token: [UInt8], in bytes: [UInt8]) -> Range<Int>? {
        guard bytes.count >= token.count else {
            return nil
        }
        for offset in stride(from: bytes.count - token.count, through: 0, by: -1)
            where matches(token, in: bytes, at: offset)
        {
            return offset ..< offset + token.count
        }
        return nil
    }

    /// Case-insensitive ASCII comparison of `token` against `bytes[offset...]`.
    private static func matches(_ token: [UInt8], in bytes: [UInt8], at offset: Int) -> Bool {
        for (index, tokenByte) in token.enumerated() where lowercased(bytes[offset + index]) != tokenByte {
            return false
        }
        return true
    }

    private static func lowercased(_ byte: UInt8) -> UInt8 {
        byte >= 0x41 && byte <= 0x5A ? byte + 0x20 : byte
    }
}
