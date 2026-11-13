import CarrierWaveData
import Foundation

// MARK: - RadioService + EquipmentItem Profile

extension RadioService {
    /// Connect using a profile loaded from an `EquipmentItem`.
    ///
    /// Applies the profile to the singleton's stored state (so the
    /// existing transport-specific connect paths work unchanged), then
    /// kicks off `connectToSavedDevice()`. Today this still mutates the
    /// global `UserDefaults`/Keychain keys — phase 4 of the unified
    /// equipment plan will lift those onto the item directly.
    func connect(toItem snapshot: EquipmentInventorySnapshot) {
        guard let profile = snapshot.connectionProfile, profile.isConfigured else {
            addLog(.info, "No connection profile on \(snapshot.displayName)")
            return
        }
        apply(profile: profile, owningItemID: snapshot.id, displayName: snapshot.displayName)
        connectToSavedDevice()
    }

    /// Apply a profile to the singleton's mutable state without
    /// initiating a connect. Useful for previewing the active radio.
    func apply(
        profile: RadioConnectionProfile,
        owningItemID _: UUID,
        displayName: String
    ) {
        switch profile.transport {
        case .ble:
            transportType = .ble
            if let uuid = profile.bleDeviceUUID {
                UserDefaults.standard.set(
                    uuid.uuidString, forKey: Keys.savedDeviceUUID
                )
            }
            if let name = profile.bleDeviceName {
                UserDefaults.standard.set(name, forKey: Keys.savedDeviceName)
            }

        case .wifi:
            transportType = .wifi
            wifiIPAddress = profile.hostAddress
            if let civAddress = profile.civAddress {
                UserDefaults.standard.set(
                    Int(civAddress), forKey: Keys.rigAddress
                )
            }

        case .flex:
            transportType = .flex
            flexIPAddress = profile.hostAddress
            if let port = profile.port {
                flexPort = UInt16(port)
            }
            if let slice = profile.flexSliceIndex {
                flexSliceIndex = slice
            }
            useSmartLink = profile.useSmartLink

        case .scuLan10:
            transportType = .scuLan10
            sculan10IPAddress = profile.hostAddress
            if let port = profile.port {
                sculan10Port = UInt16(port)
            }
        }

        if let proto = profile.protocolKind {
            rigProtocol = proto == .civ ? .civ : .kenwood
        }

        addLog(.info, "Loaded profile for \(displayName) — \(profile.summary)")
    }

    /// Capture the current global radio state as a profile suitable for
    /// attaching to an `EquipmentItem`. Used by the per-item connection
    /// sheet when migrating in the user's current settings.
    func currentProfileSnapshot() -> RadioConnectionProfile? {
        switch transportType {
        case .ble:
            guard let uuid = savedDeviceUUID else {
                return nil
            }
            return RadioConnectionProfile(
                transport: .ble,
                protocolKind: rigProtocol == .civ ? .civ : .kenwood,
                bleDeviceUUID: uuid,
                bleDeviceName: savedDeviceName,
                bleViaBridge: false
            )
        case .wifi:
            guard let host = wifiIPAddress, !host.isEmpty else {
                return nil
            }
            return RadioConnectionProfile(
                transport: .wifi,
                protocolKind: .civ,
                hostAddress: host,
                civAddress: configuredRigAddress
            )
        case .flex:
            guard let host = flexIPAddress, !host.isEmpty else {
                return nil
            }
            return RadioConnectionProfile(
                transport: .flex,
                protocolKind: nil,
                hostAddress: host,
                port: Int(flexPort),
                flexSliceIndex: flexSliceIndex,
                useSmartLink: useSmartLink
            )
        case .scuLan10:
            guard let host = sculan10IPAddress, !host.isEmpty else {
                return nil
            }
            return RadioConnectionProfile(
                transport: .scuLan10,
                protocolKind: nil,
                hostAddress: host,
                port: Int(sculan10Port)
            )
        }
    }
}
