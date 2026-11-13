// Prefix Row Settings View
//
// Configures the callsign prefix hot-key row (CAR-290): Suggested mode
// ranks prefixes local to the operator's current position (shared Rust
// logic); Custom mode is the user's own ordered list.

import CarrierWaveData
import SwiftUI

struct PrefixRowSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            sourceSection
            if prefixRowMode == "custom" {
                customListSection
                nearYouSection
            } else {
                positionSection
                suggestionsSection
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Prefixes")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            KeyboardRowsStackPreview(highlighted: .prefixes)
        }
        .onAppear {
            prefixService.refresh()
        }
    }

    // MARK: Private

    @AppStorage("prefixRowMode") private var prefixRowMode = "suggested"
    @AppStorage("prefixRowCustom") private var prefixRowCustom = ""

    @State private var prefixService = PrefixRowService.shared
    @State private var newPrefix = ""

    private var customPrefixes: [String] {
        prefixRowCustom.components(separatedBy: ",").filter { !$0.isEmpty }
    }

    private var sourceSection: some View {
        Section {
            sourceRow(
                mode: "suggested",
                title: "Suggested",
                subtitle: "Prefixes local to your current position"
            )
            sourceRow(
                mode: "custom",
                title: "Custom",
                subtitle: "Your own list, in your order"
            )
        } header: {
            Text("Source")
        } footer: {
            Text(
                """
                One tap stamps a prefix into the callsign field. Tapping a \
                key while a prefix is already typed replaces it and keeps \
                the suffix.
                """
            )
        }
    }

    // MARK: Custom mode

    private var customListSection: some View {
        Section {
            if customPrefixes.isEmpty {
                Text("No prefixes yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(customPrefixes, id: \.self) { prefix in
                    customRow(prefix)
                }
                .onMove(perform: moveCustom)
            }

            HStack {
                TextField("Add prefix", text: $newPrefix)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onSubmit(addNewPrefix)
                Button("Add", action: addNewPrefix)
                    .disabled(sanitized(newPrefix).isEmpty)
            }
        } header: {
            Text("Prefixes")
        } footer: {
            Text("Drag to reorder — keys appear left to right. Tap − to remove.")
        }
    }

    private var nearYouSection: some View {
        Section {
            let available = prefixService.suggested.filter { !customPrefixes.contains($0) }
            if available.isEmpty {
                Text("No nearby suggestions to add")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(available, id: \.self) { prefix in
                    Button {
                        appendCustom(prefix)
                    } label: {
                        HStack {
                            Text(prefix)
                                .font(.body.monospaced())
                            Spacer()
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.green)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(prefix)")
                }
            }
        } header: {
            Text("Common near you")
        } footer: {
            Text("Your list is yours — it never changes on its own when you travel.")
        }
    }

    // MARK: Suggested mode

    private var positionSection: some View {
        Section {
            HStack {
                Image(systemName: "location.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Current position")
                Spacer()
                Text(DeviceLocationHint.lastKnownGrid ?? "Unknown")
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var suggestionsSection: some View {
        Section {
            if prefixService.suggested.isEmpty {
                Text("No suggestions yet — log a few QSOs first")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(prefixService.suggested, id: \.self) { prefix in
                            Text(prefix)
                                .font(.subheadline.weight(.medium).monospaced())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("Current suggestions")
        } footer: {
            Text(
                """
                Always local to where you are operating right now: prefixes \
                most worked near your current grid, recomputed whenever it \
                changes. Your logbook never adds prefixes from somewhere else.
                """
            )
        }
    }

    private func sourceRow(mode: String, title: String, subtitle: String) -> some View {
        Button {
            prefixRowMode = mode
            notifyChange()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if prefixRowMode == mode {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(prefixRowMode == mode ? .isSelected : [])
    }

    private func customRow(_ prefix: String) -> some View {
        Button {
            removeCustom(prefix)
        } label: {
            HStack {
                Text(prefix)
                    .font(.body.monospaced())
                Spacer()
                Image(systemName: "minus.circle")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(prefix)")
    }

    // MARK: Mutation

    private func sanitized(_ raw: String) -> String {
        raw.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private func addNewPrefix() {
        let prefix = sanitized(newPrefix)
        guard !prefix.isEmpty, prefix.count <= 4 else {
            return
        }
        newPrefix = ""
        appendCustom(prefix)
    }

    private func appendCustom(_ prefix: String) {
        var list = customPrefixes
        guard !list.contains(prefix) else {
            return
        }
        list.append(prefix)
        saveCustom(list)
    }

    private func removeCustom(_ prefix: String) {
        saveCustom(customPrefixes.filter { $0 != prefix })
    }

    private func moveCustom(from source: IndexSet, to destination: Int) {
        var list = customPrefixes
        list.move(fromOffsets: source, toOffset: destination)
        saveCustom(list)
    }

    private func saveCustom(_ list: [String]) {
        prefixRowCustom = list.joined(separator: ",")
        notifyChange()
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .keyboardRowConfigurationChanged, object: nil)
    }
}

#Preview {
    NavigationStack {
        PrefixRowSettingsView()
    }
}
