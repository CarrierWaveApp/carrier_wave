import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - Section Content

extension QSOEditSheet {
    var contestPickerSheetContent: some View {
        NavigationStack {
            ContestCalendarView(onSelectDefinition: { definition in
                selectedContest = definition
                showContestPicker = false
            })
        }
    }

    var contactSection: some View {
        Section("Contact") {
            TextField("Callsign", text: $callsign)
                .font(.body.monospaced())
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()

            pickerRow("Band", icon: "waveform", value: bandDisplayLabel) {
                showBandPicker = true
            }

            pickerRow("Mode", icon: "antenna.radiowaves.left.and.right",
                      value: modeDisplayLabel)
            {
                showModePicker = true
            }

            LabeledTrailingField("Frequency", text: $frequencyText, placeholder: "MHz",
                                 keyboard: .decimalPad, monospaced: true, width: 120)
                .onChange(of: frequencyText) { _, newValue in
                    guard let parsed = FrequencyFormatter.parse(newValue),
                          let derived = BandUtilities.deriveBand(from: parsed * 1_000)
                    else {
                        return
                    }
                    band = derived
                }

            DatePicker(
                "Date/Time (UTC)",
                selection: $timestamp,
                displayedComponents: [.date, .hourAndMinute]
            )
            .environment(\.timeZone, TimeZone(identifier: "UTC")!)

            TextField("Name", text: $name)
                .textInputAutocapitalization(.words)
        }
    }

    @ViewBuilder
    var myStationSectionContent: some View {
        TextField("My Callsign", text: $myCallsign)
            .font(.body.monospaced())
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()

        TextField("Station Callsign (club)", text: $stationCallsign)
            .font(.body.monospaced())
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()

        LabeledTrailingField("My Grid", text: $myGrid, placeholder: "FN31",
                             autocaps: .characters, monospaced: true, width: 120)

        pickerRow("Rig", icon: "radio", value: myRig.nonEmpty) {
            activePickerCategory = .radio
        }

        TextField("Station Profile", text: $stationProfileName)

        LabeledTrailingField("Power", text: $powerText, placeholder: "W",
                             keyboard: .numberPad, suffix: "W", width: 80)
    }

    @ViewBuilder
    var signalSectionContent: some View {
        LabeledTrailingField("RST Sent", text: $rstSent, placeholder: "599",
                             keyboard: .numberPad, monospaced: true, width: 80)

        LabeledTrailingField("RST Received", text: $rstReceived, placeholder: "599",
                             keyboard: .numberPad, monospaced: true, width: 80)
    }

    @ViewBuilder
    var theirLocationSectionContent: some View {
        LabeledTrailingField("Their Grid", text: $theirGrid, placeholder: "FN31",
                             autocaps: .characters, monospaced: true, width: 120)

        TextField("QTH", text: $qth)

        pickerRow("State / Province", icon: "map", value: stateDisplayLabel) {
            showStatePicker = true
        }

        TextField("Country", text: $country)
            .textInputAutocapitalization(.words)

        pickerRow("DXCC", icon: "globe", value: resolvedDXCCLabel) {
            showDXCCPicker = true
        }

        TextField("License Class", text: $licenseClass)
            .textInputAutocapitalization(.words)
    }

    /// Displayable label for the current DXCC selection.
    /// Resolves via the bundled lookup first; falls back to the raw number (e.g.
    /// when the user has supplied a custom entity) so the row always shows
    /// something meaningful if a value is set.
    var resolvedDXCCLabel: String? {
        guard let number = Int(dxccText.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        if let entity = DescriptionLookup.dxccEntity(forNumber: number) {
            return "\(entity.name) · #\(number)"
        }
        return "#\(number)"
    }

    /// "MA · Massachusetts" when we recognise the code; raw code otherwise.
    var stateDisplayLabel: String? {
        let trimmed = state.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return nil
        }
        if let entry = ADIFCatalog.stateProvince(forCode: trimmed) {
            return "\(entry.code) · \(entry.name)"
        }
        return trimmed.uppercased()
    }

    /// "20m · 14 MHz" when we recognise the band; raw code otherwise.
    var bandDisplayLabel: String? {
        let trimmed = band.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return nil
        }
        if let info = ADIFCatalog.band(forCode: trimmed) {
            return "\(info.code) · \(info.description)"
        }
        return trimmed
    }

    /// "FT8 · Joe Taylor..." when we recognise the mode; raw code otherwise.
    var modeDisplayLabel: String? {
        let trimmed = mode.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return nil
        }
        if let info = ADIFCatalog.mode(forCode: trimmed) {
            return "\(info.code) · \(info.description)"
        }
        return trimmed.uppercased()
    }

    @ViewBuilder
    var referencesSectionContent: some View {
        pickerRow("My Park (POTA)", icon: "tree", value: parkReference.nonEmpty,
                  monospacedValue: true)
        {
            showMyParkPicker = true
        }

        pickerRow("Their Park (POTA)", icon: "tree", value: theirParkReference.nonEmpty,
                  monospacedValue: true)
        {
            showTheirParkPicker = true
        }

        // Operator's own summit, sourced from the parent session — read-only
        // here, matches what ADIF export emits as `MY_SOTA_REF`. Surfaced
        // alongside "Their Summit" so the user can tell at a glance which
        // QSOs in a SOTA session got an S2S tag and which didn't.
        if !mySotaReference.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "mountain.2.fill")
                    .foregroundStyle(.secondary)
                Text("My Summit (SOTA)")
                Spacer()
                Text(mySotaReference)
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
            }
        }

        pickerRow("Their Summit (S2S)", icon: "mountain.2", value: sotaRef.nonEmpty,
                  monospacedValue: true)
        {
            showSummitPicker = true
        }

        pickerRow("WWFF", icon: "leaf", value: wwffRef.nonEmpty,
                  monospacedValue: true)
        {
            showWWFFPicker = true
        }

        LabeledTrailingField("AoA", text: $aoaCode, placeholder: "Code",
                             autocaps: .characters, monospaced: true, width: 120)
    }

    @ViewBuilder
    var contestSectionContent: some View {
        pickerRow(
            "Contest",
            icon: "trophy",
            value: selectedContest?.name ?? contestName.nonEmpty
        ) {
            showContestPicker = true
        }

        LabeledTrailingField("Serial Sent", text: $contestSerialSent,
                             keyboard: .numberPad, monospaced: true, width: 100)

        LabeledTrailingField("Serial Received", text: $contestSerialReceived,
                             keyboard: .numberPad, monospaced: true, width: 100)

        TextField("Exchange Sent", text: $contestExchangeSent)
            .textInputAutocapitalization(.characters)

        TextField("Exchange Received", text: $contestExchangeReceived)
            .textInputAutocapitalization(.characters)
    }

    @ViewBuilder
    var satelliteSectionContent: some View {
        LabeledTrailingField("Satellite", text: $satName, placeholder: "AO-91",
                             autocaps: .characters, monospaced: true, width: 120)

        LabeledTrailingField("Prop Mode", text: $propMode, placeholder: "SAT",
                             autocaps: .characters, monospaced: true, width: 120)
    }

    var notesSectionContent: some View {
        TextField("Notes", text: $notes, axis: .vertical)
            .lineLimit(3 ... 8)
    }

    /// Collapsible section with a guaranteed-tappable header.
    ///
    /// `Section(_:isExpanded:)` does not render a disclosure chevron inside
    /// `Form` on iOS — the title looks like an ordinary section header with
    /// no affordance, so users can't tell it's tappable (and on some iOS
    /// builds it isn't). We render the header as an explicit `Button` with
    /// a rotating chevron and toggle `isExpanded` ourselves, then gate the
    /// body on that binding.
    func collapsibleSection(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> some View
    ) -> some View {
        Section {
            if isExpanded.wrappedValue {
                content()
            }
        } header: {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Form-row helper: leading icon + label, trailing current value with chevron.
    /// Tapping triggers the supplied action (typically presenting a picker sheet).
    /// Mirrors the pattern in `SessionMetadataEditSheet.equipmentRow`.
    func pickerRow(
        _ label: String,
        icon: String,
        value: String?,
        monospacedValue: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Label(label, systemImage: icon)
                    .foregroundStyle(.primary)
                Spacer()
                Text(value ?? "None")
                    .font(monospacedValue && value != nil ? .body.monospaced() : .body)
                    .foregroundStyle(value == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - LabeledTrailingField

/// Compact row: label on the leading edge, trailing-aligned text field, optional suffix.
struct LabeledTrailingField: View {
    // MARK: Lifecycle

    init(
        _ label: String,
        text: Binding<String>,
        placeholder: String = "",
        keyboard: UIKeyboardType = .default,
        autocaps: TextInputAutocapitalization = .never,
        monospaced: Bool = false,
        suffix: String? = nil,
        width: CGFloat = 120
    ) {
        self.label = label
        _text = text
        self.placeholder = placeholder
        self.keyboard = keyboard
        self.autocaps = autocaps
        self.monospaced = monospaced
        self.suffix = suffix
        self.width = width
    }

    // MARK: Internal

    @Binding var text: String

    let label: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default
    var autocaps: TextInputAutocapitalization = .never
    var monospaced: Bool = false
    var suffix: String?
    var width: CGFloat = 120

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            field
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: width)
            if let suffix {
                Text(suffix)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Private

    @ViewBuilder
    private var field: some View {
        let base = TextField(placeholder, text: $text)
            .keyboardType(keyboard)
            .textInputAutocapitalization(autocaps)
            .autocorrectionDisabled()
        if monospaced {
            base.font(.body.monospaced())
        } else {
            base
        }
    }
}
