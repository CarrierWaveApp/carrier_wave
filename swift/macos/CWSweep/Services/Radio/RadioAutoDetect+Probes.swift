import Foundation

// MARK: - Probe helpers

extension RadioAutoDetect {
    /// Send a CI-V identify and wait for a valid response. Returns nil on timeout.
    static func tryCIV(port: SerialPort, baudRate: Int, timeoutMs: Int) async throws -> Result? {
        let identify = Data([0xFE, 0xFE, 0x00, 0xE0, 0x19, 0x00, 0xFD])
        _ = try? port.write(identify)

        guard let response = try await drainUntil(port: port, timeoutMs: timeoutMs, terminator: 0xFD),
              let parsed = parseCIVResponse(response)
        else {
            return nil
        }
        return Result(
            protocolType: .civ,
            baudRate: baudRate,
            civAddress: parsed,
            rawID: String(format: "%02X", parsed),
            radioName: civAddressName(parsed)
        )
    }

    /// Send Kenwood `ID;` and wait for `IDxxx;`. Returns nil on timeout.
    static func tryKenwood(port: SerialPort, baudRate: Int, timeoutMs: Int) async throws -> Result? {
        _ = try? port.write(Data("ID;".utf8))

        guard let response = try await drainUntil(port: port, timeoutMs: timeoutMs, terminator: 0x3B),
              let identifier = parseKenwoodID(response)
        else {
            return nil
        }
        let proto: RadioProtocolType = identifier == "ID017" ? .elecraft
            : (isYaesuID(identifier) ? .yaesu : .kenwood)
        return Result(
            protocolType: proto,
            baudRate: baudRate,
            civAddress: nil,
            rawID: identifier,
            radioName: kenwoodIDName(identifier)
        )
    }

    /// Read bytes until `terminator` is seen or `timeoutMs` elapses.
    static func drainUntil(port: SerialPort, timeoutMs: Int, terminator: UInt8) async throws -> Data? {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1_000)
        var buffer = Data()
        while Date() < deadline {
            let chunk = (try? port.read(maxBytes: 256)) ?? Data()
            if !chunk.isEmpty {
                buffer.append(chunk)
                if buffer.contains(terminator) {
                    return buffer
                }
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return buffer.isEmpty ? nil : buffer
    }

    /// Extract the CI-V "from" address from a `FE FE E0 <addr> ... FD` reply.
    /// Skips our own echo (where `to == 0x00` or `from == 0xE0`).
    static func parseCIVResponse(_ data: Data) -> UInt8? {
        let bytes = Array(data)
        guard bytes.count >= 6 else {
            return nil
        }
        var idx = 0
        while idx + 5 < bytes.count {
            guard bytes[idx] == 0xFE, bytes[idx + 1] == 0xFE else {
                idx += 1
                continue
            }
            let toAddr = bytes[idx + 2]
            let fromAddr = bytes[idx + 3]
            if toAddr == 0x00 || fromAddr == 0xE0 {
                idx += 1
                continue
            }
            guard toAddr == 0xE0 else {
                idx += 1
                continue
            }
            guard bytes[(idx + 4)...].contains(0xFD) else {
                return nil
            }
            return fromAddr
        }
        return nil
    }

    /// Extract `IDxxx` from a buffer that may contain our own echo.
    /// Requires at least one digit between `ID` and `;`.
    static func parseKenwoodID(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .ascii) else {
            return nil
        }
        var search = text[...]
        while let range = search.range(of: "ID") {
            let after = range.upperBound
            if let semi = search[after...].firstIndex(of: ";"), semi > after {
                let payload = search[after ..< semi]
                if payload.allSatisfy(\.isNumber) {
                    return "ID" + payload
                }
            }
            search = search[range.upperBound...]
        }
        return nil
    }

    /// Yaesu Kenwood-compat rigs answer with `IDxxxx` (4 digits = 6-char total).
    /// Kenwood/Elecraft answer with `IDxxx` (3 digits = 5-char total).
    static func isYaesuID(_ rawID: String) -> Bool {
        rawID.count == 6 && rawID.hasPrefix("ID") && rawID.dropFirst(2).allSatisfy(\.isNumber)
    }
}
