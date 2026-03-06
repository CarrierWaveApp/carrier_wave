// Coastline Data
//
// Simplified continent outlines for rendering on azimuthal projection maps.
// ~350 coordinate pairs providing recognizable land/ocean contrast without
// requiring any mapping framework. Derived from Natural Earth (public domain).
//
// Each continent is a closed polygon of (lat, lon) pairs in degrees.

import Foundation

// MARK: - CoastlineData

public enum CoastlineData {
    /// All continent outlines as closed polygons of (lat, lon) pairs.
    public static let continents: [[(lat: Double, lon: Double)]] = [
        northAmerica,
        southAmerica,
        europeAfrica,
        asia,
        australia,
    ]
}

// MARK: - Continent Polygons

extension CoastlineData {
    // MARK: - North America (~70 points)

    static let northAmerica: [(lat: Double, lon: Double)] = [
        // Alaska / NW
        (64, -165), (68, -164), (71, -157), (71, -140),
        // Northern Canada / Arctic coast
        (69, -135), (70, -128), (69, -105), (63, -92),
        (66, -85), (63, -78), (70, -70), (73, -80),
        (75, -95), (73, -120), (76, -119),
        // NE Canada / Greenland gap
        (62, -64), (53, -56), (47, -53),
        // US East coast
        (46, -67), (43, -70), (41, -72), (39, -74),
        (35, -76), (32, -80), (30, -81), (25, -80),
        // Florida tip & Gulf
        (25, -81), (29, -83), (30, -87), (29, -89),
        (27, -97), (26, -97),
        // Mexico Pacific
        (23, -106), (20, -105), (16, -95),
        // Central America
        (14, -88), (10, -84), (8, -77),
        // Mexico / Baja
        (32, -117), (34, -120), (38, -123),
        // US West coast
        (42, -124), (46, -124), (48, -123),
        // BC / Alaska panhandle
        (50, -128), (54, -130), (57, -135),
        (59, -139), (60, -147), (62, -153), (64, -165),
    ]

    // MARK: - South America (~50 points)

    static let southAmerica: [(lat: Double, lon: Double)] = [
        (10, -72), (12, -72), (12, -68),
        // N coast / Venezuela
        (11, -62), (8, -60), (7, -55), (5, -52),
        // Brazil NE
        (0, -50), (-3, -38), (-8, -35), (-13, -39),
        // Brazil SE
        (-18, -39), (-23, -41), (-29, -49),
        // Uruguay / Argentina
        (-34, -53), (-36, -57), (-38, -58), (-41, -63),
        // Patagonia
        (-45, -66), (-48, -66), (-52, -68), (-55, -67),
        // Tierra del Fuego / southern tip
        (-55, -69), (-52, -75),
        // Chile coast
        (-47, -75), (-41, -73), (-33, -72), (-27, -71),
        (-18, -71), (-14, -76), (-5, -81),
        // Ecuador / Colombia
        (-1, -80), (2, -78), (7, -77), (8, -77),
        (10, -72),
    ]

    // MARK: - Europe + Africa (~80 points)

    static let europeAfrica: [(lat: Double, lon: Double)] = [
        // Iberia
        (36, -6), (37, -9), (43, -9), (43, -2),
        // France
        (46, -2), (48, -5), (49, -1), (51, 2),
        // North Sea / Scandinavia
        (54, 8), (57, 8), (58, 6), (62, 5),
        (65, 12), (68, 16), (70, 20), (71, 28),
        // Finland / Kola
        (70, 30), (66, 30), (60, 30),
        // Baltic
        (55, 20), (54, 14),
        // Germany / Poland coast
        (54, 10), (53, 7),
        // British Isles (simplified outline point)
        (51, 1),
        // Back to W Europe
        (47, -2), (44, -1),
        // Mediterranean
        (43, 3), (43, 6), (44, 9),
        // Italy
        (40, 15), (38, 16), (37, 15),
        // Greece / Turkey border
        (37, 22), (39, 26), (41, 29),
        // N Africa Mediterranean
        (37, 10), (37, 3), (36, -1), (36, -6),
        // Morocco Atlantic
        (34, -7), (32, -9), (28, -13),
        // W Africa
        (22, -17), (15, -17), (12, -16),
        (5, -4), (5, 2), (4, 9),
        // Gulf of Guinea / Central Africa
        (0, 9), (-4, 12), (-10, 14), (-17, 12),
        // S Africa
        (-29, 17), (-34, 18), (-34, 26),
        (-27, 33), (-24, 35),
        // E Africa
        (-12, 40), (-5, 40), (0, 42),
        (5, 45), (12, 44), (14, 43),
        // Horn / Red Sea
        (12, 50), (15, 42), (20, 37), (27, 34),
        // Suez / Egypt
        (30, 33), (32, 34), (36, 36),
        // closing back to Iberia through Mediterranean
        (36, -6),
    ]

    // MARK: - Asia (~80 points)

    static let asia: [(lat: Double, lon: Double)] = [
        // Turkey / Black Sea
        (41, 29), (42, 36), (42, 41),
        // Caucasus / Caspian
        (42, 44), (40, 50), (37, 54),
        // Iran / Persian Gulf
        (25, 57), (24, 54), (26, 50),
        // Arabian Peninsula
        (22, 55), (17, 54), (13, 45),
        (13, 43), (15, 42),
        // India
        (24, 68), (20, 73), (16, 73),
        (10, 76), (8, 77), (13, 80),
        (17, 83), (22, 87),
        // Bangladesh / Myanmar
        (22, 90), (21, 92), (16, 97),
        // SE Asia
        (10, 99), (7, 100), (1, 104),
        // Indonesia / Malaysia
        (-1, 104), (1, 110), (4, 118),
        // Philippines area
        (7, 117), (10, 119), (15, 120),
        (18, 122),
        // Taiwan / China coast
        (22, 120), (25, 120), (30, 122),
        (35, 120), (37, 122),
        // Korea
        (38, 127), (37, 129), (35, 129),
        (34, 126),
        // China / N coast
        (39, 118), (40, 120), (41, 122),
        // Manchuria / Russia Far East
        (43, 131), (46, 136), (51, 141),
        // Sakhalin / Kamchatka
        (55, 138), (59, 143), (60, 163),
        (62, 170), (64, 177),
        // Chukotka
        (66, -170), (65, -169),
        // Arctic Russia coast
        (70, 170), (72, 140), (73, 120),
        (72, 100), (70, 70), (68, 55),
        // Ural region / back to Turkey
        (60, 60), (55, 55), (50, 52),
        (45, 40), (42, 33), (41, 29),
    ]

    // MARK: - Australia (~35 points)

    static let australia: [(lat: Double, lon: Double)] = [
        // NW
        (-15, 124), (-13, 130), (-12, 132),
        // Top End / Gulf
        (-12, 136), (-14, 136), (-17, 140),
        // Cape York
        (-11, 142), (-16, 146),
        // E coast
        (-19, 147), (-23, 150), (-27, 153),
        (-32, 152), (-35, 151), (-37, 150),
        // SE / Victoria
        (-39, 146), (-39, 144),
        // Tasmania (approximate)
        (-41, 145), (-43, 147), (-41, 148),
        // SA coast
        (-38, 141), (-35, 137), (-35, 136),
        (-34, 137), (-33, 134),
        // Great Australian Bight
        (-34, 130), (-34, 124), (-33, 116),
        // SW
        (-35, 116), (-34, 115),
        // W coast
        (-31, 115), (-26, 113), (-22, 114),
        (-20, 119), (-15, 124),
    ]
}
