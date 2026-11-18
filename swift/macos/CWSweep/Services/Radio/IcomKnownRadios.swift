import CarrierWaveData
import Foundation

// MARK: - IcomLANCredentials

/// Network User ID + password for an Icom radio's RS-BA1 login.
struct IcomLANCredentials: Codable, Equatable {
    let username: String
    let password: String
}

// MARK: - IcomKnownRadios

/// Icom LAN radios this Mac has logged into before, keyed by host. The model
/// (`IcomRadioInfo`, learned at login) lives in UserDefaults so discovery can
/// say "Found IC-9700"; the login itself lives in the Keychain.
enum IcomKnownRadios {
    // MARK: Internal

    static func info(for host: String) -> IcomRadioInfo? {
        all()[host]
    }

    /// Hosts we've logged into before; discovery probes these hardest.
    static func knownHosts() -> [String] {
        Array(all().keys)
    }

    static func remember(_ info: IcomRadioInfo, host: String) {
        var radios = all()
        radios[host] = info
        if let data = try? JSONEncoder().encode(radios) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    static func credentials(for host: String) -> IcomLANCredentials? {
        guard let data = try? KeychainHelper.shared.read(for: keychainKey(host)) else {
            return nil
        }
        return try? JSONDecoder().decode(IcomLANCredentials.self, from: data)
    }

    static func saveCredentials(_ credentials: IcomLANCredentials, host: String) {
        guard let data = try? JSONEncoder().encode(credentials) else {
            return
        }
        try? KeychainHelper.shared.save(data, for: keychainKey(host))
    }

    static func forgetCredentials(host: String) {
        try? KeychainHelper.shared.delete(for: keychainKey(host))
    }

    // MARK: Private

    private static let defaultsKey = "icomLAN.knownRadios"

    private static func all() -> [String: IcomRadioInfo] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: IcomRadioInfo].self, from: data)) ?? [:]
    }

    private static func keychainKey(_ host: String) -> String {
        "icom.lan.credentials.\(host)"
    }
}

// MARK: - RadioModel + Icom LAN

extension RadioModel {
    /// The known LAN/WiFi model with this CI-V address (IC-9700 → `ic9700-lan`,
    /// which the satellite duplex code keys off), else an ad-hoc model named
    /// after what the radio reported.
    static func icomLAN(_ info: IcomRadioInfo) -> RadioModel {
        if let known = knownModels.first(where: {
            $0.protocolType == .icomWiFi && $0.civAddress == info.civAddress
        }) {
            return known
        }
        let name = info.name.isEmpty ? String(format: "Icom (CI-V %02X)", info.civAddress) : info.name
        return RadioModel(
            id: String(format: "icom-lan-%02x", info.civAddress),
            name: name,
            manufacturer: "Icom",
            protocolType: .icomWiFi,
            defaultBaudRate: 0,
            civAddress: info.civAddress,
            dtrDefault: false,
            rtsDefault: false
        )
    }
}
