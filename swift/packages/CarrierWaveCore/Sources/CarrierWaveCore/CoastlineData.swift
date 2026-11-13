// Coastline Data (Natural Earth 110m)
//
// Land polygon outlines from Natural Earth 1:110m (public domain).
// ~4982 coordinate pairs across 103 polygons. Each polygon is a
// closed ring of (lat, lon) pairs in degrees.
//
// Source: https://www.naturalearthdata.com/downloads/110m-physical-vectors/
// License: Public Domain
//
// Data is split across extension files to stay within SwiftLint limits:
//   CoastlineData.swift
//   CoastlineData.swift
//   CoastlineData.swift
//   CoastlineData.swift
//   CoastlineData.swift
//   CoastlineData.swift

import Foundation

// MARK: - CoastlineData

public enum CoastlineData {
    /// All land polygon outlines as closed rings of (lat, lon) pairs.
    public static let continents: [[(lat: Double, lon: Double)]] =
        part1 + part2 + part3 + part4 + part5 + part6
}
