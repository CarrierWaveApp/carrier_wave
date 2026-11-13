import SwiftUI

// MARK: - SMSSpottingSettingsView

struct SMSSpottingSettingsView: View {
    // MARK: Internal

    /// The Twilio phone number operators text their spots to.
    static let twilioPhoneNumber = "+16504145052"

    /// Format phone number for display (e.g. "+18005551234" → "(800) 555-1234")
    static var formattedPhoneNumber: String {
        let digits = twilioPhoneNumber.filter(\.isNumber)
        guard digits.count == 11, digits.hasPrefix("1") else {
            return twilioPhoneNumber
        }
        let area = digits[digits.index(digits.startIndex, offsetBy: 1) ..< digits.index(digits.startIndex, offsetBy: 4)]
        let prefix = digits[digits.index(digits.startIndex, offsetBy: 4) ..< digits.index(
            digits.startIndex,
            offsetBy: 7
        )]
        let line = digits[digits.index(digits.startIndex, offsetBy: 7)...]
        return "(\(area)) \(prefix)-\(line)"
    }

    var body: some View {
        List {
            if let marker = spotMarkerCode, !marker.isEmpty {
                markerDisplaySection(marker)
                howToSection(marker)
                regenerateSection
            } else {
                setupSection
            }
        }
        .navigationTitle("SMS Spotting")
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: Private

    @AppStorage("spotMarkerCode") private var spotMarkerCode: String?
    @AppStorage("spotMarkerCallsign") private var spotMarkerCallsign: String?

    @State private var isGenerating = false
    @State private var showingError = false
    @State private var errorMessage = ""

    private var regenerateSection: some View {
        Section {
            Button {
                Task { await generateMarker() }
            } label: {
                if isGenerating {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 4)
                        Text("Generating...")
                    }
                } else {
                    Label("Generate New Marker", systemImage: "arrow.clockwise")
                }
            }
            .disabled(isGenerating)
        } footer: {
            Text("Generating a new marker invalidates the old one.")
        }
    }

    private var setupSection: some View {
        Section {
            Button {
                Task { await generateMarker() }
            } label: {
                if isGenerating {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 4)
                        Text("Setting up...")
                    }
                } else {
                    Label("Set Up SMS Spotting", systemImage: "antenna.radiowaves.left.and.right")
                }
            }
            .disabled(isGenerating)
        } header: {
            Text("SMS Spotting")
        } footer: {
            Text(
                "Spot POTA and SOTA activations via SMS when you have "
                    + "cellular service but no data connection."
            )
        }
    }

    // MARK: - Sections

    private func markerDisplaySection(_ marker: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your SMS Marker")
                    .font(.headline)

                Text(marker)
                    .font(.system(.title, design: .monospaced))
                    .bold()
                    .textSelection(.enabled)

                if let callsign = spotMarkerCallsign {
                    Text("Linked to \(callsign)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func howToSection(_ marker: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                instructionRow(
                    number: 1,
                    text: "Text your spot to \(Self.formattedPhoneNumber)"
                )
                instructionRow(
                    number: 2,
                    text: "Format: \(marker) K-1234 14.062 CW"
                )
                instructionRow(
                    number: 3,
                    text: "You'll get a confirmation text back"
                )
            }
            .padding(.vertical, 4)
        } header: {
            Text("How to Use")
        } footer: {
            Text(
                "Works for POTA parks (K-1234) and SOTA summits (W7W/KI-001). "
                    + "Your marker stays the same until you generate a new one."
            )
        }
    }

    // MARK: - Helpers

    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(.blue))

            Text(text)
                .font(.subheadline)
        }
    }

    private func generateMarker() async {
        isGenerating = true
        defer { isGenerating = false }

        let client = ActivitiesClient()
        guard client.hasAuthToken() else {
            errorMessage = "Please enable community features and set your callsign first."
            showingError = true
            return
        }

        do {
            let marker = try await client.generateSpotMarker()
            spotMarkerCode = marker.marker
            spotMarkerCallsign = marker.callsign
        } catch {
            errorMessage = "Failed to generate marker: \(error.localizedDescription)"
            showingError = true
        }
    }
}

#Preview("Setup") {
    NavigationStack {
        SMSSpottingSettingsView()
    }
}
