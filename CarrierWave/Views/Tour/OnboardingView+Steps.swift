import SwiftUI

// MARK: - OnboardingView Step Content Views

extension OnboardingView {
    var callsignStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 60))
                .foregroundStyle(Color.accentColor)

            Text("Let's set up your profile")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Enter your callsign and we'll look up your information from HamDB.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("Callsign", text: $callsign)
                .textFieldStyle(.roundedBorder)
                .textContentType(.username)
                .autocapitalization(.allCharacters)
                .autocorrectionDisabled()
                .font(.title2.monospaced())
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .onSubmit { lookupCallsign() }

            if isLookingUp {
                HStack {
                    ProgressView()
                    Text("Looking up callsign...")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    var lookupResultStep: some View {
        if let profile {
            VStack(spacing: 20) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)

                Text(profile.callsign)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .monospaced()

                if let name = profile.fullName {
                    Text(name)
                        .font(.title2)
                }

                profileInfoGrid(profile)

                Text("We found your information! You can update this later in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        } else {
            VStack(spacing: 20) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)

                Text(callsign.uppercased())
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .monospaced()

                Text(
                    "We couldn't find your callsign in HamDB. "
                        + "This might be a non-US callsign or a new license."
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

                Text("You can still use the app and update your profile later in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    var connectServicesStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "link.circle")
                .font(.system(size: 60))
                .foregroundStyle(Color.accentColor)

            Text("Connect your logging services")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Connect the services you use to sync your QSOs.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 16) {
                // LoTW - uses callsign as username
                serviceConnectionCard(
                    name: "LoTW",
                    icon: "checkmark.seal",
                    isConnected: connectedServices.contains("lotw"),
                    content: {
                        VStack(spacing: 8) {
                            HStack {
                                Text("Username")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(callsign.uppercased())
                                    .foregroundStyle(.secondary)
                                    .monospaced()
                            }
                            SecureField("Password", text: $lotwPassword)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.password)
                        }
                    },
                    onConnect: connectLoTW
                )

                // POTA - uses email
                serviceConnectionCard(
                    name: "POTA",
                    icon: "tree",
                    isConnected: connectedServices.contains("pota"),
                    content: {
                        VStack(spacing: 8) {
                            TextField("Email", text: $potaUsername)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.emailAddress)
                                .autocapitalization(.none)
                                .keyboardType(.emailAddress)
                            SecureField("Password", text: $potaPassword)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.password)
                        }
                    },
                    onConnect: connectPOTA
                )

                // QRZ - uses API key
                serviceConnectionCard(
                    name: "QRZ Logbook",
                    icon: "globe",
                    isConnected: connectedServices.contains("qrz"),
                    content: {
                        VStack(spacing: 8) {
                            Text("Get your API key from QRZ Logbook settings")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            SecureField("API Key", text: $qrzApiKey)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.password)
                        }
                    },
                    onConnect: connectQRZ
                )
            }

            Text("You can skip this and connect services later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    var activitiesStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.accentColor)

            Text("Join the community")
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

            Toggle("Enable community features", isOn: $activitiesOptIn)
                .padding(.horizontal)

            Text("You can change this later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if isRegistering {
                HStack {
                    ProgressView()
                    Text("Registering...")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    var completeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("Welcome, \(profile?.firstName ?? callsign.uppercased())!")
                .font(.title)
                .fontWeight(.bold)

            Text("Your profile is set up and you're ready to start logging contacts.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !connectedServices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connected Services:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(Array(connectedServices).sorted(), id: \.self) { service in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(service.capitalized)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Text("You can always update your profile and connect more services in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
