import CarrierWaveData
import SwiftUI
import UIKit

// MARK: - SpotConfirmContext

/// Bundled state for the explicit respot confirmation alert. Packed into a
/// single value so the host view only carries one `@State` declaration.
struct SpotConfirmContext {
    var pendingSpot: EnrichedSpot?
    var message: String = ""
    /// Whether this confirm is also bypassing the anti-spam cooldown.
    var isCooldownBypass = false
    var showAlert: Bool = false
}

// MARK: - SpotConfirmAlertModifier

/// Renders the explicit "Spot on POTA?" confirmation. Respotting publishes to
/// POTA under the user's callsign, so it is never a one-tap action; when the
/// per-callsign cooldown is active the message carries the spam warning too.
struct SpotConfirmAlertModifier: ViewModifier {
    @Binding var context: SpotConfirmContext

    let onConfirm: (EnrichedSpot) -> Void

    func body(content: Content) -> some View {
        content.alert(
            "Spot on POTA?",
            isPresented: $context.showAlert,
            presenting: context.pendingSpot
        ) { spot in
            Button(
                context.isCooldownBypass ? "Spot Anyway" : "Spot",
                role: context.isCooldownBypass ? .destructive : nil
            ) {
                onConfirm(spot)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(context.message)
        }
    }
}

// MARK: - Spot Action (no-log respot from hunter log)

extension ActivityLogSpotsList {
    /// Called when the user picks "Spot" from a hunter log row's long-press menu.
    /// Always confirms before posting — the alert shows exactly what will be
    /// published (activator, park, frequency, mode, spotter) and folds in the
    /// per-callsign cooldown warning when the activator was spotted recently.
    @MainActor
    func handleSpot(_ spot: EnrichedSpot) {
        guard spot.spot.source == .pota, let parkRef = spot.spot.parkRef else {
            ToastManager.shared.warning("Only POTA spots can be reposted")
            return
        }
        guard let myCallsign = manager.activeLog?.myCallsign, !myCallsign.isEmpty else {
            ToastManager.shared.warning("Set your callsign before spotting")
            return
        }

        var message = "Posts a spot for \(spot.spot.callsign) at \(parkRef) on "
            + "\(FrequencyFormatter.format(spot.spot.frequencyMHz)) \(spot.spot.mode) "
            + "as \(myCallsign)."
        var isCooldownBypass = false
        if let remaining = SpotCooldownTracker.shared.cooldownRemaining(for: spot.spot.callsign) {
            let elapsed = SpotCooldownTracker.shared.cooldown - remaining
            let seconds = max(1, Int(elapsed.rounded()))
            message += "\n\nYou spotted \(spot.spot.callsign) \(seconds)s ago — posting "
                + "again may be considered spam. Only repost if the frequency or mode "
                + "has changed."
            isCooldownBypass = true
        }

        spotConfirm = SpotConfirmContext(
            pendingSpot: spot,
            message: message,
            isCooldownBypass: isCooldownBypass,
            showAlert: true
        )
    }

    /// Fire-and-forget POTA respot used by both the immediate path and the
    /// cooldown bypass. Records the cooldown timestamp so back-to-back taps are
    /// throttled.
    @MainActor
    func sendSpot(_ spot: EnrichedSpot) {
        guard let parkRef = spot.spot.parkRef,
              let myCallsign = manager.activeLog?.myCallsign
        else {
            return
        }

        let activator = spot.spot.callsign
        let frequency = spot.spot.frequencyKHz
        let mode = spot.spot.mode

        SpotCooldownTracker.shared.recordSpot(activator)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task {
            do {
                let client = POTAClient(authService: POTAAuthService())
                _ = try await client.postRespot(
                    activator: activator,
                    spotter: myCallsign,
                    reference: parkRef,
                    frequency: frequency,
                    mode: mode,
                    comments: nil
                )
                ToastManager.shared.spotPosted(park: parkRef)
            } catch {
                SyncDebugLog.shared.error(
                    "Spot failed: \(error.localizedDescription)", service: .pota
                )
                ToastManager.shared.error("Spot failed: \(error.localizedDescription)")
            }
        }
    }
}
