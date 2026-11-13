# Bug Report Interface Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a bug report feature that emails jaysvana@gmail.com with app info, service status, and sync logs.

**Architecture:** BugReportService collects device/app/service info. BugReportView presents the form and handles mail composition. Shake gesture detected via UIWindow subclass in the app's scene.

**Tech Stack:** SwiftUI, MessageUI (MFMailComposeViewController), PhotosUI (PhotosPicker), UIKit (shake detection)

---

## Task 1: Create BugReportService

**Files:**
- Create: `CarrierWave/Services/BugReportService.swift`

**Step 1: Create the service with device info collection**

```swift
import Foundation
import MessageUI
import UIKit

// MARK: - BugCategory

enum BugCategory: String, CaseIterable {
    case syncIssue = "Sync Issue"
    case uiProblem = "UI Problem"
    case crash = "Crash"
    case other = "Other"
}

// MARK: - BugReportService

@MainActor
final class BugReportService {
    // MARK: Lifecycle

    init(
        qrzClient: QRZClient = QRZClient(),
        lofiClient: LoFiClient = LoFiClient(),
        lotwClient: LoTWClient = LoTWClient(),
        hamrsClient: HAMRSClient = HAMRSClient(),
        potaAuth: POTAAuthService? = nil,
        iCloudMonitor: ICloudMonitor? = nil
    ) {
        self.qrzClient = qrzClient
        self.lofiClient = lofiClient
        self.lotwClient = lotwClient
        self.hamrsClient = hamrsClient
        self.potaAuth = potaAuth
        self.iCloudMonitor = iCloudMonitor
    }

    // MARK: Internal

    static let recipientEmail = "jaysvana@gmail.com"

    struct DeviceInfo {
        let appVersion: String
        let buildNumber: String
        let iosVersion: String
        let deviceModel: String
        let debugMode: Bool
    }

    struct ServiceStatus {
        let qrzConfigured: Bool
        let potaConfigured: Bool
        let lofiConfigured: Bool
        let lotwConfigured: Bool
        let hamrsConfigured: Bool
        let iCloudStatus: String
    }

    func collectDeviceInfo(debugMode: Bool) -> DeviceInfo {
        DeviceInfo(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown",
            iosVersion: UIDevice.current.systemVersion,
            deviceModel: deviceModelName(),
            debugMode: debugMode
        )
    }

    func collectServiceStatus() -> ServiceStatus {
        ServiceStatus(
            qrzConfigured: qrzClient.hasApiKey(),
            potaConfigured: potaAuth?.isAuthenticated ?? false,
            lofiConfigured: lofiClient.hasCredentials(),
            lotwConfigured: lotwClient.hasCredentials(),
            hamrsConfigured: hamrsClient.hasApiKey(),
            iCloudStatus: iCloudMonitor?.statusDescription ?? "Unknown"
        )
    }

    func collectSyncLogs() -> String {
        let entries = SyncDebugLog.shared.logEntries.prefix(50)
        if entries.isEmpty {
            return "No recent sync activity"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        return entries.map { entry in
            let service = entry.service.map { "[\($0.displayName)]" } ?? ""
            return "[\(formatter.string(from: entry.timestamp))][\(entry.level.rawValue)]\(service) \(entry.message)"
        }.joined(separator: "\n")
    }

    func formatReport(
        category: BugCategory,
        description: String,
        deviceInfo: DeviceInfo,
        serviceStatus: ServiceStatus,
        syncLogs: String
    ) -> String {
        """
        Bug Report - Carrier Wave

        Category: \(category.rawValue)

        Description:
        \(description.isEmpty ? "(No description provided)" : description)

        ---
        App Information:
        - Version: \(deviceInfo.appVersion) (\(deviceInfo.buildNumber))
        - iOS: \(deviceInfo.iosVersion)
        - Device: \(deviceInfo.deviceModel)
        - Debug Mode: \(deviceInfo.debugMode ? "On" : "Off")

        Service Status:
        - QRZ: \(serviceStatus.qrzConfigured ? "Configured" : "Not configured")
        - POTA: \(serviceStatus.potaConfigured ? "Configured" : "Not configured")
        - LoFi: \(serviceStatus.lofiConfigured ? "Configured" : "Not configured")
        - LoTW: \(serviceStatus.lotwConfigured ? "Configured" : "Not configured")
        - HAMRS: \(serviceStatus.hamrsConfigured ? "Configured" : "Not configured")
        - iCloud: \(serviceStatus.iCloudStatus)

        Recent Sync Log:
        \(syncLogs)
        """
    }

    func emailSubject(category: BugCategory, version: String) -> String {
        "[Carrier Wave Bug] \(category.rawValue) - v\(version)"
    }

    static func canSendMail() -> Bool {
        MFMailComposeViewController.canSendMail()
    }

    // MARK: Private

    private let qrzClient: QRZClient
    private let lofiClient: LoFiClient
    private let lotwClient: LoTWClient
    private let hamrsClient: HAMRSClient
    private let potaAuth: POTAAuthService?
    private let iCloudMonitor: ICloudMonitor?

    private func deviceModelName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return mapDeviceIdentifier(identifier)
    }

    private func mapDeviceIdentifier(_ identifier: String) -> String {
        // Common device mappings
        let mappings: [String: String] = [
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus",
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,5": "iPhone 13",
            "iPhone14,4": "iPhone 13 mini",
            "x86_64": "Simulator (Intel)",
            "arm64": "Simulator (Apple Silicon)",
        ]
        return mappings[identifier] ?? identifier
    }
}
```

**Step 2: Add Xcode project reference**

Add `BugReportService.swift` to the CarrierWave target in Xcode.

**Step 3: Commit**

```bash
git add CarrierWave/Services/BugReportService.swift
git commit -m "feat: add BugReportService for collecting device and app info"
```

---

## Task 2: Add ICloudMonitor statusDescription

**Files:**
- Modify: `CarrierWave/Services/ICloudMonitor.swift`

**Step 1: Add computed property for status description**

Add this computed property to `ICloudMonitor`:

```swift
var statusDescription: String {
    switch status {
    case .available:
        return "Available"
    case .noAccount:
        return "No Account"
    case .restricted:
        return "Restricted"
    case .couldNotDetermine:
        return "Could Not Determine"
    case .temporarilyUnavailable:
        return "Temporarily Unavailable"
    @unknown default:
        return "Unknown"
    }
}
```

**Step 2: Commit**

```bash
git add CarrierWave/Services/ICloudMonitor.swift
git commit -m "feat: add statusDescription to ICloudMonitor for bug reports"
```

---

## Task 3: Add LoFiClient and HAMRSClient credential checks

**Files:**
- Modify: `CarrierWave/Services/LoFiClient.swift`
- Modify: `CarrierWave/Services/HAMRSClient.swift`

**Step 1: Add hasCredentials to LoFiClient**

Add this method to `LoFiClient`:

```swift
func hasCredentials() -> Bool {
    do {
        _ = try KeychainHelper.shared.readString(for: KeychainHelper.Keys.lofiAuthToken)
        return true
    } catch {
        return false
    }
}
```

**Step 2: Add hasApiKey to HAMRSClient**

Add this method to `HAMRSClient`:

```swift
func hasApiKey() -> Bool {
    do {
        _ = try KeychainHelper.shared.readString(for: KeychainHelper.Keys.hamrsApiKey)
        return true
    } catch {
        return false
    }
}
```

**Step 3: Commit**

```bash
git add CarrierWave/Services/LoFiClient.swift CarrierWave/Services/HAMRSClient.swift
git commit -m "feat: add credential check methods for bug report service status"
```

---

## Task 4: Create MailComposeView wrapper

**Files:**
- Create: `CarrierWave/Views/Settings/MailComposeView.swift`

**Step 1: Create the UIViewControllerRepresentable wrapper**

```swift
import MessageUI
import SwiftUI

struct MailComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let body: String
    let attachmentData: Data?
    let attachmentMimeType: String?
    let attachmentFileName: String?
    var onDismiss: (MFMailComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setToRecipients(recipients)
        composer.setSubject(subject)
        composer.setMessageBody(body, isHTML: false)

        if let data = attachmentData,
           let mimeType = attachmentMimeType,
           let fileName = attachmentFileName {
            composer.addAttachmentData(data, mimeType: mimeType, fileName: fileName)
        }

        return composer
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onDismiss: (MFMailComposeResult) -> Void

        init(onDismiss: @escaping (MFMailComposeResult) -> Void) {
            self.onDismiss = onDismiss
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true) {
                self.onDismiss(result)
            }
        }
    }
}
```

**Step 2: Add to Xcode project**

Add `MailComposeView.swift` to the CarrierWave target.

**Step 3: Commit**

```bash
git add CarrierWave/Views/Settings/MailComposeView.swift
git commit -m "feat: add MailComposeView wrapper for MFMailComposeViewController"
```

---

## Task 5: Create BugReportView

**Files:**
- Create: `CarrierWave/Views/Settings/BugReportView.swift`

**Step 1: Create the bug report form view**

```swift
import MessageUI
import PhotosUI
import SwiftUI

struct BugReportView: View {
    // MARK: Lifecycle

    init(potaAuth: POTAAuthService, iCloudMonitor: ICloudMonitor) {
        self.potaAuth = potaAuth
        self.iCloudMonitor = iCloudMonitor
    }

    // MARK: Internal

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                categorySection
                descriptionSection
                screenshotSection
                infoSection
                if debugMode {
                    logsSection
                }
            }
            .navigationTitle("Report a Bug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { sendReport() }
                        .disabled(isSending)
                }
            }
            .sheet(isPresented: $showingMailComposer) {
                MailComposeView(
                    recipients: [BugReportService.recipientEmail],
                    subject: emailSubject,
                    body: emailBody,
                    attachmentData: screenshotData,
                    attachmentMimeType: screenshotData != nil ? "image/jpeg" : nil,
                    attachmentFileName: screenshotData != nil ? "screenshot.jpg" : nil,
                    onDismiss: handleMailResult
                )
            }
            .alert("Report Copied", isPresented: $showingCopiedAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text("The bug report has been copied to your clipboard. Please email it to \(BugReportService.recipientEmail)")
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: Private

    @AppStorage("debugMode") private var debugMode = false

    @State private var selectedCategory: BugCategory = .other
    @State private var descriptionText = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var screenshotData: Data?
    @State private var screenshotImage: UIImage?
    @State private var showingMailComposer = false
    @State private var showingCopiedAlert = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isSending = false
    @State private var showingLogs = false

    private let potaAuth: POTAAuthService
    private let iCloudMonitor: ICloudMonitor

    private var service: BugReportService {
        BugReportService(potaAuth: potaAuth, iCloudMonitor: iCloudMonitor)
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

    private var emailSubject: String {
        service.emailSubject(category: selectedCategory, version: deviceInfo.appVersion)
    }

    private var emailBody: String {
        service.formatReport(
            category: selectedCategory,
            description: descriptionText,
            deviceInfo: deviceInfo,
            serviceStatus: serviceStatus,
            syncLogs: syncLogs
        )
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

    private var screenshotSection: some View {
        Section {
            if let image = screenshotImage {
                HStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 100)
                        .cornerRadius(8)

                    Spacer()

                    Button(role: .destructive) {
                        screenshotData = nil
                        screenshotImage = nil
                        selectedPhoto = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Attach Screenshot", systemImage: "photo")
                }
            }
        } header: {
            Text("Screenshot (Optional)")
        }
        .onChange(of: selectedPhoto) { _, newValue in
            Task {
                if let data = try? await newValue?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    screenshotImage = image
                    screenshotData = image.jpegData(compressionQuality: 0.7)
                }
            }
        }
    }

    private var infoSection: some View {
        Section {
            DisclosureGroup("Report includes...") {
                LabeledContent("Version", value: "\(deviceInfo.appVersion) (\(deviceInfo.buildNumber))")
                LabeledContent("iOS", value: deviceInfo.iosVersion)
                LabeledContent("Device", value: deviceInfo.deviceModel)
                LabeledContent("QRZ", value: serviceStatus.qrzConfigured ? "Configured" : "Not configured")
                LabeledContent("POTA", value: serviceStatus.potaConfigured ? "Configured" : "Not configured")
                LabeledContent("LoFi", value: serviceStatus.lofiConfigured ? "Configured" : "Not configured")
                LabeledContent("LoTW", value: serviceStatus.lotwConfigured ? "Configured" : "Not configured")
                LabeledContent("HAMRS", value: serviceStatus.hamrsConfigured ? "Configured" : "Not configured")
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

    private func sendReport() {
        isSending = true

        if BugReportService.canSendMail() {
            showingMailComposer = true
        } else {
            // Fallback: copy to clipboard
            UIPasteboard.general.string = emailBody
            showingCopiedAlert = true
        }

        isSending = false
    }

    private func handleMailResult(_ result: MFMailComposeResult) {
        showingMailComposer = false
        switch result {
        case .sent:
            dismiss()
        case .failed:
            errorMessage = "Failed to send email. Please try again."
            showingError = true
        case .cancelled, .saved:
            break
        @unknown default:
            break
        }
    }
}
```

**Step 2: Add to Xcode project**

Add `BugReportView.swift` to the CarrierWave target.

**Step 3: Commit**

```bash
git add CarrierWave/Views/Settings/BugReportView.swift
git commit -m "feat: add BugReportView with form, screenshot picker, and mail composer"
```

---

## Task 6: Add Report a Bug to Settings

**Files:**
- Modify: `CarrierWave/Views/Settings/SettingsView.swift`

**Step 1: Add state for showing bug report sheet**

In `SettingsMainView`, add:

```swift
@State private var showingBugReport = false
```

**Step 2: Add button to aboutSection**

In the `aboutSection` computed property, add before the AttributionsView NavigationLink:

```swift
Button {
    showingBugReport = true
} label: {
    Label("Report a Bug", systemImage: "ant")
}
```

**Step 3: Add sheet modifier**

Add this sheet modifier to the NavigationStack in `body`:

```swift
.sheet(isPresented: $showingBugReport) {
    BugReportView(potaAuth: potaAuth, iCloudMonitor: iCloudMonitor)
}
```

**Step 4: Commit**

```bash
git add CarrierWave/Views/Settings/SettingsView.swift
git commit -m "feat: add Report a Bug button to Settings"
```

---

## Task 7: Add shake gesture detection

**Files:**
- Create: `CarrierWave/Utilities/ShakeDetector.swift`
- Modify: `CarrierWave/ContentView.swift`

**Step 1: Create shake detection notification extension**

```swift
import UIKit

extension UIDevice {
    static let deviceDidShakeNotification = Notification.Name("deviceDidShakeNotification")
}

extension UIWindow {
    override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: UIDevice.deviceDidShakeNotification, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}
```

**Step 2: Add to Xcode project**

Add `ShakeDetector.swift` to the CarrierWave target.

**Step 3: Add shake handler to ContentView**

In `ContentView`, add these state variables:

```swift
@State private var showingBugReport = false
@State private var lastShakeTime: Date?
```

Add this computed property:

```swift
private var potaAuth: POTAAuthService {
    potaAuthService
}
```

Add this `.onReceive` modifier and sheet to the TabView:

```swift
.onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)) { _ in
    // Debounce: ignore shakes within 1 second of each other
    let now = Date()
    if let lastShake = lastShakeTime, now.timeIntervalSince(lastShake) < 1.0 {
        return
    }
    lastShakeTime = now
    showingBugReport = true
}
.sheet(isPresented: $showingBugReport) {
    BugReportView(potaAuth: potaAuthService, iCloudMonitor: iCloudMonitor)
}
```

**Step 4: Commit**

```bash
git add CarrierWave/Utilities/ShakeDetector.swift CarrierWave/ContentView.swift
git commit -m "feat: add shake gesture to trigger bug report"
```

---

## Task 8: Update CLAUDE.md file index

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Add new files to index**

Add to Services section:

```markdown
| `BugReportService.swift` | Collects device/app info for bug reports |
```

Add to Views - Settings section:

```markdown
| `BugReportView.swift` | Bug report form with mail composer |
| `MailComposeView.swift` | MFMailComposeViewController wrapper |
```

Add to Utilities section:

```markdown
| `ShakeDetector.swift` | Shake gesture notification for bug reports |
```

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add bug report files to CLAUDE.md index"
```

---

## Task 9: Final verification

**Step 1: Prompt user to build and test**

Ask the user to:
1. Build the project in Xcode
2. Test the Settings → Report a Bug flow
3. Test the shake gesture
4. Verify mail composer appears (or clipboard fallback works)

**Step 2: Push changes**

```bash
git push
```
