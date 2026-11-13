//
//  FT8AudioLevel.swift
//  CarrierWave
//

import Foundation

/// Snapshot of input audio loudness for the level meter and overload tracker.
///
/// `rms`/`peak` are wide-band stats on the post-decimation signal (0–6 kHz)
/// and are kept for diagnostics — wide-band peak alone is a poor clipping
/// signal because adjacent-channel signals (broadcast splatter, out-of-band
/// carriers) peg it without affecting FT8 decoding.
///
/// `bandRMS`/`bandPeak` are measured on the same samples after a 200–2900 Hz
/// band-pass and are the correct measure of FT8-relevant level. The meter
/// and overload tracker both work off these.
///
/// `captureTime` is set inside the audio actor at the moment the buffer is
/// processed. The overload tracker uses it (rather than `Date()` at
/// `record` time) so a backlog of level-update tasks on the main actor
/// can't collapse multiple historical samples onto the same timestamp and
/// instantly fill the rolling clip window.
struct FT8AudioLevel: Equatable {
    static let zero = FT8AudioLevel(
        rms: 0,
        peak: 0,
        bandRMS: 0,
        bandPeak: 0,
        captureTime: .distantPast
    )

    let rms: Float
    let peak: Float
    let bandRMS: Float
    let bandPeak: Float
    let captureTime: Date
}
