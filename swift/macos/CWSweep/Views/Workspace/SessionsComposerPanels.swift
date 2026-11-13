import CarrierWaveData
import SwiftUI

// MARK: - ComposerPanel

/// Section container used inside `SessionsComposerView`. Wraps a group of
/// related fields in a subtly-lifted card with an icon-tinted header.
///
/// The composer used to be a sparse vertical stack of unwrapped fields
/// floating in a vast empty page. Panels add the visual structure the dense,
/// Linear/Raycast-inspired aesthetic calls for — grouping fields into
/// "stations" the operator can scan at a glance.
struct ComposerPanel<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .tracking(0.9)
                    .foregroundStyle(.primary.opacity(0.85))
                Spacer(minLength: 8)
            }
            Divider().opacity(0.25)
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - ComposerEquipmentPicker

/// Styled equipment picker that visually matches the rest of the composer
/// (small-caps label, rounded field chrome, monospaced display). Backed by
/// the same `EquipmentStorage` as `EquipmentPickerField`, but the chrome is
/// rebuilt so it stops looking like a stock NSPopUpButton dropped onto the
/// page.
struct ComposerEquipmentPicker: View {
    // MARK: Internal

    let type: EquipmentType
    @Binding var selection: String?

    var width: CGFloat = 168

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(type.displayName.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Menu {
                Button("None") { selection = nil }
                if !items.isEmpty {
                    Divider()
                    ForEach(items, id: \.self) { item in
                        Button(item) { selection = item }
                    }
                    Divider()
                }
                Button("Add \(type.displayName)…") { showAddPopover = true }
                if selection != nil {
                    Divider()
                    Button("Remove from saved list", role: .destructive, action: deleteCurrent)
                }
            } label: {
                pickerLabel
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .popover(isPresented: $showAddPopover) { addItemPopover }
        }
        .onAppear { items = EquipmentStorage.load(for: type) }
    }

    // MARK: Private

    @State private var items: [String] = []
    @State private var showAddPopover = false
    @State private var newItemText = ""
    @FocusState private var addFieldFocused: Bool

    private var pickerLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: type.icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(selection == nil ? .secondary : .primary)
            Text(selection ?? "None")
                .font(.body.monospaced())
                .foregroundStyle(selection == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: width, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    private var addItemPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New \(type.displayName)")
                .font(.headline)
            HStack {
                TextField(type.addPrompt, text: $newItemText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .focused($addFieldFocused)
                    .onSubmit { addItem() }
                Button("Add") { addItem() }
                    .disabled(newItemText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .onAppear {
            newItemText = ""
            addFieldFocused = true
        }
    }

    private func addItem() {
        let trimmed = newItemText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return
        }
        EquipmentStorage.add(trimmed, for: type)
        items = EquipmentStorage.load(for: type)
        selection = trimmed
        newItemText = ""
        showAddPopover = false
    }

    private func deleteCurrent() {
        guard let current = selection else {
            return
        }
        EquipmentStorage.remove(current, for: type)
        items = EquipmentStorage.load(for: type)
        selection = nil
    }
}

// MARK: - ComposerNotesField

/// Multi-line notes field with composer styling. Used by the optional Notes
/// panel for an operator-supplied session memo.
struct ComposerNotesField: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: 56, maxHeight: 96)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
    }
}

// MARK: - BandChip

/// Compact monospaced band readout derived from frequency. Tinted purple
/// because band info is operator metadata, not a hardware-supplied value.
struct BandChip: View {
    let band: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "waveform.path")
                .font(.system(size: 9, weight: .semibold))
            Text(band)
                .font(.caption.monospaced().weight(.semibold))
                .tracking(0.4)
        }
        .foregroundStyle(.purple)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.purple.opacity(0.12), in: Capsule())
    }
}

// MARK: - LastSessionPreviewPanel

/// Right-rail preview card showing the operator's most recent session of the
/// same intent. Gives the composer somewhere useful to live instead of dead
/// space and lets an operator one-click reuse equipment from last time.
struct LastSessionPreviewPanel: View {
    // MARK: Internal

    let intent: SessionsIntent
    let session: LoggingSession?
    let qsoCount: Int
    let onReuseEquipment: ((String?, String?, String?) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider().opacity(0.25)
            if let session {
                populatedBody(session: session)
            } else {
                emptyBody
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: Private

    private var emptyHint: String {
        switch intent {
        case .activate: "Pick a park, summit, or WWFF area, fill in your equipment, and start logging."
        case .hunt: "Spots will appear in the band map. Pick a needed one and call."
        case .casual: "Quick ragchew log — no rules, no scoring. Start whenever."
        case .contest: "Pick a contest and your exchange surface will appear."
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(intent.tint)
            Text("LAST \(intent.label.uppercased())")
                .font(.caption.weight(.semibold))
                .tracking(0.9)
                .foregroundStyle(.primary.opacity(0.85))
            Spacer()
        }
    }

    private var emptyBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No \(intent.label.lowercased()) sessions yet")
                .font(.subheadline.weight(.medium))
            Text(emptyHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func populatedBody(session: LoggingSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titleText(for: session))
                .font(.title3.monospaced().weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Text(session.startedAt.formatted(.relative(presentation: .named)))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(qsoCount)")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(qsoCount == 1 ? "QSO" : "QSOs")
                .font(.caption.weight(.medium))
                .tracking(0.6)
                .foregroundStyle(.secondary)
        }
        Divider().opacity(0.2)
        VStack(alignment: .leading, spacing: 5) {
            previewRow(label: "FREQ", value: session.frequency.map { String(format: "%.3f", $0) })
            previewRow(label: "MODE", value: session.mode)
            previewRow(label: "ANT", value: session.myAntenna)
            previewRow(label: "KEY", value: session.myKey)
            previewRow(label: "MIC", value: session.myMic)
            previewRow(label: "RIG", value: session.myRig)
        }
        if let onReuseEquipment, hasReusableEquipment(session) {
            Button {
                onReuseEquipment(session.myAntenna, session.myKey, session.myMic)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.right.square")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Reuse equipment")
                        .font(.caption.weight(.medium))
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(intent.tint)
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func previewRow(label: String, value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(spacing: 8) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .leading)
                Text(value)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
        }
    }

    private func titleText(for session: LoggingSession) -> String {
        if let custom = session.customTitle, !custom.isEmpty {
            return custom
        }
        if let contest = session.contestId, !contest.isEmpty {
            return contest.uppercased()
        }
        if let park = session.parkReference, !park.isEmpty {
            return park
        }
        if let sota = session.sotaReference, !sota.isEmpty {
            return sota
        }
        if let wwff = session.wwffReference, !wwff.isEmpty {
            return wwff
        }
        return session.myCallsign.isEmpty ? "Session" : session.myCallsign
    }

    private func hasReusableEquipment(_ session: LoggingSession) -> Bool {
        (session.myAntenna?.isEmpty == false)
            || (session.myKey?.isEmpty == false)
            || (session.myMic?.isEmpty == false)
    }
}
