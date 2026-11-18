import Foundation

// MARK: - Radio port pairing

/// The power switch is paired with the radio's CAT port so Power On can bring
/// up comms with the radio it just turned on. Power is only usable when both
/// halves of the pair are set.
extension RadioPowerController {
    static let radioPortPathKey = "radioPower.radioPortPath"
    static let connectAttempts = 4
    static let connectRetryDelay: Duration = .seconds(2)

    /// Ports that can't be a radio's CAT port.
    nonisolated static let systemPortNames = ["debug-console", "Bluetooth-Incoming-Port"]

    /// Ports the user can pair as the radio: everything except the power
    /// switch candidates and macOS system ports.
    func radioPortChoices(
        in ports: [SerialPortMonitor.SerialPortInfo]
    ) -> [SerialPortMonitor.SerialPortInfo] {
        ports.filter { port in
            port.path != powerPortPath
                && !candidates.contains(port.path)
                && !Self.systemPortNames.contains { port.path.hasSuffix($0) }
        }
    }

    /// The paired radio port, if it is plugged in.
    func radioPort(in ports: [SerialPortMonitor.SerialPortInfo]) -> SerialPortMonitor.SerialPortInfo? {
        guard let radioPortPath else {
            return nil
        }
        return ports.first { $0.path == radioPortPath }
    }

    /// Connect the paired radio after power-on. Uses the profile saved from a
    /// previous connection on this same port, otherwise autodetects. (Saved
    /// profiles are keyed by device fingerprint, which can be shared by
    /// several ports, so the path check keeps another device's profile out.)
    /// Retries while the radio finishes booting. Returns the profile name.
    func connectPairedRadio(
        port: SerialPortMonitor.SerialPortInfo,
        radioManager: RadioManager
    ) async throws -> String {
        var lastError: Error?
        for attempt in 1 ... Self.connectAttempts {
            do {
                var profile: RadioProfile
                if let saved = radioManager.loadProfile(for: port.deviceFingerprint),
                   saved.serialPortPath == port.path
                {
                    profile = saved
                } else {
                    let result = try await RadioAutoDetect.probe(
                        portPath: port.path, vendorId: port.vendorId, productId: port.productId
                    )
                    profile = result.toProfile(portPath: port.path)
                }
                profile.serialPortPath = port.path
                _ = try await radioManager.connect(profile: profile, port: port)
                return profile.name
            } catch {
                lastError = error
                radioManager.appendConnectionLog(
                    "Power: connect attempt \(attempt) failed: \(error.localizedDescription)"
                )
                if attempt < Self.connectAttempts {
                    try? await Task.sleep(for: Self.connectRetryDelay)
                }
            }
        }
        throw lastError ?? RadioAutoDetect.DetectError.noResponse
    }
}
