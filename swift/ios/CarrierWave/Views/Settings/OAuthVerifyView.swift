import CarrierWaveData
import SwiftUI

// MARK: - OAuthVerifyView

/// Phase 5 OAuth callsign-ownership verification (magic link). Opt-in entry from
/// Activities settings. Drives `OAuthClient`: request a link, then complete via
/// EITHER return path (O4) — polling here, or a universal/`carrierwave://auth`
/// link that posts `.didCompleteOAuthVerification`. The forced `fd_` cutover is
/// deferred, so this is additive: verifying upgrades the device to an OAuth
/// session without disrupting the legacy token.
struct OAuthVerifyView: View {
    // MARK: Internal

    var body: some View {
        Group {
            switch phase {
            case .entry: entryForm
            case .waiting: waitingView
            case .success: successView
            case let .failed(message): failureView(message)
            }
        }
        .navigationTitle("Verify Callsign")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: prefillCallsign)
        .onReceive(NotificationCenter.default.publisher(for: .didCompleteOAuthVerification)) { _ in
            pollTask?.cancel()
            phase = .success
        }
        .onDisappear { pollTask?.cancel() }
    }

    // MARK: Private

    private enum Phase: Equatable {
        case entry
        case waiting
        case success
        case failed(String)
    }

    private struct TimeoutError: Error {}

    @Environment(\.dismiss) private var dismiss

    @AppStorage("loggerDefaultCallsign") private var stationCallsign = ""

    @State private var oauth = OAuthClient()
    @State private var callsign = ""
    @State private var email = ""
    @State private var phase: Phase = .entry
    @State private var isSending = false
    @State private var pollTask: Task<Void, Never>?

    private var trimmedCallsign: String {
        callsign.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Subviews

    private var entryForm: some View {
        Form {
            Section {
                TextField("Callsign", text: $callsign)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            } footer: {
                Text("We verify that you own this callsign before linking it to your account.")
            }

            Section {
                TextField("Email (optional)", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
            } footer: {
                Text(
                    "We email a verification link to your callsign's published address. "
                        + "If none is on file, we use the address you enter here."
                )
            }

            Section {
                Button(action: sendLink) {
                    if isSending {
                        HStack {
                            ProgressView()
                            Text("Sending…").padding(.leading, 4)
                        }
                    } else {
                        Text("Send Verification Link")
                    }
                }
                .disabled(isSending || trimmedCallsign.isEmpty)
            }
        }
    }

    private var waitingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Check your email")
                .font(.headline)
            Text("Tap the verification link we sent. This screen finishes automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Cancel") {
                pollTask?.cancel()
                Task { await oauth.cancelPendingVerification() }
                phase = .entry
            }
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var successView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Callsign Verified")
                .font(.headline)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Verification Failed")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") { phase = .entry }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Run `operation`, throwing `TimeoutError` if it doesn't finish in `seconds`.
    /// Guards against a hung/never-returning async FFI call.
    private static func withTimeout(
        seconds: Double,
        _ operation: @escaping @Sendable () async throws -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            _ = try await group.next()
            group.cancelAll()
        }
    }

    private func prefillCallsign() {
        if callsign.isEmpty {
            callsign = stationCallsign.uppercased()
        }
    }

    private func sendLink() {
        let callValue = trimmedCallsign.uppercased()
        let emailValue = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !callValue.isEmpty else {
            return
        }
        isSending = true
        Task {
            do {
                // Bound the FFI call so a hung request can never spin "Sending…"
                // forever — surface a real, actionable error instead.
                try await Self.withTimeout(seconds: 30) {
                    try await oauth.startVerification(
                        callsign: callValue,
                        email: emailValue.isEmpty ? nil : emailValue
                    )
                }
                isSending = false
                phase = .waiting
                startPolling()
            } catch is TimeoutError {
                isSending = false
                phase = .failed(
                    "The sign-in server didn't respond (timed out after 30s). "
                        + "Check the Activities Server URL in Developer settings and your connection."
                )
            } catch {
                isSending = false
                phase = .failed("Couldn't send the verification link: \(error.localizedDescription)")
            }
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            do {
                try await oauth.pollForCompletion()
                if !Task.isCancelled {
                    phase = .success
                }
            } catch is CancellationError {
                // User left / cancelled — leave the phase as-is.
            } catch OAuthError.timedOut {
                if !Task.isCancelled {
                    phase = .failed("We didn't see the link get tapped in time. Send a new link to try again.")
                }
            } catch {
                if !Task.isCancelled {
                    phase = .failed("Something went wrong finishing sign-in. Send a new link to try again.")
                }
            }
        }
    }
}
