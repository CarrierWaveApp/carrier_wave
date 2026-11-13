import CarrierWaveData
import SwiftUI

// MARK: - ActivationHeader + POTA Spot Controls

/// Spot button + auto re-spot toggle that appear in the activator
/// header for any session with a `parkReference`. Lives in an
/// extension so the main `ActivationHeader` body stays under the
/// type-body-length limit.
extension ActivationHeader {
    @ViewBuilder
    func potaSpotControls(_ session: LoggingSession) -> some View {
        // Only POTA sessions get the spot row — SOTA/WWFF have their own
        // workflows and the API call here is POTA-specific.
        if session.parkReference != nil {
            Divider().frame(height: 28)

            HStack(spacing: 6) {
                spotButton
                respotToggle

                if let nextSpot = spotService.nextSpotDate {
                    Text(nextSpot, style: .timer)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 36, alignment: .leading)
                }

                if let last = lastSpotSentAt {
                    Text(last, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .help("Last spot sent")
                }
            }
        }
    }

    private var spotButton: some View {
        Button {
            Task { await postSpotNow() }
        } label: {
            HStack(spacing: 4) {
                if isSpotting {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.caption2)
                }
                Text("Spot")
                    .font(.caption.bold())
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .tint(.accentColor)
        .disabled(isSpotting)
        .help(spotButtonHelp)
    }

    private var respotToggle: some View {
        Toggle(isOn: respotBinding) {
            Image(systemName: "repeat")
                .font(.caption2)
        }
        .toggleStyle(.button)
        .controlSize(.small)
        .help(respotToggleHelp)
    }

    private var spotButtonHelp: String {
        if isSpotting {
            return "Posting spot…"
        }
        return "Post a self-spot to POTA at the current frequency and mode"
    }

    private var respotToggleHelp: String {
        spotService.isReSpotTimerActive
            ? "Auto re-spot enabled — posting every \(potaReSpotIntervalMinutes) min. Click to stop."
            : "Click to auto re-spot every \(potaReSpotIntervalMinutes) min " +
            "(adjust interval in Settings → POTA)"
    }

    /// Drives the auto re-spot toggle. Reads "is timer active" from the
    /// service (so the UI reflects state changes triggered elsewhere,
    /// e.g. session switches) and sets it via start/stop calls.
    private var respotBinding: Binding<Bool> {
        Binding(
            get: { spotService.isReSpotTimerActive },
            set: { newValue in
                if newValue {
                    startRespotTimer()
                } else {
                    spotService.stopReSpotTimer()
                }
            }
        )
    }

    private func startRespotTimer() {
        // Re-read current radio + session state so the timer fires with
        // the right freq/mode even if the service was last configured
        // with stale values from session start.
        guard
            let session = activeSession,
            let parkReference = session.parkReference
        else {
            return
        }
        let parameters = SpotParameters(
            callsign: UserDefaults.standard.string(forKey: "myCallsign") ?? "",
            reference: parkReference,
            frequencyKHz: spotFrequencyKHz(for: session),
            mode: spotMode(for: session),
            comment: spotService.sessionComment
        )
        spotService.startReSpotTimer(
            intervalMinutes: potaReSpotIntervalMinutes,
            parameters: parameters
        )
    }

    func postSpotNow() async {
        guard !isSpotting else {
            return
        }
        isSpotting = true
        defer { isSpotting = false }
        do {
            _ = try await spotService.postCurrentSpot()
            lastSpotSentAt = Date()
        } catch {
            lastSpotError = error.localizedDescription
            showSpotError = true
        }
    }

    private func spotFrequencyKHz(for session: LoggingSession) -> Double {
        if let sessionMHz = session.frequency, sessionMHz > 0 {
            return sessionMHz * 1_000
        }
        return 14_074
    }

    private func spotMode(for session: LoggingSession) -> String {
        session.mode.isEmpty ? "CW" : session.mode
    }
}
