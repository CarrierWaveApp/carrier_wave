// End Session Flow View
//
// Multi-step sheet shown when ending a session. Guides the user through:
// 1. Session summary with confirmation
// 2. POTA upload prompt (if applicable)
// 3. Session brag sheet with share option
//
// Step views are in EndSessionFlowView+Steps.swift.

import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - EndSessionFlowStep

enum EndSessionFlowStep: Int, CaseIterable {
    case summary
    case potaUpload
    case bragSheet
}

// MARK: - EndSessionFlowView

struct EndSessionFlowView: View {
    // MARK: Internal

    let sessionTitle: String
    let qsoCount: Int
    let duration: String
    let bands: [String]
    let modes: [String]
    let isPOTA: Bool
    let potaParkRef: String?
    let potaParkName: String?
    let potaQSOsNeedingUpload: Int
    let roveStops: [RoveUploadSummary]
    let isInMaintenance: Bool
    let maintenanceTimeRemaining: String?
    let hasNoFrequency: Bool
    let onEndSession: () -> ActivityItem?
    let onUpload: () async -> Bool
    let onComplete: () -> Void

    // MARK: - State (internal for extension access)

    @State var currentStep: EndSessionFlowStep = .summary
    @State var uploadState: EndSessionUploadState = .idle
    @State var uploadError: String?
    @State var activityItem: ActivityItem?

    var showPOTAStep: Bool {
        isPOTA && potaQSOsNeedingUpload > 0
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $currentStep) {
                summaryStep
                    .tag(EndSessionFlowStep.summary)

                if showPOTAStep {
                    potaUploadStep
                        .tag(EndSessionFlowStep.potaUpload)
                }

                bragSheetStep
                    .tag(EndSessionFlowStep.bragSheet)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentStep)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onComplete()
                    }
                }
            }
        }
        .interactiveDismissDisabled(uploadState == .uploading)
        .landscapeAdaptiveDetents(portrait: [.large])
    }

    func endAndAdvance() {
        activityItem = onEndSession()
        if showPOTAStep {
            currentStep = .potaUpload
        } else {
            currentStep = .bragSheet
        }
    }

    func advanceToBragSheet() {
        currentStep = .bragSheet
    }

    func performUpload() async {
        uploadState = .uploading
        uploadError = nil

        let success = await onUpload()

        await MainActor.run {
            withAnimation {
                if success {
                    uploadState = .success
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        advanceToBragSheet()
                    }
                } else {
                    uploadState = .failed
                }
            }
        }
    }

    // MARK: Private

    private var navigationTitle: String {
        switch currentStep {
        case .summary: "End Session"
        case .potaUpload: "Upload to POTA"
        case .bragSheet: "Session Summary"
        }
    }

    // MARK: - Summary Step

    private var summaryStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: isPOTA ? "tree.fill" : "antenna.radiowaves.left.and.right")
                    .font(.system(size: 48))
                    .foregroundStyle(isPOTA ? .green : .blue)
                    .padding(.top, 8)

                VStack(spacing: 8) {
                    Text(sessionTitle)
                        .font(.title2.weight(.bold))
                    Text("\(qsoCount)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                    Text("QSOs logged")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                summaryDetails

                if hasNoFrequency, qsoCount > 0 {
                    Label(
                        "QSOs were logged without a frequency and will show as \"Unknown\" band.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal)
                }

                Button {
                    endAndAdvance()
                } label: {
                    Text("End Session")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding(.horizontal)
            }
            .padding()
        }
    }

    private var summaryDetails: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Duration", systemImage: "clock")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(duration)
            }
            if !bands.isEmpty {
                HStack {
                    Label("Bands", systemImage: "waveform")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(bands.joined(separator: ", "))
                }
            }
            if !modes.isEmpty {
                HStack {
                    Label("Modes", systemImage: "dot.radiowaves.right")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(modes.joined(separator: ", "))
                }
            }
            if let parkRef = potaParkRef {
                HStack {
                    Label("Park", systemImage: "tree")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(parkRef)
                        .foregroundStyle(.green)
                }
            }
        }
        .font(.subheadline)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

// MARK: - EndSessionUploadState

enum EndSessionUploadState {
    case idle
    case uploading
    case success
    case failed
}
