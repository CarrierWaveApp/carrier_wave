import Foundation

// MARK: - RemoteOpFraming

//
// Frames go on the wire as UTF-8 JSON inside WebSocket text messages. Dates are
// ISO-8601 with fractional seconds for precise timestamping of decodes/spots.

public enum RemoteOpFraming {
    // MARK: Public

    public static func encode(_ frame: RemoteOpFrame) throws -> Data {
        try makeEncoder().encode(frame)
    }

    public static func encodeText(_ frame: RemoteOpFrame) throws -> String {
        let data = try encode(frame)
        guard let text = String(data: data, encoding: .utf8) else {
            throw RemoteOpFramingError.encodingFailed
        }
        return text
    }

    public static func decode(_ data: Data) throws -> RemoteOpFrame {
        try makeDecoder().decode(RemoteOpFrame.self, from: data)
    }

    public static func decode(text: String) throws -> RemoteOpFrame {
        guard let data = text.data(using: .utf8) else {
            throw RemoteOpFramingError.decodingFailed
        }
        return try decode(data)
    }

    // MARK: Private

    private static func makeEncoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.withoutEscapingSlashes]
        enc.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.iso8601String(from: date))
        }
        return enc
    }

    private static func makeDecoder() -> JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = Self.iso8601Parse(raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized ISO8601 date: \(raw)"
            )
        }
        return dec
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func iso8601Parse(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}

// MARK: - RemoteOpFramingError

public enum RemoteOpFramingError: Error, Sendable {
    case encodingFailed
    case decodingFailed
}
