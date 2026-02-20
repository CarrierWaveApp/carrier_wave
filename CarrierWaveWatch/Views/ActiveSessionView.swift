import SwiftUI

/// Active session display showing QSO count, callsign, and activation progress.
/// Supports both WatchConnectivity live data and App Group snapshot fallback.
struct ActiveSessionView: View {
    // MARK: Lifecycle

    /// Initialize from WatchConnectivity live session
    init(liveSession: WatchLiveSession) {
        _qsoCount = State(initialValue: liveSession.qsoCount)
        _lastCallsign = State(initialValue: liveSession.lastCallsign)
        _frequency = State(initialValue: liveSession.frequency)
        _band = State(initialValue: liveSession.band)
        _mode = State(initialValue: liveSession.mode)
        _parkReference = State(initialValue: liveSession.parkReference)
        _activationType = State(initialValue: liveSession.activationType)
        _startedAt = State(initialValue: liveSession.startedAt)
        _myCallsign = State(initialValue: liveSession.myCallsign)
        _currentStopPark = State(initialValue: liveSession.currentStopPark)
        _stopNumber = State(initialValue: liveSession.stopNumber)
        _currentStopQSOs = State(initialValue: liveSession.currentStopQSOs)
        isLive = true
    }

    /// Initialize from App Group snapshot (fallback)
    init(session: WatchSessionSnapshot) {
        _qsoCount = State(initialValue: session.qsoCount)
        _lastCallsign = State(initialValue: session.lastCallsign)
        _frequency = State(initialValue: session.frequency)
        _band = State(initialValue: nil)
        _mode = State(initialValue: session.mode)
        _parkReference = State(initialValue: session.parkReference)
        _activationType = State(initialValue: session.activationType)
        _startedAt = State(initialValue: session.startedAt)
        _myCallsign = State(initialValue: nil)
        _currentStopPark = State(initialValue: nil)
        _stopNumber = State(initialValue: nil)
        _currentStopQSOs = State(initialValue: nil)
        isLive = false
    }

    // MARK: Internal

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                timerAndMode
                qsoDisplay
                callsignDisplay
                sessionInfo
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: Private

    @State private var qsoCount: Int
    @State private var lastCallsign: String?
    @State private var frequency: String?
    @State private var band: String?
    @State private var mode: String?
    @State private var parkReference: String?
    @State private var activationType: String?
    @State private var startedAt: Date?
    @State private var myCallsign: String?
    @State private var currentStopPark: String?
    @State private var stopNumber: Int?
    @State private var currentStopQSOs: Int?
    private let isLive: Bool

    private var isPOTA: Bool {
        activationType == "pota"
    }

    private var isRove: Bool {
        currentStopPark != nil
    }

    // MARK: - Timer and Mode

    private var timerAndMode: some View {
        HStack {
            if let startedAt {
                Text(startedAt, style: .timer)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let mode {
                Text(mode)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    // MARK: - QSO Count / Progress Ring

    @ViewBuilder
    private var qsoDisplay: some View {
        if isPOTA, qsoCount < 10 {
            // Show activation progress ring for POTA under 10 QSOs
            ActivationProgressRing(
                qsoCount: qsoCount,
                target: 10
            )
        } else if isRove, let stopQSOs = currentStopQSOs {
            // Rove: show stop progress + total
            VStack(spacing: 2) {
                ActivationProgressRing(
                    qsoCount: stopQSOs,
                    target: 10
                )
                HStack(spacing: 4) {
                    Text("\(qsoCount) total")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if let stop = stopNumber {
                        Text("Stop \(stop)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        } else {
            // Large QSO count
            Text("\(qsoCount)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isPOTA ? .green : .primary)
            Text(qsoCount == 1 ? "QSO" : "QSOs")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Last Callsign

    @ViewBuilder
    private var callsignDisplay: some View {
        if let callsign = lastCallsign {
            Text(callsign)
                .font(.system(.title3, design: .monospaced, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: - Session Info

    private var sessionInfo: some View {
        VStack(spacing: 2) {
            if let park = currentStopPark ?? parkReference {
                Text(park)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                    .lineLimit(1)
            }
            if let freq = frequency, let band {
                Text("\(freq) MHz \u{00B7} \(band)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else if let freq = frequency {
                Text("\(freq) MHz")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
