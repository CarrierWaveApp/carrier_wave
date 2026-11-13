# Onboarding Tour Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement a progressive onboarding tour system with intro tour on first launch and contextual mini-tours for specific features.

**Architecture:** UserDefaults-backed state tracking (`TourState`), reusable `TourSheetView` component for all tour presentations, integration points in existing views via `.onAppear` checks.

**Tech Stack:** SwiftUI, UserDefaults (via @AppStorage pattern), @Observable for state

---

## Task 1: Create TourState Model

**Files:**
- Create: `CarrierWave/Models/TourState.swift`

**Step 1: Create the TourState model**

```swift
import Foundation

// MARK: - TourState

@Observable
final class TourState {
    // MARK: Lifecycle

    init() {
        hasCompletedIntroTour = UserDefaults.standard.bool(forKey: Keys.hasCompletedIntroTour)
        lastTourVersion = UserDefaults.standard.string(forKey: Keys.lastTourVersion) ?? ""
        seenMiniTours = Set(
            UserDefaults.standard.stringArray(forKey: Keys.seenMiniTours) ?? []
        )
    }

    // MARK: Internal

    enum MiniTourID: String, CaseIterable {
        case potaActivations = "pota_activations"
        case potaAccountSetup = "pota_account_setup"
        case challenges = "challenges"
        case statsDrilldown = "stats_drilldown"
        case lofiSetup = "lofi_setup"
    }

    private(set) var hasCompletedIntroTour: Bool {
        didSet { UserDefaults.standard.set(hasCompletedIntroTour, forKey: Keys.hasCompletedIntroTour) }
    }

    private(set) var lastTourVersion: String {
        didSet { UserDefaults.standard.set(lastTourVersion, forKey: Keys.lastTourVersion) }
    }

    private(set) var seenMiniTours: Set<String> {
        didSet { UserDefaults.standard.set(Array(seenMiniTours), forKey: Keys.seenMiniTours) }
    }

    func shouldShowIntroTour() -> Bool {
        !hasCompletedIntroTour
    }

    func completeIntroTour(version: String) {
        hasCompletedIntroTour = true
        lastTourVersion = version
    }

    func shouldShowUpdatePrompt(currentVersion: String, majorVersions: [String]) -> Bool {
        guard hasCompletedIntroTour else { return false }
        guard majorVersions.contains(currentVersion) else { return false }
        return lastTourVersion < currentVersion
    }

    func acknowledgeUpdatePrompt(version: String) {
        lastTourVersion = version
    }

    func shouldShowMiniTour(_ id: MiniTourID) -> Bool {
        !seenMiniTours.contains(id.rawValue)
    }

    func markMiniTourSeen(_ id: MiniTourID) {
        seenMiniTours.insert(id.rawValue)
    }

    func resetForTesting() {
        hasCompletedIntroTour = false
        lastTourVersion = ""
        seenMiniTours = []
    }

    // MARK: Private

    private enum Keys {
        static let hasCompletedIntroTour = "tour.hasCompletedIntroTour"
        static let lastTourVersion = "tour.lastTourVersion"
        static let seenMiniTours = "tour.seenMiniTours"
    }
}
```

**Step 2: Commit**

```bash
git add CarrierWave/Models/TourState.swift
git commit -m "feat(tour): add TourState model for tracking tour progress"
```

---

## Task 2: Create TourSheetView Component

**Files:**
- Create: `CarrierWave/Views/Tour/TourSheetView.swift`

**Step 1: Create the reusable tour sheet component**

```swift
import SwiftUI

// MARK: - TourPage

struct TourPage: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let body: String
}

// MARK: - TourSheetView

struct TourSheetView: View {
    let pages: [TourPage]
    let onComplete: () -> Void
    let onSkip: (() -> Void)?

    @State private var currentPage = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(pages: [TourPage], onComplete: @escaping () -> Void, onSkip: (() -> Void)? = nil) {
        self.pages = pages
        self.onComplete = onComplete
        self.onSkip = onSkip
    }

    var body: some View {
        VStack(spacing: 0) {
            // Page content
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    VStack(spacing: 16) {
                        Image(systemName: page.icon)
                            .font(.system(size: 48))
                            .foregroundStyle(.tint)
                            .padding(.top, 24)

                        Text(page.title)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)

                        Text(page.body)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        Spacer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(reduceMotion ? .none : .easeInOut, value: currentPage)

            // Page indicators
            if pages.count > 1 {
                HStack(spacing: 8) {
                    ForEach(0 ..< pages.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.bottom, 16)
            }

            // Buttons
            HStack(spacing: 16) {
                if let onSkip, currentPage < pages.count - 1 {
                    Button("Skip") {
                        onSkip()
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if currentPage < pages.count - 1 {
                    Button {
                        withAnimation(reduceMotion ? .none : .easeInOut) {
                            currentPage += 1
                        }
                    } label: {
                        Text("Next")
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        onComplete()
                        dismiss()
                    } label: {
                        Text("Done")
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            TourSheetView(
                pages: [
                    TourPage(
                        icon: "antenna.radiowaves.left.and.right",
                        title: "Welcome to Carrier Wave",
                        body: "Your amateur radio log aggregator."
                    ),
                    TourPage(
                        icon: "arrow.triangle.2.circlepath",
                        title: "One Log, Many Destinations",
                        body: "Import QSOs from any source and sync everywhere."
                    ),
                ],
                onComplete: {},
                onSkip: {}
            )
        }
}
```

**Step 2: Commit**

```bash
git add CarrierWave/Views/Tour/TourSheetView.swift
git commit -m "feat(tour): add TourSheetView reusable component"
```

---

## Task 3: Create Intro Tour Content and View

**Files:**
- Create: `CarrierWave/Views/Tour/IntroTourView.swift`

**Step 1: Create the intro tour view with QRZ setup**

```swift
import SwiftUI

// MARK: - IntroTourView

struct IntroTourView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    @State private var qrzUsername = ""
    @State private var qrzPassword = ""
    @State private var isValidating = false
    @State private var validationError: String?
    @State private var showOtherServices = false

    let tourState: TourState
    let appVersion: String
    let qrzClient: QRZClient

    private let totalSteps = 5

    var body: some View {
        VStack(spacing: 0) {
            // Blurred background effect
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            Spacer()

            // Content card
            VStack(spacing: 20) {
                stepContent
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
                    .shadow(radius: 10)
            )
            .padding(.horizontal, 20)

            Spacer()

            // Navigation
            navigationButtons
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 0:
            welcomeStep
        case 1:
            syncExplanationStep
        case 2:
            qrzSetupStep
        case 3:
            otherServicesStep
        case 4:
            feedbackStep
        default:
            EmptyView()
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Welcome to Carrier Wave")
                .font(.title)
                .fontWeight(.bold)

            Text(
                "Your amateur radio log aggregator. Download QSOs from logging apps and services, then upload them everywhere else - automatically. Carrier Wave doesn't create logs; it syncs them."
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
    }

    private var syncExplanationStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("One Log, Many Destinations")
                .font(.title2)
                .fontWeight(.bold)

            Text(
                "Import QSOs from any source. Carrier Wave deduplicates them (same callsign + band + mode within 5 minutes = one contact) and tracks what's been uploaded where."
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
    }

    private var qrzSetupStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.badge.key")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Let's Connect Your First Service")
                .font(.title2)
                .fontWeight(.bold)

            Text("QRZ.com is the most popular logbook. Enter your credentials to start syncing.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                TextField("QRZ Username", text: $qrzUsername)
                    .textContentType(.username)
                    .autocapitalization(.none)
                    .textFieldStyle(.roundedBorder)

                SecureField("QRZ Password", text: $qrzPassword)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)

                if let error = validationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.top, 8)

            Button("Connect a different service instead") {
                showOtherServices = true
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showOtherServices) {
            otherServicesSheet
        }
    }

    private var otherServicesSheet: some View {
        NavigationStack {
            List {
                Section {
                    Label("POTA", systemImage: "tree")
                    Label("Ham2K LoFi", systemImage: "icloud.and.arrow.down")
                    Label("HAMRS", systemImage: "doc.text")
                    Label("LoTW", systemImage: "checkmark.seal")
                } footer: {
                    Text("Configure these in Settings after completing the tour.")
                }
            }
            .navigationTitle("Other Services")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showOtherServices = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var otherServicesStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("More Services Available")
                .font(.title2)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 12) {
                serviceRow(icon: "tree", name: "POTA", desc: "Upload activations to Parks on the Air")
                serviceRow(icon: "icloud.and.arrow.down", name: "Ham2K LoFi", desc: "Import logs from PoLo app")
                serviceRow(icon: "doc.text", name: "HAMRS", desc: "Sync with HAMRS logbook")
                serviceRow(icon: "checkmark.seal", name: "LoTW", desc: "Download QSL confirmations")
            }

            Text("Configure these anytime in Settings")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func serviceRow(icon: String, name: String, desc: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var feedbackStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("We'd Love Your Feedback")
                .font(.title2)
                .fontWeight(.bold)

            Text(
                "Found a bug or have a feature idea? Tap Settings → Report a Bug to send us details. Join our Discord to connect with other users."
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
    }

    private var navigationButtons: some View {
        HStack {
            if currentStep > 0 {
                Button("Back") {
                    withAnimation { currentStep -= 1 }
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Page indicator
            Text("\(currentStep + 1) of \(totalSteps)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if currentStep < totalSteps - 1 {
                Button("Skip") {
                    completeTour()
                }
                .foregroundStyle(.secondary)

                if currentStep == 2 {
                    // QRZ step - show Connect or Skip
                    Button {
                        if qrzUsername.isEmpty || qrzPassword.isEmpty {
                            withAnimation { currentStep += 1 }
                        } else {
                            Task { await validateAndSaveQRZ() }
                        }
                    } label: {
                        if isValidating {
                            ProgressView()
                        } else {
                            Text(qrzUsername.isEmpty ? "Skip" : "Connect")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isValidating)
                } else {
                    Button("Next") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Button("Get Started") {
                    completeTour()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func validateAndSaveQRZ() async {
        isValidating = true
        validationError = nil

        do {
            _ = try await qrzClient.authenticate(username: qrzUsername, password: qrzPassword)
            // Save credentials
            KeychainHelper.save(key: "qrz_username", value: qrzUsername)
            KeychainHelper.save(key: "qrz_password", value: qrzPassword)
            withAnimation { currentStep += 1 }
        } catch {
            validationError = "Invalid credentials. Please try again."
        }

        isValidating = false
    }

    private func completeTour() {
        tourState.completeIntroTour(version: appVersion)
        dismiss()
    }
}
```

**Step 2: Commit**

```bash
git add CarrierWave/Views/Tour/IntroTourView.swift
git commit -m "feat(tour): add IntroTourView with QRZ setup flow"
```

---

## Task 4: Create Mini Tour Content Definitions

**Files:**
- Create: `CarrierWave/Views/Tour/MiniTourContent.swift`

**Step 1: Define all mini tour content**

```swift
import Foundation

// MARK: - MiniTourContent

enum MiniTourContent {
    static let potaActivations: [TourPage] = [
        TourPage(
            icon: "tree",
            title: "Your POTA Activations",
            body: "QSOs with a park reference are grouped here by park and date. Each group is an activation you can upload to POTA."
        ),
        TourPage(
            icon: "arrow.up.doc",
            title: "Uploading to POTA",
            body: "Tap an activation to review its QSOs, then upload. You need 10+ QSOs for activation credit, but you can upload smaller logs to credit your hunters."
        ),
    ]

    static let potaAccountSetup: [TourPage] = [
        TourPage(
            icon: "person.2.badge.gearshape",
            title: "POTA Accounts Explained",
            body: "POTA has two account systems that can be confusing."
        ),
        TourPage(
            icon: "server.rack",
            title: "Service Login (AWS Cognito)",
            body: "If you registered years ago, you may have an AWS Cognito login. This is separate from your pota.app account."
        ),
        TourPage(
            icon: "envelope.badge.person.crop",
            title: "Creating a pota.app Account",
            body: "Go to pota.app, create an account with email/password, then link your existing service login in your profile settings. Carrier Wave uses your pota.app credentials."
        ),
    ]

    static let challenges: [TourPage] = [
        TourPage(
            icon: "flag.2.crossed",
            title: "Challenges Coming Soon",
            body: "We're building something exciting here - track your progress toward awards, compete on leaderboards, and join community events. Stay tuned!"
        ),
    ]

    static let statsDrilldown: [TourPage] = [
        TourPage(
            icon: "chart.bar.xaxis",
            title: "Explore Your Stats",
            body: "Tap any statistic to see the breakdown. Expand individual items to view the QSOs that count toward that total."
        ),
    ]

    static let lofiSetup: [TourPage] = [
        TourPage(
            icon: "icloud.and.arrow.down",
            title: "Ham2K LoFi",
            body: "LoFi syncs your logs from the Ham2K Portable Logger (PoLo) app. It's download-only - Carrier Wave imports your PoLo operations."
        ),
        TourPage(
            icon: "link.badge.plus",
            title: "Device Linking",
            body: "Enter the email address associated with your PoLo account. You'll receive a verification code to link this device."
        ),
    ]

    static func pages(for id: TourState.MiniTourID) -> [TourPage] {
        switch id {
        case .potaActivations: potaActivations
        case .potaAccountSetup: potaAccountSetup
        case .challenges: challenges
        case .statsDrilldown: statsDrilldown
        case .lofiSetup: lofiSetup
        }
    }
}
```

**Step 2: Commit**

```bash
git add CarrierWave/Views/Tour/MiniTourContent.swift
git commit -m "feat(tour): add MiniTourContent definitions"
```

---

## Task 5: Create MiniTourModifier for Easy Integration

**Files:**
- Create: `CarrierWave/Views/Tour/MiniTourModifier.swift`

**Step 1: Create a view modifier for mini tour presentation**

```swift
import SwiftUI

// MARK: - MiniTourModifier

struct MiniTourModifier: ViewModifier {
    let tourId: TourState.MiniTourID
    let tourState: TourState
    let triggerOnAppear: Bool

    @State private var showTour = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                if triggerOnAppear, tourState.shouldShowMiniTour(tourId) {
                    showTour = true
                }
            }
            .sheet(isPresented: $showTour) {
                TourSheetView(
                    pages: MiniTourContent.pages(for: tourId),
                    onComplete: {
                        tourState.markMiniTourSeen(tourId)
                    },
                    onSkip: {
                        tourState.markMiniTourSeen(tourId)
                    }
                )
            }
    }
}

extension View {
    func miniTour(
        _ tourId: TourState.MiniTourID,
        tourState: TourState,
        triggerOnAppear: Bool = true
    ) -> some View {
        modifier(MiniTourModifier(tourId: tourId, tourState: tourState, triggerOnAppear: triggerOnAppear))
    }
}
```

**Step 2: Commit**

```bash
git add CarrierWave/Views/Tour/MiniTourModifier.swift
git commit -m "feat(tour): add MiniTourModifier for easy integration"
```

---

## Task 6: Integrate TourState into App

**Files:**
- Modify: `CarrierWave/CarrierWaveApp.swift`
- Modify: `CarrierWave/ContentView.swift`

**Step 1: Add TourState to CarrierWaveApp and pass to ContentView**

In `CarrierWaveApp.swift`, add `@State private var tourState = TourState()` and pass it to ContentView:

```swift
// Add after sharedModelContainer declaration
@State private var tourState = TourState()

// In body, update ContentView call:
ContentView(tourState: tourState)
```

**Step 2: Update ContentView to accept and use TourState**

In `ContentView.swift`:

1. Add parameter: `let tourState: TourState`
2. Add state for intro tour: `@State private var showIntroTour = false`
3. Add `.onAppear` check for intro tour
4. Add `.fullScreenCover` for intro tour presentation

Key changes to ContentView:
```swift
// Add parameter
let tourState: TourState

// Add state
@State private var showIntroTour = false

// Add to existing .onAppear block:
if tourState.shouldShowIntroTour() {
    showIntroTour = true
}

// Add modifier after existing modifiers:
.fullScreenCover(isPresented: $showIntroTour) {
    IntroTourView(
        tourState: tourState,
        appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
        qrzClient: qrzClient
    )
}
```

**Step 3: Update ContentView Preview**

```swift
#Preview {
    ContentView(tourState: TourState())
        .modelContainer(
            for: [QSO.self, ServicePresence.self, UploadDestination.self, POTAUploadAttempt.self],
            inMemory: true
        )
}
```

**Step 4: Commit**

```bash
git add CarrierWave/CarrierWaveApp.swift CarrierWave/ContentView.swift
git commit -m "feat(tour): integrate TourState into app entry point"
```

---

## Task 7: Integrate Mini Tours into Feature Views

**Files:**
- Modify: `CarrierWave/Views/POTAActivations/POTAActivationsView.swift`
- Modify: `CarrierWave/Views/Challenges/ChallengesView.swift`
- Modify: `CarrierWave/Views/Dashboard/DashboardView.swift`
- Modify: `CarrierWave/Views/Settings/ServiceSettingsViews.swift`

**Step 1: Pass tourState through ContentView to child views**

Update view initializers and bindings to accept `tourState: TourState` parameter.

**Step 2: Add mini tour modifiers**

For each view, add the appropriate `.miniTour()` modifier:

POTAActivationsContentView:
```swift
.miniTour(.potaActivations, tourState: tourState)
```

ChallengesView:
```swift
.miniTour(.challenges, tourState: tourState)
```

DashboardView (for stats drilldown - trigger on navigation to StatDetailView):
```swift
// In the NavigationLink or sheet for StatDetailView
.miniTour(.statsDrilldown, tourState: tourState)
```

LoFiSettingsView:
```swift
.miniTour(.lofiSetup, tourState: tourState)
```

POTASettingsView:
```swift
.miniTour(.potaAccountSetup, tourState: tourState)
```

**Step 3: Commit**

```bash
git add CarrierWave/Views/POTAActivations/POTAActivationsView.swift \
    CarrierWave/Views/Challenges/ChallengesView.swift \
    CarrierWave/Views/Dashboard/DashboardView.swift \
    CarrierWave/Views/Settings/ServiceSettingsViews.swift
git commit -m "feat(tour): integrate mini tours into feature views"
```

---

## Task 8: Add "Show App Tour" to Settings

**Files:**
- Modify: `CarrierWave/Views/Settings/SettingsView.swift`

**Step 1: Add button to about section**

In SettingsMainView, add a "Show App Tour" button in the about section:

```swift
Button {
    tourState.resetForTesting()
    // Trigger navigation back and show intro tour
    // This requires passing a binding or using NotificationCenter
} label: {
    Label("Show App Tour", systemImage: "questionmark.circle")
}
```

**Step 2: Wire up the reset and presentation logic**

Add `@State private var showIntroTourFromSettings = false` and present via sheet or pass through to ContentView via binding.

**Step 3: Commit**

```bash
git add CarrierWave/Views/Settings/SettingsView.swift
git commit -m "feat(tour): add Show App Tour button to Settings"
```

---

## Task 9: Update CLAUDE.md File Index

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Add new Tour files to the File Index**

Add a new "Views - Tour" section:

```markdown
### Views - Tour (`CarrierWave/Views/Tour/`)
| File | Purpose |
|------|---------|
| `TourSheetView.swift` | Reusable bottom sheet component for tour screens |
| `IntroTourView.swift` | Intro tour flow with QRZ setup |
| `MiniTourContent.swift` | Content definitions for all mini-tours |
| `MiniTourModifier.swift` | View modifier for easy mini-tour integration |
```

Add TourState to Models section:
```markdown
| `TourState.swift` | UserDefaults-backed tour progress tracking |
```

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update file index with tour components"
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | TourState model | `Models/TourState.swift` |
| 2 | TourSheetView component | `Views/Tour/TourSheetView.swift` |
| 3 | IntroTourView | `Views/Tour/IntroTourView.swift` |
| 4 | MiniTourContent | `Views/Tour/MiniTourContent.swift` |
| 5 | MiniTourModifier | `Views/Tour/MiniTourModifier.swift` |
| 6 | App integration | `CarrierWaveApp.swift`, `ContentView.swift` |
| 7 | Feature view integration | Multiple views |
| 8 | Settings button | `SettingsView.swift` |
| 9 | Documentation | `CLAUDE.md` |

After completing all tasks, verify:
1. Fresh install shows intro tour
2. QRZ credentials save correctly from intro tour
3. Each mini-tour appears once on first visit to feature
4. "Show App Tour" in Settings resets and shows tour again
5. Skip buttons work and mark tours as seen
