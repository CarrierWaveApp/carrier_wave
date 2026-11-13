import CarrierWaveData
import SwiftUI

// MARK: - MacroEditorView+HeaderSection

extension MacroEditorView {
    @ViewBuilder
    var headerSection: some View {
        @Bindable var boundModel = model

        Section("Identity") {
            TextField("Name", text: $boundModel.spec.name)
                .onChange(of: model.spec.name) { _, _ in model.markDirty() }

            HStack {
                Text("Icon")
                Spacer()
                NavigationLink {
                    MacroIconPickerView(selection: Binding(
                        get: { model.spec.icon ?? "wand.and.stars" },
                        set: { newValue in
                            model.spec.icon = newValue
                            model.markDirty()
                        }
                    ))
                } label: {
                    HStack {
                        Image(systemName: model.spec.icon ?? "wand.and.stars")
                            .font(.title3)
                            .foregroundStyle(.tint)
                        Text(model.spec.icon ?? "default")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Description")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(
                    "Short description",
                    text: Binding(
                        get: { model.spec.description ?? "" },
                        set: { newValue in
                            model.spec.description = newValue.isEmpty ? nil : newValue
                            model.markDirty()
                        }
                    ),
                    axis: .vertical
                )
                .lineLimit(2 ... 5)
            }

            TextField(
                "Author (optional)",
                text: Binding(
                    get: { model.spec.author ?? "" },
                    set: { newValue in
                        model.spec.author = newValue.isEmpty ? nil : newValue
                        model.markDirty()
                    }
                )
            )
        }

        Section {
            MacroTagsEditor(
                tags: Binding(
                    get: { model.spec.tags ?? [] },
                    set: { newValue in
                        model.spec.tags = newValue.isEmpty ? nil : newValue
                        model.markDirty()
                    }
                )
            )
        } header: {
            Text("Tags")
        } footer: {
            Text("Tags help find macros via search. Lowercase, no spaces.")
        }

        Section {
            MacroAppliesToEditor(
                appliesTo: Binding(
                    get: { model.spec.appliesTo ?? [] },
                    set: { newValue in
                        model.spec.appliesTo = newValue.isEmpty ? nil : newValue
                        model.markDirty()
                    }
                )
            )
        } header: {
            Text("Applies To")
        } footer: {
            Text("Macros run only against connected radios on a matching protocol.")
        }
    }
}

// MARK: - MacroIconPickerView

struct MacroIconPickerView: View {
    // MARK: Internal

    @Binding var selection: String

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Self.icons, id: \.self) { name in
                    Button {
                        selection = name
                        dismiss()
                    } label: {
                        Image(systemName: name)
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .background(
                                selection == name
                                    ? Color.accentColor.opacity(0.25)
                                    : Color.secondary.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .foregroundStyle(selection == name ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle("Pick an Icon")
    }

    // MARK: Private

    private static let icons: [String] = [
        "wand.and.stars", "antenna.radiowaves.left.and.right",
        "dot.radiowaves.left.and.right", "waveform", "waveform.path",
        "speaker.wave.2", "speaker.wave.3", "mic",
        "headphones", "tuningfork", "music.note",
        "bolt", "bolt.fill", "power",
        "play.fill", "pause.fill", "stop.fill",
        "arrow.up.right", "arrow.up.right.circle", "arrow.triangle.2.circlepath",
        "gauge.with.dots.needle.bottom.50percent", "gauge.with.dots.needle.bottom.0percent",
        "slider.horizontal.3", "dial.high",
        "keyboard", "command", "option",
        "globe.americas", "globe.europe.africa", "globe.asia.australia",
        "moon.stars", "sun.max", "cloud.sun",
        "star", "star.fill", "flag.fill",
        "tag.fill", "bookmark.fill", "pin.fill",
        "checkmark.circle", "checkmark.shield", "exclamationmark.triangle",
    ]

    @Environment(\.dismiss) private var dismiss

    private var columns: [GridItem] {
        Array(repeating: GridItem(.adaptive(minimum: 50)), count: 6)
    }
}

// MARK: - MacroTagsEditor

struct MacroTagsEditor: View {
    // MARK: Internal

    @Binding var tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            HStack(spacing: 4) {
                                Text("#\(tag)")
                                    .font(.caption.weight(.semibold))
                                Button {
                                    remove(tag)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.18), in: Capsule())
                            .foregroundStyle(.tint)
                        }
                    }
                }
            }
            HStack {
                TextField("Add tag", text: $pending)
                    .onSubmit { add() }
                Button("Add") { add() }
                    .disabled(cleaned.isEmpty)
            }
        }
    }

    // MARK: Private

    @State private var pending: String = ""

    private var cleaned: String {
        pending
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func add() {
        let value = cleaned
        guard !value.isEmpty, !tags.contains(value) else {
            return
        }
        tags.append(value)
        pending = ""
    }

    private func remove(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
}

// MARK: - MacroAppliesToEditor

struct MacroAppliesToEditor: View {
    // MARK: Internal

    @Binding var appliesTo: [RadioCommandProtocol]

    var body: some View {
        ForEach(RadioCommandProtocol.allCases, id: \.rawValue) { rigProtocol in
            Toggle(isOn: binding(for: rigProtocol)) {
                Label(rigProtocol.displayName, systemImage: icon(for: rigProtocol))
            }
        }
    }

    // MARK: Private

    private func binding(for rigProtocol: RadioCommandProtocol) -> Binding<Bool> {
        Binding(
            get: { appliesTo.contains(rigProtocol) },
            set: { newValue in
                if newValue, !appliesTo.contains(rigProtocol) {
                    appliesTo.append(rigProtocol)
                } else if !newValue {
                    appliesTo.removeAll { $0 == rigProtocol }
                }
            }
        )
    }

    private func icon(for rigProtocol: RadioCommandProtocol) -> String {
        switch rigProtocol {
        case .civ: "dot.radiowaves.left.and.right"
        case .kenwood: "antenna.radiowaves.left.and.right"
        case .yaesu: "waveform"
        case .flex: "rectangle.connected.to.line.below"
        }
    }
}
