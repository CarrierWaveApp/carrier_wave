import SwiftUI
import UIKit

struct CommunityFeaturesPromptSheet: View {
    // MARK: Internal

    let callsign: String
    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(Color.accentColor)

                    Text("Community Features")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(
                        "Register with Carrier Wave's community server to discover friends, "
                            + "join challenges, and share activity with other operators."
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 12) {
                        featureRow(icon: "magnifyingglass", text: "Find friends by callsign")
                        featureRow(icon: "trophy", text: "Join challenges and leaderboards")
                        featureRow(icon: "bell", text: "See activity from friends and clubs")
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Toggle("Enable community features", isOn: $optIn)
                        .padding(.horizontal)

                    Text("You can change this later in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if let error = registrationError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    if isRegistering {
                        HStack {
                            ProgressView()
                            Text("Registering...")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        confirmAndRegister()
                    }
                    .disabled(isRegistering)
                }
            }
        }
        .landscapeAdaptiveDetents(portrait: [.medium, .large])
    }

    // MARK: Private

    @AppStorage("activitiesServerEnabled") private var activitiesEnabled = false
    @State private var optIn = true
    @State private var isRegistering = false
    @State private var registrationError: String?

    private let activitiesSourceURL = "https://activities.carrierwave.app"

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }

    private func confirmAndRegister() {
        activitiesEnabled = optIn

        guard optIn, !callsign.isEmpty, callsign != "Me" else {
            onComplete()
            return
        }

        isRegistering = true
        Task {
            do {
                let client = ActivitiesClient()
                _ = try await client.register(
                    callsign: callsign.uppercased(),
                    deviceName: UIDevice.current.name,
                    sourceURL: activitiesSourceURL
                )
            } catch {
                // Non-fatal — auto-register on next sync will retry
                print("[CommunityPrompt] Registration failed: \(error)")
            }
            await MainActor.run {
                onComplete()
            }
        }
    }
}
