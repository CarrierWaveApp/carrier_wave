import CarrierWaveData
import Foundation

// MARK: - ContinentMapper

/// Maps DXCC entity numbers to continents.
/// Uses standard ITU/DXCC continent assignments.
nonisolated enum ContinentMapper {
    // MARK: Internal

    /// The 6 inhabited continents used in amateur radio.
    static let allContinents = ["NA", "SA", "EU", "AF", "AS", "OC"]

    /// Map a DXCC entity number to its continent abbreviation.
    static func continent(forDXCC number: Int) -> String? {
        // North America
        if northAmerica.contains(number) {
            return "NA"
        }
        // South America
        if southAmerica.contains(number) {
            return "SA"
        }
        // Europe
        if europe.contains(number) {
            return "EU"
        }
        // Africa
        if africa.contains(number) {
            return "AF"
        }
        // Asia
        if asia.contains(number) {
            return "AS"
        }
        // Oceania
        if oceania.contains(number) {
            return "OC"
        }
        return nil
    }

    /// Display name for continent abbreviation.
    static func displayName(_ abbrev: String) -> String {
        switch abbrev {
        case "NA": "North America"
        case "SA": "South America"
        case "EU": "Europe"
        case "AF": "Africa"
        case "AS": "Asia"
        case "OC": "Oceania"
        default: abbrev
        }
    }

    // MARK: Private

    // MARK: - Continent Entity Sets

    /// Key North American DXCC entity numbers.
    private static let northAmerica: Set<Int> = [
        1, 6, 8, 9, 10, 11, 20, 21, 31, 39, 43, 44, 49, 51,
        57, 63, 65, 72, 78, 84, 89, 94, 96, 97, 98, 100, 105,
        106, 109, 110, 112, 182, 191, 230, 246, 248, 249, 285,
        287, 288, 289, 291, // 291 = USA
    ]

    /// Key South American DXCC entity numbers.
    private static let southAmerica: Set<Int> = [
        12, 13, 47, 55, 56, 70, 73, 80, 82, 100, 104, 108, 116,
        117, 120, 128, 131, 132, 144, 148, 149, 153, 159, 171,
    ]

    /// Key European DXCC entity numbers.
    private static let europe: Set<Int> = [
        4, 5, 7, 14, 15, 17, 21, 27, 29, 32, 33, 34, 36, 37,
        40, 45, 46, 50, 52, 54, 58, 59, 61, 62, 66, 67, 68,
        71, 74, 75, 77, 79, 83, 85, 86, 88, 90, 91, 93, 95,
        99, 103, 107, 111, 114, 118, 121, 122, 123, 126, 129,
        130, 135, 136, 137, 140, 142, 143, 145, 146, 147, 150,
        151, 155, 156, 158, 160, 162, 163, 164, 165, 167, 169,
        170, 179, 180, 185, 190, 192, 206, 207, 209, 211, 212,
        214, 215, 216, 217, 221, 222, 223, 224, 225, 226, 227,
        232, 233, 239, 242, 245, 247, 251, 252, 254, 256, 257,
        259, 260, 261, 262, 263, 264, 265, 266, 269, 272, 273,
        274, 275, 276, 277, 278, 279, 280, 281, 282, 283, 284,
        286, 296, 503, 504, 514,
    ]

    /// Key African DXCC entity numbers.
    private static let africa: Set<Int> = [
        3, 18, 22, 24, 25, 26, 35, 38, 48, 53, 57, 60, 64, 69,
        76, 81, 87, 102, 115, 119, 124, 125, 127, 133, 134, 138,
        139, 141, 145, 168, 173, 174, 175, 176, 177, 188, 195,
        197, 201, 202, 208, 213, 218, 219, 220, 228, 298, 400,
        401, 402, 403, 404, 406, 407, 408, 409, 410, 411, 412,
        414, 416, 417, 420, 421, 422, 424, 428, 430, 432, 434,
        436, 438, 440, 442, 444, 446, 448, 450, 452, 453, 454,
        456, 458, 460, 462, 464, 466, 468, 470, 474, 478, 480,
        482, 483, 484, 488, 489, 490, 492,
    ]

    /// Key Asian DXCC entity numbers.
    private static let asia: Set<Int> = [
        2, 6, 15, 17, 23, 33, 41, 42, 50, 54, 55, 68, 75, 78,
        165, 166, 170, 183, 187, 294, 295, 297, 299, 301, 302,
        303, 305, 306, 308, 309, 312, 318, 321, 327, 330, 333,
        336, 339, 342, 345, 348, 354, 363, 369, 370, 372, 375,
        376, 378, 379, 381, 382, 384, 386, 387, 390, 391, 393,
        395, 497, 499, 501, 502, 505, 506, 507, 509, 510, 511,
        513, 515, 516, 517, 518, 519, 520, 521, 522,
    ]

    /// Key Oceanian DXCC entity numbers.
    private static let oceania: Set<Int> = [
        9, 16, 19, 28, 30, 32, 103, 110, 123, 134, 138, 147,
        150, 152, 157, 160, 161, 169, 171, 172, 175, 176, 180,
        181, 186, 189, 190, 193, 194, 196, 197, 203, 204, 240,
        301, 508, 512, 515,
    ]
}
