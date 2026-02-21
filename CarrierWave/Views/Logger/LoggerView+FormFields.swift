import CarrierWaveCore
import SwiftUI

// MARK: - LoggerView Form Fields

extension LoggerView {
    // MARK: - Callsign Input

    var callsignInputSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Text field with clear button
                HStack(spacing: 12) {
                    CallsignTextField(
                        "Callsign or command...",
                        text: $callsignInput,
                        isFocused: $callsignFieldFocused,
                        onSubmit: {
                            // Defer to next run loop to avoid UICollectionView crash
                            // when keyboard dismiss triggers List updates simultaneously
                            DispatchQueue.main.async {
                                handleInputSubmit()
                            }
                        },
                        onCommand: { command in
                            executeCommand(command)
                        }
                    )
                    .foregroundStyle(detectedCommand != nil ? .purple : .primary)
                    .onChange(of: callsignInput) { _, newValue in
                        onCallsignChanged(newValue)
                    }

                    Button {
                        callsignInput = ""
                        lookupResult = nil
                        lookupError = nil
                        quickEntryResult = nil
                        quickEntryTokens = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .opacity(callsignInput.isEmpty ? 0 : 1)
                    .disabled(callsignInput.isEmpty)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(detectedCommand != nil ? Color.purple : Color.clear, lineWidth: 2)
                )

                // Action button to the right of text field (always present)
                Button {
                    if let command = detectedCommand {
                        executeCommand(command)
                        callsignInput = ""
                    } else if quickEntryResult != nil {
                        logQuickEntry()
                    } else {
                        logQSO()
                    }
                } label: {
                    Text(actionButtonLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxHeight: .infinity)
                        .frame(width: 48)
                        .background(actionButtonColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!actionButtonEnabled)
                .opacity(actionButtonEnabled ? 1 : 0.4)
                .accessibilityLabel(actionButtonAccessibilityLabel)
            }

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

            // Quick entry preview
            if !quickEntryTokens.isEmpty, detectedCommand == nil {
                QuickEntryPreview(tokens: quickEntryTokens)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Cancel spot button - shown when tuned away from session frequency
            if preSpotFrequency != nil {
                Button {
                    cancelSpot()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                        Text("Cancel Spot")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Compact Fields

    /// Compact RST and State fields with inline More expansion
    var compactFieldsSection: some View {
        VStack(spacing: 8) {
            // Row 1: State, RST Sent, RST Rcvd, More chevron
            HStack(spacing: 8) {
                // State field
                compactField(
                    label: "State",
                    placeholder: lookupResult?.state ?? "ST",
                    text: $theirState,
                    width: 50
                )

                // RST Sent
                compactField(label: "Sent", placeholder: defaultRST, text: $rstSent, width: 50)
                    .keyboardType(.numberPad)

                // RST Rcvd
                compactField(label: "Rcvd", placeholder: defaultRST, text: $rstReceived, width: 50)
                    .keyboardType(.numberPad)

                Spacer()

                // More fields chevron
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

            // Row 2: Expanded fields (Grid, Park, Operator, Notes)
            if showMoreFields {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        compactField(
                            label: "Grid",
                            placeholder: lookupResult?.grid ?? "",
                            text: $theirGrid
                        )
                        compactField(label: "Park", placeholder: "", text: $theirPark)
                    }
                    compactField(
                        label: "Operator",
                        placeholder: lookupResult?.displayName ?? "",
                        text: $operatorName,
                        isMonospaced: false
                    )
                    compactField(
                        label: "Notes",
                        placeholder: "",
                        text: $notes,
                        isMonospaced: false
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - QSO List

    @ViewBuilder
    var qsoListSection: some View {
        // Only show QSO list when there's an active session
        if sessionManager?.hasActiveSession == true {
            VStack(alignment: .leading, spacing: 8) {
                if let viewingPark = viewingParkOverride {
                    viewingPastStopBanner(viewingPark)
                }

                HStack {
                    Text("Session Log")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(displayQSOs.count) QSOs")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if sessionLogEntries.isEmpty {
                    Text("No entries yet")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    let entries = Array(sessionLogEntries.prefix(15))
                    List {
                        ForEach(entries) { entry in
                            switch entry {
                            case let .qso(qso):
                                LoggerQSORow(
                                    qso: qso,
                                    utcDayQSOs: utcDayQSOs,
                                    isPOTASession: sessionManager?.activeSession?
                                        .activationType == .pota,
                                    onQSODeleted: { deletedQSO in
                                        sessionManager?.hideQSO(deletedQSO)
                                        refreshSessionQSOs()
                                    },
                                    onEditCallsign: { qsoToEdit in
                                        startEditingCallsign(qsoToEdit)
                                    }
                                )
                                .swipeActions(
                                    edge: .trailing,
                                    allowsFullSwipe: false
                                ) {
                                    Button(role: .destructive) {
                                        qsoToDelete = qso
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            case let .note(note):
                                LoggerNoteRow(note: note)
                            }
                        }
                        .listRowInsets(
                            EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(.secondary.opacity(0.2))
                    }
                    .listStyle(.plain)
                    .scrollDisabled(true)
                    .scrollContentBackground(.hidden)
                    .frame(height: CGFloat(entries.count) * 54)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .alert(
                "Delete QSO",
                isPresented: Binding(
                    get: { qsoToDelete != nil },
                    set: { newValue in
                        if !newValue {
                            qsoToDelete = nil
                        }
                    }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let qso = qsoToDelete {
                        sessionManager?.hideQSO(qso)
                        refreshSessionQSOs()
                    }
                    qsoToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    qsoToDelete = nil
                }
            } message: {
                if let qso = qsoToDelete {
                    Text("Delete QSO with \(qso.callsign)?")
                }
            }
        }
    }

    // MARK: - Helper Views

    func viewingPastStopBanner(_ parkRef: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.caption)
                .foregroundStyle(.blue)

            Text("Viewing \(ParkReference.split(parkRef).first ?? parkRef)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.blue)

            Spacer()

            Button {
                viewingParkOverride = nil
            } label: {
                Text("Back to Current")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            .controlSize(.mini)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Reusable compact field with label above
    func compactField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        width: CGFloat? = nil,
        isMonospaced: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .font(isMonospaced ? .subheadline.monospaced() : .subheadline)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.horizontal, 8)
                .frame(height: fieldHeight)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(width: width)
        }
    }

    // MARK: - Action Button Properties

    var userLicenseClass: LicenseClass {
        LicenseClass(rawValue: licenseClassRaw) ?? .extra
    }

    /// Whether the log button should be enabled
    var canLog: Bool {
        guard sessionManager?.hasActiveSession == true else {
            return false
        }

        // Determine which callsign to validate
        let callsignToValidate: String
        if let qeResult = quickEntryResult {
            // In quick entry mode, use the parsed callsign
            callsignToValidate = qeResult.callsign
        } else {
            // Normal mode, use the input directly
            guard !callsignInput.isEmpty, callsignInput.count >= 3 else {
                return false
            }
            callsignToValidate = callsignInput.uppercased()
        }

        // Don't allow logging your own callsign
        let myCallsign = sessionManager?.activeSession?.myCallsign.uppercased() ?? ""
        if !myCallsign.isEmpty, callsignToValidate.uppercased() == myCallsign {
            return false
        }

        // Block POTA duplicates on same band (requirement 6a)
        if case .duplicateBand = potaDuplicateStatus {
            return false
        }

        return true
    }

    /// Whether the action button next to the callsign field is enabled
    var actionButtonEnabled: Bool {
        detectedCommand != nil || canLog
    }

    /// Label for the action button next to the callsign field
    var actionButtonLabel: String {
        if detectedCommand != nil {
            return "RUN"
        } else if editingQSO != nil {
            return "SAVE"
        }
        return "LOG"
    }

    /// Color for the action button next to the callsign field
    var actionButtonColor: Color {
        if detectedCommand != nil {
            return .purple
        } else if editingQSO != nil {
            return .orange
        }
        return .green
    }

    /// Accessibility label for the action button
    var actionButtonAccessibilityLabel: String {
        if detectedCommand != nil {
            return "Run command"
        } else if editingQSO != nil {
            return "Save callsign edit"
        }
        return "Log QSO"
    }

    /// Current mode (for RST default)
    var currentMode: String {
        sessionManager?.activeSession?.mode ?? "CW"
    }

    /// Whether current mode uses 3-digit RST (CW/digital) vs 2-digit RS (phone)
    var isCWMode: Bool {
        let mode = currentMode.uppercased()
        let threeDigitModes = [
            "CW", "RTTY", "PSK", "PSK31", "FT8", "FT4", "JT65", "JT9", "DATA", "DIGITAL",
        ]
        return threeDigitModes.contains(mode)
    }

    /// Default RST based on current mode
    var defaultRST: String {
        isCWMode ? "599" : "59"
    }

    /// Detected command from input (if any)
    var detectedCommand: LoggerCommand? {
        LoggerCommand.parse(callsignInput)
    }

    /// Whether to show the lookup error banner (when keyboard is not visible)
    var shouldShowLookupError: Bool {
        lookupError != nil && lookupResult == nil && !callsignFieldFocused && !callsignInput.isEmpty
            && callsignInput.count >= 3 && detectedCommand == nil
    }

    /// Key for animating POTA status changes
    var potaDuplicateStatusKey: String {
        switch potaDuplicateStatus {
        case .none: "none"
        case .firstContact: "first"
        case .newBand: "newband"
        case .duplicateBand: "dupe"
        }
    }

    /// Current frequency warning (if any) - convenience property
    var currentWarning: FrequencyWarning? {
        computeCurrentWarning(spotCount: cachedPOTASpots.count, inputText: callsignInput)
    }
}
