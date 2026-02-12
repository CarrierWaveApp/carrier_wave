import CarrierWaveCore
import Foundation

/// App-specific convenience factory for LoFiClient
@MainActor
extension LoFiClient {
    static func appDefault() -> LoFiClient {
        LoFiClient(
            credentials: KeychainCredentialStore(),
            logger: SyncDebugLogAdapter()
        )
    }
}
