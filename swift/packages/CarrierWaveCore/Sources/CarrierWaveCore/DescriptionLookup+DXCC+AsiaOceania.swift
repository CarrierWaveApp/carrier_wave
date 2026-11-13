import Foundation

// MARK: - DXCC Asia & Oceania Region Data

nonisolated public extension DescriptionLookup {
    /// DXCC entities for Middle East, South Asia, East Asia, Southeast Asia, Oceania
    nonisolated(unsafe) static let dxccEntitiesAsiaOceania: [(prefixes: [String], entity: DXCCEntityRef)] = [
        // ==================== Middle East ====================
        (["TA", "TB", "TC", "YM"], DXCCEntityRef(number: 390, name: "Republic of Turkiye")),
        (["4X", "4Z"], DXCCEntityRef(number: 336, name: "Israel")),
        (["E4"], DXCCEntityRef(number: 510, name: "Palestine")),
        (["JY"], DXCCEntityRef(number: 342, name: "Jordan")),
        (["OD"], DXCCEntityRef(number: 354, name: "Lebanon")),
        (["YK"], DXCCEntityRef(number: 384, name: "Syrian Arab Republic")),
        (["YI"], DXCCEntityRef(number: 333, name: "Iraq")),
        (["EP", "EQ"], DXCCEntityRef(number: 330, name: "Iran")),
        (["HZ", "7Z", "8Z"], DXCCEntityRef(number: 378, name: "Saudi Arabia")),
        (["9K"], DXCCEntityRef(number: 348, name: "Kuwait")),
        (["A9"], DXCCEntityRef(number: 304, name: "Bahrain")),
        (["A7"], DXCCEntityRef(number: 376, name: "Qatar")),
        (["A6"], DXCCEntityRef(number: 391, name: "United Arab Emirates")),
        (["A4"], DXCCEntityRef(number: 370, name: "Oman")),
        (["7O"], DXCCEntityRef(number: 492, name: "Yemen")),

        // ==================== South Asia ====================
        (["AP", "AS", "6P", "6Q", "6R", "6S"], DXCCEntityRef(number: 372, name: "Pakistan")),
        (["YA", "T6"], DXCCEntityRef(number: 3, name: "Afghanistan")),
        (
            [
                "VU2", "VU3", "VU4", "VU7", "AT", "AU", "AV", "AW", "8T", "8U", "8V", "8W", "8X",
                "8Y",
            ], DXCCEntityRef(number: 324, name: "India")
        ),
        (["VU4"], DXCCEntityRef(number: 11, name: "Andaman & Nicobar Is.")),
        (["VU7"], DXCCEntityRef(number: 142, name: "Lakshadweep Is.")),
        (["4S", "4R"], DXCCEntityRef(number: 315, name: "Sri Lanka")),
        (["8Q"], DXCCEntityRef(number: 159, name: "Maldives")),
        (["S2", "S3"], DXCCEntityRef(number: 305, name: "Bangladesh")),
        (["9N"], DXCCEntityRef(number: 369, name: "Nepal")),
        (["A5"], DXCCEntityRef(number: 306, name: "Bhutan")),

        // ==================== East Asia ====================
        (["JD1O"], DXCCEntityRef(number: 192, name: "Ogasawara")),
        (["JD1M"], DXCCEntityRef(number: 177, name: "Minami Torishima")),
        (
            [
                "JA", "JD", "JE", "JF", "JG", "JH", "JI", "JJ", "JK", "JL", "JM", "JN", "JO", "JP",
                "JQ", "JR", "JS", "7J", "7K", "7L", "7M", "7N", "8J", "8K", "8L", "8M", "8N",
            ], DXCCEntityRef(number: 339, name: "Japan")
        ),
        (["HL", "DS", "6K", "6L", "6M", "6N"], DXCCEntityRef(number: 137, name: "Republic of Korea")),
        (["P5"], DXCCEntityRef(number: 344, name: "DPR of Korea")),
        (
            ["BV", "BW", "BX", "BM", "BN", "BO", "BP", "BQ"],
            DXCCEntityRef(number: 386, name: "Taiwan")
        ),
        (["BV9P"], DXCCEntityRef(number: 505, name: "Pratas I.")),
        (
            [
                "BY", "BA", "BD", "BG", "BH", "BI", "BJ", "BL", "BT", "BZ", "3H", "3I", "3J", "3K",
                "3L", "3M", "3N", "3O", "3P", "3Q", "3R", "3S", "3T", "3U", "XS",
            ], DXCCEntityRef(number: 318, name: "China")
        ),
        (["BS7"], DXCCEntityRef(number: 506, name: "Scarborough Reef")),
        (["VR", "VR2"], DXCCEntityRef(number: 321, name: "Hong Kong")),
        (["XX9"], DXCCEntityRef(number: 152, name: "Macao")),
        (["JT", "JU", "JV"], DXCCEntityRef(number: 363, name: "Mongolia")),

        // ==================== Southeast Asia ====================
        (["HS", "E2"], DXCCEntityRef(number: 387, name: "Thailand")),
        (["XV", "3W"], DXCCEntityRef(number: 293, name: "Viet Nam")),
        (["XU"], DXCCEntityRef(number: 312, name: "Cambodia")),
        (["XW"], DXCCEntityRef(number: 143, name: "Lao People's Dem Repub")),
        (["XZ", "XY"], DXCCEntityRef(number: 309, name: "Myanmar")),
        (["9M2", "9M4", "9W2", "9W4"], DXCCEntityRef(number: 299, name: "West Malaysia")),
        (["9M6", "9M8", "9W6", "9W8"], DXCCEntityRef(number: 46, name: "East Malaysia")),
        (["9V", "S6"], DXCCEntityRef(number: 381, name: "Singapore")),
        (["V8"], DXCCEntityRef(number: 345, name: "Brunei Darussalam")),
        (
            ["DU", "DV", "DW", "DX", "DY", "DZ", "4D", "4E", "4F", "4G", "4H", "4I"],
            DXCCEntityRef(number: 375, name: "Philippines")
        ),
        (
            [
                "YB", "YC", "YD", "YE", "YF", "YG", "YH", "7A", "7B", "7C", "7D", "7E", "7F", "7G",
                "7H", "7I", "8A", "8B", "8C", "8D", "8E", "8F", "8G", "8H", "8I",
            ], DXCCEntityRef(number: 327, name: "Indonesia")
        ),
        (["4W"], DXCCEntityRef(number: 511, name: "Timor - Leste")),

        // ==================== Oceania ====================
        // Australia and territories
        (["VK9N"], DXCCEntityRef(number: 189, name: "Norfolk I.")),
        (["VK9L"], DXCCEntityRef(number: 147, name: "Lord Howe I.")),
        (["VK9C"], DXCCEntityRef(number: 38, name: "Cocos (Keeling) Is.")),
        (["VK9X"], DXCCEntityRef(number: 35, name: "Christmas I.")),
        (["VK9W"], DXCCEntityRef(number: 303, name: "Willis I.")),
        (["VK9M"], DXCCEntityRef(number: 171, name: "Mellish Reef")),
        (["VK0H"], DXCCEntityRef(number: 111, name: "Heard I.")),
        (["VK0M"], DXCCEntityRef(number: 153, name: "Macquarie I.")),
        (["VK", "AX"], DXCCEntityRef(number: 150, name: "Australia")),

        // New Zealand and territories
        (["ZL7"], DXCCEntityRef(number: 34, name: "Chatham Is.")),
        (["ZL8"], DXCCEntityRef(number: 133, name: "Kermadec Is.")),
        (["ZL9"], DXCCEntityRef(number: 16, name: "New Zealand Subantarctic Islands")),
        (["ZL", "ZM"], DXCCEntityRef(number: 170, name: "New Zealand")),

        // Pacific Islands
        (["P2"], DXCCEntityRef(number: 163, name: "Papua New Guinea")),
        (["H4"], DXCCEntityRef(number: 185, name: "Solomon Is.")),
        (["H40"], DXCCEntityRef(number: 507, name: "Temotu Province")),
        (["YJ"], DXCCEntityRef(number: 158, name: "Vanuatu")),
        (["FK"], DXCCEntityRef(number: 162, name: "New Caledonia")),
        (["TX"], DXCCEntityRef(number: 512, name: "Chesterfield Is.")),
        (["3D2R"], DXCCEntityRef(number: 460, name: "Rotuma I.")),
        (["3D2C"], DXCCEntityRef(number: 489, name: "Conway Reef")),
        (["3D2", "3D"], DXCCEntityRef(number: 176, name: "Fiji")),
        (["A3"], DXCCEntityRef(number: 160, name: "Tonga")),
        (["5W"], DXCCEntityRef(number: 190, name: "Samoa")),
        (["ZK3"], DXCCEntityRef(number: 270, name: "Tokelau Is.")),
        (["E51N"], DXCCEntityRef(number: 191, name: "N. Cook Is.")),
        (["E51S"], DXCCEntityRef(number: 234, name: "S. Cook Is.")),
        (["E5"], DXCCEntityRef(number: 191, name: "N. Cook Is.")),
        (["ZK2"], DXCCEntityRef(number: 188, name: "Niue")),
        (["FO0M"], DXCCEntityRef(number: 509, name: "Marquesas Is.")),
        (["FO0"], DXCCEntityRef(number: 175, name: "French Polynesia")),
        (["FO"], DXCCEntityRef(number: 508, name: "Austral I.")),
        (["T32"], DXCCEntityRef(number: 48, name: "E. Kiribati")),
        (["T31"], DXCCEntityRef(number: 31, name: "C. Kiribati")),
        (["T33"], DXCCEntityRef(number: 490, name: "Banaba I.")),
        (["T30"], DXCCEntityRef(number: 301, name: "W. Kiribati")),
        (["T2"], DXCCEntityRef(number: 282, name: "Tuvalu")),
        (["V7"], DXCCEntityRef(number: 168, name: "Marshall Is.")),
        (["V6"], DXCCEntityRef(number: 173, name: "Micronesia")),
        (["T8", "KC6"], DXCCEntityRef(number: 22, name: "Palau")),
        (["KX6"], DXCCEntityRef(number: 168, name: "Marshall Is.")),
        (["C2"], DXCCEntityRef(number: 157, name: "Nauru")),
        (["T3"], DXCCEntityRef(number: 301, name: "W. Kiribati")),
        (["FW"], DXCCEntityRef(number: 298, name: "Wallis & Futuna Is.")),
        (["VP6D"], DXCCEntityRef(number: 513, name: "Ducie I.")),
        (["VP6"], DXCCEntityRef(number: 172, name: "Pitcairn I.")),
    ]
}
