import CarrierWaveData
import Foundation

// MARK: - DescriptionLookup DXCC Data

nonisolated extension DescriptionLookup {
    /// Look up DXCC entity by entity number
    /// Returns entity with name, or nil if not found
    nonisolated static func dxccEntity(forNumber number: Int) -> DXCCEntity? {
        numberLookup[number]
    }

    /// Pre-built lookup table by entity number for O(1) access
    nonisolated static let numberLookup: [Int: DXCCEntity] = {
        var result: [Int: DXCCEntity] = [:]
        for (_, entity) in dxccEntities {
            result[entity.number] = entity
        }
        return result
    }()

    // MARK: - DXCC Entity Database

    /// Official DXCC entities with their numbers
    /// Source: ARRL DXCC List - https://www.arrl.org/files/file/DXCC/DXCC_Current.pdf
    /// Prefixes from ITU allocations and cty.dat
    /// Note: Prefixes are checked longest-first to handle special cases like KH6 before K
    ///
    /// Full list assembled from regional extension files:
    /// - dxccEntitiesAmericas (US, Canada, Mexico, South/Central America, Caribbean)
    /// - dxccEntitiesEurope (Western, Eastern, Scandinavia, etc.)
    /// - dxccEntitiesAsiaOceania (East/South/Southeast Asia, Oceania)
    /// - dxccEntitiesAfricaOther (Africa, Middle East, Atlantic, special entities)
    nonisolated static let dxccEntities: [(prefixes: [String], entity: DXCCEntity)] =
        dxccEntitiesAmericas
            + dxccEntitiesEurope
            + dxccEntitiesAsiaOceania
            + dxccEntitiesAfricaOther
}
