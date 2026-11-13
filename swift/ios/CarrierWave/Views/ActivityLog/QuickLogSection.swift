import CarrierWaveData
import SwiftData
import SwiftUI
import UIKit

// MARK: - QuickLogSection

/// Manual callsign entry section for the Activity Log.
/// Mirrors the Logger's callsign input + compact fields layout.
struct QuickLogSection: View {
    // MARK: Internal

    @Binding var currentMode: String
    @Binding var currentFrequency: Double?
    @Binding var recalledSpot: EnrichedSpot?
    @Binding var recalledQSO: QSO?

    let spotCallsigns: [String]
    let contactCounts: [String: Int]
    var initialSpotInfo: [String: Any]?
    let onLog: (QuickLogData) -> Void
    var onMyCallChanged: ((String) -> Void)?
    /// RBN / SOLAR / WX / MAP / MANUAL — the host presents the panel.
    var onPanelCommand: ((LoggerCommand) -> Void)?

    // MARK: - Lookup State (accessed by QuickLogSection+Lookup)

    @Environment(\.modelContext) var modelContext

    @State var lookupResult: CallsignInfo?
    @State var previousQSOCount: Int = 0
    @State var lookupTask: Task<Void, Never>?
    @State var multiLookupResults: [MultiCallsignLookupState] = []
    @State var selectedMultiLookupIndex: Int = 0
    @State var lastLookedUpCallsigns: [String] = []

    /// Resolved POTA park names for the currently typed park refs (ref → name).
    @State var parkNames: [String: String] = [:]
    @State var parkLookupTask: Task<Void, Never>?

    @AppStorage("hunterLogShowFields") var showFields = false
    @AppStorage("rstParseOrder") var rstParseOrderRaw = RSTOrder.receivedFirst.rawValue

    @State var callsignInput = ""
    @State var rstSent = ""
    @State var rstReceived = ""
    @State var theirState = ""
    @State var theirGrid = ""
    @State var theirPark = ""
    @State var notes = ""
    @State var showMoreFields = false
    @State var suggestions: [String] = []
    @State var showHelpSheet = false
    @FocusState var callsignFocused: Bool

    var rstParseOrder: RSTOrder {
        RSTOrder(rawValue: rstParseOrderRaw) ?? .receivedFirst
    }

    var defaultRST: String {
        let mode = currentMode.uppercased()
        if mode == "SSB" || mode == "USB" || mode == "LSB" || mode == "FM" || mode == "AM" {
            return "59"
        }
        return "599"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Log")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            callsignRow

            // Command description badge
            if let command = detectedCommand {
                HStack {
                    Text(command.description)
                        .font(.caption)
                        .foregroundStyle(.purple)

                    Spacer()

                    Text("Press Return to execute")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Callsign lookup display
            lookupDisplay

            // Callsign suggestions (SCP + spots)
            if !suggestions.isEmpty, detectedCommand == nil {
                SCPSuggestionsView(
                    suggestions: suggestions,
                    contactCounts: contactCounts,
                    spotCallsigns: Set(spotCallsigns.map { $0.uppercased() })
                ) { selected in
                    callsignInput = selected
                }
                .padding(.top, 4)
            }

            // Show quick entry preview with labeled pills
            if !parsedTokens.isEmpty, detectedCommand == nil {
                QuickEntryPreview(tokens: parsedTokens)
                    .padding(.top, 4)
            }

            // Resolved park name(s) for typed park refs (each park of an n-fer)
            parkNameDisplay

            if showFields {
                fieldsRow
            }
        }
        .onChange(of: callsignInput) { _, newValue in
            suggestions = CallsignSuggestionProvider.suggestions(
                for: newValue,
                spotCallsigns: spotCallsigns,
                contactCounts: contactCounts
            )
            onCallsignInputChanged(newValue)
            resolveParks(newValue)
        }
        .onChange(of: recalledSpot?.id) { _, newID in
            guard newID != nil, let spot = recalledSpot else {
                return
            }
            populateFromSpot(spot)
            recalledSpot = nil
        }
        .onChange(of: recalledQSO?.id) { _, newID in
            guard newID != nil, let qso = recalledQSO else {
                return
            }
            populateFromQSO(qso)
            recalledQSO = nil
        }
        .onAppear {
            applyInitialSpot()
        }
        .onChange(of: initialSpotInfo?["callsign"] as? String) { _, callsign in
            // When the hosting view (e.g. the hunter-default tab) is already
            // on screen and a new spot is dispatched into `initialSpotInfo`,
            // `.onAppear` won't re-fire — handle the in-place delivery here.
            guard callsign != nil else {
                return
            }
            applyInitialSpot()
        }
        .sheet(isPresented: $showHelpSheet) {
            LoggerHelpSheet()
        }
    }

    // MARK: Private

    @ScaledMetric(relativeTo: .subheadline) private var fieldHeight: CGFloat = 36
    @ScaledMetric(relativeTo: .subheadline) private var rstFieldWidth: CGFloat = 50

    private var parsedTokens: [ParsedToken] {
        let trimmed = callsignInput.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains(" ") else {
            return []
        }
        // Use multi-callsign parser for preview
        let order = rstParseOrder
        let multiTokens = QuickEntryParser.parseMultiTokens(trimmed, rstOrder: order)
        if !multiTokens.isEmpty {
            return multiTokens
        }
        return QuickEntryParser.parseTokens(trimmed, rstOrder: order)
    }

    private var isInputEmpty: Bool {
        callsignInput.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var detectedCommand: LoggerCommand? {
        LoggerCommand.parse(callsignInput)
    }

    // MARK: - Lookup Display

    @ViewBuilder
    private var lookupDisplay: some View {
        if !multiLookupResults.isEmpty {
            MultiCallsignLookupView(
                lookupStates: multiLookupResults,
                selectedIndex: $selectedMultiLookupIndex,
                myGrid: nil
            )
            .transition(
                .asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                )
            )
        } else if let info = lookupResult, !callsignFocused {
            LoggerCallsignCard(
                info: info,
                previousQSOCount: previousQSOCount,
                myGrid: nil
            )
            .transition(
                .asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                )
            )
        }
    }

    // MARK: - Callsign Row (matches Logger callsignInputSection)

    private var callsignRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 12) {
                CallsignTextField(
                    "Callsign or quick entry...",
                    text: $callsignInput,
                    isFocused: $callsignFocused,
                    fontSize: 15,
                    showCommands: true,
                    allowedCommands: CommandRowItem.hunterLogItems,
                    onSubmit: { logFromInput() },
                    onCommand: { command in executeCommand(command) }
                )

                Button {
                    callsignInput = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .opacity(callsignInput.isEmpty ? 0 : 1)
                .disabled(callsignInput.isEmpty)
                .accessibilityLabel("Clear callsign")
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button {
                logFromInput()
            } label: {
                Text(detectedCommand != nil ? "RUN" : "LOG")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxHeight: .infinity)
                    .frame(width: 48)
                    .background(detectedCommand != nil ? .purple : .green)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(isInputEmpty)
            .opacity(isInputEmpty ? 0.4 : 1)
            .accessibilityLabel(
                detectedCommand != nil ? "Run command" : "Log QSO"
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Fields Row (matches Logger compactFieldsSection)

    private var fieldsRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                compactField(label: "Sent", placeholder: defaultRST, text: $rstSent, width: rstFieldWidth)
                    .keyboardType(.numberPad)
                compactField(label: "Rcvd", placeholder: defaultRST, text: $rstReceived, width: rstFieldWidth)
                    .keyboardType(.numberPad)
                compactField(
                    label: "QTH",
                    placeholder: lookupResult?.state ?? "QTH",
                    text: $theirState,
                    width: 50
                )

                Spacer()

                bandModeLabel

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showMoreFields.toggle()
                    }
                } label: {
                    Image(systemName: showMoreFields ? "chevron.up" : "chevron.down")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: fieldHeight)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            if showMoreFields {
                expandedFields
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var expandedFields: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                compactField(
                    label: "Grid",
                    placeholder: lookupResult?.grid ?? "",
                    text: $theirGrid
                )
                compactField(label: "Park", placeholder: "", text: $theirPark)
            }
            compactField(label: "Notes", placeholder: "", text: $notes)
        }
    }

    private var bandModeLabel: some View {
        let band = currentFrequency.map {
            LoggingSession.bandForFrequency($0)
        } ?? "No band"
        return Text("\(band) \(currentMode)")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(Capsule())
    }

    // MARK: - Compact Field (matches Logger compactField)

    private func compactField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        width: CGFloat? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .font(.subheadline.monospaced())
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.horizontal, 8)
                .frame(height: max(fieldHeight, 44))
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(width: width)
        }
    }
}

// MARK: - QuickLogSection Helpers

extension QuickLogSection {
    func logFromInput() {
        let trimmed = callsignInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return
        }

        // Check for commands first
        if let command = LoggerCommand.parse(trimmed) {
            executeCommand(command)
            callsignInput = ""
            return
        }

        // Try multi-callsign quick entry first
        let order = rstParseOrder
        if let results = QuickEntryParser.parseMulti(trimmed, rstOrder: order), results.count >= 2 {
            for result in results {
                onLog(buildQuickLogData(from: result))
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            resetForm()
            return
        }

        // Try single quick entry parse
        if let result = QuickEntryParser.parse(trimmed, rstOrder: order) {
            onLog(buildQuickLogData(from: result))
        } else {
            // Single callsign
            var data = QuickLogData()
            data.callsign = trimmed.uppercased()
            data.mode = currentMode
            data.rstSent = effectiveRST(rstSent)
            data.rstReceived = effectiveRST(rstReceived)
            data.theirParkReference = nonEmpty(theirPark)
            data.theirGrid = nonEmpty(theirGrid) ?? lookupResult?.grid
            data.state = nonEmpty(theirState) ?? lookupResult?.state
            data.notes = nonEmpty(notes)
            data.frequency = currentFrequency
            data.band = currentFrequency.map {
                LoggingSession.bandForFrequency($0)
            } ?? "Unknown"
            data.name = lookupResult?.name
            data.country = lookupResult?.country
            onLog(data)
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        resetForm()
    }

    func buildQuickLogData(from result: QuickEntryResult) -> QuickLogData {
        var data = QuickLogData()
        data.callsign = result.callsign
        data.mode = result.mode ?? currentMode

        // Single RST applies to both sent and received
        if result.rstSent == nil, let rst = result.rstReceived {
            data.rstSent = rst
            data.rstReceived = rst
        } else {
            data.rstSent = result.rstSent ?? effectiveRST(rstSent)
            data.rstReceived = result.rstReceived ?? effectiveRST(rstReceived)
        }

        data.theirParkReference = result.theirPark ?? nonEmpty(theirPark)
        data.theirGrid = result.theirGrid ?? nonEmpty(theirGrid)
        data.state = result.state ?? nonEmpty(theirState)
        data.notes = result.notes ?? nonEmpty(notes)
        data.frequency = result.frequency ?? currentFrequency
        data.band = result.band ?? currentFrequency.map {
            LoggingSession.bandForFrequency($0)
        } ?? "Unknown"
        return data
    }

    func resetForm() {
        callsignInput = ""
        rstSent = ""
        rstReceived = ""
        theirState = ""
        theirGrid = ""
        theirPark = ""
        notes = ""
        clearLookupState()
    }
}
