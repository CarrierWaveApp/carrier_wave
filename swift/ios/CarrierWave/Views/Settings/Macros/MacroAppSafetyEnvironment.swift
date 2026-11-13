import CarrierWaveCore
import CarrierWaveData
import UIKit

// MARK: - MacroAppSafetyEnvironment

/// Production `MacroSafetyEnvironment` for the iOS app. Reads radio
/// protocol from `RadioService` and region from `UserRegionProfile`.
/// Phase 1 keeps `globalInhibitTx` off and `sessionAllowsTx` on — the
/// settings + arm UI ship later.
struct MacroAppSafetyEnvironment: MacroSafetyEnvironment {
    var connectedProtocol: RadioCommandProtocol? {
        get async {
            await MainActor.run {
                guard RadioService.shared.isConnected else {
                    return nil
                }
                switch RadioService.shared.rigProtocol {
                case .civ: return .civ
                case .kenwood: return .kenwood
                }
            }
        }
    }

    var sessionAllowsTx: Bool {
        get async { true }
    }

    var globalInhibitTx: Bool {
        get async {
            await MainActor.run {
                UserDefaults.standard.bool(forKey: "macroGlobalInhibitTx")
            }
        }
    }

    var deviceRegion: String {
        get async {
            await MainActor.run {
                switch UserRegionProfile.primaryIARURegion {
                case .region1: "R1"
                case .region2: "R2"
                case .region3: "R3"
                case .none: "R2"
                }
            }
        }
    }
}
