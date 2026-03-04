import CarrierWaveData
import PhotosUI
import SwiftUI
import UIKit

struct BugReportView: View {
    // MARK: Lifecycle

    init(
        syncService: SyncService? = nil,
        potaAuth: POTAAuthService,
        iCloudMonitor: ICloudMonitor
    ) {
        self.syncService = syncService
        self.potaAuth = potaAuth
        self.iCloudMonitor = iCloudMonitor
    }

    // MARK: Internal

    var body: some View {
        NavigationStack {
            Form {
                if !hasSubmitted {
                    categorySection
                    descriptionSection
                    infoSection
                    if debugMode {
                        logsSection
                    }
                } else {
                    resultSection
                }
            }
            .navigationTitle("Report a Bug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(hasSubmitted ? "Done" : "Cancel") { dismiss() }
                }
                if !hasSubmitted {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Submit") { submitReport() }
                    }
                }
            }
            .task {
                callsignInfo = service.collectCallsignInfo()
            }
        }
    }

    // MARK: Private

    private static let discordURL = "https://discord.gg/PqubUxWW62"

    @Environment(\.dismiss) private var dismiss

    @AppStorage("debugMode") private var debugMode = false

    @State private var selectedCategory: BugCategory = .other
    @State private var descriptionText = ""
    @State private var showingLogs = false
    @State private var hasSubmitted = false
    @State private var callsignInfo = BugReportService.CallsignInfo(
        currentCallsign: nil, previousCallsigns: []
    )

    private let syncService: SyncService?
    private let potaAuth: POTAAuthService
    private let iCloudMonitor: ICloudMonitor

    private var service: BugReportService {
        BugReportService(
            qrzClient: syncService?.qrzClient,
            lofiClient: syncService?.lofiClient,
            lotwClient: syncService?.lotwClient,
            hamrsClient: syncService?.hamrsClient,
            potaAuth: potaAuth,
            iCloudMonitor: iCloudMonitor
        )
    }

    private var deviceInfo: BugReportService.DeviceInfo {
        service.collectDeviceInfo(debugMode: debugMode)
    }

    private var serviceStatus: BugReportService.ServiceStatus {
        service.collectServiceStatus()
    }

    private var syncLogs: String {
        service.collectSyncLogs()
    }

    private var reportBody: String {
        let context = BugReportService.ReportContext(
            category: selectedCategory,
            description: descriptionText,
            deviceInfo: deviceInfo,
            serviceStatus: serviceStatus,
            callsignInfo: callsignInfo,
            syncLogs: syncLogs
        )
        return service.formatReport(context)
    }

    private var categorySection: some View {
        Section {
            Picker("Category", selection: $selectedCategory) {
                ForEach(BugCategory.allCases, id: \.self) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var descriptionSection: some View {
        Section {
            TextField("Describe what happened...", text: $descriptionText, axis: .vertical)
                .lineLimit(5 ... 10)
        } header: {
            Text("Description")
        }
    }

    private var infoSection: some View {
        Section {
            DisclosureGroup("Report includes...") {
                LabeledContent("Version", value: deviceInfo.appVersion)
                LabeledContent("iOS", value: deviceInfo.iosVersion)
                LabeledContent("Device", value: deviceInfo.deviceModel)
                LabeledContent(
                    "Current Callsign", value: callsignInfo.currentCallsign ?? "Not configured"
                )
                if !callsignInfo.previousCallsigns.isEmpty {
                    LabeledContent(
                        "Previous Callsigns",
                        value: callsignInfo.previousCallsigns.joined(separator: ", ")
                    )
                }
                LabeledContent(
                    "QRZ", value: serviceStatus.qrzConfigured ? "Configured" : "Not configured"
                )
                LabeledContent(
                    "POTA", value: serviceStatus.potaConfigured ? "Configured" : "Not configured"
                )
                LabeledContent(
                    "LoFi", value: serviceStatus.lofiConfigured ? "Configured" : "Not configured"
                )
                LabeledContent(
                    "LoTW", value: serviceStatus.lotwConfigured ? "Configured" : "Not configured"
                )
                LabeledContent(
                    "HAMRS", value: serviceStatus.hamrsConfigured ? "Configured" : "Not configured"
                )
                LabeledContent("iCloud", value: serviceStatus.iCloudStatus)
            }
        } footer: {
            Text("Report includes recent sync activity which may contain callsigns.")
        }
    }

    private var logsSection: some View {
        Section {
            DisclosureGroup("Sync Debug Logs", isExpanded: $showingLogs) {
                Text(syncLogs)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var resultSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Label("Report Copied", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)

                Text(
                    "Your bug report has been copied to the clipboard. "
                        + "Please paste it in the **#bug-reports** channel on Discord."
                )
                .font(.subheadline)

                Text("Please include screenshots detailing the issue.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Open Discord") {
                    if let url = URL(string: Self.discordURL) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
            .padding(.vertical, 8)
        }
    }

    private func submitReport() {
        UIPasteboard.general.string = reportBody
        hasSubmitted = true
    }
}
