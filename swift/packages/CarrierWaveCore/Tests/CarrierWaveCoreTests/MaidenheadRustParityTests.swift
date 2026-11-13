//
//  MaidenheadRustParityTests.swift
//  CarrierWaveCoreTests
//
//  Parity gate for the Maidenhead port (see
//  docs/plans/2026-06-13-rust-core-handoff.md, Phase 2 mechanical ports).
//
//  Runs the same inputs through the legacy Swift `MaidenheadConverter` and the
//  Rust `cw-domain::maidenhead` impl via UniFFI. Asserts agreement on the
//  observable surface: coordinate from grid (sub-arc-second precision), grid
//  from coordinate (exact string), distance/bearing (within 0.01 km / 0.01°),
//  validity.
//

import Testing
@testable import CarrierWaveCore

struct MaidenheadRustParityTests {
    // MARK: Internal

    @Test("Rust parity: coordinate(from:) matches Swift")
    func coordinateMatches() {
        for grid in Self.grids {
            let swift = MaidenheadConverter.coordinate(from: grid)
            let rust = MaidenheadConverter.coordinateViaRust(from: grid)

            switch (swift, rust) {
            case (nil, nil):
                continue
            case let (sw?, ru?):
                #expect(abs(sw.latitude - ru.latitude) < 1e-9, "lat mismatch for \(grid)")
                #expect(abs(sw.longitude - ru.longitude) < 1e-9, "lon mismatch for \(grid)")
            default:
                Issue.record(
                    "nullability mismatch for \(grid): swift=\(swift as Any) rust=\(rust as Any)"
                )
            }
        }
    }

    @Test("Rust parity: grid(from:precision:) matches Swift")
    func gridMatches() {
        for (lat, lon) in Self.coordinates {
            let coord = Coordinate(latitude: lat, longitude: lon)
            for precision in MaidenheadConverter.Precision.allCases {
                let swift = MaidenheadConverter.grid(from: coord, precision: precision)
                let rust = MaidenheadConverter.gridViaRust(from: coord, precision: precision)
                #expect(
                    swift == rust,
                    "grid mismatch at (\(lat),\(lon)) precision=\(precision): swift=\(swift) rust=\(rust)"
                )
            }
        }
    }

    @Test("Rust parity: distance + bearing match Swift")
    func distanceAndBearingMatch() {
        let pairs: [(String, String)] = [
            ("FN31pr", "EM73uu"),
            ("FN31pr", "DM12"),
            ("FN31", "JN58td"),
            ("AA00aa", "RR99xx"),
        ]
        for (a, b) in pairs {
            let sd = MaidenheadConverter.distanceKm(from: a, to: b)
            let rd = MaidenheadConverter.distanceKmViaRust(from: a, to: b)
            if let sd, let rd {
                #expect(abs(sd - rd) < 0.01, "distance mismatch \(a)→\(b): swift=\(sd) rust=\(rd)")
            } else {
                #expect(sd == nil && rd == nil, "distance nullability mismatch for \(a)→\(b)")
            }

            let sb = MaidenheadConverter.bearing(from: a, to: b)
            let rb = MaidenheadConverter.bearingViaRust(from: a, to: b)
            if let sb, let rb {
                #expect(abs(sb - rb) < 0.01, "bearing mismatch \(a)→\(b): swift=\(sb) rust=\(rb)")
            } else {
                #expect(sb == nil && rb == nil, "bearing nullability mismatch for \(a)→\(b)")
            }
        }
    }

    @Test("Rust parity: isValid matches Swift")
    func validityMatches() {
        for grid in Self.grids + ["", "ZZ", "garbage", "FN3", "FN3A"] {
            let swift = MaidenheadConverter.isValid(grid)
            let rust = MaidenheadConverter.isValidViaRust(grid)
            #expect(swift == rust, "validity mismatch for '\(grid)': swift=\(swift) rust=\(rust)")
        }
    }

    // MARK: Private

    private static let grids: [String] = [
        "FN31", // 4-char
        "FN31pr", // 6-char (W1AW)
        "EM73uu", // 6-char (Nashville area)
        "JN58td", // Munich area, southern hemisphere edge
        "RR73", // valid 4-char
        "AA00aa", // SW corner
        "RR99xx", // NE corner
        "FN31pr12", // 8-char extended
    ]

    private static let coordinates: [(lat: Double, lon: Double)] = [
        (41.7292, -72.4583), // W1AW
        (37.7749, -122.4194), // San Francisco
        (-33.8688, 151.2093), // Sydney (Southern hemisphere)
        (51.5074, -0.1278), // London
        (0.0, 0.0), // Equator/prime meridian
        (-89.9, -179.9), // Near SW corner
        (89.9, 179.9), // Near NE corner
    ]
}
