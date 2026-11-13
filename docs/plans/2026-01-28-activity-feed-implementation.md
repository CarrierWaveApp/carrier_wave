# Social Activity Feed Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform the Challenges tab into a social Activity tab with friends, clubs, and an activity feed.

**Architecture:** The Activity tab replaces Challenges, containing a "Your Challenges" section (existing functionality) and a "Recent Activity" feed. Social graph (friends/clubs) is managed server-side via the existing challenges API. Activity detection happens client-side during QSO sync, then reported to server.

**Tech Stack:** SwiftUI, SwiftData, existing ChallengesClient extended for social endpoints.

**Note:** Per project rules, do not run builds or tests yourself. Each "Run tests" step means ask the user to run the command and report results.

---

## Phase 1: Activity Tab Shell

Transform the Challenges tab to Activity, preserving existing functionality while adding structure for the feed.

---

### Task 1.1: Rename AppTab.challenges to AppTab.activity

**Files:**
- Modify: `CarrierWave/ContentView.swift:6-12`

**Step 1: Update the AppTab enum**

Change `.challenges` to `.activity`:

```swift
enum AppTab: Hashable {
    case dashboard
    case logs
    case map
    case activity  // was: challenges
    case settings
}
```

**Step 2: Update all references in ContentView**

Find and replace `.challenges` with `.activity` in:
- Line ~77-81: The ChallengesView tabItem
- Line ~135: The notification handler that navigates to challenges tab

**Step 3: Update the tab label**

Change the tabItem label from "Challenges" to "Activity":

```swift
.tabItem {
    Label("Activity", systemImage: "person.2")  // was: "Challenges", "flag.2.crossed"
}
.tag(AppTab.activity)
```

**Step 4: Commit**

```bash
git add CarrierWave/ContentView.swift
git commit -m "refactor: rename challenges tab to activity"
```

---

### Task 1.2: Create ActivityView shell

**Files:**
- Create: `CarrierWave/Views/Activity/ActivityView.swift`

**Step 1: Create the Activity directory**

```bash
mkdir -p CarrierWave/Views/Activity
```

**Step 2: Create ActivityView.swift**

```swift
import SwiftData
import SwiftUI

// MARK: - ActivityView

struct ActivityView: View {
    // MARK: Internal

    let tourState: TourState

    @Environment(\.modelContext) var modelContext

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    challengesSection
                    activityFeedSection
                }
                .padding()
            }
            .navigationTitle("Activity")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(isRefreshing)
                    .accessibilityLabel("Refresh")
                }
            }
        }
    }

    // MARK: Private

    @State private var isRefreshing = false

    // MARK: - Challenges Section

    private var challengesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Challenges")
                    .font(.headline)
                Spacer()
                NavigationLink {
                    BrowseChallengesView()
                } label: {
                    Text("Browse")
                        .font(.subheadline)
                }
            }

            // Placeholder - will embed challenge content
            Text("Challenge cards will appear here")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Activity Feed Section

    private var activityFeedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline)

            // Placeholder for feed
            ContentUnavailableView(
                "No Activity Yet",
                systemImage: "person.2",
                description: Text("Activity from friends and clubs will appear here.")
            )
        }
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        // TODO: Refresh challenges and activity feed
        try? await Task.sleep(nanoseconds: 500_000_000)
    }
}

#Preview {
    ActivityView(tourState: TourState())
        .modelContainer(
            for: [
                ChallengeSource.self,
                ChallengeDefinition.self,
                ChallengeParticipation.self,
            ], inMemory: true
        )
}
```

**Step 3: Ask user to verify it compiles**

Ask: "Please run `make build` and let me know if there are any errors."

**Step 4: Commit**

```bash
git add CarrierWave/Views/Activity/ActivityView.swift
git commit -m "feat(activity): add ActivityView shell"
```

---

### Task 1.3: Wire ActivityView into ContentView

**Files:**
- Modify: `CarrierWave/ContentView.swift`

**Step 1: Replace ChallengesView with ActivityView**

Change:
```swift
ChallengesView(tourState: tourState)
    .tabItem {
        Label("Activity", systemImage: "person.2")
    }
    .tag(AppTab.activity)
```

To:
```swift
ActivityView(tourState: tourState)
    .tabItem {
        Label("Activity", systemImage: "person.2")
    }
    .tag(AppTab.activity)
```

**Step 2: Ask user to verify**

Ask: "Please run `make build` and confirm the app compiles."

**Step 3: Commit**

```bash
git add CarrierWave/ContentView.swift
git commit -m "feat(activity): wire ActivityView into main tab bar"
```

---

### Task 1.4: Embed existing challenge content into ActivityView

**Files:**
- Modify: `CarrierWave/Views/Activity/ActivityView.swift`

**Step 1: Add challenge queries and state**

Add to the private properties section:

```swift
@Query(sort: \ChallengeParticipation.joinedAt, order: .reverse)
private var allParticipations: [ChallengeParticipation]

@State private var syncService: ChallengesSyncService?
@State private var errorMessage: String?
@State private var showingError = false

private var activeParticipations: [ChallengeParticipation] {
    allParticipations.filter { $0.status == .active }
}

private var completedParticipations: [ChallengeParticipation] {
    allParticipations.filter { $0.status == .completed }
}
```

**Step 2: Update challengesSection**

Replace the placeholder challengesSection with:

```swift
private var challengesSection: some View {
    VStack(alignment: .leading, spacing: 12) {
        HStack {
            Text("Your Challenges")
                .font(.headline)
            Spacer()
            NavigationLink {
                BrowseChallengesView()
            } label: {
                Text("Browse")
                    .font(.subheadline)
            }
        }

        if activeParticipations.isEmpty, completedParticipations.isEmpty {
            challengesEmptyState
        } else {
            if !activeParticipations.isEmpty {
                ForEach(activeParticipations) { participation in
                    NavigationLink {
                        ChallengeDetailView(participation: participation)
                    } label: {
                        ChallengeProgressCard(participation: participation)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !completedParticipations.isEmpty {
                DisclosureGroup("Completed (\(completedParticipations.count))") {
                    ForEach(completedParticipations) { participation in
                        NavigationLink {
                            ChallengeDetailView(participation: participation)
                        } label: {
                            CompletedChallengeCard(participation: participation)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .foregroundStyle(.primary)
            }
        }
    }
}

private var challengesEmptyState: some View {
    VStack(spacing: 8) {
        Text("No active challenges")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        NavigationLink {
            BrowseChallengesView()
        } label: {
            Text("Browse Challenges")
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
}
```

**Step 3: Add onAppear and alert handling**

Add to the body, after the toolbar modifier:

```swift
.onAppear {
    if syncService == nil {
        syncService = ChallengesSyncService(modelContext: modelContext)
    }
}
.alert("Error", isPresented: $showingError) {
    Button("OK") { showingError = false }
} message: {
    Text(errorMessage ?? "An unknown error occurred")
}
```

**Step 4: Update refresh function**

```swift
private func refresh() async {
    guard let syncService else { return }

    isRefreshing = true
    defer { isRefreshing = false }

    do {
        try await syncService.refreshChallenges(forceUpdate: true)
        for participation in activeParticipations {
            syncService.progressEngine.reevaluateAllQSOs(for: participation)
        }
        try modelContext.save()
    } catch {
        errorMessage = error.localizedDescription
        showingError = true
    }
}
```

**Step 5: Ask user to verify**

Ask: "Please run `make build` and confirm everything compiles."

**Step 6: Commit**

```bash
git add CarrierWave/Views/Activity/ActivityView.swift
git commit -m "feat(activity): embed challenge content into ActivityView"
```

---

### Task 1.5: Handle challenge invite notifications in ActivityView

**Files:**
- Modify: `CarrierWave/Views/Activity/ActivityView.swift`

**Step 1: Add invite state properties**

Add to private properties:

```swift
@State private var pendingInvite: PendingChallengeInvite?
@State private var showingInviteSheet = false
@State private var isJoiningFromInvite = false
```

**Step 2: Add notification handlers and sheet**

Add after the `.alert` modifier:

```swift
.sheet(isPresented: $showingInviteSheet) {
    if let invite = pendingInvite {
        InviteJoinSheet(
            invite: invite,
            syncService: syncService,
            isJoining: $isJoiningFromInvite,
            onComplete: { success in
                showingInviteSheet = false
                pendingInvite = nil
                if !success {
                    errorMessage = "Failed to join challenge"
                    showingError = true
                }
            }
        )
    }
}
.onReceive(
    NotificationCenter.default.publisher(for: .didReceiveChallengeInvite)
) { notification in
    handleInviteNotification(notification)
}
.onReceive(
    NotificationCenter.default.publisher(for: .didSyncQSOs)
) { _ in
    Task { await evaluateNewQSOs() }
}
.miniTour(.challenges, tourState: tourState)
```

**Step 3: Add helper functions**

Add these private functions:

```swift
private func handleInviteNotification(_ notification: Notification) {
    guard let userInfo = notification.userInfo,
          let source = userInfo["source"] as? String,
          let challengeId = userInfo["challengeId"] as? UUID
    else {
        return
    }

    let token = userInfo["token"] as? String

    pendingInvite = PendingChallengeInvite(
        sourceURL: source,
        challengeId: challengeId,
        token: token
    )
    showingInviteSheet = true
}

private func evaluateNewQSOs() async {
    guard let syncService else { return }

    let descriptor = FetchDescriptor<QSO>(
        sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
    )

    do {
        let recentQSOs = try modelContext.fetch(descriptor)
        for qso in recentQSOs.prefix(100) {
            syncService.progressEngine.evaluateQSO(qso, notificationsEnabled: false)
        }
        try modelContext.save()
    } catch {
        // Silently fail - background operation
    }
}
```

**Step 4: Ask user to verify**

Ask: "Please run `make build` and confirm everything compiles."

**Step 5: Commit**

```bash
git add CarrierWave/Views/Activity/ActivityView.swift
git commit -m "feat(activity): add challenge invite and QSO notification handling"
```

---

### Task 1.6: Update CLAUDE.md file index

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Add Activity views to file index**

Add a new section under "Views - Challenges" or update it:

```markdown
### Views - Activity (`CarrierWave/Views/Activity/`)
| File | Purpose |
|------|---------|
| `ActivityView.swift` | Main activity tab with challenges section and activity feed |
```

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add Activity views to file index"
```

---

## Phase 1 Complete

At this point:
- The Challenges tab is renamed to Activity
- ActivityView contains the existing challenge functionality
- The activity feed section shows a placeholder
- All existing challenge features (browse, join, progress, invites) still work

---

## Phase 2: Data Models for Social Features

Create the SwiftData models for friends, clubs, and activity items.

---

### Task 2.1: Create ActivityType enum

**Files:**
- Create: `CarrierWave/Models/ActivityType.swift`

**Step 1: Create the file**

```swift
import Foundation

// MARK: - ActivityType

enum ActivityType: String, Codable, CaseIterable {
    case challengeTierUnlock
    case challengeCompletion
    case newDXCCEntity
    case newBand
    case newMode
    case dxContact
    case potaActivation
    case sotaActivation
    case dailyStreak
    case potaDailyStreak
    case personalBest

    // MARK: Internal

    var icon: String {
        switch self {
        case .challengeTierUnlock: "trophy.fill"
        case .challengeCompletion: "flag.checkered"
        case .newDXCCEntity: "globe"
        case .newBand: "antenna.radiowaves.left.and.right"
        case .newMode: "waveform"
        case .dxContact: "location.circle"
        case .potaActivation: "leaf.fill"
        case .sotaActivation: "mountain.2.fill"
        case .dailyStreak: "flame.fill"
        case .potaDailyStreak: "flame.fill"
        case .personalBest: "chart.line.uptrend.xyaxis"
        }
    }

    var displayName: String {
        switch self {
        case .challengeTierUnlock: "Tier Unlocked"
        case .challengeCompletion: "Challenge Complete"
        case .newDXCCEntity: "New DXCC Entity"
        case .newBand: "New Band"
        case .newMode: "New Mode"
        case .dxContact: "DX Contact"
        case .potaActivation: "POTA Activation"
        case .sotaActivation: "SOTA Activation"
        case .dailyStreak: "Daily Streak"
        case .potaDailyStreak: "POTA Streak"
        case .personalBest: "Personal Best"
        }
    }
}
```

**Step 2: Ask user to verify**

Ask: "Please run `make build` to verify the new file compiles."

**Step 3: Commit**

```bash
git add CarrierWave/Models/ActivityType.swift
git commit -m "feat(models): add ActivityType enum"
```

---

### Task 2.2: Create FriendshipStatus enum and Friendship model

**Files:**
- Create: `CarrierWave/Models/Friendship.swift`

**Step 1: Create the file**

```swift
import Foundation
import SwiftData

// MARK: - FriendshipStatus

enum FriendshipStatus: String, Codable {
    case pending
    case accepted
    case declined
}

// MARK: - Friendship

@Model
final class Friendship {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        friendCallsign: String,
        friendUserId: String,
        status: FriendshipStatus = .pending,
        requestedAt: Date = Date(),
        acceptedAt: Date? = nil,
        isOutgoing: Bool
    ) {
        self.id = id
        self.friendCallsign = friendCallsign
        self.friendUserId = friendUserId
        self.statusRawValue = status.rawValue
        self.requestedAt = requestedAt
        self.acceptedAt = acceptedAt
        self.isOutgoing = isOutgoing
    }

    // MARK: Internal

    var id = UUID()
    var friendCallsign = ""
    var friendUserId = ""
    var statusRawValue = FriendshipStatus.pending.rawValue
    var requestedAt = Date()
    var acceptedAt: Date?
    var isOutgoing = true

    var status: FriendshipStatus {
        get { FriendshipStatus(rawValue: statusRawValue) ?? .pending }
        set { statusRawValue = newValue.rawValue }
    }

    var isAccepted: Bool {
        status == .accepted
    }

    var isPending: Bool {
        status == .pending
    }
}
```

**Step 2: Ask user to verify**

Ask: "Please run `make build` to verify the model compiles."

**Step 3: Commit**

```bash
git add CarrierWave/Models/Friendship.swift
git commit -m "feat(models): add Friendship model"
```

---

### Task 2.3: Create Club model

**Files:**
- Create: `CarrierWave/Models/Club.swift`

**Step 1: Create the file**

```swift
import Foundation
import SwiftData

// MARK: - Club

@Model
final class Club {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        name: String,
        poloNotesListURL: String,
        descriptionText: String? = nil,
        memberCallsignsData: Data = Data(),
        lastSyncedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.poloNotesListURL = poloNotesListURL
        self.descriptionText = descriptionText
        self.memberCallsignsData = memberCallsignsData
        self.lastSyncedAt = lastSyncedAt
    }

    // MARK: Internal

    var id = UUID()
    var name = ""
    var poloNotesListURL = ""
    var descriptionText: String?
    var memberCallsignsData = Data()
    var lastSyncedAt = Date()

    var memberCallsigns: [String] {
        get {
            (try? JSONDecoder().decode([String].self, from: memberCallsignsData)) ?? []
        }
        set {
            memberCallsignsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    func isMember(callsign: String) -> Bool {
        memberCallsigns.contains { $0.uppercased() == callsign.uppercased() }
    }

    var memberCount: Int {
        memberCallsigns.count
    }
}
```

**Step 2: Ask user to verify**

Ask: "Please run `make build` to verify the model compiles."

**Step 3: Commit**

```bash
git add CarrierWave/Models/Club.swift
git commit -m "feat(models): add Club model"
```

---

### Task 2.4: Create ActivityItem model

**Files:**
- Create: `CarrierWave/Models/ActivityItem.swift`

**Step 1: Create the file**

```swift
import Foundation
import SwiftData

// MARK: - ActivityItem

@Model
final class ActivityItem {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        callsign: String,
        activityType: ActivityType,
        timestamp: Date = Date(),
        detailsData: Data = Data(),
        isOwn: Bool = false,
        challengeId: UUID? = nil
    ) {
        self.id = id
        self.callsign = callsign
        self.activityTypeRawValue = activityType.rawValue
        self.timestamp = timestamp
        self.detailsData = detailsData
        self.isOwn = isOwn
        self.challengeId = challengeId
    }

    // MARK: Internal

    var id = UUID()
    var callsign = ""
    var activityTypeRawValue = ActivityType.dxContact.rawValue
    var timestamp = Date()
    var detailsData = Data()
    var isOwn = false
    var challengeId: UUID?

    var activityType: ActivityType {
        get { ActivityType(rawValue: activityTypeRawValue) ?? .dxContact }
        set { activityTypeRawValue = newValue.rawValue }
    }

    var details: ActivityDetails? {
        get {
            try? JSONDecoder().decode(ActivityDetails.self, from: detailsData)
        }
        set {
            detailsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }
}

// MARK: - ActivityDetails

struct ActivityDetails: Codable {
    // Generic fields that apply to multiple activity types
    var entityName: String?      // DXCC entity name
    var entityCode: String?      // DXCC entity code
    var band: String?
    var mode: String?
    var distanceKm: Double?
    var workedCallsign: String?  // The station worked for DX contacts
    var parkReference: String?   // POTA/SOTA reference
    var parkName: String?
    var qsoCount: Int?           // For activations
    var streakDays: Int?         // For streak activities
    var challengeName: String?   // For challenge activities
    var tierName: String?        // For tier unlock
    var recordType: String?      // For personal bests (e.g., "distance", "qsos_in_day")
    var recordValue: String?     // The record value as display string
}
```

**Step 2: Ask user to verify**

Ask: "Please run `make build` to verify the model compiles."

**Step 3: Commit**

```bash
git add CarrierWave/Models/ActivityItem.swift
git commit -m "feat(models): add ActivityItem model"
```

---

### Task 2.5: Register new models with SwiftData container

**Files:**
- Modify: `CarrierWave/CarrierWaveApp.swift`

**Step 1: Find the modelContainer configuration**

Look for where the ModelContainer is configured with the schema.

**Step 2: Add the new models**

Add `Friendship.self`, `Club.self`, and `ActivityItem.self` to the schema array.

**Step 3: Ask user to verify**

Ask: "Please run `make build` to verify the app still compiles with the new models."

**Step 4: Commit**

```bash
git add CarrierWave/CarrierWaveApp.swift
git commit -m "feat(models): register social models with SwiftData container"
```

---

### Task 2.6: Update CLAUDE.md with new model files

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Add to Models section**

```markdown
| `ActivityType.swift` | Activity type enum with icons and display names |
| `Friendship.swift` | Friend connection model with status tracking |
| `Club.swift` | Club model with Polo notes list membership |
| `ActivityItem.swift` | Activity feed item model |
```

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add social model files to index"
```

---

## Phase 2 Complete

At this point:
- All data models for the social features exist
- Models are registered with SwiftData
- Ready to build UI components and API client extensions

---

## Remaining Phases (Summary)

### Phase 3: Activity Feed UI
- Create ActivityItemRow view
- Create FilterBar component
- Wire feed display into ActivityView
- Add pull-to-refresh

### Phase 4: Friends System
- Extend ChallengesClient with friend endpoints
- Create FriendRequestsView
- Create FriendProfileView
- Add friend search UI
- Handle invite links

### Phase 5: Clubs System
- Extend ChallengesClient with club endpoints
- Create ClubDetailView
- Integrate club filters into feed

### Phase 6: Activity Detection
- Create ActivityDetector service
- Hook into QSO sync flow
- Detect notable events (new DXCC, streaks, etc.)
- Report to server

### Phase 7: Sharing
- Create ShareCardView templates
- Implement image rendering
- Create SummaryCardSheet
- Integrate iOS share sheet

---

## Testing Notes

Per project rules, the implementer should ask the user to run:
- `make build` after each code change to verify compilation
- `make test` if adding unit tests

Do not attempt to run these commands directly.
