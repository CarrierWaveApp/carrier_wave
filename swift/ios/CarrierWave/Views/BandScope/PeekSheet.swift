import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - PeekSheet

/// The shared bottom sheet (spec §11), identical over either lens:
/// callsign + frequency in tier color, `heard N×` line, the FULL chip set
/// (everything the rows deliberately omit — park ref, club identity,
/// WPM · dB), and the two actions: Tune (sets the anchor) and Log QSO
/// (opens the prefilled log flow; logging refreshes the anchor).
struct PeekSheet: View {
    // MARK: Internal

    let spot: EnrichedSpot
    let model: BandScopeViewModel
    let manager: ActivityLogManager

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                header
                chipSet
                Spacer()
                actions
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BandScopeTheme.background)
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await runCallsignLookup()
        }
        .sheet(isPresented: $showLogSheet) {
            SpotLogSheet(spot: spot, manager: manager) {
                // Logging a QSO refreshes the anchor (§6/§11).
                model.declareAnchor(
                    frequencyKHz: spot.spot.frequencyKHz, band: spot.spot.band
                )
                dismiss()
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showLogSheet = false
    @State private var lookupInfo: CallsignInfo?
    @State private var previousQSOCount = 0

    private var tier: SpotTier {
        spot.tier(for: model.activeProfile)
    }

    private var heardCount: Int {
        model.allSpots.count {
            $0.spot.callsign.uppercased() == spot.spot.callsign.uppercased()
        }
    }

    private var signalText: String {
        var parts: [String] = []
        if let wpm = spot.spot.wpm {
            parts.append("\(wpm) WPM")
        }
        if let snr = spot.spot.snr {
            parts.append("\(snr) dB")
        }
        return parts.joined(separator: " · ")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(spot.spot.callsign)
                .font(.title2.weight(.bold).monospaced())
                .foregroundStyle(BandScopeTheme.text)
            HStack(spacing: 8) {
                Text(String(format: "%.4f MHz", spot.spot.frequencyKHz / 1_000))
                    .font(.subheadline.weight(.semibold).monospaced())
                    .foregroundStyle(BandScopeTheme.color(for: tier))
                Text(spot.spot.band)
                    .font(.caption.monospaced())
                    .foregroundStyle(BandScopeTheme.dim)
                Text(spot.spot.mode)
                    .font(.caption.weight(.medium).monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        ModeColors.color(for: spot.spot.mode)
                            .opacity(BandScopeTheme.chipBackgroundAlpha),
                        in: Capsule()
                    )
                    .foregroundStyle(ModeColors.color(for: spot.spot.mode))
            }
            if heardCount > 1 {
                Text("heard \(heardCount)× this session")
                    .font(.caption2.monospaced())
                    .foregroundStyle(BandScopeTheme.faint)
            }
        }
    }

    /// Full chip set (§11) — everything the row suppressed. The callsign
    /// card is the SAME preview the session logger shows while typing.
    private var chipSet: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let lookupInfo {
                LoggerCallsignCard(
                    info: lookupInfo,
                    previousQSOCount: previousQSOCount,
                    myGrid: UserDefaults.standard.string(forKey: "loggerDefaultGrid")
                )
                .transition(.opacity)
            }
            let needs = spot.profileNeeds(for: model.activeProfile)
            if !needs.isEmpty {
                HStack(spacing: 6) {
                    ForEach(needs.prefix(3)) { need in
                        GoalChip(label: need.label, tier: .needed)
                    }
                }
            }
            detailRows
        }
    }

    @ViewBuilder
    private var detailRows: some View {
        detailRow(
            "AGE", "\(BandScopeAge.compact(spot.spot.timestamp)) ago"
        )
        if let park = spot.spot.parkRef {
            detailRow(
                "PARK",
                [park, spot.spot.parkName, spot.spot.stateAbbr]
                    .compactMap(\.self).joined(separator: " · ")
            )
        }
        if let summit = spot.spot.summitCode {
            detailRow("SOTA", [summit, spot.spot.summitName].compactMap(\.self)
                .joined(separator: " · "))
        }
        if let wwff = spot.spot.wwffRef {
            detailRow("WWFF", wwff)
        }
        if let member = spot.skccMember {
            detailRow("SKCC", member.badge)
        }
        if spot.spot.wpm != nil || spot.spot.snr != nil {
            detailRow("SIGNAL", signalText)
        }
        if let spotter = spot.spot.spotter {
            detailRow("SPOTTER", spotter)
        }
        if let comments = spot.spot.comments, !comments.isEmpty {
            detailRow("NOTE", comments)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                tune()
            } label: {
                Label(
                    String(format: "Tune %.4f", spot.spot.frequencyKHz / 1_000),
                    systemImage: "dot.radiowaves.left.and.right"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                showLogSheet = true
            } label: {
                Label("Log QSO", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BandScopeTheme.faint)
                .frame(width: 54, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(BandScopeTheme.text)
        }
    }

    /// Mirror the logger's lookup pipeline (LoggerView+Data): primary
    /// callsign → previous-QSO count → streamed lookup (cached row first,
    /// QRZ/HamDB-enriched row when it resolves).
    private func runCallsignLookup() async {
        let primary = CallsignParsing.primaryCallsign(from: spot.spot.callsign)
        let upper = primary.uppercased()
        previousQSOCount = (try? modelContext.boundedCount(
            QSO.self,
            predicate: #Predicate<QSO> { qso in
                qso.callsign == upper
                    && !qso.isHidden
                    && qso.mode != "WEATHER"
                    && qso.mode != "SOLAR"
                    && qso.mode != "NOTE"
            }
        )) ?? 0

        let service = CallsignLookupService(modelContext: modelContext)
        for await result in service.lookupStream(primary) {
            guard !Task.isCancelled else {
                return
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                lookupInfo = result.info
            }
        }
    }

    /// Tune (§11): CAT-tune when a radio is connected; either way the
    /// anchor is declared (§6 — dial-by-declaration) and the sheet
    /// dismisses.
    private func tune() {
        let radio = RadioService.shared
        if radio.isConnected {
            radio.setFrequency(spot.spot.frequencyMHz)
            radio.setMode(RadioCommandParser.resolveMode(
                spot.spot.mode, frequencyMHz: spot.spot.frequencyMHz
            ))
        }
        model.declareAnchor(
            frequencyKHz: spot.spot.frequencyKHz, band: spot.spot.band
        )
        dismiss()
    }
}
