import CarrierWaveData
import SwiftUI

// MARK: - ContestScoreSummaryView

/// Contest score summary and Cabrillo export shown in end session flow
struct ContestScoreSummaryView: View {
    // MARK: Internal

    let session: LoggingSession
    let qsos: [QSO]
    let score: ContestScoreSnapshot

    var body: some View {
        VStack(spacing: 16) {
            contestHeader
            scoreGrid
            phaseBreakdown
            bandBreakdown
            cabrilloExportButton
        }
        .sheet(isPresented: $showShareSheet) {
            if let text = cabrilloText {
                CabrilloShareSheet(cabrilloText: text, contestName: session.contestId ?? "contest")
            }
        }
    }

    // MARK: Private

    @State private var cabrilloText: String?
    @State private var showShareSheet = false
    @State private var isLoadingCabrillo = false
    @State private var loadedDefinition: ContestDefinition?

    private var contestHeader: some View {
        VStack(spacing: 4) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 36))
                .foregroundStyle(.yellow)
            Text(loadedDefinition?.displayName ?? session.contestId ?? "Contest")
                .font(.headline)
            Text("\(session.contestCategory ?? "—") / \(session.contestPower ?? "HIGH")")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let overlay = session.contestOverlayCategory {
                Text("Overlay: \(overlay)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: session.contestId) {
            if let contestId = session.contestId {
                loadedDefinition = await ContestDefinitions.definition(id: contestId)
            }
        }
    }

    private var scoreGrid: some View {
        HStack(spacing: 0) {
            scoreItem(label: "QSOs", value: "\(score.totalQSOs)")
            Divider().frame(height: 32)
            scoreItem(label: "Points", value: "\(score.totalPoints)")
            Divider().frame(height: 32)
            scoreItem(label: "Mults", value: "\(score.multiplierCount)")
            Divider().frame(height: 32)
            scoreItem(label: "Score", value: "\(score.finalScore)")
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    @ViewBuilder
    private var phaseBreakdown: some View {
        if let phases = loadedDefinition?.scoring.phases, !phases.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Phases")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(phases, id: \.id) { phase in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(phase.id)
                                .font(.caption.monospaced())
                            if let description = phase.description {
                                Text(description)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("\(score.phaseResults[phase.id] ?? 0)")
                            .font(.caption.monospaced().bold())
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var bandBreakdown: some View {
        if !score.qsosByBand.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("By Band")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(
                    score.qsosByBand.keys.sorted(),
                    id: \.self
                ) { band in
                    HStack {
                        Text(band)
                            .font(.caption.monospaced())
                        Spacer()
                        Text("\(score.qsosByBand[band] ?? 0) Qs")
                            .font(.caption)
                        if let mults = score.multsByBand[band], mults > 0 {
                            Text("\(mults) M")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }

    private var cabrilloExportButton: some View {
        Button {
            generateCabrillo()
        } label: {
            Label(
                isLoadingCabrillo ? "Generating..." : "Export Cabrillo Log",
                systemImage: "square.and.arrow.up"
            )
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
        .disabled(isLoadingCabrillo)
        .padding(.horizontal)
    }

    private func scoreItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.monospaced().bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func generateCabrillo() {
        isLoadingCabrillo = true
        Task {
            guard let contestId = session.contestId,
                  let definition = await ContestDefinitions.definition(id: contestId)
            else {
                isLoadingCabrillo = false
                return
            }
            let service = CabrilloExportService()
            let context = CabrilloExportService.Context(
                categoryID: session.contestCategory,
                overlayCategoryID: session.contestOverlayCategory,
                powerClass: session.contestPower,
                location: session.myGrid,
                operators: [session.contestOperator ?? session.myCallsign]
            )
            let text = service.generate(
                session: session,
                qsos: qsos,
                definition: definition,
                score: score,
                context: context
            )
            cabrilloText = text
            isLoadingCabrillo = false
            showShareSheet = true
        }
    }
}

// MARK: - CabrilloShareSheet

/// Share sheet for Cabrillo log text
struct CabrilloShareSheet: View {
    // MARK: Internal

    let cabrilloText: String
    let contestName: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text(cabrilloText)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding()
                        .background(Color(.systemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 12) {
                        ShareLink(
                            item: cabrilloText,
                            subject: Text("\(contestName) Cabrillo Log"),
                            message: Text("Cabrillo log from Carrier Wave")
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            UIPasteboard.general.string = cabrilloText
                            showCopied = true
                        } label: {
                            Label(
                                showCopied ? "Copied" : "Copy",
                                systemImage: showCopied
                                    ? "checkmark" : "doc.on.doc"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            .navigationTitle("Cabrillo Log")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: Private

    @State private var showCopied = false
}
