import Foundation

// MARK: - RadioService Key Namespace

extension RadioService {
    /// UserDefaults / Keychain key constants for radio configuration.
    enum Keys {
        static let transportType = "radio.transportType"
        static let savedDeviceName = "bleRadio.savedDeviceName"
        static let savedDeviceUUID = "bleRadio.savedDeviceUUID"
        static let rigAddress = "bleRadio.rigAddress"
        static let rigProtocol = "bleRadio.rigProtocol"
        static let wifiIPAddress = "radio.wifi.ipAddress"
        static let wifiKeychainUsername = "icomWifi.username"
        static let wifiKeychainPassword = "icomWifi.password"
        static let flexIPAddress = "radio.flex.ipAddress"
        static let flexPort = "radio.flex.port"
        static let flexSliceIndex = "radio.flex.sliceIndex"
        static let flexUseSmartLink = "radio.flex.useSmartLink"
        static let smartLinkEmail = "smartlink.email"
        static let smartLinkKeychainRefreshToken = "smartlink.refreshToken"
        static let sculan10IPAddress = "radio.sculan10.ipAddress"
        static let sculan10Port = "radio.sculan10.port"
        static let sculan10KeychainUsername = "sculan10.username"
        static let sculan10KeychainPassword = "sculan10.password"
    }
}
