import CarrierWaveData

extension QSO {
    /// DXCC entity for this QSO (from LoTW when available)
    nonisolated var dxccEntity: DXCCEntity? {
        if let dxcc {
            return DescriptionLookup.dxccEntity(forNumber: dxcc)
        }
        return nil
    }

    /// Check if this is likely a US station (for state counting)
    nonisolated var isUSStation: Bool {
        dxccEntity?.number == 291
    }
}
