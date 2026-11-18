import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "USBRadioDiscovery")

// MARK: - DetectedUSBRadio

/// A radio that answered the autodetect probe on a USB serial port.
struct DetectedUSBRadio: Identifiable {
    let port: SerialPortMonitor.SerialPortInfo
    let result: RadioAutoDetect.Result

    var id: String {
        port.path
    }

    var displayName: String {
        result.radioName ?? "\(result.protocolType.rawValue) radio"
    }
}

// MARK: - USBRadioDiscovery

/// USB counterpart of `IcomDiscoveryService`. Each time a USB serial port
/// appears (at launch, plug-in, or a radio powering up its built-in USB) it
/// is probed once with `RadioAutoDetect`. If a radio answers:
/// - on a port with a saved profile (connected there before) it reconnects,
///   in the slot it last used;
/// - otherwise it is listed in `found` for the "Found … on USB. Connect?"
///   banner.
/// Probing first means a powered-off radio behind an always-present cable
/// (FTDI, CH340) isn't "connected" with nothing answering, which would also
/// make the power switch's Power On think the radio is already up.
///
/// Never touched: ports already in a radio session, the radio power switch
/// (a CH340 whose DTR powers the radio on), the WinKeyer, and non-USB ports
/// (Bluetooth, debug console).
@MainActor
@Observable
final class USBRadioDiscovery {
    // MARK: Internal

    private(set) var found: [DetectedUSBRadio] = []
    private(set) var probingPath: String?

    /// Handle the current port list. Re-entrant calls while a pass is
    /// running are coalesced into one follow-up pass with the latest list.
    func portsChanged(_ ports: [SerialPortMonitor.SerialPortInfo], manager: RadioManager) async {
        let present = Set(ports.map(\.path))
        handled.formIntersection(present)
        found.removeAll { !present.contains($0.port.path) }

        guard !isRunning else {
            pendingPorts = ports
            return
        }
        isRunning = true
        for port in ports where !handled.contains(port.path) && !isExcluded(port, manager: manager) {
            handled.insert(port.path)
            guard let result = await probe(port: port, manager: manager) else {
                continue
            }
            if let profile = manager.loadProfile(for: port.deviceFingerprint) {
                await reconnect(port: port, profile: profile, manager: manager)
            } else {
                found.append(DetectedUSBRadio(port: port, result: result))
            }
        }
        isRunning = false

        if let next = pendingPorts {
            pendingPorts = nil
            await portsChanged(next, manager: manager)
        }
    }

    /// Forget a found radio (banner dismissed or connected).
    func dismiss(path: String) {
        found.removeAll { $0.port.path == path }
    }

    // MARK: Private

    /// UserDefaults key `RadioPowerController` remembers its switch under.
    private static let powerSwitchKey = "radioPower.portPath"

    /// Paths already reconnected or probed since they last appeared.
    @ObservationIgnored private var handled: Set<String> = []
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var pendingPorts: [SerialPortMonitor.SerialPortInfo]?

    private func isExcluded(_ port: SerialPortMonitor.SerialPortInfo, manager: RadioManager) -> Bool {
        if port.vendorId == nil || manager.slotForPortPath(port.path) != nil {
            return true
        }
        if port.path == UserDefaults.standard.string(forKey: Self.powerSwitchKey) {
            return true
        }
        let winKeyer = SharedEnvironment.shared.winKeyerManager
        return port.path == winKeyer.connectedPortPath
            || port.deviceFingerprint == winKeyer.lastDeviceFingerprint
    }

    private func reconnect(
        port: SerialPortMonitor.SerialPortInfo,
        profile: RadioProfile,
        manager: RadioManager
    ) async {
        guard manager.nextAvailableSlot() != nil else {
            return
        }
        var profile = profile
        profile.serialPortPath = port.path
        // Prefer the slot this radio last lived in, if it's free.
        let slot = RadioSlot.allCases.first {
            manager.lastFingerprint(for: $0) == port.deviceFingerprint && manager.slots[$0] == nil
        }
        logger.info("Reconnecting known radio \(profile.name, privacy: .public) on \(port.path, privacy: .public)")
        do {
            _ = try await manager.connect(profile: profile, port: port, slot: slot)
        } catch {
            manager.commandLog.append(
                direction: .status,
                text: "Auto-connect \(profile.name) on \(port.name) failed: \(error.localizedDescription)"
            )
        }
    }

    /// Identify the radio on `port`, or nil if nothing answers (or the user
    /// connected the port by hand meanwhile).
    private func probe(
        port: SerialPortMonitor.SerialPortInfo,
        manager: RadioManager
    ) async -> RadioAutoDetect.Result? {
        probingPath = port.path
        defer { probingPath = nil }
        do {
            let result = try await RadioAutoDetect.probe(
                portPath: port.path,
                vendorId: port.vendorId,
                productId: port.productId
            )
            guard manager.slotForPortPath(port.path) == nil else {
                return nil
            }
            logger.info("Found \(result.radioName ?? result.rawID, privacy: .public) on \(port.path, privacy: .public)")
            return result
        } catch {
            logger.info("No radio answering on \(port.path, privacy: .public)")
            return nil
        }
    }
}
