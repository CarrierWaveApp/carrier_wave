import Foundation
import IOKit
import IOKit.serial

/// Monitors USB serial port hot-plug events using IOKit notifications.
@MainActor
@Observable
final class SerialPortMonitor {
    // MARK: Internal

    struct SerialPortInfo: Identifiable, Hashable {
        let id: String
        let path: String
        let name: String
        let vendorId: Int?
        let productId: Int?
        let serialNumber: String?

        /// Stable identifier for a physical USB device (survives unplug/replug).
        var deviceFingerprint: String {
            "\(vendorId ?? 0)-\(productId ?? 0)-\(serialNumber ?? "")"
        }
    }

    private(set) var availablePorts: [SerialPortInfo] = []

    /// Port nicknames keyed by device fingerprint, persisted in UserDefaults.
    private(set) var nicknames: [String: String] = [:] {
        didSet {
            UserDefaults.standard.set(nicknames, forKey: "serial.portNicknames")
        }
    }

    /// Discover all /dev/cu.* serial ports via IOKit
    static func discoverSerialPorts() -> [SerialPortInfo] {
        var ports: [SerialPortInfo] = []

        let matchingDict = IOServiceMatching(kIOSerialBSDServiceValue) as NSMutableDictionary
        matchingDict[kIOSerialBSDTypeKey] = kIOSerialBSDAllTypes

        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        guard result == KERN_SUCCESS else {
            return ports
        }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            if let info = portInfo(from: service) {
                ports.append(info)
            }
        }

        IOObjectRelease(iterator)
        return ports.sorted { $0.name < $1.name }
    }

    func startMonitoring() {
        nicknames = (UserDefaults.standard.dictionary(forKey: "serial.portNicknames") as? [String: String]) ?? [:]
        refreshPorts()
        // IOKit notification setup would go here for hot-plug detection
        // For now, we poll on demand
    }

    /// Returns the nickname for a port, or nil if not set.
    /// Looks up by port path first (unique per port), then falls back to
    /// device fingerprint for backwards compatibility with existing nicknames.
    func nickname(for port: SerialPortInfo) -> String? {
        nicknames[port.id] ?? nicknames[port.deviceFingerprint]
    }

    /// Sets or clears a nickname for a port (keyed by port path for uniqueness).
    func setNickname(_ name: String?, for port: SerialPortInfo) {
        // Remove any legacy fingerprint-based entry to avoid stale duplicates
        nicknames.removeValue(forKey: port.deviceFingerprint)
        if let name, !name.isEmpty {
            nicknames[port.id] = name
        } else {
            nicknames.removeValue(forKey: port.id)
        }
    }

    /// Display name for a port: nickname if set, otherwise USB product name.
    func displayName(for port: SerialPortInfo) -> String {
        nickname(for: port) ?? port.name
    }

    func stopMonitoring() {
        if let port = notificationPort {
            IONotificationPortDestroy(port)
            notificationPort = nil
        }
    }

    func refreshPorts() {
        availablePorts = Self.discoverSerialPorts()
    }

    // MARK: Private

    private var notificationPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0

    private static func portInfo(from service: io_object_t) -> SerialPortInfo? {
        guard let pathCF = IORegistryEntryCreateCFProperty(
            service, kIOCalloutDeviceKey as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? String else {
            return nil
        }

        guard pathCF.hasPrefix("/dev/cu."), !pathCF.contains("Bluetooth") else {
            return nil
        }

        let name = (IORegistryEntryCreateCFProperty(
            service, "USB Product Name" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? String) ?? pathCF.replacingOccurrences(of: "/dev/cu.", with: "")

        let vendorId = IORegistryEntryCreateCFProperty(
            service, "idVendor" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? Int

        let productId = IORegistryEntryCreateCFProperty(
            service, "idProduct" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? Int

        let serialNumber = IORegistryEntryCreateCFProperty(
            service, "USB Serial Number" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? String

        return SerialPortInfo(
            id: pathCF, path: pathCF, name: name,
            vendorId: vendorId, productId: productId, serialNumber: serialNumber
        )
    }
}
