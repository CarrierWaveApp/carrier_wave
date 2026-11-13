import CarrierWaveData
import SwiftUI

// MARK: - Pass capture + quick log (P3)

/// The pointing screen's capture surface: REC PASS / giant MARK button while
/// the pass is up, and the post-LOS quick-log entry point. Split from
/// AntennaPointingView.swift for the 500-line file limit.
extension AntennaPointingView {
    /// Post-LOS quick log: appears whenever the bird is below the horizon —
    /// the moment operators actually log (from memory/scratch, after the pass).
    var quickLogButton: some View {
        Button {
            // The pass is over — retire its countdown Live Activity too.
            SatellitePassActivityController.shared.endIfPast()
            if let position = model.selectedPosition {
                pendingRecording = SatellitePassRecorder.shared
                    .recentRecording(noradID: position.noradID)
            }
            showQuickLog = true
        } label: {
            Label("Log pass QSOs", systemImage: "square.and.pencil")
                .font(.headline)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
        }
        .accessibilityLabel("Log QSOs from this pass")
    }

    @ViewBuilder
    var quickLogSheet: some View {
        if let position = model.selectedPosition {
            SatelliteQuickLogSheet(
                satName: position.name,
                detailName: position.detailName,
                transmitters: model.transmitters(for: position.noradID),
                pass: recentPass(at: Date()),
                observerGrid: model.observerCoordinate.map {
                    MaidenheadConverter.grid(from: $0, precision: .six)
                },
                recording: pendingRecording,
                onLogged: { _ in }
            )
        }
    }

    /// P3 capture: record the whole pass, tap MARK per contact, structure it
    /// after LOS from the recording. One giant mark button — both hands are
    /// on the boom and the radio, so the target has to be huge.
    @ViewBuilder
    var recordControls: some View {
        let recorder = SatellitePassRecorder.shared
        VStack(spacing: 6) {
            if recorder.isRecording {
                activeRecordingControls(recorder)
            } else if model.selectedPosition != nil {
                Button {
                    Task {
                        if let position = model.selectedPosition {
                            _ = await recorder.start(
                                noradID: position.noradID, satelliteName: position.name
                            )
                        }
                    }
                } label: {
                    Label("REC PASS", systemImage: "record.circle")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.25), in: Capsule())
                }
                .accessibilityLabel("Record pass audio")
                if recorder.permissionDenied {
                    Text("Microphone access denied — allow it in Settings to record")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: recorder.markCount)
    }

    func activeRecordingControls(_ recorder: SatellitePassRecorder) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    recorder.mark()
                } label: {
                    Label(
                        recorder.markCount == 0 ? "MARK" : "MARK \(recorder.markCount)",
                        systemImage: "flag.fill"
                    )
                    .font(.system(size: 22, weight: .black, design: .monospaced))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Color.orange.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
                }
                .accessibilityLabel("Mark a contact in the recording")
                Button {
                    recorder.stopIfRecording()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                }
                .accessibilityLabel("Stop recording")
            }
            if let started = recorder.recordingStartedAt {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                    Text("REC")
                    Text(started, style: .timer)
                        .monospacedDigit()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    /// The pass worth logging against: the one that ended within the last
    /// 30 minutes (post-LOS flow), else an in-progress pass, else nil.
    func recentPass(at date: Date) -> SatellitePass? {
        if let current = forecast.passes.first(where: { $0.isInProgress(at: date) }) {
            return current
        }
        return forecast.passes
            .filter { $0.los <= date && date.timeIntervalSince($0.los) < 30 * 60 }
            .max { $0.los < $1.los }
    }
}
