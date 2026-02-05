import CarrierWaveCore
import SwiftUI

// MARK: - IntroTourWelcomeStep

struct IntroTourWelcomeStep: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Welcome to Carrier Wave")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(
                "Your amateur radio logging companion. " +
                    "Track your QSOs, sync with cloud services, and never lose a contact."
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
    }
}

// MARK: - IntroTourSyncStep

struct IntroTourSyncStep: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Keep Your Logs in Sync")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(
                "Carrier Wave syncs your QSOs with popular logging services. " +
                    "Your contacts are automatically uploaded and downloaded, keeping everything up to date."
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                IntroTourFeatureRow(icon: "checkmark.circle.fill", text: "Two-way sync with QRZ Logbook")
                IntroTourFeatureRow(icon: "checkmark.circle.fill", text: "POTA activation uploads")
                IntroTourFeatureRow(icon: "checkmark.circle.fill", text: "Ham2K LoFi integration")
                IntroTourFeatureRow(icon: "checkmark.circle.fill", text: "iCloud backup across devices")
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - IntroTourQRZStep

struct IntroTourQRZStep: View {
    @Binding var apiKey: String

    let qrzConnected: Bool
    let connectedCallsign: String?
    let onShowOtherServices: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            Text("Connect to QRZ")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            if qrzConnected, let callsign = connectedCallsign {
                IntroTourQRZConnected(callsign: callsign)
            } else {
                IntroTourQRZForm(apiKey: $apiKey)
            }

            Button {
                onShowOtherServices()
            } label: {
                Text("Connect a different service instead")
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            }
        }
    }
}

// MARK: - IntroTourQRZForm

struct IntroTourQRZForm: View {
    @Binding var apiKey: String

    var body: some View {
        Text(
            "Enter your QRZ Logbook API key to sync your contacts. " +
                "You can find this in your QRZ Logbook settings."
        )
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

        VStack(spacing: 12) {
            TextField("API Key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Link(destination: URL(string: "https://logbook.qrz.com/logbook")!) {
                Label("Get API key from QRZ Logbook", systemImage: "arrow.up.right.square")
                    .font(.subheadline)
            }
        }

        Text("Requires QRZ XML Logbook Data subscription.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

// MARK: - IntroTourQRZConnected

struct IntroTourQRZConnected: View {
    let callsign: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Connected as \(callsign)")
                .font(.headline)
                .foregroundStyle(.green)

            Text("Your QRZ Logbook is now linked to Carrier Wave.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - IntroTourServicesStep

struct IntroTourServicesStep: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 64))
                .foregroundStyle(.purple)

            Text("More Services Available")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("You can connect additional services anytime from Settings. Carrier Wave supports:")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                IntroTourServiceRow(name: "POTA", description: "Parks on the Air activations")
                IntroTourServiceRow(name: "Ham2K LoFi", description: "Multi-device logging sync")
                IntroTourServiceRow(name: "LoTW", description: "ARRL Logbook of the World")
                IntroTourServiceRow(name: "HAMRS", description: "Import from HAMRS logs")
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - IntroTourStatisticsStep

struct IntroTourStatisticsStep: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "flame.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            Text("Track Your Progress")
                .font(.title)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(
                "Stay motivated with detailed statistics and streak tracking. " +
                    "See your daily activity, track your best streaks, and watch your progress grow."
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                IntroTourFeatureRow(icon: "flame.fill", text: "Daily QSO streaks")
                IntroTourFeatureRow(icon: "leaf.fill", text: "POTA activation streaks")
                IntroTourFeatureRow(icon: "waveform.path", text: "Mode and band streaks")
                IntroTourFeatureRow(icon: "chart.bar.fill", text: "Activity grid visualization")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }
    }
}

// MARK: - IntroTourMapStep

struct IntroTourMapStep: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "map.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("See Your Contacts")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(
                "Visualize your QSOs on an interactive map. " +
                    "See where your contacts are located and track your grid square coverage."
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                IntroTourFeatureRow(icon: "mappin.circle.fill", text: "QSO locations by grid square")
                IntroTourFeatureRow(icon: "arrow.triangle.swap", text: "Geodesic paths to contacts")
                IntroTourFeatureRow(icon: "square.grid.3x3.fill", text: "Grids, States, and DXCC counts")
                IntroTourFeatureRow(icon: "slider.horizontal.3", text: "Filter by band, mode, and date")
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - IntroTourActivityStep

struct IntroTourActivityStep: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 64))
                .foregroundStyle(.indigo)

            Text("Connect with the Community")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(
                "Join challenges, connect with friends, and see what the ham radio community is up to. " +
                    "More social features are coming soon!"
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                IntroTourFeatureRow(icon: "flag.2.crossed.fill", text: "Join challenges and track progress")
                IntroTourFeatureRow(icon: "person.badge.plus", text: "Add friends and follow their activity")
                IntroTourFeatureRow(icon: "person.3.fill", text: "Join clubs and see member activity")
                IntroTourFeatureRow(icon: "bell.fill", text: "Activity feed with milestones")
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - IntroTourFeedbackStep

struct IntroTourFeedbackStep: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 64))
                .foregroundStyle(.yellow)

            Text("You're All Set!")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(
                "Start logging your contacts. " +
                    "If you have any questions or feedback, we'd love to hear from you."
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Link(destination: URL(string: "https://discord.gg/carrierwave")!) {
                    Label("Join our Discord", systemImage: "bubble.left.and.bubble.right.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Link(destination: URL(string: "mailto:feedback@carrierwave.app")!) {
                    Label("Send Feedback", systemImage: "envelope.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - IntroTourOtherServicesSheet

struct IntroTourOtherServicesSheet: View {
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("You can connect these services now or later from Settings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Available Services") {
                    IntroTourServiceRow(name: "POTA", description: "Parks on the Air activations")
                    IntroTourServiceRow(name: "Ham2K LoFi", description: "Multi-device logging sync")
                    IntroTourServiceRow(name: "LoTW", description: "ARRL Logbook of the World")
                    IntroTourServiceRow(name: "HAMRS", description: "Import from HAMRS logbook")
                }
            }
            .navigationTitle("Other Services")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

// MARK: - IntroTourFeatureRow

struct IntroTourFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - IntroTourServiceRow

struct IntroTourServiceRow: View {
    let name: String
    let description: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
