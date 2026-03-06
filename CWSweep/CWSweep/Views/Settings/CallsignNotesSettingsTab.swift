// Callsign Notes Settings Tab
//
// macOS settings tab for managing Polo callsign notes sources.
// Source config syncs to/from Carrier Wave (iOS) via iCloud KVS.

import CarrierWaveCore
import SwiftUI

// MARK: - CallsignNotesSettingsTab

struct CallsignNotesSettingsTab: View {
    // MARK: Internal

    var body: some View {
        Form {
            Section("Sources") {
                if sources.isEmpty {
                    Text("No callsign notes sources configured.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    ForEach(sources) { source in
                        sourceRow(source)
                    }
                }
            }

            Section {
                HStack {
                    Button("Add Source") {
                        showAddSheet = true
                    }

                    Spacer()

                    if !sources.isEmpty {
                        Button {
                            Task {
                                isRefreshing = true
                                defer { isRefreshing = false }
                                await PoloNotesStore.shared.forceRefresh()
                            }
                        } label: {
                            if isRefreshing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Refresh All")
                            }
                        }
                        .disabled(isRefreshing)
                    }
                }
            }

            Section {
                Text(
                    "Sources are shared with Carrier Wave (iOS) via iCloud. "
                        + "Notes are refreshed automatically every 24 hours."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { loadSources() }
        .sheet(isPresented: $showAddSheet) {
            addSourceSheet
        }
    }

    // MARK: Private

    @State private var sources: [CallsignNotesSourceConfig] = []
    @State private var showAddSheet = false
    @State private var isRefreshing = false
    @State private var newTitle = ""
    @State private var newURL = ""

    private var isValidNewSource: Bool {
        !newTitle.trimmingCharacters(in: .whitespaces).isEmpty
            && !newURL.trimmingCharacters(in: .whitespaces).isEmpty
            && URL(string: newURL.trimmingCharacters(in: .whitespaces)) != nil
    }

    private var addSourceSheet: some View {
        VStack(spacing: 16) {
            Text("Add Notes Source")
                .font(.headline)

            TextField("Title", text: $newTitle)
                .textFieldStyle(.roundedBorder)

            TextField("URL", text: $newURL)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    newTitle = ""
                    newURL = ""
                    showAddSheet = false
                }

                Spacer()

                Button("Add") {
                    addSource()
                }
                .disabled(!isValidNewSource)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func sourceRow(_ source: CallsignNotesSourceConfig) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.title)
                Text(source.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { source.isEnabled },
                set: { newValue in
                    toggleSource(id: source.id, isEnabled: newValue)
                }
            ))
            .labelsHidden()

            Button(role: .destructive) {
                deleteSource(id: source.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Data Operations

    private func loadSources() {
        // Read from KVS first, fall back to UserDefaults
        if let data = NSUbiquitousKeyValueStore.default.data(forKey: PoloNotesStore.kvsKey),
           let configs = try? JSONDecoder().decode([CallsignNotesSourceConfig].self, from: data)
        {
            sources = configs
        } else if let data = UserDefaults.standard.data(forKey: "callsignNotesSources"),
                  let configs = try? JSONDecoder().decode([CallsignNotesSourceConfig].self, from: data)
        {
            sources = configs
        }
    }

    private func saveSources() {
        guard let data = try? JSONEncoder().encode(sources) else {
            return
        }
        NSUbiquitousKeyValueStore.default.set(data, forKey: PoloNotesStore.kvsKey)
        UserDefaults.standard.set(data, forKey: "callsignNotesSources")
    }

    private func addSource() {
        let config = CallsignNotesSourceConfig(
            title: newTitle.trimmingCharacters(in: .whitespaces),
            url: newURL.trimmingCharacters(in: .whitespaces)
        )
        sources.append(config)
        saveSources()
        newTitle = ""
        newURL = ""
        showAddSheet = false
    }

    private func deleteSource(id: UUID) {
        sources.removeAll { $0.id == id }
        saveSources()
    }

    private func toggleSource(id: UUID, isEnabled: Bool) {
        guard let index = sources.firstIndex(where: { $0.id == id }) else {
            return
        }
        sources[index].isEnabled = isEnabled
        saveSources()
    }
}
