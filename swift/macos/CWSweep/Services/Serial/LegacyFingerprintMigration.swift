import Foundation

// MARK: - LegacyFingerprintMigration

/// Moves settings saved under the old blank device fingerprint (`0-0-`) to
/// each device's real fingerprint.
///
/// `SerialPortMonitor` used to read the USB IDs off the serial node instead of
/// its parent USB device, so every port got `0-0-` and devices overwrote each
/// other's saved radio profile, last-used slot radio, and WinKeyer. The saved
/// radio profile records its port path, so it can be moved to the right
/// device once that port is plugged in. The WinKeyer saved no path, so its
/// blank fingerprint is dropped and the next manual connect saves a real one.
enum LegacyFingerprintMigration {
    // MARK: Internal

    static let blank = "0-0-"
    static let profileKey = "radio.savedProfile.\(blank)"
    static let legacyRadioKey = "radio.lastDeviceFingerprint"
    static let winKeyerKey = "winkeyer.lastDeviceFingerprint"
    static let nicknamesKey = "serial.portNicknames"

    static var slotKeys: [String] {
        RadioSlot.allCases.map { "radio.slot.\($0.rawValue).lastDeviceFingerprint" } + [legacyRadioKey]
    }

    static func run(ports: [SerialPortMonitor.SerialPortInfo], defaults: UserDefaults = .standard) {
        migrateRadio(ports: ports, defaults: defaults)

        if defaults.string(forKey: winKeyerKey) == blank {
            defaults.removeObject(forKey: winKeyerKey)
        }
        if var nicknames = defaults.dictionary(forKey: nicknamesKey),
           nicknames.removeValue(forKey: blank) != nil
        {
            defaults.set(nicknames, forKey: nicknamesKey)
        }
    }

    // MARK: Private

    private static func migrateRadio(ports: [SerialPortMonitor.SerialPortInfo], defaults: UserDefaults) {
        let blankSlotKeys = slotKeys.filter { defaults.string(forKey: $0) == blank }
        guard let data = defaults.data(forKey: profileKey) else {
            // Nothing to move them to; the next connect records a real one.
            blankSlotKeys.forEach { defaults.removeObject(forKey: $0) }
            return
        }
        guard let profile = try? JSONDecoder().decode(RadioProfile.self, from: data) else {
            defaults.removeObject(forKey: profileKey)
            blankSlotKeys.forEach { defaults.removeObject(forKey: $0) }
            return
        }
        // Wait until the radio's port is plugged in to learn its fingerprint.
        guard let port = ports.first(where: { $0.path == profile.serialPortPath }),
              port.deviceFingerprint != blank
        else {
            return
        }
        let newKey = "radio.savedProfile.\(port.deviceFingerprint)"
        if defaults.data(forKey: newKey) == nil {
            defaults.set(data, forKey: newKey)
        }
        for key in blankSlotKeys {
            defaults.set(port.deviceFingerprint, forKey: key)
        }
        defaults.removeObject(forKey: profileKey)
    }
}
