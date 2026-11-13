import Foundation

// MARK: - RotatorProtocolCodec

/// Pure encoders/parsers for the rotator wire protocols. No sockets here so
/// every format is unit-testable byte for byte.
///
/// Formats (PSR-100 Mk2 manual, Appendix B; Hamlib rotctld man page):
/// - Hamlib:    `P 180.0 45.0\n` → `RPRT 0\n`; `p\n` → `180.00\n45.00\n`; `S\n`
/// - EasyComm:  `AZ180.5 EL45.2\n`; `AZ EL\n` → `AZ180.0 EL45.0`; `SA SE\n`
/// - GS-232B:   `W180 045\r`; `C2\r` → `AZ=180 EL=045`; `S\r`
/// - S.A.T. XML: `<PST><AZIMUTH>180</AZIMUTH><ELEVATION>45</ELEVATION></PST>`;
///              `<PST>AZ?</PST>` → `AZ:180`; `<PST>EL?</PST>` → `EL:45`;
///              `<PST><STOP>1</STOP></PST>`
/// - PSR-100 HTTP: `GET /command?cmd=AZ180EL45` → `Command executed: AZ=180 EL=45`;
///              position from `GET /data` JSON (`AZ EL` over HTTP is a MOVE to 0/0); `cmd=STOP`
public enum RotatorProtocolCodec: Sendable {
    // MARK: Public

    /// Sent in place of a text query when the transport should fetch the
    /// unit's status resource instead (PSR-100 HTTP `/data`).
    public static let statusQueryToken = "?status"

    // MARK: - Encoding

    /// Command that moves the rotator to `position`.
    public static func moveCommand(_ position: RotatorPosition, protocolKind: RotatorProtocolKind) -> Data {
        let pointing = position.normalized()
        let text = switch protocolKind {
        case .hamlibRotctl:
            String(format: "P %.1f %.1f\n", pointing.azimuthDeg, pointing.elevationDeg)
        case .easycommII:
            String(format: "AZ%.1f EL%.1f\n", pointing.azimuthDeg, pointing.elevationDeg)
        case .gs232B:
            String(
                format: "W%03d %03d\r",
                Int(pointing.azimuthDeg.rounded()), Int(pointing.elevationDeg.rounded())
            )
        case .csnSATxml:
            "<PST><AZIMUTH>\(Int(pointing.azimuthDeg.rounded()))</AZIMUTH>"
                + "<ELEVATION>\(Int(pointing.elevationDeg.rounded()))</ELEVATION></PST>"
        case .psr100HTTP:
            // Same string the rotor's own Go To button sends.
            "AZ\(Int(pointing.azimuthDeg.rounded()))EL\(Int(pointing.elevationDeg.rounded()))"
        }
        return Data(text.utf8)
    }

    /// Commands that ask for the current position. The S.A.T. XML protocol
    /// needs two round trips (azimuth, then elevation).
    public static func positionQueries(protocolKind: RotatorProtocolKind) -> [Data] {
        let texts: [String] = switch protocolKind {
        case .hamlibRotctl: ["p\n"]
        case .easycommII: ["AZ EL\n"]
        case .gs232B: ["C2\r"]
        case .csnSATxml: ["<PST>AZ?</PST>", "<PST>EL?</PST>"]
        // The web handler would read `AZ EL` as a move to 0/0 — the rotor's
        // own page reads position from `/data`, so do we (see transport).
        case .psr100HTTP: [statusQueryToken]
        }
        return texts.map { Data($0.utf8) }
    }

    /// Command that halts both axes.
    public static func stopCommand(protocolKind: RotatorProtocolKind) -> Data {
        let text = switch protocolKind {
        case .hamlibRotctl: "S\n"
        case .easycommII: "SA SE\n"
        case .gs232B: "S\r"
        case .csnSATxml: "<PST><STOP>1</STOP></PST>"
        case .psr100HTTP: "STOP"
        }
        return Data(text.utf8)
    }

    // MARK: - Parsing

    /// Parse whatever the rotator sent back. Returns the axes it mentioned
    /// (one or both). `nil` when the text carries no position at all.
    public static func parsePosition(_ text: String) -> PartialPosition? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        // PSR-100 `/data` JSON: {"azimuth":123,"elevation":45,...}
        if trimmed.hasPrefix("{") {
            var partial = PartialPosition()
            for match in matches(of: #""(azimuth|elevation)"\s*:\s*(-?\d+(?:\.\d+)?)"#, in: trimmed) {
                apply(axis: match.0.hasPrefix("az") ? "AZ" : "EL", value: match.1, to: &partial)
            }
            return partial.hasAny ? partial : nil
        }
        // Error replies (`RPRT -1`) carry no position.
        if trimmed.uppercased().hasPrefix("RPRT") {
            return nil
        }
        var partial = PartialPosition()

        // S.A.T. XML replies: `AZ:180` / `EL:45` (possibly both in one datagram).
        for match in matches(of: #"(?i)\b(AZ|EL)\s*[:=]\s*(-?\d+(?:\.\d+)?)"#, in: trimmed) {
            apply(axis: match.0, value: match.1, to: &partial)
        }
        if partial.hasAny {
            return partial
        }

        // EasyComm: `AZ180.0 EL45.0` (no separator between label and number).
        for match in matches(of: #"(?i)\b(AZ|EL)(-?\d+(?:\.\d+)?)"#, in: trimmed) {
            apply(axis: match.0, value: match.1, to: &partial)
        }
        if partial.hasAny {
            return partial
        }

        // Hamlib `p`: two bare numbers, azimuth then elevation, newline or
        // whitespace separated.
        let numbers = trimmed
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == " " || $0 == "\t" })
            .compactMap { Double($0) }
        if numbers.count >= 2 {
            partial.azimuthDeg = numbers[0]
            partial.elevationDeg = numbers[1]
            return partial
        }
        return nil
    }

    /// Guess which protocol produced a reply — used by discovery when a
    /// broadcast probe comes back from an unknown unit.
    public static func detectProtocol(fromReply text: String) -> RotatorProtocolKind? {
        let upper = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !upper.isEmpty else {
            return nil
        }
        if upper.contains("AZ:") || upper.contains("EL:") {
            return .csnSATxml
        }
        if upper.contains("AZ=") || upper.contains("EL=") {
            return .gs232B
        }
        if upper.hasPrefix("AZ") || upper.hasPrefix("EL") {
            return .easycommII
        }
        if upper.hasPrefix("RPRT") {
            return .hamlibRotctl
        }
        let numbers = upper.split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == " " })
            .compactMap { Double($0) }
        return numbers.count >= 2 ? .hamlibRotctl : nil
    }

    /// Whether a Hamlib reply reports success (`RPRT 0`).
    public static func hamlibReplyIsOK(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines) == "RPRT 0"
    }

    // MARK: Private

    private static func apply(axis: String, value: String, to partial: inout PartialPosition) {
        guard let number = Double(value) else {
            return
        }
        if axis.uppercased() == "AZ" {
            partial.azimuthDeg = number
        } else {
            partial.elevationDeg = number
        }
    }

    private static func matches(of pattern: String, in text: String) -> [(String, String)] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges >= 3,
                  let axisRange = Range(match.range(at: 1), in: text),
                  let valueRange = Range(match.range(at: 2), in: text)
            else {
                return nil
            }
            return (String(text[axisRange]), String(text[valueRange]))
        }
    }
}

// MARK: RotatorProtocolCodec.PartialPosition

public extension RotatorProtocolCodec {
    /// A reply may carry one axis (S.A.T. XML) or both.
    struct PartialPosition: Equatable, Sendable {
        // MARK: Lifecycle

        public init(azimuthDeg: Double? = nil, elevationDeg: Double? = nil) {
            self.azimuthDeg = azimuthDeg
            self.elevationDeg = elevationDeg
        }

        // MARK: Public

        public var azimuthDeg: Double?
        public var elevationDeg: Double?

        public var hasAny: Bool {
            azimuthDeg != nil || elevationDeg != nil
        }

        /// Merge onto a previous reading so single-axis replies still yield a
        /// full position.
        public func merged(onto previous: RotatorPosition?) -> RotatorPosition? {
            let az = azimuthDeg ?? previous?.azimuthDeg
            let el = elevationDeg ?? previous?.elevationDeg
            guard let az, let el else {
                return nil
            }
            return RotatorPosition(azimuthDeg: az, elevationDeg: el)
        }
    }
}
