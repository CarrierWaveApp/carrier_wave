import Foundation

// MARK: - DescriptionLookup DXCC Data

nonisolated public extension DescriptionLookup {
    /// Look up DXCC entity by entity number
    /// Returns entity with name, or nil if not found
    nonisolated static func dxccEntity(forNumber number: Int) -> DXCCEntityRef? {
        numberLookup[number]
    }

    /// Pre-built lookup table by entity number for O(1) access
    nonisolated(unsafe) static let numberLookup: [Int: DXCCEntityRef] = {
        var result: [Int: DXCCEntityRef] = [:]
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
    nonisolated(unsafe) static let dxccEntities: [(prefixes: [String], entity: DXCCEntityRef)] =
        dxccEntitiesAmericas
            + dxccEntitiesEurope
            + dxccEntitiesAsiaOceania
            + dxccEntitiesAfricaOther
}
