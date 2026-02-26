import Foundation

// MARK: - DXCC Africa & Other Region Data

nonisolated extension DescriptionLookup {
    /// DXCC entities for Africa, Indian Ocean, Atlantic Ocean, special entities
    nonisolated static let dxccEntitiesAfricaOther: [(prefixes: [String], entity: DXCCEntity)] = [
        // ==================== Africa ====================
        // North Africa
        (["SU"], DXCCEntity(number: 478, name: "Egypt")),
        (["5A"], DXCCEntity(number: 436, name: "Libya")),
        (["3V", "TS"], DXCCEntity(number: 474, name: "Tunisia")),
        (["7X"], DXCCEntity(number: 400, name: "Algeria")),
        (["CN", "5C", "5D", "5E", "5F", "5G"], DXCCEntity(number: 446, name: "Morocco")),
        (["S0"], DXCCEntity(number: 302, name: "Western Sahara")),

        // West Africa
        (["5T"], DXCCEntity(number: 444, name: "Mauritania")),
        (["6W"], DXCCEntity(number: 456, name: "Senegal")),
        (["C5"], DXCCEntity(number: 422, name: "Gambia")),
        (["J5"], DXCCEntity(number: 109, name: "Guinea-Bissau")),
        (["3X"], DXCCEntity(number: 107, name: "Guinea")),
        (["9L"], DXCCEntity(number: 458, name: "Sierra Leone")),
        (["EL"], DXCCEntity(number: 434, name: "Liberia")),
        (["TU"], DXCCEntity(number: 428, name: "Cote d'Ivoire")),
        (["XT"], DXCCEntity(number: 480, name: "Burkina Faso")),
        (["9G"], DXCCEntity(number: 424, name: "Ghana")),
        (["5V"], DXCCEntity(number: 483, name: "Togo")),
        (["TY"], DXCCEntity(number: 416, name: "Benin")),
        (["5U"], DXCCEntity(number: 187, name: "Niger")),
        (["5N"], DXCCEntity(number: 450, name: "Nigeria")),

        // Central Africa
        (["TT"], DXCCEntity(number: 410, name: "Chad")),
        (["TL"], DXCCEntity(number: 408, name: "Central Africa")),
        (["TJ"], DXCCEntity(number: 406, name: "Cameroon")),
        (["3C"], DXCCEntity(number: 49, name: "Equatorial Guinea")),
        (["3C0"], DXCCEntity(number: 195, name: "Annobon I.")),
        (["TR"], DXCCEntity(number: 420, name: "Gabon")),
        (["S9"], DXCCEntity(number: 219, name: "Sao Tome & Principe")),
        (["TN"], DXCCEntity(number: 412, name: "Congo")),
        (["9Q", "9R", "9S", "9T"], DXCCEntity(number: 414, name: "Dem. Rep. of the Congo")),
        (["D2"], DXCCEntity(number: 401, name: "Angola")),

        // East Africa
        (["ST"], DXCCEntity(number: 466, name: "Sudan")),
        (["Z8"], DXCCEntity(number: 521, name: "South Sudan")),
        (["ET", "E3"], DXCCEntity(number: 53, name: "Ethiopia")),
        (["E3"], DXCCEntity(number: 51, name: "Eritrea")),
        (["J2"], DXCCEntity(number: 382, name: "Djibouti")),
        (["6O", "T5"], DXCCEntity(number: 232, name: "Somalia")),
        (["5Z"], DXCCEntity(number: 430, name: "Kenya")),
        (["5X"], DXCCEntity(number: 286, name: "Uganda")),
        (["5H"], DXCCEntity(number: 470, name: "Tanzania")),
        (["9U"], DXCCEntity(number: 404, name: "Burundi")),
        (["9X"], DXCCEntity(number: 454, name: "Rwanda")),

        // Southern Africa
        (["9J"], DXCCEntity(number: 482, name: "Zambia")),
        (["7Q"], DXCCEntity(number: 440, name: "Malawi")),
        (["C9"], DXCCEntity(number: 181, name: "Mozambique")),
        (["Z2"], DXCCEntity(number: 452, name: "Zimbabwe")),
        (["A2"], DXCCEntity(number: 402, name: "Botswana")),
        (["V5"], DXCCEntity(number: 464, name: "Namibia")),
        (["7P"], DXCCEntity(number: 432, name: "Lesotho")),
        (["3DA"], DXCCEntity(number: 468, name: "Kingdom of Eswatini")),
        (["ZS8"], DXCCEntity(number: 201, name: "Prince Edward & Marion Is.")),
        (["ZS", "ZR", "ZT", "ZU"], DXCCEntity(number: 462, name: "South Africa")),

        // Indian Ocean Africa
        (["5R"], DXCCEntity(number: 438, name: "Madagascar")),
        (["D6"], DXCCEntity(number: 411, name: "Comoros")),
        (["FT5Z", "FT/Z"], DXCCEntity(number: 10, name: "Amsterdam & St. Paul Is.")),
        (["FT5W", "FT/W"], DXCCEntity(number: 41, name: "Crozet I.")),
        (["FT5X", "FT/X"], DXCCEntity(number: 131, name: "Kerguelen Is.")),
        (["FH"], DXCCEntity(number: 169, name: "Mayotte")),
        (["FR", "FT"], DXCCEntity(number: 453, name: "Reunion I.")),
        (["FR/G", "FT/G"], DXCCEntity(number: 99, name: "Glorioso Is.")),
        (["FR/J", "FT/J"], DXCCEntity(number: 124, name: "Juan de Nova & Europa")),
        (["FR/T", "FT/T"], DXCCEntity(number: 276, name: "Tromelin I.")),
        (["3B6", "3B7"], DXCCEntity(number: 4, name: "Agalega & St. Brandon Is.")),
        (["3B8"], DXCCEntity(number: 165, name: "Mauritius")),
        (["3B9"], DXCCEntity(number: 207, name: "Rodrigues I.")),
        (["S7"], DXCCEntity(number: 379, name: "Seychelles")),
        (["D4"], DXCCEntity(number: 409, name: "Cabo Verde")),

        // Atlantic Ocean Africa
        (["ZD7"], DXCCEntity(number: 250, name: "St. Helena")),
        (["ZD8"], DXCCEntity(number: 205, name: "Ascension I.")),
        (["ZD9"], DXCCEntity(number: 274, name: "Tristan da Cunha & Gough I.")),

        // ==================== Special Entities ====================
        (["FO0C"], DXCCEntity(number: 36, name: "Clipperton I.")),
        (["VQ9"], DXCCEntity(number: 33, name: "Chagos Is.")),
        (["4U1I"], DXCCEntity(number: 117, name: "ITU HQ")),
        (["4U1U"], DXCCEntity(number: 289, name: "United Nations HQ")),
        (["1A"], DXCCEntity(number: 246, name: "Sov. Mil. Order of Malta")),
        (["BQ9"], DXCCEntity(number: 247, name: "Spratly Is.")),
        (["RI1F"], DXCCEntity(number: 61, name: "Franz Josef Land")),
        (["3Y0B"], DXCCEntity(number: 24, name: "Bouvet")),
        (["3Y0P"], DXCCEntity(number: 199, name: "Peter 1 I.")),
    ]
}
