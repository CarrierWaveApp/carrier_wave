// QRQ Crew Spot Sheet
//
// Prompts the user for CW speed and posts a QRQ Crew spot message
// when both operators are QRQ Crew members during a POTA activation.

import SwiftUI

// MARK: - QRQCrewSpotSheet

struct QRQCrewSpotSheet: View {
    // MARK: Lifecycle

    init(
        spotInfo: QRQCrewSpotInfo,
        onPost: @escaping (Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.spotInfo = spotInfo
        self.onPost = onPost
        self.onCancel = onCancel
        _wpmText = State(initialValue: spotInfo.rbnWPM.map(String.init) ?? "")
    }

    // MARK: Internal

    let spotInfo: QRQCrewSpotInfo
    let onPost: (Int) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                headerSection

                Divider()

                speedSection

                previewSection

                Spacer()
            }
            .padding()
            .navigationTitle("QRQ Crew Spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post Spot") {
                        if let wpm = Int(wpmText), wpm >= QRQCrewService.minimumWPM {
                            onPost(wpm)
                        }
                    }
                    .disabled(!isValidSpeed)
                    .fontWeight(.semibold)
                }
            }
        }
        .landscapeAdaptiveDetents(portrait: [.medium])
    }

    // MARK: Private

    @State private var wpmText: String

    private var isValidSpeed: Bool {
        guard let wpm = Int(wpmText) else {
            return false
        }
        return wpm >= QRQCrewService.minimumWPM
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.title)
                .foregroundStyle(.orange)

            Text("QRQ Crew Contact!")
                .font(.headline)

            Text(
                "\(spotInfo.myInfo.displayLabel) worked "
                    + "\(spotInfo.theirInfo.displayLabel)"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
    }

    private var speedSection: some View {
        VStack(spacing: 8) {
            Text("CW Speed (WPM)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("e.g. 35", text: $wpmText)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 120)

            if spotInfo.rbnWPM != nil {
                Text("from RBN (fastest)")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }

            let showError = if let wpm = Int(wpmText) {
                wpm > 0 && wpm < QRQCrewService.minimumWPM
            } else {
                false
            }
            Text("QRQ Crew contacts require \(QRQCrewService.minimumWPM)+ WPM")
                .font(.caption)
                .foregroundStyle(.red)
                .opacity(showError ? 1 : 0)
        }
    }

    private var previewSection: some View {
        VStack(spacing: 8) {
            Text("Spot Preview")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            let wpm = Int(wpmText) ?? 0
            let comment = wpm > 0
                ? spotInfo.spotComment(wpm: wpm)
                : spotInfo.spotComment(wpm: 0)
                .replacingOccurrences(of: "at 0 WPM", with: "at __ WPM")

            Text(comment)
                .font(.caption)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
