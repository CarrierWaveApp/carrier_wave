import CarrierWaveData
import Foundation

// MARK: - DXCC Asia & Oceania Region Data

nonisolated extension DescriptionLookup {
    /// DXCC entities for Middle East, South Asia, East Asia, Southeast Asia, Oceania
    nonisolated static let dxccEntitiesAsiaOceania: [(prefixes: [String], entity: DXCCEntity)] = [
        // ==================== Middle East ====================
        (["TA", "TB", "TC", "YM"], DXCCEntity(number: 390, name: "Republic of Turkiye")),
        (["4X", "4Z"], DXCCEntity(number: 336, name: "Israel")),
        (["E4"], DXCCEntity(number: 510, name: "Palestine")),
        (["JY"], DXCCEntity(number: 342, name: "Jordan")),
        (["OD"], DXCCEntity(number: 354, name: "Lebanon")),
        (["YK"], DXCCEntity(number: 384, name: "Syrian Arab Republic")),
        (["YI"], DXCCEntity(number: 333, name: "Iraq")),
        (["EP", "EQ"], DXCCEntity(number: 330, name: "Iran")),
        (["HZ", "7Z", "8Z"], DXCCEntity(number: 378, name: "Saudi Arabia")),
        (["9K"], DXCCEntity(number: 348, name: "Kuwait")),
        (["A9"], DXCCEntity(number: 304, name: "Bahrain")),
        (["A7"], DXCCEntity(number: 376, name: "Qatar")),
        (["A6"], DXCCEntity(number: 391, name: "United Arab Emirates")),
        (["A4"], DXCCEntity(number: 370, name: "Oman")),
        (["7O"], DXCCEntity(number: 492, name: "Yemen")),

        // ==================== South Asia ====================
        (["AP", "AS", "6P", "6Q", "6R", "6S"], DXCCEntity(number: 372, name: "Pakistan")),
        (["YA", "T6"], DXCCEntity(number: 3, name: "Afghanistan")),
        (
            [
                "VU2", "VU3", "VU4", "VU7", "AT", "AU", "AV", "AW", "8T", "8U", "8V", "8W", "8X",
                "8Y",
            ], DXCCEntity(number: 324, name: "India")
        ),
        (["VU4"], DXCCEntity(number: 11, name: "Andaman & Nicobar Is.")),
        (["VU7"], DXCCEntity(number: 142, name: "Lakshadweep Is.")),
        (["4S", "4R"], DXCCEntity(number: 315, name: "Sri Lanka")),
        (["8Q"], DXCCEntity(number: 159, name: "Maldives")),
        (["S2", "S3"], DXCCEntity(number: 305, name: "Bangladesh")),
        (["9N"], DXCCEntity(number: 369, name: "Nepal")),
        (["A5"], DXCCEntity(number: 306, name: "Bhutan")),

        // ==================== East Asia ====================
        (["JD1O"], DXCCEntity(number: 192, name: "Ogasawara")),
        (["JD1M"], DXCCEntity(number: 177, name: "Minami Torishima")),
        (
            [
                "JA", "JD", "JE", "JF", "JG", "JH", "JI", "JJ", "JK", "JL", "JM", "JN", "JO", "JP",
                "JQ", "JR", "JS", "7J", "7K", "7L", "7M", "7N", "8J", "8K", "8L", "8M", "8N",
            ], DXCCEntity(number: 339, name: "Japan")
        ),
        (["HL", "DS", "6K", "6L", "6M", "6N"], DXCCEntity(number: 137, name: "Republic of Korea")),
        (["P5"], DXCCEntity(number: 344, name: "DPR of Korea")),
        (
            ["BV", "BW", "BX", "BM", "BN", "BO", "BP", "BQ"],
            DXCCEntity(number: 386, name: "Taiwan")
        ),
        (["BV9P"], DXCCEntity(number: 505, name: "Pratas I.")),
        (
            [
                "BY", "BA", "BD", "BG", "BH", "BI", "BJ", "BL", "BT", "BZ", "3H", "3I", "3J", "3K",
                "3L", "3M", "3N", "3O", "3P", "3Q", "3R", "3S", "3T", "3U", "XS",
            ], DXCCEntity(number: 318, name: "China")
        ),
        (["BS7"], DXCCEntity(number: 506, name: "Scarborough Reef")),
        (["VR", "VR2"], DXCCEntity(number: 321, name: "Hong Kong")),
        (["XX9"], DXCCEntity(number: 152, name: "Macao")),
        (["JT", "JU", "JV"], DXCCEntity(number: 363, name: "Mongolia")),

        // ==================== Southeast Asia ====================
        (["HS", "E2"], DXCCEntity(number: 387, name: "Thailand")),
        (["XV", "3W"], DXCCEntity(number: 293, name: "Viet Nam")),
        (["XU"], DXCCEntity(number: 312, name: "Cambodia")),
        (["XW"], DXCCEntity(number: 143, name: "Lao People's Dem Repub")),
        (["XZ", "XY"], DXCCEntity(number: 309, name: "Myanmar")),
        (["9M2", "9M4", "9W2", "9W4"], DXCCEntity(number: 299, name: "West Malaysia")),
        (["9M6", "9M8", "9W6", "9W8"], DXCCEntity(number: 46, name: "East Malaysia")),
        (["9V", "S6"], DXCCEntity(number: 381, name: "Singapore")),
        (["V8"], DXCCEntity(number: 345, name: "Brunei Darussalam")),
        (
            ["DU", "DV", "DW", "DX", "DY", "DZ", "4D", "4E", "4F", "4G", "4H", "4I"],
            DXCCEntity(number: 375, name: "Philippines")
        ),
        (
            [
                "YB", "YC", "YD", "YE", "YF", "YG", "YH", "7A", "7B", "7C", "7D", "7E", "7F", "7G",
                "7H", "7I", "8A", "8B", "8C", "8D", "8E", "8F", "8G", "8H", "8I",
            ], DXCCEntity(number: 327, name: "Indonesia")
        ),
        (["4W"], DXCCEntity(number: 511, name: "Timor - Leste")),

        // ==================== Oceania ====================
        // Australia and territories
        (["VK9N"], DXCCEntity(number: 189, name: "Norfolk I.")),
        (["VK9L"], DXCCEntity(number: 147, name: "Lord Howe I.")),
        (["VK9C"], DXCCEntity(number: 38, name: "Cocos (Keeling) Is.")),
        (["VK9X"], DXCCEntity(number: 35, name: "Christmas I.")),
        (["VK9W"], DXCCEntity(number: 303, name: "Willis I.")),
        (["VK9M"], DXCCEntity(number: 171, name: "Mellish Reef")),
        (["VK0H"], DXCCEntity(number: 111, name: "Heard I.")),
        (["VK0M"], DXCCEntity(number: 153, name: "Macquarie I.")),
        (["VK", "AX"], DXCCEntity(number: 150, name: "Australia")),

        // New Zealand and territories
        (["ZL7"], DXCCEntity(number: 34, name: "Chatham Is.")),
        (["ZL8"], DXCCEntity(number: 133, name: "Kermadec Is.")),
        (["ZL9"], DXCCEntity(number: 16, name: "New Zealand Subantarctic Islands")),
        (["ZL", "ZM"], DXCCEntity(number: 170, name: "New Zealand")),

        // Pacific Islands
        (["P2"], DXCCEntity(number: 163, name: "Papua New Guinea")),
        (["H4"], DXCCEntity(number: 185, name: "Solomon Is.")),
        (["H40"], DXCCEntity(number: 507, name: "Temotu Province")),
        (["YJ"], DXCCEntity(number: 158, name: "Vanuatu")),
        (["FK"], DXCCEntity(number: 162, name: "New Caledonia")),
        (["TX"], DXCCEntity(number: 512, name: "Chesterfield Is.")),
        (["3D2R"], DXCCEntity(number: 460, name: "Rotuma I.")),
        (["3D2C"], DXCCEntity(number: 489, name: "Conway Reef")),
        (["3D2", "3D"], DXCCEntity(number: 176, name: "Fiji")),
        (["A3"], DXCCEntity(number: 160, name: "Tonga")),
        (["5W"], DXCCEntity(number: 190, name: "Samoa")),
        (["ZK3"], DXCCEntity(number: 270, name: "Tokelau Is.")),
        (["E51N"], DXCCEntity(number: 191, name: "N. Cook Is.")),
        (["E51S"], DXCCEntity(number: 234, name: "S. Cook Is.")),
        (["E5"], DXCCEntity(number: 191, name: "N. Cook Is.")),
        (["ZK2"], DXCCEntity(number: 188, name: "Niue")),
        (["FO0M"], DXCCEntity(number: 509, name: "Marquesas Is.")),
        (["FO0"], DXCCEntity(number: 175, name: "French Polynesia")),
        (["FO"], DXCCEntity(number: 508, name: "Austral I.")),
        (["T32"], DXCCEntity(number: 48, name: "E. Kiribati")),
        (["T31"], DXCCEntity(number: 31, name: "C. Kiribati")),
        (["T33"], DXCCEntity(number: 490, name: "Banaba I.")),
        (["T30"], DXCCEntity(number: 301, name: "W. Kiribati")),
        (["T2"], DXCCEntity(number: 282, name: "Tuvalu")),
        (["V7"], DXCCEntity(number: 168, name: "Marshall Is.")),
        (["V6"], DXCCEntity(number: 173, name: "Micronesia")),
        (["T8", "KC6"], DXCCEntity(number: 22, name: "Palau")),
        (["KX6"], DXCCEntity(number: 168, name: "Marshall Is.")),
        (["C2"], DXCCEntity(number: 157, name: "Nauru")),
        (["T3"], DXCCEntity(number: 301, name: "W. Kiribati")),
        (["FW"], DXCCEntity(number: 298, name: "Wallis & Futuna Is.")),
        (["VP6D"], DXCCEntity(number: 513, name: "Ducie I.")),
        (["VP6"], DXCCEntity(number: 172, name: "Pitcairn I.")),
    ]
}
