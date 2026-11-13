//
//  FT8AudioOverloadTracker.swift
//  CarrierWave
//

import Foundation

// MARK: - FT8AudioOverloadTracker

/// Detects sustained input overload that will destroy FT8 decodes — measured
/// on the FT8 sub-band (200–2900 Hz), not on the full audio bandwidth. The
/// historical wide-band peak detector mis-fired constantly: a single strong
/// adjacent-channel signal pegged the meter even though the FT8 passband
/// was healthy, and on busy bands the 5-second clip-fraction window could
/// not exit `.critical` between 12.6 s TX bursts.
///
/// We now require BOTH band-limited RMS in the danger range AND sustained
/// near-full-scale peaks to enter `.critical`. Either alone is normal:
/// strong but unclipped FT8 audio is high RMS without peak saturation, and
/// out-of-band carriers produce wide-band peak excursions without raising
/// in-band RMS.
///
/// A watchdog reverts the state to `.ok` if no level samples arrive for
/// over a second — covering the case where the audio engine pauses (route
/// change, interruption) while `state == .critical`, leaving the banner
/// stuck because nothing else calls `record()`.
@MainActor @Observable
final class FT8AudioOverloadTracker {
    // MARK: Internal

    enum State: Equatable {
        case ok
        case critical
    }

    private(set) var state: State = .ok

    func record(_ level: FT8AudioLevel) {
        let now = level.captureTime == .distantPast ? Date() : level.captureTime
        history.append(Sample(time: now, bandRMS: level.bandRMS, peak: level.peak))
        let cutoff = now.addingTimeInterval(-Self.window)
        history.removeAll { $0.time < cutoff }

        runWatchdog(now: now)

        guard history.count >= 8 else {
            commit(.ok, at: now)
            return
        }

        let clipping = history.filter { $0.peak >= Self.clipPeak }.count
        let clipFraction = Float(clipping) / Float(history.count)
        // Average band-limited dBFS over the window.
        let bandDBFS = history.map { Self.toDBFS($0.bandRMS) }
        let avgBandDBFS = bandDBFS.reduce(0, +) / Float(bandDBFS.count)

        let candidate = nextState(
            from: state,
            clipFraction: clipFraction,
            avgBandDBFS: avgBandDBFS
        )
        commit(candidate, at: now)
    }

    /// Reset to `.ok` and drop accumulated samples. Call when the audio
    /// engine stops, on route change, and when the user picks a different
    /// input — so the previous device's clipped peaks don't latch the
    /// banner against the new device.
    func reset() {
        state = .ok
        pendingState = .ok
        pendingSince = nil
        history.removeAll()
        lastSampleAt = nil
    }

    // MARK: Private

    private struct Sample {
        let time: Date
        let bandRMS: Float
        let peak: Float
    }

    private static let window: TimeInterval = 5.0

    /// Wide-band peak that counts as ADC clipping. Kept very near full-scale
    /// because the band-limited RMS gate is what carries most of the signal.
    private static let clipPeak: Float = 0.99

    /// Fraction of buffers in the window that must hit `clipPeak` to count
    /// as "ADC is actually saturating," not just transient.
    private static let enterClipFraction: Float = 0.50
    private static let exitClipFraction: Float = 0.25

    /// Band-limited average level (in dBFS) above which FT8 audio is
    /// considered too hot. -3 dBFS leaves no headroom for the GFSK crest
    /// factor; below ~-12 dBFS even a strong band is fine.
    private static let enterBandDBFS: Float = -3
    private static let exitBandDBFS: Float = -10

    /// Dwell required before a state change is committed. Avoids flapping
    /// on transient bursts.
    private static let minDwell: TimeInterval = 1.5

    /// If `state == .critical` and no new sample arrives within this many
    /// seconds, the watchdog forces back to `.ok`. The engine emits ~10
    /// level updates per second when running, so a 1.5 s gap is a clear
    /// signal that capture has stalled (route change in progress,
    /// interruption, or the session was stopped). Without this, the banner
    /// can stick across a pause because nothing else calls `record()`.
    private static let watchdogTimeout: TimeInterval = 1.5

    private var history: [Sample] = []
    private var pendingState: State = .ok
    private var pendingSince: Date?
    private var lastSampleAt: Date?

    private static func toDBFS(_ rms: Float) -> Float {
        guard rms > 1e-6 else {
            return -120
        }
        return 20 * log10(rms)
    }

    private func runWatchdog(now: Date) {
        if let last = lastSampleAt,
           state == .critical,
           now.timeIntervalSince(last) >= Self.watchdogTimeout
        {
            // Capture pause: drop old samples and let the new arrivals decide.
            history.removeAll()
            state = .ok
            pendingState = .ok
            pendingSince = nil
        }
        lastSampleAt = now
    }

    private func nextState(
        from current: State,
        clipFraction: Float,
        avgBandDBFS: Float
    ) -> State {
        let bandTooHot = avgBandDBFS >= Self.enterBandDBFS
        let bandRecovered = avgBandDBFS < Self.exitBandDBFS
        let peaksClipping = clipFraction >= Self.enterClipFraction
        let peaksClear = clipFraction < Self.exitClipFraction
        switch current {
        case .critical:
            return (bandRecovered || peaksClear) ? .ok : .critical
        case .ok:
            return (bandTooHot && peaksClipping) ? .critical : .ok
        }
    }

    private func commit(_ candidate: State, at now: Date) {
        if candidate == state {
            pendingState = state
            pendingSince = nil
            return
        }
        if candidate != pendingState {
            pendingState = candidate
            pendingSince = now
            return
        }
        if let since = pendingSince, now.timeIntervalSince(since) >= Self.minDwell {
            state = candidate
            pendingSince = nil
        }
    }
}
