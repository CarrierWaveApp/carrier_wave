// WWFF Representative Directory - Data
//
// Static data for WWFF national program representatives and DXCC mapping.
// Separated from the main directory for file length compliance.

import Foundation

extension WWFFRepresentativeDirectory {
    // MARK: - Representative Data

    // Source: WWFF Global Rules V5.10 and wwff.co/awards/national-programs/
    // Note: Email addresses included only where publicly listed by WWFF.
    // For unlisted emails, use QRZ.com lookup on the coordinator callsign.
    static let representatives: [WWFFRepresentative] = [
        WWFFRepresentative(
            id: "A6FF", programCode: "A6FF", country: "United Arab Emirates",
            coordinatorCallsign: "A65D", coordinatorName: "Patrick",
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "BYFF", programCode: "BYFF", country: "China",
            coordinatorCallsign: "BV2AAA", coordinatorName: nil,
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "CEFF", programCode: "CEFF", country: "Spain",
            coordinatorCallsign: "EA1AKS", coordinatorName: nil,
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "CTFF", programCode: "CTFF", country: "Portugal",
            coordinatorCallsign: "CT1END", coordinatorName: nil,
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "DAFF", programCode: "DAFF", country: "Germany",
            coordinatorCallsign: "DL7VOA", coordinatorName: nil,
            email: nil, website: "https://www.daff.info",
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "E7FF", programCode: "E7FF", country: "Bosnia and Herzegovina",
            coordinatorCallsign: "E71DX", coordinatorName: nil,
            email: nil, website: "https://e7ff.net",
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "EIFF", programCode: "EIFF", country: "Ireland",
            coordinatorCallsign: "EI3HGB", coordinatorName: "Jer",
            email: nil, website: nil,
            logManagerCallsign: "EI9HQ", awardManagerCallsign: "EI3HGB"
        ),
        WWFFRepresentative(
            id: "ERFF", programCode: "ERFF", country: "Moldova",
            coordinatorCallsign: "ER1DA", coordinatorName: nil,
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "ESFF", programCode: "ESFF", country: "Estonia",
            coordinatorCallsign: "ES1NOA", coordinatorName: "Timo",
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "FFF", programCode: "FFF", country: "France",
            coordinatorCallsign: "F5UKH", coordinatorName: nil,
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "GFF", programCode: "GFF", country: "United Kingdom",
            coordinatorCallsign: "G0OEY", coordinatorName: nil,
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "HAFF", programCode: "HAFF", country: "Hungary",
            coordinatorCallsign: "HA5BA", coordinatorName: nil,
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "HBFF", programCode: "HBFF", country: "Switzerland & Liechtenstein",
            coordinatorCallsign: "HB9DRM", coordinatorName: nil,
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: "HB9CBR"
        ),
        WWFFRepresentative(
            id: "HCFF", programCode: "HCFF", country: "Ecuador",
            coordinatorCallsign: "HC2IC", coordinatorName: nil,
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: "HC2TKV"
        ),
        WWFFRepresentative(
            id: "I44FF", programCode: "I44FF", country: "Italy",
            coordinatorCallsign: "IK1GPG", coordinatorName: nil,
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "JAFF", programCode: "JAFF", country: "Japan",
            coordinatorCallsign: "JH1NBN", coordinatorName: nil,
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "KFF", programCode: "KFF", country: "United States",
            coordinatorCallsign: "N9MM", coordinatorName: "Norm",
            email: "n9mm.norm@gmail.com", website: "https://wwff.us",
            logManagerCallsign: nil, awardManagerCallsign: "N9MM"
        ),
        WWFFRepresentative(
            id: "LUFF", programCode: "LUFF", country: "Argentina",
            coordinatorCallsign: "LU1DZ", coordinatorName: nil,
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "LYFF", programCode: "LYFF", country: "Lithuania",
            coordinatorCallsign: "LY2BOS", coordinatorName: nil,
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "LZFF", programCode: "LZFF", country: "Bulgaria",
            coordinatorCallsign: "LZ2HT", coordinatorName: "Ivan",
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "OEFF", programCode: "OEFF", country: "Austria",
            coordinatorCallsign: "OE5REO", coordinatorName: nil,
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "OHFF", programCode: "OHFF", country: "Finland",
            coordinatorCallsign: "OH6KZP", coordinatorName: "Kim",
            email: nil, website: nil,
            logManagerCallsign: "OH3KRH", awardManagerCallsign: "OH4MFA"
        ),
        WWFFRepresentative(
            id: "OKFF", programCode: "OKFF", country: "Czech Republic",
            coordinatorCallsign: "OK1IN", coordinatorName: nil,
            email: nil, website: nil,
            logManagerCallsign: "OK1VEI", awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "OMFF", programCode: "OMFF", country: "Slovakia",
            coordinatorCallsign: "OK2APY", coordinatorName: nil,
            email: nil, website: nil,
            logManagerCallsign: "OK2APY", awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "ONFF", programCode: "ONFF", country: "Belgium",
            coordinatorCallsign: "ON4BB", coordinatorName: nil,
            email: nil, website: "https://onffbelgium.blogspot.com",
            logManagerCallsign: "ON6EF", awardManagerCallsign: "ON5SWA"
        ),
        WWFFRepresentative(
            id: "PAFF", programCode: "PAFF", country: "Netherlands",
            coordinatorCallsign: "PA0INA", coordinatorName: nil,
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "PYFF", programCode: "PYFF", country: "Brazil",
            coordinatorCallsign: "PS8RV", coordinatorName: "Ronaldo",
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "S5FF", programCode: "S5FF", country: "Slovenia",
            coordinatorCallsign: "S50CLX", coordinatorName: nil,
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "SPFF", programCode: "SPFF", country: "Poland",
            coordinatorCallsign: "SP5XO", coordinatorName: nil,
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "SVFF", programCode: "SVFF", country: "Greece",
            coordinatorCallsign: "SV1GYG", coordinatorName: nil,
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "TAFF", programCode: "TAFF", country: "Turkey",
            coordinatorCallsign: "TA1EYE", coordinatorName: "Ersan",
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "URFF", programCode: "URFF", country: "Ukraine",
            coordinatorCallsign: "UR5WA", coordinatorName: nil,
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "VEFF", programCode: "VEFF", country: "Canada",
            coordinatorCallsign: "VA3QV", coordinatorName: nil,
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "VKFF", programCode: "VKFF", country: "Australia",
            coordinatorCallsign: "VK5PAS", coordinatorName: "Paul",
            email: nil, website: "https://www.wwffaustralia.com",
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "YOFF", programCode: "YOFF", country: "Romania",
            coordinatorCallsign: "YO3JW", coordinatorName: nil,
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "ZLFF", programCode: "ZLFF", country: "New Zealand",
            coordinatorCallsign: "VK5PAS", coordinatorName: "Paul",
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "ZSFF", programCode: "ZSFF", country: "South Africa",
            coordinatorCallsign: "ZS6TVB", coordinatorName: nil,
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
        WWFFRepresentative(
            id: "9AFF", programCode: "9AFF", country: "Croatia",
            coordinatorCallsign: "9A2MF", coordinatorName: nil,
            email: nil, website: nil,
            logManagerCallsign: nil, awardManagerCallsign: nil
        ),
    ]

    /// DXCC entity number to WWFF program code mapping.
    /// Used to look up representative when we only know the DXCC.
    static let dxccToProgramCode: [Int: String] = [
        1: "VEFF", // Canada
        6: "KFF", // United States (Alaska)
        100: "LUFF", // Argentina
        108: "PYFF", // Brazil
        110: "HCFF", // Ecuador
        209: "GFF", // England
        211: "EIFF", // Ireland
        212: "GFF", // Scotland
        213: "GFF", // Wales
        214: "GFF", // Northern Ireland
        215: "CEFF", // Spain
        227: "FFF", // France
        230: "DAFF", // Germany
        232: "SVFF", // Greece
        234: "HAFF", // Hungary
        236: "I44FF", // Italy
        239: "LYFF", // Lithuania
        245: "PAFF", // Netherlands
        248: "SPFF", // Poland
        263: "OEFF", // Austria
        269: "CTFF", // Portugal
        275: "YOFF", // Romania
        278: "S5FF", // Slovenia
        284: "HBFF", // Switzerland
        288: "URFF", // Ukraine
        291: "KFF", // United States
        292: "I44FF", // Italy (Sardinia)
        296: "TAFF", // Turkey
        318: "BYFF", // China
        339: "JAFF", // Japan
        340: "ESFF", // Estonia
        462: "VKFF", // Australia
        497: "ZSFF", // South Africa
        499: "OKFF", // Czech Republic
        502: "OMFF", // Slovakia
        503: "ONFF", // Belgium
        504: "LZFF", // Bulgaria
        507: "E7FF", // Bosnia & Herzegovina
        508: "9AFF", // Croatia
        514: "OHFF", // Finland
        520: "ERFF", // Moldova
        170: "ZLFF", // New Zealand
    ]
}
