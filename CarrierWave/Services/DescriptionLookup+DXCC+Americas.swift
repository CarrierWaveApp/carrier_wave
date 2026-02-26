import Foundation

// MARK: - DXCC Americas Region Data

nonisolated extension DescriptionLookup {
    /// DXCC entities for US, Canada, Mexico, South/Central America, Caribbean
    nonisolated static let dxccEntitiesAmericas: [(prefixes: [String], entity: DXCCEntity)] = [
        // ==================== US & Territories ====================
        // US Territories (must check before general US prefixes)
        (["KG4"], DXCCEntity(number: 105, name: "Guantanamo Bay")),
        (["KH0", "AH0", "NH0", "WH0"], DXCCEntity(number: 166, name: "Mariana Is.")),
        (["KH1", "AH1", "NH1", "WH1"], DXCCEntity(number: 20, name: "Baker & Howland Is.")),
        (["KH2", "AH2", "NH2", "WH2"], DXCCEntity(number: 103, name: "Guam")),
        (["KH3", "AH3", "NH3", "WH3"], DXCCEntity(number: 123, name: "Johnston I.")),
        (["KH4", "AH4", "NH4", "WH4"], DXCCEntity(number: 174, name: "Midway I.")),
        (["KH5K"], DXCCEntity(number: 138, name: "Kure I.")),
        (["KH5", "AH5", "NH5", "WH5"], DXCCEntity(number: 197, name: "Palmyra & Jarvis Is.")),
        (
            ["KH6", "KH7", "AH6", "AH7", "NH6", "NH7", "WH6", "WH7"],
            DXCCEntity(number: 110, name: "Hawaii")
        ),
        (["KH8S", "AH8S", "NH8S", "WH8S"], DXCCEntity(number: 515, name: "Swains I.")),
        (["KH8", "AH8", "NH8", "WH8"], DXCCEntity(number: 9, name: "American Samoa")),
        (["KH9", "AH9", "NH9", "WH9"], DXCCEntity(number: 297, name: "Wake I.")),
        (
            ["KL7", "KL", "AL7", "AL", "NL7", "NL", "WL7", "WL"],
            DXCCEntity(number: 6, name: "Alaska")
        ),
        (["KP1", "NP1", "WP1"], DXCCEntity(number: 182, name: "Navassa I.")),
        (["KP2", "NP2", "WP2"], DXCCEntity(number: 285, name: "Virgin Is.")),
        (["KP3", "KP4", "NP3", "NP4", "WP3", "WP4"], DXCCEntity(number: 202, name: "Puerto Rico")),
        (["KP5", "NP5", "WP5"], DXCCEntity(number: 43, name: "Desecheo I.")),

        // USA (general - checked after territories)
        (
            ["K", "W", "N", "AA", "AB", "AC", "AD", "AE", "AF", "AG", "AI", "AJ", "AK"],
            DXCCEntity(number: 291, name: "United States of America")
        ),

        // ==================== Canada ====================
        (["VE", "VA", "VO", "VY", "CY", "CZ"], DXCCEntity(number: 1, name: "Canada")),

        // ==================== Mexico ====================
        (
            [
                "XE", "XA", "XB", "XC", "XD", "XF", "4A", "4B", "4C", "6D", "6E", "6F", "6G", "6H",
                "6I", "6J",
            ],
            DXCCEntity(number: 50, name: "Mexico")
        ),
        (["XF4"], DXCCEntity(number: 204, name: "Revillagigedo")),

        // ==================== South America ====================
        (["PP0F", "PY0F"], DXCCEntity(number: 56, name: "Fernando de Noronha")),
        (["PP0S", "PY0S"], DXCCEntity(number: 253, name: "St. Peter & St. Paul Rocks")),
        (["PP0T", "PY0T"], DXCCEntity(number: 273, name: "Trindade & Martim Vaz Is.")),
        (
            [
                "PP", "PQ", "PR", "PS", "PT", "PU", "PV", "PW", "PX", "PY", "ZV", "ZW", "ZX", "ZY",
                "ZZ",
            ], DXCCEntity(number: 108, name: "Brazil")
        ),
        (
            [
                "LU", "AY", "AZ", "L2", "L3", "L4", "L5", "L6", "L7", "L8", "L9", "LO", "LP", "LQ",
                "LR", "LS", "LT", "LV", "LW",
            ], DXCCEntity(number: 100, name: "Argentina")
        ),
        (["CE", "CA", "CB", "CC", "CD", "XQ", "XR", "3G"], DXCCEntity(number: 112, name: "Chile")),
        (["HK", "5J", "5K"], DXCCEntity(number: 116, name: "Colombia")),
        (["HK0M"], DXCCEntity(number: 161, name: "Malpelo I.")),
        (["HK0"], DXCCEntity(number: 216, name: "San Andres & Providencia")),
        (["YV0"], DXCCEntity(number: 17, name: "Aves I.")),
        (["YV", "4M"], DXCCEntity(number: 148, name: "Venezuela")),
        (["HC", "HD"], DXCCEntity(number: 120, name: "Ecuador")),
        (["HC8", "HD8"], DXCCEntity(number: 71, name: "Galapagos Is.")),
        (["OA", "OB", "OC", "4T"], DXCCEntity(number: 136, name: "Peru")),
        (["CP"], DXCCEntity(number: 104, name: "Bolivia")),
        (["ZP"], DXCCEntity(number: 132, name: "Paraguay")),
        (["CX"], DXCCEntity(number: 144, name: "Uruguay")),
        (["8R"], DXCCEntity(number: 129, name: "Guyana")),
        (["PZ"], DXCCEntity(number: 140, name: "Suriname")),
        (["FY"], DXCCEntity(number: 63, name: "French Guiana")),

        // ==================== Central America ====================
        (["HR"], DXCCEntity(number: 80, name: "Honduras")),
        (["YS", "HU"], DXCCEntity(number: 74, name: "El Salvador")),
        (["TG"], DXCCEntity(number: 76, name: "Guatemala")),
        (["TI", "TE"], DXCCEntity(number: 308, name: "Costa Rica")),
        (["TI9"], DXCCEntity(number: 37, name: "Cocos I.")),
        (["HP", "HO", "H3", "H8", "H9"], DXCCEntity(number: 88, name: "Panama")),
        (["YN", "H7", "HT"], DXCCEntity(number: 86, name: "Nicaragua")),
        (["V3"], DXCCEntity(number: 66, name: "Belize")),

        // ==================== Caribbean ====================
        (["HI"], DXCCEntity(number: 72, name: "Dominican Republic")),
        (["HH"], DXCCEntity(number: 78, name: "Haiti")),
        (["CO", "CM", "CL", "T4"], DXCCEntity(number: 70, name: "Cuba")),
        (["6Y"], DXCCEntity(number: 82, name: "Jamaica")),
        (["ZF"], DXCCEntity(number: 69, name: "Cayman Is.")),
        (["C6"], DXCCEntity(number: 60, name: "Bahamas")),
        (["VP5"], DXCCEntity(number: 89, name: "Turks & Caicos Is.")),
        (["VP9"], DXCCEntity(number: 64, name: "Bermuda")),
        (["VP2E", "V2"], DXCCEntity(number: 94, name: "Antigua & Barbuda")),
        (["VP2M"], DXCCEntity(number: 96, name: "Montserrat")),
        (["VP2A"], DXCCEntity(number: 12, name: "Anguilla")),
        (["VP2V"], DXCCEntity(number: 65, name: "British Virgin Is.")),
        (["8P"], DXCCEntity(number: 62, name: "Barbados")),
        (["J3"], DXCCEntity(number: 77, name: "Grenada")),
        (["J6"], DXCCEntity(number: 97, name: "St. Lucia")),
        (["J7"], DXCCEntity(number: 95, name: "Dominica")),
        (["J8"], DXCCEntity(number: 98, name: "St. Vincent")),
        (["V4"], DXCCEntity(number: 249, name: "St. Kitts & Nevis")),
        (["9Y", "9Z"], DXCCEntity(number: 90, name: "Trinidad & Tobago")),
        (["PJ2"], DXCCEntity(number: 517, name: "Curacao")),
        (["PJ4"], DXCCEntity(number: 520, name: "Bonaire")),
        (["PJ5", "PJ6"], DXCCEntity(number: 519, name: "Saba & St. Eustatius")),
        (["PJ7"], DXCCEntity(number: 518, name: "Sint Maarten")),
        (["P4"], DXCCEntity(number: 91, name: "Aruba")),
        (["FG"], DXCCEntity(number: 79, name: "Guadeloupe")),
        (["FS"], DXCCEntity(number: 213, name: "Saint Martin")),
        (["FJ"], DXCCEntity(number: 516, name: "Saint Barthelemy")),
        (["FM"], DXCCEntity(number: 84, name: "Martinique")),
        (["FP"], DXCCEntity(number: 277, name: "St. Pierre & Miquelon")),

        // ==================== Atlantic Islands (Americas) ====================
        (["CY0"], DXCCEntity(number: 211, name: "Sable I.")),
        (["CY9"], DXCCEntity(number: 252, name: "St. Paul I.")),
        (["VP8/F", "VP8F"], DXCCEntity(number: 141, name: "Falkland Is.")),
        (["VP8/G", "VP8G"], DXCCEntity(number: 235, name: "South Georgia I.")),
        (["VP8/O", "VP8O"], DXCCEntity(number: 238, name: "South Orkney Is.")),
        (["VP8/H", "VP8H"], DXCCEntity(number: 240, name: "South Sandwich Is.")),
        (["VP8/S", "VP8S"], DXCCEntity(number: 241, name: "South Shetland Is.")),
        (["CE9", "VP8"], DXCCEntity(number: 13, name: "Antarctica")),
        (["CE0X"], DXCCEntity(number: 217, name: "San Felix & San Ambrosio")),
        (["CE0Y"], DXCCEntity(number: 47, name: "Easter I.")),
        (["CE0Z"], DXCCEntity(number: 125, name: "Juan Fernandez Is.")),
    ]
}
