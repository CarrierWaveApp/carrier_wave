import CarrierWaveData
import Foundation
import IOKit
import IOKit.serial

// MARK: - RadioPowerController

/// Drives a USB radio power switch: a CH340 USB-serial adapter whose DTR line
/// pulls the radio's POWER ON input (K3 ACC connector) low. Power-on is a
/// short DTR pulse on that adapter; power-off is `PS0;` over CAT to the
/// connected Elecraft, since the switch can only turn the radio on.
@MainActor
@Observable
final class RadioPowerController {
    // MARK: Internal

    enum Status: Equatable {
        case idle
        case notFound
        case chooseDevice
        case found
        case poweringOn
        case connecting
        case done(String)
        case poweringOff
        case error(String)
    }

    /// Result of matching CH340 ports against the remembered choice.
    enum Selection: Equatable {
        case none
        case one(String)
        case many([String])
    }

    static let vendorId = 0x1A86
    static let productId = 0x7523
    static let pulseDuration: Duration = .milliseconds(500)
    static let bootDelay: Duration = .seconds(4)
    static let answerTimeout: Duration = .seconds(6)

    private(set) var status: Status = .idle
    private(set) var candidates: [String] = []

    /// The adapter used for power-on. Setting it remembers the choice.
    var powerPortPath: String? {
        didSet {
            UserDefaults.standard.set(powerPortPath, forKey: Self.rememberedPortKey)
        }
    }

    var isBusy: Bool {
        switch status {
        case .poweringOn,
             .connecting,
             .poweringOff: true
        default: false
        }
    }

    /// Pick the power adapter: the remembered port if it is still present,
    /// otherwise the only candidate, otherwise ask the user.
    nonisolated static func choosePort(candidates: [String], remembered: String?) -> Selection {
        if let remembered, candidates.contains(remembered) {
            return .one(remembered)
        }
        switch candidates.count {
        case 0: return .none
        case 1: return .one(candidates[0])
        default: return .many(candidates.sorted())
        }
    }

    /// USB vendor/product IDs keyed by /dev/cu.* path. The IDs live on the
    /// parent USB device, so search up the registry from each serial client.
    nonisolated static func usbIDsByCalloutPath() -> [String: (vendor: Int, product: Int)] {
        var result: [String: (vendor: Int, product: Int)] = [:]
        let matching = IOServiceMatching(kIOSerialBSDServiceValue)
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return result
        }
        defer { IOObjectRelease(iterator) }

        let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            guard let path = IORegistryEntryCreateCFProperty(
                      service, kIOCalloutDeviceKey as CFString, kCFAllocatorDefault, 0
                  )?.takeRetainedValue() as? String,
                  let vendor = IORegistryEntrySearchCFProperty(
                      service, kIOServicePlane, "idVendor" as CFString, kCFAllocatorDefault, options
                  ) as? Int,
                  let product = IORegistryEntrySearchCFProperty(
                      service, kIOServicePlane, "idProduct" as CFString, kCFAllocatorDefault, options
                  ) as? Int
            else {
                continue
            }
            result[path] = (vendor, product)
        }
        return result
    }

    /// Assert DTR for `duration`, then release it. DTR is released before the
    /// port closes so the radio's POWER ON line is never left held low.
    nonisolated static func pulseDTR(path: String, duration: Duration) async throws {
        let port = SerialPort(path: path)
        try port.open(baudRate: 9_600, assertDTR: false, assertRTS: false)
        defer {
            try? port.setDTR(false)
            port.close()
        }
        try port.setDTR(true)
        try? await Task.sleep(for: duration)
        try port.setDTR(false)
    }

    /// Find CH340 adapters that are not in use as a radio port.
    func detect(radioManager: RadioManager) {
        let ids = Self.usbIDsByCalloutPath()
        candidates = ids
            .filter { $0.value.vendor == Self.vendorId && $0.value.product == Self.productId }
            .map(\.key)
            .filter { radioManager.slotForPortPath($0) == nil }
            .sorted()

        let remembered = UserDefaults.standard.string(forKey: Self.rememberedPortKey)
        switch Self.choosePort(candidates: candidates, remembered: remembered) {
        case .none:
            status = .notFound
        case let .one(path):
            powerPortPath = path
            status = .found
        case .many:
            status = .chooseDevice
        }
    }

    /// Pulse the power switch, wait for the radio to boot, then reconnect the
    /// radio last used in slot A and wait for it to answer.
    func powerOn(radioManager: RadioManager, ports: [SerialPortMonitor.SerialPortInfo]) async {
        guard let path = powerPortPath else {
            status = .notFound
            return
        }
        status = .poweringOn
        radioManager.appendConnectionLog("Power: DTR pulse on \(path)")
        do {
            try await Self.pulseDTR(path: path, duration: Self.pulseDuration)
        } catch {
            status = .error("Power pulse failed: \(error.localizedDescription)")
            return
        }

        guard let fingerprint = radioManager.lastFingerprint(for: .a),
              let port = ports.first(where: { $0.deviceFingerprint == fingerprint }),
              port.path != path,
              var profile = radioManager.loadProfile(for: fingerprint)
        else {
            status = .done("Power pulse sent. Click Connect on the radio's port.")
            return
        }
        if radioManager.slotForPortPath(port.path) != nil {
            status = .done("Power pulse sent. \(profile.name) is already connected.")
            return
        }

        status = .connecting
        try? await Task.sleep(for: Self.bootDelay)
        profile.serialPortPath = port.path
        do {
            _ = try await radioManager.connect(profile: profile, port: port)
        } catch {
            status = .error("Radio powered on, but connecting failed: \(error.localizedDescription)")
            return
        }

        let deadline = ContinuousClock.now + Self.answerTimeout
        while radioManager.frequency <= 0, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(250))
        }
        status = if radioManager.frequency > 0 {
            .done(String(format: "%@ is on (%.3f MHz)", profile.name, radioManager.frequency))
        } else {
            .done("Connected to \(profile.name), but it hasn't answered yet")
        }
    }

    /// The connected Elecraft session, if any. Power-off only works over CAT.
    func elecraftSessionId(radioManager: RadioManager) -> UUID? {
        guard let slot = radioManager.slotStates
            .first(where: { $0.value.profile.protocolType == .elecraft })?.key
        else {
            return nil
        }
        return radioManager.slots[slot]
    }

    /// Send `PS0;` to the connected Elecraft, then disconnect it.
    func powerOff(radioManager: RadioManager) async {
        guard let id = elecraftSessionId(radioManager: radioManager),
              let session = radioManager.sessions[id]
        else {
            status = .error("No Elecraft radio is connected")
            return
        }
        status = .poweringOff
        radioManager.appendConnectionLog("Power: sending PS0;")
        do {
            try await session.sendRaw(Data("PS0;".utf8))
        } catch {
            status = .error("Power off failed: \(error.localizedDescription)")
            return
        }
        await radioManager.disconnect(id: id)
        status = .done("Radio powered off")
    }

    // MARK: Private

    private static let rememberedPortKey = "radioPower.portPath"
}
