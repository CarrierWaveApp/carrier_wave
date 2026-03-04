import CarrierWaveData
import Foundation

// MARK: - DXCC Europe Region Data

nonisolated extension DescriptionLookup {
    /// DXCC entities for Europe (UK, Western, Eastern, Scandinavia, Baltic, Russia)
    nonisolated static let dxccEntitiesEurope: [(prefixes: [String], entity: DXCCEntity)] = [
        // ==================== Europe ====================
        // UK and Crown Dependencies
        (["GD", "GT", "MD", "2D"], DXCCEntity(number: 114, name: "Isle of Man")),
        (["GI", "GN", "MI", "2I"], DXCCEntity(number: 265, name: "Northern Ireland")),
        (["GJ", "GH", "MJ", "2J"], DXCCEntity(number: 122, name: "Jersey")),
        (["GM", "GS", "MM", "2M"], DXCCEntity(number: 279, name: "Scotland")),
        (["GU", "GP", "MU", "2U"], DXCCEntity(number: 106, name: "Guernsey")),
        (["GW", "GC", "MW", "2W"], DXCCEntity(number: 294, name: "Wales")),
        (
            ["G", "M", "2E"],
            DXCCEntity(number: 223, name: "United Kingdom of Great Britain & Northern Ireland")
        ),

        // Western Europe
        (["F"], DXCCEntity(number: 227, name: "France")),
        (
            [
                "DA", "DB", "DC", "DD", "DF", "DG", "DH", "DI", "DJ", "DK", "DL", "DM", "DN", "DO",
                "DP", "DQ", "DR",
            ],
            DXCCEntity(number: 230, name: "Germany")
        ),
        (
            ["PA", "PB", "PC", "PD", "PE", "PF", "PG", "PH", "PI"],
            DXCCEntity(number: 263, name: "Netherlands")
        ),
        (["ON", "OO", "OP", "OQ", "OR", "OS", "OT"], DXCCEntity(number: 209, name: "Belgium")),
        (["LX"], DXCCEntity(number: 254, name: "Luxembourg")),
        (["HB0"], DXCCEntity(number: 251, name: "Liechtenstein")),
        (["HB", "HE"], DXCCEntity(number: 287, name: "Switzerland")),
        (["OE"], DXCCEntity(number: 206, name: "Austria")),

        // Scandinavia
        (["OZ", "OU", "OV", "OW", "5P", "5Q"], DXCCEntity(number: 221, name: "Denmark")),
        (["OX", "XP"], DXCCEntity(number: 237, name: "Greenland")),
        (["OY"], DXCCEntity(number: 222, name: "Faroe Is.")),
        (["JW", "JX"], DXCCEntity(number: 259, name: "Svalbard")),
        (
            ["LA", "LB", "LC", "LD", "LE", "LF", "LG", "LH", "LI", "LJ", "LK", "LL", "LM", "LN"],
            DXCCEntity(number: 266, name: "Norway")
        ),
        (["OJ0"], DXCCEntity(number: 167, name: "Market Reef")),
        (["OH0"], DXCCEntity(number: 5, name: "Aland Is.")),
        (["OH", "OG", "OI", "OJ"], DXCCEntity(number: 224, name: "Finland")),
        (
            [
                "SA", "SB", "SC", "SD", "SE", "SF", "SG", "SH", "SI", "SJ", "SK", "SL", "SM", "7S",
                "8S",
            ], DXCCEntity(number: 284, name: "Sweden")
        ),
        (["TF"], DXCCEntity(number: 242, name: "Iceland")),

        // Iberian Peninsula
        (
            ["EA6", "EB6", "EC6", "ED6", "EE6", "EF6", "EG6", "EH6"],
            DXCCEntity(number: 21, name: "Balearic Is.")
        ),
        (
            ["EA8", "EB8", "EC8", "ED8", "EE8", "EF8", "EG8", "EH8"],
            DXCCEntity(number: 29, name: "Canary Is.")
        ),
        (
            ["EA9", "EB9", "EC9", "ED9", "EE9", "EF9", "EG9", "EH9"],
            DXCCEntity(number: 32, name: "Ceuta & Melilla")
        ),
        (["EA", "EB", "EC", "ED", "EE", "EF", "EG", "EH"], DXCCEntity(number: 281, name: "Spain")),
        (["CT3"], DXCCEntity(number: 256, name: "Madeira Is.")),
        (["CU"], DXCCEntity(number: 149, name: "Azores")),
        (["CT", "CS"], DXCCEntity(number: 272, name: "Portugal")),
        (["C3"], DXCCEntity(number: 203, name: "Andorra")),
        (["ZB", "ZG"], DXCCEntity(number: 233, name: "Gibraltar")),

        // Italy and neighbors
        (["IS0", "IM0"], DXCCEntity(number: 225, name: "Sardinia")),
        (["I", "IK", "IN", "IT", "IU", "IW", "IZ"], DXCCEntity(number: 248, name: "Italy")),
        (["T7"], DXCCEntity(number: 278, name: "San Marino")),
        (["HV"], DXCCEntity(number: 295, name: "Vatican")),
        (["3A"], DXCCEntity(number: 260, name: "Monaco")),
        (["9H"], DXCCEntity(number: 257, name: "Malta")),

        // Greece and Eastern Mediterranean
        (["SV5", "J45"], DXCCEntity(number: 45, name: "Dodecanese")),
        (["SV9"], DXCCEntity(number: 40, name: "Crete")),
        (["SY"], DXCCEntity(number: 180, name: "Mount Athos")),
        (["SV", "SW", "SX", "SZ", "J4"], DXCCEntity(number: 236, name: "Greece")),
        (["5B", "C4", "H2", "P3"], DXCCEntity(number: 215, name: "Cyprus")),
        (["ZC4"], DXCCEntity(number: 283, name: "UK Sov. Base Areas on Cyprus")),

        // Central Europe
        (["SP", "SN", "SO", "SQ", "SR", "3Z", "HF"], DXCCEntity(number: 269, name: "Poland")),
        (["OK", "OL"], DXCCEntity(number: 503, name: "Czech Republic")),
        (["OM"], DXCCEntity(number: 504, name: "Slovak Republic")),
        (["HA", "HG"], DXCCEntity(number: 239, name: "Hungary")),
        (["S5"], DXCCEntity(number: 499, name: "Slovenia")),
        (["9A"], DXCCEntity(number: 497, name: "Croatia")),
        (["E7"], DXCCEntity(number: 501, name: "Bosnia-Herzegovina")),
        (["YU", "YT", "4N", "4O"], DXCCEntity(number: 296, name: "Serbia")),
        (["4O"], DXCCEntity(number: 514, name: "Montenegro")),
        (["Z3"], DXCCEntity(number: 502, name: "North Macedonia")),
        (["Z6"], DXCCEntity(number: 522, name: "Republic of Kosovo")),
        (["ZA"], DXCCEntity(number: 7, name: "Albania")),

        // Romania and Bulgaria
        (["YO", "YP", "YQ", "YR"], DXCCEntity(number: 275, name: "Romania")),
        (["LZ"], DXCCEntity(number: 212, name: "Bulgaria")),

        // Ireland
        (["EI", "EJ"], DXCCEntity(number: 245, name: "Ireland")),

        // Baltic States
        (["LY"], DXCCEntity(number: 146, name: "Lithuania")),
        (["YL"], DXCCEntity(number: 145, name: "Latvia")),
        (["ES"], DXCCEntity(number: 52, name: "Estonia")),

        // Belarus, Ukraine, Moldova
        (["EU", "EV", "EW"], DXCCEntity(number: 27, name: "Belarus")),
        (
            ["UR", "US", "UT", "UU", "UV", "UW", "UX", "UY", "UZ", "EM", "EN", "EO"],
            DXCCEntity(number: 288, name: "Ukraine")
        ),
        (["ER"], DXCCEntity(number: 179, name: "Moldova")),

        // Russia
        (["UA2"], DXCCEntity(number: 126, name: "Kaliningrad")),
        (
            [
                "UA9", "UA0", "RA9", "RA0", "R0", "R8", "R9", "RC9", "RC0", "RD9", "RD0", "RE9",
                "RE0", "RF9", "RF0", "RG9", "RG0", "RI0", "RJ9", "RJ0", "RK9", "RK0", "RL9", "RL0",
                "RM9", "RM0", "RN9", "RN0", "RO9", "RO0", "RQ9", "RQ0", "RT9", "RT0", "RU9", "RU0",
                "RV9", "RV0", "RW9", "RW0", "RX9", "RX0", "RY9", "RY0", "RZ9", "RZ0", "U0", "U8",
                "U9",
            ], DXCCEntity(number: 15, name: "Asiatic Russia")
        ),
        (
            [
                "UA", "RA", "R1", "R2", "R3", "R4", "R5", "R6", "R7", "RC", "RD", "RE", "RF", "RG",
                "RI", "RJ", "RK", "RL", "RM", "RN", "RO", "RQ", "RT", "RU", "RV", "RW", "RX", "RY",
                "RZ", "U1", "U2", "U3", "U4", "U5", "U6", "U7",
            ], DXCCEntity(number: 54, name: "European Russia")
        ),

        // ==================== Caucasus & Central Asia ====================
        (["4J", "4K"], DXCCEntity(number: 18, name: "Azerbaijan")),
        (["4L"], DXCCEntity(number: 75, name: "Georgia")),
        (["EK"], DXCCEntity(number: 14, name: "Armenia")),
        (["UN", "UL", "UM", "UP", "UQ"], DXCCEntity(number: 130, name: "Kazakhstan")),
        (["UK"], DXCCEntity(number: 292, name: "Uzbekistan")),
        (["EX"], DXCCEntity(number: 135, name: "Kyrgyz Republic")),
        (["EY"], DXCCEntity(number: 262, name: "Tajikistan")),
        (["EZ"], DXCCEntity(number: 280, name: "Turkmenistan")),
    ]
}
