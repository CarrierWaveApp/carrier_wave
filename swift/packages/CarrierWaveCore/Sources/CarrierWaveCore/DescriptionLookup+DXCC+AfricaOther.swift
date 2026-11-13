import Foundation

// MARK: - DXCC Africa & Other Region Data

nonisolated public extension DescriptionLookup {
    /// DXCC entities for Africa, Indian Ocean, Atlantic Ocean, special entities
    nonisolated(unsafe) static let dxccEntitiesAfricaOther: [(prefixes: [String], entity: DXCCEntityRef)] = [
        // ==================== Africa ====================
        // North Africa
        (["SU"], DXCCEntityRef(number: 478, name: "Egypt")),
        (["5A"], DXCCEntityRef(number: 436, name: "Libya")),
        (["3V", "TS"], DXCCEntityRef(number: 474, name: "Tunisia")),
        (["7X"], DXCCEntityRef(number: 400, name: "Algeria")),
        (["CN", "5C", "5D", "5E", "5F", "5G"], DXCCEntityRef(number: 446, name: "Morocco")),
        (["S0"], DXCCEntityRef(number: 302, name: "Western Sahara")),

        // West Africa
        (["5T"], DXCCEntityRef(number: 444, name: "Mauritania")),
        (["6W"], DXCCEntityRef(number: 456, name: "Senegal")),
        (["C5"], DXCCEntityRef(number: 422, name: "Gambia")),
        (["J5"], DXCCEntityRef(number: 109, name: "Guinea-Bissau")),
        (["3X"], DXCCEntityRef(number: 107, name: "Guinea")),
        (["9L"], DXCCEntityRef(number: 458, name: "Sierra Leone")),
        (["EL"], DXCCEntityRef(number: 434, name: "Liberia")),
        (["TU"], DXCCEntityRef(number: 428, name: "Cote d'Ivoire")),
        (["XT"], DXCCEntityRef(number: 480, name: "Burkina Faso")),
        (["9G"], DXCCEntityRef(number: 424, name: "Ghana")),
        (["5V"], DXCCEntityRef(number: 483, name: "Togo")),
        (["TY"], DXCCEntityRef(number: 416, name: "Benin")),
        (["5U"], DXCCEntityRef(number: 187, name: "Niger")),
        (["5N"], DXCCEntityRef(number: 450, name: "Nigeria")),

        // Central Africa
        (["TT"], DXCCEntityRef(number: 410, name: "Chad")),
        (["TL"], DXCCEntityRef(number: 408, name: "Central Africa")),
        (["TJ"], DXCCEntityRef(number: 406, name: "Cameroon")),
        (["3C"], DXCCEntityRef(number: 49, name: "Equatorial Guinea")),
        (["3C0"], DXCCEntityRef(number: 195, name: "Annobon I.")),
        (["TR"], DXCCEntityRef(number: 420, name: "Gabon")),
        (["S9"], DXCCEntityRef(number: 219, name: "Sao Tome & Principe")),
        (["TN"], DXCCEntityRef(number: 412, name: "Congo")),
        (["9Q", "9R", "9S", "9T"], DXCCEntityRef(number: 414, name: "Dem. Rep. of the Congo")),
        (["D2"], DXCCEntityRef(number: 401, name: "Angola")),

        // East Africa
        (["ST"], DXCCEntityRef(number: 466, name: "Sudan")),
        (["Z8"], DXCCEntityRef(number: 521, name: "South Sudan")),
        (["ET", "E3"], DXCCEntityRef(number: 53, name: "Ethiopia")),
        (["E3"], DXCCEntityRef(number: 51, name: "Eritrea")),
        (["J2"], DXCCEntityRef(number: 382, name: "Djibouti")),
        (["6O", "T5"], DXCCEntityRef(number: 232, name: "Somalia")),
        (["5Z"], DXCCEntityRef(number: 430, name: "Kenya")),
        (["5X"], DXCCEntityRef(number: 286, name: "Uganda")),
        (["5H"], DXCCEntityRef(number: 470, name: "Tanzania")),
        (["9U"], DXCCEntityRef(number: 404, name: "Burundi")),
        (["9X"], DXCCEntityRef(number: 454, name: "Rwanda")),

        // Southern Africa
        (["9J"], DXCCEntityRef(number: 482, name: "Zambia")),
        (["7Q"], DXCCEntityRef(number: 440, name: "Malawi")),
        (["C9"], DXCCEntityRef(number: 181, name: "Mozambique")),
        (["Z2"], DXCCEntityRef(number: 452, name: "Zimbabwe")),
        (["A2"], DXCCEntityRef(number: 402, name: "Botswana")),
        (["V5"], DXCCEntityRef(number: 464, name: "Namibia")),
        (["7P"], DXCCEntityRef(number: 432, name: "Lesotho")),
        (["3DA"], DXCCEntityRef(number: 468, name: "Kingdom of Eswatini")),
        (["ZS8"], DXCCEntityRef(number: 201, name: "Prince Edward & Marion Is.")),
        (["ZS", "ZR", "ZT", "ZU"], DXCCEntityRef(number: 462, name: "South Africa")),

        // Indian Ocean Africa
        (["5R"], DXCCEntityRef(number: 438, name: "Madagascar")),
        (["D6"], DXCCEntityRef(number: 411, name: "Comoros")),
        (["FT5Z", "FT/Z"], DXCCEntityRef(number: 10, name: "Amsterdam & St. Paul Is.")),
        (["FT5W", "FT/W"], DXCCEntityRef(number: 41, name: "Crozet I.")),
        (["FT5X", "FT/X"], DXCCEntityRef(number: 131, name: "Kerguelen Is.")),
        (["FH"], DXCCEntityRef(number: 169, name: "Mayotte")),
        (["FR", "FT"], DXCCEntityRef(number: 453, name: "Reunion I.")),
        (["FR/G", "FT/G"], DXCCEntityRef(number: 99, name: "Glorioso Is.")),
        (["FR/J", "FT/J"], DXCCEntityRef(number: 124, name: "Juan de Nova & Europa")),
        (["FR/T", "FT/T"], DXCCEntityRef(number: 276, name: "Tromelin I.")),
        (["3B6", "3B7"], DXCCEntityRef(number: 4, name: "Agalega & St. Brandon Is.")),
        (["3B8"], DXCCEntityRef(number: 165, name: "Mauritius")),
        (["3B9"], DXCCEntityRef(number: 207, name: "Rodrigues I.")),
        (["S7"], DXCCEntityRef(number: 379, name: "Seychelles")),
        (["D4"], DXCCEntityRef(number: 409, name: "Cabo Verde")),

        // Atlantic Ocean Africa
        (["ZD7"], DXCCEntityRef(number: 250, name: "St. Helena")),
        (["ZD8"], DXCCEntityRef(number: 205, name: "Ascension I.")),
        (["ZD9"], DXCCEntityRef(number: 274, name: "Tristan da Cunha & Gough I.")),

        // ==================== Special Entities ====================
        (["FO0C"], DXCCEntityRef(number: 36, name: "Clipperton I.")),
        (["VQ9"], DXCCEntityRef(number: 33, name: "Chagos Is.")),
        (["4U1I"], DXCCEntityRef(number: 117, name: "ITU HQ")),
        (["4U1U"], DXCCEntityRef(number: 289, name: "United Nations HQ")),
        (["1A"], DXCCEntityRef(number: 246, name: "Sov. Mil. Order of Malta")),
        (["BQ9"], DXCCEntityRef(number: 247, name: "Spratly Is.")),
        (["RI1F"], DXCCEntityRef(number: 61, name: "Franz Josef Land")),
        (["3Y0B"], DXCCEntityRef(number: 24, name: "Bouvet")),
        (["3Y0P"], DXCCEntityRef(number: 199, name: "Peter 1 I.")),
    ]
}
