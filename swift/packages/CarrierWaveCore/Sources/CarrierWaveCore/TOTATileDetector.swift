//
//  TOTATileDetector.swift
//  CarrierWaveCore
//
//  QSO-anchored tile detection. Given a list of track samples, a list of
//  QSO timestamps, and the declared activation coordinate, returns the
//  set of 6-char Maidenhead tiles that count as activated, plus the
//  candidate set (tiles the track passed through but no QSO anchored).
//
//  Algorithm:
//   1. For each QSO timestamp, find the nearest two TilePathSamples and
//      linearly interpolate position; convert to a 6-char tile.
//   2. Always include the tile of `activationCoord` (declared site).
//   3. The "candidate" set is all tiles touched by the track minus the
//      activated set.
//

import Foundation

// MARK: - TilePathSample

/// One GPS sample. Mirrors `CarrierWaveData.TrackPoint` without the SwiftData
/// dependency so the engine stays pure.
public struct TilePathSample: Sendable, Equatable {
    // MARK: Lifecycle

    public init(timestamp: Date, latitude: Double, longitude: Double) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
    }

    // MARK: Public

    public let timestamp: Date
    public let latitude: Double
    public let longitude: Double
}

// MARK: - TileDetectionResult

public struct TileDetectionResult: Sendable, Equatable {
    // MARK: Lifecycle

    public init(activated: [String], candidates: [String]) {
        self.activated = activated
        self.candidates = candidates
    }

    // MARK: Public

    /// Tiles credited to this activation (QSO-anchored or declared).
    public let activated: [String]
    /// Tiles the track passed through but no QSO was anchored to.
    public let candidates: [String]
}

// MARK: - TOTATileDetector

public enum TOTATileDetector: Sendable {
    // MARK: Public

    /// Detect activated and candidate tiles.
    /// - Parameters:
    ///   - track: Track samples in any order. Empty = no track recorded.
    ///   - qsoTimestamps: Timestamps of logged QSOs.
    ///   - activationCoord: Declared activation coordinate (always-included tile).
    public static func detect(
        track: [TilePathSample],
        qsoTimestamps: [Date],
        activationCoord: (latitude: Double, longitude: Double)?
    ) -> TileDetectionResult {
        var activated = Set<String>()
        if let coord = activationCoord {
            let tile = MaidenheadConverter.grid(
                from: Coordinate(latitude: coord.latitude, longitude: coord.longitude)
            )
            activated.insert(tile)
        }

        let sortedTrack = track.sorted { $0.timestamp < $1.timestamp }

        // QSO-anchored tiles
        for ts in qsoTimestamps {
            guard let sample = interpolatedSample(in: sortedTrack, at: ts) else {
                continue
            }
            let tile = MaidenheadConverter.grid(
                from: Coordinate(latitude: sample.latitude, longitude: sample.longitude)
            )
            activated.insert(tile)
        }

        // Candidate set: tiles touched by track but not activated
        var touched = Set<String>()
        for sample in sortedTrack {
            let tile = MaidenheadConverter.grid(
                from: Coordinate(latitude: sample.latitude, longitude: sample.longitude)
            )
            touched.insert(tile)
        }
        let candidates = touched.subtracting(activated)

        return TileDetectionResult(
            activated: activated.sorted(),
            candidates: candidates.sorted()
        )
    }

    // MARK: Internal

    // MARK: Internal — visible to tests

    /// Interpolate a sample for the given timestamp from a sorted-by-timestamp
    /// track. Returns nil when timestamp is outside the track range.
    static func interpolatedSample(
        in sortedTrack: [TilePathSample],
        at timestamp: Date
    ) -> TilePathSample? {
        guard !sortedTrack.isEmpty else {
            return nil
        }
        guard let first = sortedTrack.first, let last = sortedTrack.last else {
            return nil
        }
        if timestamp < first.timestamp || timestamp > last.timestamp {
            return nil
        }
        // Find the two nearest samples bracketing the timestamp
        var before = first
        var after = last
        for sample in sortedTrack {
            if sample.timestamp <= timestamp {
                before = sample
            } else {
                after = sample
                break
            }
        }
        let span = after.timestamp.timeIntervalSince(before.timestamp)
        guard span > 0 else {
            return before
        }
        let frac = timestamp.timeIntervalSince(before.timestamp) / span
        let lat = before.latitude + (after.latitude - before.latitude) * frac
        let lon = before.longitude + (after.longitude - before.longitude) * frac
        return TilePathSample(timestamp: timestamp, latitude: lat, longitude: lon)
    }
}
