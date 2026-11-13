import Foundation

// MARK: - DXCC Americas Region Data

nonisolated public extension DescriptionLookup {
    /// DXCC entities for US, Canada, Mexico, South/Central America, Caribbean
    nonisolated(unsafe) static let dxccEntitiesAmericas: [(prefixes: [String], entity: DXCCEntityRef)] = [
        // ==================== US & Territories ====================
        // US Territories (must check before general US prefixes)
        (["KG4"], DXCCEntityRef(number: 105, name: "Guantanamo Bay")),
        (["KH0", "AH0", "NH0", "WH0"], DXCCEntityRef(number: 166, name: "Mariana Is.")),
        (["KH1", "AH1", "NH1", "WH1"], DXCCEntityRef(number: 20, name: "Baker & Howland Is.")),
        (["KH2", "AH2", "NH2", "WH2"], DXCCEntityRef(number: 103, name: "Guam")),
        (["KH3", "AH3", "NH3", "WH3"], DXCCEntityRef(number: 123, name: "Johnston I.")),
        (["KH4", "AH4", "NH4", "WH4"], DXCCEntityRef(number: 174, name: "Midway I.")),
        (["KH5K"], DXCCEntityRef(number: 138, name: "Kure I.")),
        (["KH5", "AH5", "NH5", "WH5"], DXCCEntityRef(number: 197, name: "Palmyra & Jarvis Is.")),
        (
            ["KH6", "KH7", "AH6", "AH7", "NH6", "NH7", "WH6", "WH7"],
            DXCCEntityRef(number: 110, name: "Hawaii")
        ),
        (["KH8S", "AH8S", "NH8S", "WH8S"], DXCCEntityRef(number: 515, name: "Swains I.")),
        (["KH8", "AH8", "NH8", "WH8"], DXCCEntityRef(number: 9, name: "American Samoa")),
        (["KH9", "AH9", "NH9", "WH9"], DXCCEntityRef(number: 297, name: "Wake I.")),
        (
            ["KL7", "KL", "AL7", "AL", "NL7", "NL", "WL7", "WL"],
            DXCCEntityRef(number: 6, name: "Alaska")
        ),
        (["KP1", "NP1", "WP1"], DXCCEntityRef(number: 182, name: "Navassa I.")),
        (["KP2", "NP2", "WP2"], DXCCEntityRef(number: 285, name: "Virgin Is.")),
        (["KP3", "KP4", "NP3", "NP4", "WP3", "WP4"], DXCCEntityRef(number: 202, name: "Puerto Rico")),
        (["KP5", "NP5", "WP5"], DXCCEntityRef(number: 43, name: "Desecheo I.")),

        // USA (general - checked after territories)
        (
            ["K", "W", "N", "AA", "AB", "AC", "AD", "AE", "AF", "AG", "AI", "AJ", "AK"],
            DXCCEntityRef(number: 291, name: "United States of America")
        ),

        // ==================== Canada ====================
        (["VE", "VA", "VO", "VY", "CY", "CZ"], DXCCEntityRef(number: 1, name: "Canada")),

        // ==================== Mexico ====================
        (
            [
                "XE", "XA", "XB", "XC", "XD", "XF", "4A", "4B", "4C", "6D", "6E", "6F", "6G", "6H",
                "6I", "6J",
            ],
            DXCCEntityRef(number: 50, name: "Mexico")
        ),
        (["XF4"], DXCCEntityRef(number: 204, name: "Revillagigedo")),

        // ==================== South America ====================
        (["PP0F", "PY0F"], DXCCEntityRef(number: 56, name: "Fernando de Noronha")),
        (["PP0S", "PY0S"], DXCCEntityRef(number: 253, name: "St. Peter & St. Paul Rocks")),
        (["PP0T", "PY0T"], DXCCEntityRef(number: 273, name: "Trindade & Martim Vaz Is.")),
        (
            [
                "PP", "PQ", "PR", "PS", "PT", "PU", "PV", "PW", "PX", "PY", "ZV", "ZW", "ZX", "ZY",
                "ZZ",
            ], DXCCEntityRef(number: 108, name: "Brazil")
        ),
        (
            [
                "LU", "AY", "AZ", "L2", "L3", "L4", "L5", "L6", "L7", "L8", "L9", "LO", "LP", "LQ",
                "LR", "LS", "LT", "LV", "LW",
            ], DXCCEntityRef(number: 100, name: "Argentina")
        ),
        (["CE", "CA", "CB", "CC", "CD", "XQ", "XR", "3G"], DXCCEntityRef(number: 112, name: "Chile")),
        (["HK", "5J", "5K"], DXCCEntityRef(number: 116, name: "Colombia")),
        (["HK0M"], DXCCEntityRef(number: 161, name: "Malpelo I.")),
        (["HK0"], DXCCEntityRef(number: 216, name: "San Andres & Providencia")),
        (["YV0"], DXCCEntityRef(number: 17, name: "Aves I.")),
        (["YV", "4M"], DXCCEntityRef(number: 148, name: "Venezuela")),
        (["HC", "HD"], DXCCEntityRef(number: 120, name: "Ecuador")),
        (["HC8", "HD8"], DXCCEntityRef(number: 71, name: "Galapagos Is.")),
        (["OA", "OB", "OC", "4T"], DXCCEntityRef(number: 136, name: "Peru")),
        (["CP"], DXCCEntityRef(number: 104, name: "Bolivia")),
        (["ZP"], DXCCEntityRef(number: 132, name: "Paraguay")),
        (["CX"], DXCCEntityRef(number: 144, name: "Uruguay")),
        (["8R"], DXCCEntityRef(number: 129, name: "Guyana")),
        (["PZ"], DXCCEntityRef(number: 140, name: "Suriname")),
        (["FY"], DXCCEntityRef(number: 63, name: "French Guiana")),

        // ==================== Central America ====================
        (["HR"], DXCCEntityRef(number: 80, name: "Honduras")),
        (["YS", "HU"], DXCCEntityRef(number: 74, name: "El Salvador")),
        (["TG"], DXCCEntityRef(number: 76, name: "Guatemala")),
        (["TI", "TE"], DXCCEntityRef(number: 308, name: "Costa Rica")),
        (["TI9"], DXCCEntityRef(number: 37, name: "Cocos I.")),
        (["HP", "HO", "H3", "H8", "H9"], DXCCEntityRef(number: 88, name: "Panama")),
        (["YN", "H7", "HT"], DXCCEntityRef(number: 86, name: "Nicaragua")),
        (["V3"], DXCCEntityRef(number: 66, name: "Belize")),

        // ==================== Caribbean ====================
        (["HI"], DXCCEntityRef(number: 72, name: "Dominican Republic")),
        (["HH"], DXCCEntityRef(number: 78, name: "Haiti")),
        (["CO", "CM", "CL", "T4"], DXCCEntityRef(number: 70, name: "Cuba")),
        (["6Y"], DXCCEntityRef(number: 82, name: "Jamaica")),
        (["ZF"], DXCCEntityRef(number: 69, name: "Cayman Is.")),
        (["C6"], DXCCEntityRef(number: 60, name: "Bahamas")),
        (["VP5"], DXCCEntityRef(number: 89, name: "Turks & Caicos Is.")),
        (["VP9"], DXCCEntityRef(number: 64, name: "Bermuda")),
        (["VP2E", "V2"], DXCCEntityRef(number: 94, name: "Antigua & Barbuda")),
        (["VP2M"], DXCCEntityRef(number: 96, name: "Montserrat")),
        (["VP2A"], DXCCEntityRef(number: 12, name: "Anguilla")),
        (["VP2V"], DXCCEntityRef(number: 65, name: "British Virgin Is.")),
        (["8P"], DXCCEntityRef(number: 62, name: "Barbados")),
        (["J3"], DXCCEntityRef(number: 77, name: "Grenada")),
        (["J6"], DXCCEntityRef(number: 97, name: "St. Lucia")),
        (["J7"], DXCCEntityRef(number: 95, name: "Dominica")),
        (["J8"], DXCCEntityRef(number: 98, name: "St. Vincent")),
        (["V4"], DXCCEntityRef(number: 249, name: "St. Kitts & Nevis")),
        (["9Y", "9Z"], DXCCEntityRef(number: 90, name: "Trinidad & Tobago")),
        (["PJ2"], DXCCEntityRef(number: 517, name: "Curacao")),
        (["PJ4"], DXCCEntityRef(number: 520, name: "Bonaire")),
        (["PJ5", "PJ6"], DXCCEntityRef(number: 519, name: "Saba & St. Eustatius")),
        (["PJ7"], DXCCEntityRef(number: 518, name: "Sint Maarten")),
        (["P4"], DXCCEntityRef(number: 91, name: "Aruba")),
        (["FG"], DXCCEntityRef(number: 79, name: "Guadeloupe")),
        (["FS"], DXCCEntityRef(number: 213, name: "Saint Martin")),
        (["FJ"], DXCCEntityRef(number: 516, name: "Saint Barthelemy")),
        (["FM"], DXCCEntityRef(number: 84, name: "Martinique")),
        (["FP"], DXCCEntityRef(number: 277, name: "St. Pierre & Miquelon")),

        // ==================== Atlantic Islands (Americas) ====================
        (["CY0"], DXCCEntityRef(number: 211, name: "Sable I.")),
        (["CY9"], DXCCEntityRef(number: 252, name: "St. Paul I.")),
        (["VP8/F", "VP8F"], DXCCEntityRef(number: 141, name: "Falkland Is.")),
        (["VP8/G", "VP8G"], DXCCEntityRef(number: 235, name: "South Georgia I.")),
        (["VP8/O", "VP8O"], DXCCEntityRef(number: 238, name: "South Orkney Is.")),
        (["VP8/H", "VP8H"], DXCCEntityRef(number: 240, name: "South Sandwich Is.")),
        (["VP8/S", "VP8S"], DXCCEntityRef(number: 241, name: "South Shetland Is.")),
        (["CE9", "VP8"], DXCCEntityRef(number: 13, name: "Antarctica")),
        (["CE0X"], DXCCEntityRef(number: 217, name: "San Felix & San Ambrosio")),
        (["CE0Y"], DXCCEntityRef(number: 47, name: "Easter I.")),
        (["CE0Z"], DXCCEntityRef(number: 125, name: "Juan Fernandez Is.")),
    ]
}
