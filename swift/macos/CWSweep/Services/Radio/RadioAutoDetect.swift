import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "RadioAutoDetect")

// MARK: - RadioAutoDetect

/// Host-side port of the firmware's `detect.rs`: walks candidate baud rates
/// for a USB-serial port, sends a CI-V identify, then a Kenwood `ID;`, and
/// reports the detected protocol/baud/CI-V address.
///
/// The probe does not depend on `RadioModel.knownModels` — it returns the raw
/// protocol family and the bytes the radio answered with. Callers (UI/Manager)
/// translate the result into a `RadioProfile`.
enum RadioAutoDetect {
    // MARK: Internal

    /// Per-cable baud-rate hints, mirroring `firmware/src/detect.rs`.
    struct CableHint {
        let vendorId: Int
        let productId: Int
        let name: String
        let bauds: [Int]
    }

    /// Result of a successful probe.
    struct Result: Equatable {
        let protocolType: RadioProtocolType
        let baudRate: Int
        let civAddress: UInt8?
        /// Raw ID string (Kenwood `IDxxx`) or hex CI-V address (e.g. "A4").
        let rawID: String
        /// Best-guess human-readable name, or nil if unrecognised.
        let radioName: String?
    }

    enum DetectError: LocalizedError {
        case openFailed(String)
        case noResponse

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case let .openFailed(msg):
                "Couldn't open serial port: \(msg)"
            case .noResponse:
                "No response from radio at any baud rate. Check the radio is powered on and the cable is in CAT mode."
            }
        }
    }

    static let cableHints: [CableHint] = [
        CableHint(vendorId: 0x0403, productId: 0x6015, name: "FTDI FT-X",
                  bauds: [38_400, 9_600]),
        CableHint(vendorId: 0x0403, productId: 0x6001, name: "FTDI FT232",
                  bauds: [38_400, 9_600, 19_200]),
        CableHint(vendorId: 0x10C4, productId: 0xEA60, name: "CP2102",
                  bauds: [4_800, 19_200, 9_600, 38_400]),
        CableHint(vendorId: 0x10C4, productId: 0xEA70, name: "CP2105",
                  bauds: [38_400, 4_800, 19_200, 9_600]),
        CableHint(vendorId: 0x1A86, productId: 0x7523, name: "CH340",
                  bauds: [9_600, 19_200, 38_400]),
        CableHint(vendorId: 0x0483, productId: 0x5740, name: "STM32 CDC",
                  bauds: [38_400]),
    ]

    static let defaultBauds: [Int] = [38_400, 9_600, 19_200, 4_800, 115_200]

    /// Candidate baud rates for a port, falling back to `defaultBauds`.
    static func candidateBauds(vendorId: Int?, productId: Int?) -> [Int] {
        guard let vid = vendorId, let pid = productId,
              let hint = cableHints.first(where: { $0.vendorId == vid && $0.productId == pid })
        else {
            return defaultBauds
        }
        logger.info("Cable: \(hint.name)")
        return hint.bauds
    }

    /// Open the port and probe each candidate baud rate. Returns the first
    /// match, or throws `DetectError.noResponse` if nothing answers.
    static func probe(
        portPath: String,
        vendorId: Int?,
        productId: Int?,
        perBaudTimeoutMs: Int = 500
    ) async throws -> Result {
        let bauds = candidateBauds(vendorId: vendorId, productId: productId)
        let port = SerialPort(path: portPath)

        for baud in bauds {
            try openPortSafely(port, baudRate: baud)

            // Settle + drain any stale RX bytes from this/previous baud.
            try? await Task.sleep(for: .milliseconds(200))
            _ = try? port.read(maxBytes: 4_096)

            if let result = try await tryCIV(port: port, baudRate: baud, timeoutMs: perBaudTimeoutMs) {
                port.close()
                return result
            }
            if let result = try await tryKenwood(port: port, baudRate: baud, timeoutMs: perBaudTimeoutMs) {
                port.close()
                return result
            }
            port.close()
        }

        throw DetectError.noResponse
    }

    /// Map a Kenwood `IDxxx` response to a known radio name.
    static func kenwoodIDName(_ rawID: String) -> String? {
        switch rawID {
        case "ID017": "Elecraft K3/KX"
        case "ID019": "Kenwood TS-990"
        case "ID020": "Kenwood TS-480"
        case "ID029": "Kenwood TS-890"
        case "ID0650": "Yaesu FT-891"
        case "ID0840": "Yaesu FTX-1"
        default: nil
        }
    }

    /// Map a CI-V address to a known radio name.
    static func civAddressName(_ address: UInt8) -> String? {
        switch address {
        case 0x70: "Xiegu G90"
        case 0x76: "Xiegu G106"
        case 0x94: "Icom IC-705"
        case 0x98: "Icom IC-7610"
        case 0xA4: "Icom IC-7300"
        default: nil
        }
    }

    // MARK: Private

    private static func openPortSafely(_ port: SerialPort, baudRate: Int) throws {
        port.close()
        do {
            try port.open(
                baudRate: baudRate,
                dataBits: 8, stopBits: 1, parity: .none, flowControl: .none,
                assertDTR: false, assertRTS: false
            )
        } catch {
            throw DetectError.openFailed(error.localizedDescription)
        }
    }
}
