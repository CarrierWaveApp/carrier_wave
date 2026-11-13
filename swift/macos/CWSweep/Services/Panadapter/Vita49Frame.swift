import Foundation

// MARK: - Vita49Frame

/// Minimal VITA-49 frame parser tailored to the FlexRadio SmartSDR
/// panadapter / waterfall streams. Only the fields needed to dispatch a
/// payload to the right consumer are decoded; the rest of the header
/// (timestamps, packet counts) is skipped.
///
/// Wire format reference:
/// ```
/// word 0: [packet_type:4][C:1][T:1][rsvd:2][TSI:2][TSF:2]
///         [packet_count:4][packet_size_words:16]
/// word 1: stream_id (32 bits)
/// word 2-3: class_id (only present if C bit set)
/// word 4 / 4-5: integer / fractional timestamps (variable, gated by TSI/TSF)
/// payload words ...
/// trailer (only if T bit set)
/// ```
///
/// All multi-byte fields are big-endian on the wire.
enum Vita49 {
    // MARK: Internal

    /// Result of parsing one VITA-49 packet from a UDP datagram.
    struct Frame: Equatable {
        let streamID: UInt32
        let classOUI: UInt32?
        let classCode: UInt32?
        let payload: Data
    }

    enum ParseError: Error, Equatable {
        case shortHeader
        case invalidPacketSize
        case shortPayload
        case unsupportedPacketType
    }

    /// Parse a single VITA-49 packet from `data`. The whole datagram must
    /// contain exactly one packet (this matches FlexRadio's behavior — they
    /// emit one panadapter line per UDP datagram).
    static func parse(_ data: Data) throws -> Frame {
        guard data.count >= 8 else {
            throw ParseError.shortHeader
        }
        let header = data.withUnsafeBytes { raw -> UInt32 in
            // word 0 is the first 32 bits, big-endian
            let bytes = raw.bindMemory(to: UInt8.self)
            return UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
        }
        let packetTypeNibble = UInt8((header >> 28) & 0xF)
        let classIDPresent = ((header >> 27) & 0x1) == 1
        let trailerPresent = ((header >> 26) & 0x1) == 1
        let tsi = UInt8((header >> 22) & 0x3)
        let tsf = UInt8((header >> 20) & 0x3)
        let packetSizeWords = Int(header & 0xFFFF)
        let packetSizeBytes = packetSizeWords * 4

        // FlexRadio spectrum streams are signal-data packets without ID
        // (type 1) or with stream ID (type 1+S, encoded as 1).
        guard packetTypeNibble == 1 || packetTypeNibble == 4 || packetTypeNibble == 5 else {
            throw ParseError.unsupportedPacketType
        }
        guard packetSizeBytes > 0, packetSizeBytes <= data.count else {
            throw ParseError.invalidPacketSize
        }

        // Stream ID is the next 4 bytes for our packet types (1: signal data
        // with stream ID, 4/5: extension/context).
        var cursor = 4
        let streamID = readUInt32(data, at: cursor)
        cursor += 4

        var classOUI: UInt32?
        var classCode: UInt32?
        if classIDPresent {
            let oui = readUInt32(data, at: cursor) & 0x00FF_FFFF
            cursor += 4
            let codes = readUInt32(data, at: cursor)
            cursor += 4
            classOUI = oui
            classCode = codes
        }
        if tsi != 0 {
            cursor += 4
        }
        if tsf != 0 {
            cursor += 8
        }

        // Trailer (if present) is the last 32-bit word of the packet.
        let payloadEnd = trailerPresent ? packetSizeBytes - 4 : packetSizeBytes
        guard cursor <= payloadEnd, payloadEnd <= data.count else {
            throw ParseError.shortPayload
        }
        let payload = data.subdata(in: cursor ..< payloadEnd)

        return Frame(
            streamID: streamID,
            classOUI: classOUI,
            classCode: classCode,
            payload: payload
        )
    }

    // MARK: Private

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24
            | UInt32(data[offset + 1]) << 16
            | UInt32(data[offset + 2]) << 8
            | UInt32(data[offset + 3])
    }
}
