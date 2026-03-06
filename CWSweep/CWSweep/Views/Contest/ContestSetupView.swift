import CarrierWaveData
import SwiftData
import SwiftUI

/// Sheet for picking a contest template and configuring station parameters.
struct ContestSetupView: View {
    // MARK: Internal

    let contestManager: ContestManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Start Contest")
                    .font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()

            Divider()

            HSplitView {
                // Left: Contest picker
                VStack(alignment: .leading, spacing: 0) {
                    TextField("Search contests...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .padding(8)

                    List(filteredTemplates, selection: $selectedTemplateId) { template in
                        VStack(alignment: .leading) {
                            Text(template.name)
                                .fontWeight(.medium)
                            Text(template.modes.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(template.id)
                    }
                    .listStyle(.sidebar)
                }
                .frame(minWidth: 250, idealWidth: 300)

                // Right: Station form
                Form {
                    if let template = selectedTemplate {
                        Section("Contest") {
                            LabeledContent("Name", value: template.name)
                            LabeledContent("Modes", value: template.modes.joined(separator: ", "))
                            LabeledContent("Bands", value: template.bands.joined(separator: ", "))
                        }

                        Section("Station") {
                            TextField("Callsign", text: $callsign)
                                .autocorrectionDisabled()
                            Picker("Category", selection: $category) {
                                ForEach(Self.categories, id: \.self) { cat in
                                    Text(Self.friendlyCategoryName(cat)).tag(cat)
                                }
                            }
                            Picker("Power", selection: $power) {
                                ForEach(Self.powerLevels, id: \.self) { p in
                                    Text(Self.friendlyPowerName(p)).tag(p)
                                }
                            }
                            Picker("Band", selection: $bands) {
                                ForEach(Self.bandOptions, id: \.self) { b in
                                    Text(b).tag(b)
                                }
                            }
                        }

                        Section("Exchange Preview") {
                            HStack {
                                ForEach(template.exchange.fields) { field in
                                    VStack {
                                        Text(field.label)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(field.defaultValue ?? "---")
                                            .font(.body.monospaced())
                                    }
                                }
                            }
                        }
                    } else {
                        Text("Select a contest from the list")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .formStyle(.grouped)
                .frame(minWidth: 300)
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Start Contest") {
                    startContest()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedTemplate == nil || callsign.isEmpty)
                .help(selectedTemplate == nil ? "Select a contest first" : callsign
                    .isEmpty ? "Enter your callsign" : "Start the contest")
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()
        }
        .frame(minWidth: 600, idealWidth: 700, minHeight: 400, idealHeight: 500)
        .task {
            templates = await (try? templateLoader.allTemplates()) ?? []
            // Pre-fill callsign from settings
            callsign = (try? KeychainHelper.shared.readString(
                for: KeychainHelper.Keys.currentCallsign
            )) ?? ""
        }
    }

    // MARK: Private

    private static let categories = [
        "SINGLE-OP", "SINGLE-OP-ASSISTED", "MULTI-ONE", "MULTI-TWO", "MULTI-MULTI",
        "CHECKLOG", "SCHOOL",
    ]
    private static let powerLevels = ["HIGH", "LOW", "QRP"]
    private static let bandOptions = ["ALL", "160m", "80m", "40m", "20m", "15m", "10m", "6m"]

    @State private var templates: [ContestDefinition] = []
    @State private var selectedTemplateId: String?
    @State private var searchText = ""
    @State private var callsign = ""
    @State private var category = "SINGLE-OP"
    @State private var power = "HIGH"
    @State private var bands = "ALL"
    @State private var myExchange = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let templateLoader = ContestTemplateLoader()

    private var filteredTemplates: [ContestDefinition] {
        if searchText.isEmpty {
            return templates
        }
        return templates.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var selectedTemplate: ContestDefinition? {
        guard let id = selectedTemplateId else {
            return nil
        }
        return templates.first { $0.id == id }
    }

    private static func friendlyCategoryName(_ raw: String) -> String {
        switch raw {
        case "SINGLE-OP": "Single Operator"
        case "SINGLE-OP-ASSISTED": "Single Op Assisted"
        case "MULTI-ONE": "Multi-Op, One Transmitter"
        case "MULTI-TWO": "Multi-Op, Two Transmitters"
        case "MULTI-MULTI": "Multi-Op, Multi Transmitter"
        case "CHECKLOG": "Checklog"
        case "SCHOOL": "School"
        default: raw
        }
    }

    private static func friendlyPowerName(_ raw: String) -> String {
        switch raw {
        case "HIGH": "High (> 100W)"
        case "LOW": "Low (≤ 100W)"
        case "QRP": "QRP (≤ 5W)"
        default: raw
        }
    }

    private func startContest() {
        guard let template = selectedTemplate else {
            return
        }

        // Create logging session for this contest
        let session = LoggingSession(
            myCallsign: callsign.uppercased(),
            mode: template.modes.first ?? "CW",
            contestId: template.id,
            contestCategory: category,
            contestPower: power,
            contestBands: bands,
            contestOperator: callsign.uppercased()
        )
        session.customTitle = template.name
        modelContext.insert(session)

        Task {
            await contestManager.startContest(
                definition: template,
                session: session
            )
        }

        dismiss()
    }
}
