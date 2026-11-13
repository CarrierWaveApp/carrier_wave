// FlexProtocolHandler is now provided by CarrierWaveData.
// This file re-exports it and adds CWSweep-specific convenience.

import CarrierWaveData
import Foundation

extension FlexProtocolHandler {
    /// CWSweep-specific client setup command with hardcoded program name.
    func encodeClientSetupForSweep() -> Data {
        encodeClientSetup(programName: "CWSweep")
    }
}
