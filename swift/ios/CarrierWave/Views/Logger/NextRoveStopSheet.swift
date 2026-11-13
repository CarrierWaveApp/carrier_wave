import CarrierWaveData
import SwiftUI

// MARK: - NextRoveStopSheet

/// Half-sheet for transitioning to the next park stop in a rove session
struct NextRoveStopSheet: View {
    // MARK: Internal

    var sessionManager: LoggingSessionManager?
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                parkSection
                gridSection
                spottingSection
                previousStopWarning
                actionsSection
            }
            .navigationTitle("Next Park Stop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
            }
            .confirmationDialog(
                "Finish Rove",
                isPresented: $showFinishConfirmation,
                titleVisibility: .visible
            ) {
                Button("Finish Rove") {
                    sessionManager?.endSession()
                    onDismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("End the rove and finish this session?")
            }
            .task {
                // Read spotting defaults from settings
                postQRTSpot = sessionManager?.potaQRTSpotEnabled ?? true
                autoSpotNewPark = sessionManager?.potaAutoSpotEnabled ?? true

                // Request GPS grid (will auto-fill when available)
                gridService.requestGrid()

                // Pre-fill grid from session while waiting for GPS
                if let grid = sessionManager?.activeSession?.myGrid {
                    myGrid = grid
                }
            }
            .onChange(of: gridService.currentGrid) { _, newGrid in
                if let newGrid, !newGrid.isEmpty {
                    myGrid = newGrid
                }
            }
        }
    }

    // MARK: Private

    @State private var parkReference = ""
    @State private var myGrid = ""
    @State private var postQRTSpot = true
    @State private var autoSpotNewPark = true
    @State private var showFinishConfirmation = false
    @State private var gridService = GridLocationService()

    // MARK: - Logic

    private var canStartStop: Bool {
        !parkReference.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var parkAlreadyVisited: Bool {
        guard let session = sessionManager?.activeSession else {
            return false
        }
        let newParks = Set(ParkReference.split(parkReference))
        return session.roveStops.contains { stop in
            let stopParks = Set(ParkReference.split(stop.parkReference))
            return !stopParks.isDisjoint(with: newParks)
        }
    }

    // MARK: - Sections

    private var parkSection: some View {
        Section {
            ParkEntryField(
                parkReference: $parkReference,
                label: "Park",
                placeholder: "1234 or US-1234",
                userGrid: myGrid.isEmpty ? nil : myGrid,
                defaultCountry: "US"
            )
        }
    }

    private var gridSection: some View {
        Section {
            HStack {
                Text("Grid")
                    .foregroundStyle(.secondary)
                Spacer()
                if gridService.isLocating {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                }
                TextField("FN31", text: $myGrid)
                    .textInputAutocapitalization(.characters)
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline.monospaced())
            }
        } footer: {
            if gridService.currentGrid != nil {
                Text("Auto-filled from GPS")
            }
        }
    }

    private var spottingSection: some View {
        Section("Spotting") {
            if let currentPark = sessionManager?.activeSession?.parkReference {
                Toggle(isOn: $postQRTSpot) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Post QRT spot")
                            .font(.subheadline)
                        Text("For \(currentPark)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Toggle(isOn: $autoSpotNewPark) {
                Text("Auto-spot at new park")
                    .font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private var previousStopWarning: some View {
        if let session = sessionManager?.activeSession,
           !parkReference.isEmpty,
           parkAlreadyVisited
        {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Park already visited")
                            .font(.subheadline.weight(.semibold))
                        let count = session.roveStops
                            .filter { stopsContainPark($0) }.count
                        Text(
                            "You've already stopped at this park"
                                + " \(count) \(count == 1 ? "time" : "times")."
                                + " You can still add another stop."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                startNextStop()
            } label: {
                HStack {
                    Spacer()
                    Label("Begin Activation", systemImage: "play.fill")
                        .font(.headline)
                    Spacer()
                }
            }
            .disabled(!canStartStop)

            Button(role: .destructive) {
                showFinishConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    Text("Finish Rove")
                        .font(.subheadline)
                    Spacer()
                }
            }
        }
    }

    private func stopsContainPark(_ stop: RoveStop) -> Bool {
        let newParks = Set(ParkReference.split(parkReference))
        let stopParks = Set(ParkReference.split(stop.parkReference))
        return !stopParks.isDisjoint(with: newParks)
    }

    private func startNextStop() {
        sessionManager?.nextRoveStop(
            parkReference: parkReference.uppercased(),
            myGrid: myGrid.isEmpty ? nil : myGrid.uppercased(),
            postQRTSpot: postQRTSpot,
            autoSpotNewPark: autoSpotNewPark
        )
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onDismiss()
    }
}
