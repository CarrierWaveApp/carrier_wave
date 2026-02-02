# Spot Improvements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Improve spot display with age coloring, self-spot badges, auto-attach comments to QSOs, and QRT spotting on session end.

**Architecture:** Four independent features that modify spot display (UnifiedSpot, POTASpot) and session management (LoggingSessionManager). Each feature can be implemented and tested independently.

**Tech Stack:** SwiftUI, SwiftData, async/await

---

## Task 1: Add Spot Age Color Helper

**Files:**
- Modify: `CarrierWave/Services/SpotsService.swift` (UnifiedSpot struct, around line 25)
- Modify: `CarrierWave/Services/POTAClient+Spots.swift` (POTASpot struct, around line 10)

**Step 1: Add ageColor to UnifiedSpot**

In `SpotsService.swift`, add this computed property to the `UnifiedSpot` struct after the `timeAgo` property (around line 55):

```swift
/// Color based on spot freshness
var ageColor: Color {
    let seconds = Date().timeIntervalSince(timestamp)
    switch seconds {
    case ..<120:
        return .green       // < 2 minutes: very fresh
    case ..<600:
        return .blue        // 2-10 minutes: recent
    case ..<1800:
        return .orange      // 10-30 minutes: getting stale
    default:
        return .secondary   // > 30 minutes: old
    }
}
```

Also add `import SwiftUI` at the top of the file if not present.

**Step 2: Add ageColor to POTASpot**

In `POTAClient+Spots.swift`, add this computed property to the `POTASpot` struct after the `timeAgo` property (around line 45):

```swift
/// Color based on spot freshness
nonisolated var ageColor: Color {
    guard let timestamp else {
        return .secondary
    }
    let seconds = Date().timeIntervalSince(timestamp)
    switch seconds {
    case ..<120:
        return .green       // < 2 minutes: very fresh
    case ..<600:
        return .blue        // 2-10 minutes: recent
    case ..<1800:
        return .orange      // 10-30 minutes: getting stale
    default:
        return .secondary   // > 30 minutes: old
    }
}
```

Also add `import SwiftUI` at the top of the file if not present.

**Step 3: Commit**

```bash
git add CarrierWave/Services/SpotsService.swift CarrierWave/Services/POTAClient+Spots.swift
git commit -m "feat(spots): add ageColor computed property for freshness indication"
```

---

## Task 2: Apply Age Color to Spot Views

**Files:**
- Modify: `CarrierWave/Views/Logger/RBNPanelView.swift` (spotRow function, around line 185)
- Modify: `CarrierWave/Views/Logger/POTASpotRow.swift` (time display, around line 35)

**Step 1: Update RBNPanelView time display**

In `RBNPanelView.swift`, find the `spotRow` function. Locate the line with `Text(spot.timeAgo)` (around line 200) and change:

```swift
Text(spot.timeAgo)
    .font(.caption2)
    .foregroundStyle(.tertiary)
```

To:

```swift
Text(spot.timeAgo)
    .font(.caption2)
    .foregroundStyle(spot.ageColor)
```

**Step 2: Update POTASpotRow time display**

In `POTASpotRow.swift`, find the time display (around line 35). Change:

```swift
Text(spot.timeAgo)
    .font(.caption)
    .foregroundStyle(.secondary)
```

To:

```swift
Text(spot.timeAgo)
    .font(.caption)
    .foregroundStyle(spot.ageColor)
```

**Step 3: Commit**

```bash
git add CarrierWave/Views/Logger/RBNPanelView.swift CarrierWave/Views/Logger/POTASpotRow.swift
git commit -m "feat(spots): apply age-based coloring to spot time display"
```

---

## Task 3: Add Self-Spot Detection Helper

**Files:**
- Modify: `CarrierWave/Services/SpotsService.swift` (UnifiedSpot struct)
- Modify: `CarrierWave/Services/POTAClient+Spots.swift` (POTASpot struct)

**Step 1: Add normalizeCallsign helper and isSelfSpot to UnifiedSpot**

In `SpotsService.swift`, add these after the `ageColor` property in `UnifiedSpot`:

```swift
/// Check if this spot is a self-spot for the given user callsign
func isSelfSpot(userCallsign: String) -> Bool {
    let normalizedUser = Self.normalizeCallsign(userCallsign)
    let normalizedSpot = Self.normalizeCallsign(callsign)
    return normalizedUser == normalizedSpot
}

/// Normalize callsign by removing portable suffixes and uppercasing
private static func normalizeCallsign(_ callsign: String) -> String {
    let upper = callsign.uppercased()
    // Remove common portable suffixes: /P, /M, /QRP, /0-9, etc.
    if let slashIndex = upper.firstIndex(of: "/") {
        return String(upper[..<slashIndex])
    }
    return upper
}
```

**Step 2: Add isSelfSpot to POTASpot**

In `POTAClient+Spots.swift`, add these after the `ageColor` property in `POTASpot`:

```swift
/// Check if this spot is a self-spot for the given user callsign
nonisolated func isSelfSpot(userCallsign: String) -> Bool {
    let normalizedUser = Self.normalizeCallsign(userCallsign)
    let normalizedSpot = Self.normalizeCallsign(activator)
    return normalizedUser == normalizedSpot
}

/// Normalize callsign by removing portable suffixes and uppercasing
private static func normalizeCallsign(_ callsign: String) -> String {
    let upper = callsign.uppercased()
    // Remove common portable suffixes: /P, /M, /QRP, /0-9, etc.
    if let slashIndex = upper.firstIndex(of: "/") {
        return String(upper[..<slashIndex])
    }
    return upper
}
```

**Step 3: Commit**

```bash
git add CarrierWave/Services/SpotsService.swift CarrierWave/Services/POTAClient+Spots.swift
git commit -m "feat(spots): add isSelfSpot detection with callsign normalization"
```

---

## Task 4: Add Self-Spot Badge to Views

**Files:**
- Modify: `CarrierWave/Views/Logger/RBNPanelView.swift`
- Modify: `CarrierWave/Views/Logger/POTASpotRow.swift`

**Step 1: Add userCallsign parameter to RBNPanelView**

In `RBNPanelView.swift`, the `callsign` property already exists and represents the user's callsign. We can use this directly.

In the `spotRow` function, add a self-spot badge after the source indicator. Find the `HStack` in `spotRow` and add the badge after `sourceIndicator(spot)`:

```swift
private func spotRow(_ spot: UnifiedSpot) -> some View {
    HStack(spacing: 12) {
        // Source indicator
        sourceIndicator(spot)

        // Self-spot badge
        if spot.isSelfSpot(userCallsign: callsign) {
            Text("SELF")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.indigo)
                .clipShape(Capsule())
        }

        VStack(alignment: .leading, spacing: 2) {
            // ... rest of existing code
```

**Step 2: Add userCallsign parameter to POTASpotRow**

In `POTASpotRow.swift`, add a new property and the badge. First, add the property after `onTap`:

```swift
let spot: POTASpot
let userCallsign: String?
let onTap: () -> Void
```

Then in the `body`, add the badge in the callsign row. Find `callsignRow` and modify:

```swift
private var callsignRow: some View {
    HStack(spacing: 4) {
        Text(spot.activator)
            .font(.subheadline.weight(.semibold).monospaced())
            .foregroundStyle(.primary)

        if let userCallsign, spot.isSelfSpot(userCallsign: userCallsign) {
            Text("SELF")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.indigo)
                .clipShape(Capsule())
        }
    }
}
```

**Step 3: Update POTASpotRow call sites**

Search for usages of `POTASpotRow` and add the `userCallsign` parameter. This will be in `POTASpotsView.swift`. The caller should pass the session's `myCallsign` or nil.

**Step 4: Commit**

```bash
git add CarrierWave/Views/Logger/RBNPanelView.swift CarrierWave/Views/Logger/POTASpotRow.swift
git commit -m "feat(spots): add SELF badge for self-spots"
```

---

## Task 5: Add Spot Comment Callback to SpotCommentsService

**Files:**
- Modify: `CarrierWave/Services/SpotCommentsService.swift`

**Step 1: Add callback property and tracking set**

In `SpotCommentsService.swift`, add these properties after the existing properties (around line 25):

```swift
/// Callback when new comments are received (comments that haven't been seen before)
var onNewComments: (([POTASpotComment]) -> Void)?

/// Track which comment IDs have been reported via callback
private var reportedSpotIds: Set<Int64> = []
```

**Step 2: Update fetchComments to call callback**

In the `fetchComments()` method, after calculating `newCommentCount`, add callback invocation. Find where `comments = sorted` is set and add:

```swift
comments = sorted
lastError = nil

// Report truly new comments via callback (ones we haven't reported before)
let unreportedComments = sorted.filter { !reportedSpotIds.contains($0.spotId) }
if !unreportedComments.isEmpty {
    reportedSpotIds.formUnion(unreportedComments.map(\.spotId))
    onNewComments?(unreportedComments)
}

if !newIds.isEmpty {
    SyncDebugLog.shared.info(
```

**Step 3: Reset reportedSpotIds in clear()**

In the `clear()` method, add:

```swift
func clear() {
    comments = []
    newCommentCount = 0
    seenSpotIds = []
    reportedSpotIds = []
    lastError = nil
}
```

**Step 4: Commit**

```bash
git add CarrierWave/Services/SpotCommentsService.swift
git commit -m "feat(spots): add onNewComments callback to SpotCommentsService"
```

---

## Task 6: Add Comment-to-QSO Attachment Logic

**Files:**
- Modify: `CarrierWave/Services/LoggingSessionManager.swift`

**Step 1: Add tracking set for processed comments**

In `LoggingSessionManager.swift`, add a new private property after the existing private properties (around line 490):

```swift
/// Track which spot comment IDs have been attached to QSOs
private var attachedSpotCommentIds: Set<Int64> = []
```

**Step 2: Add attachSpotComments method**

Add this method after `startSpotCommentsPolling()` (around line 475):

```swift
/// Attach spot comments to matching QSOs in the current session
/// Matches by callsign and ±5 minute time window
private func attachSpotComments(_ comments: [POTASpotComment]) {
    guard let session = activeSession else {
        return
    }

    let sessionQSOs = getSessionQSOs()
    guard !sessionQSOs.isEmpty else {
        return
    }

    for comment in comments {
        // Skip if already attached
        guard !attachedSpotCommentIds.contains(comment.spotId) else {
            continue
        }

        // Skip if no comment text
        guard let commentText = comment.comments, !commentText.isEmpty else {
            continue
        }

        guard let commentTimestamp = comment.timestamp else {
            continue
        }

        // Find matching QSO: same callsign, within ±5 minutes
        let spotter = comment.spotter.uppercased()
        let timeWindow: TimeInterval = 5 * 60 // 5 minutes

        for qso in sessionQSOs {
            let timeDiff = abs(qso.timestamp.timeIntervalSince(commentTimestamp))
            if qso.callsign.uppercased() == spotter, timeDiff <= timeWindow {
                // Attach comment to QSO
                let spotNote = "[Spot: \(comment.spotter)] \(commentText)"
                if let existingNotes = qso.notes, !existingNotes.isEmpty {
                    qso.notes = "\(existingNotes) | \(spotNote)"
                } else {
                    qso.notes = spotNote
                }

                attachedSpotCommentIds.insert(comment.spotId)
                try? modelContext.save()

                SyncDebugLog.shared.info(
                    "Attached spot comment from \(comment.spotter) to QSO with \(qso.callsign)",
                    service: .pota
                )
                break // Only attach to first matching QSO
            }
        }
    }
}
```

**Step 3: Wire up callback in startSpotCommentsPolling**

In `startSpotCommentsPolling()`, add the callback setup after `spotCommentsService.startPolling(...)`:

```swift
private func startSpotCommentsPolling() {
    guard let session = activeSession,
          session.activationType == .pota,
          let parkRef = session.parkReference
    else {
        return
    }

    let callsign = session.myCallsign
    guard !callsign.isEmpty else {
        return
    }

    spotCommentsService.onNewComments = { [weak self] comments in
        self?.attachSpotComments(comments)
    }

    spotCommentsService.startPolling(activator: callsign, parkRef: parkRef)
}
```

**Step 4: Clear attachedSpotCommentIds when session ends**

In `endSession()`, add after `spotCommentsService.clear()`:

```swift
spotCommentsService.clear()
attachedSpotCommentIds = []
```

Also in `deleteCurrentSession()`, add after `spotCommentsService.clear()`:

```swift
spotCommentsService.clear()
attachedSpotCommentIds = []
```

**Step 5: Commit**

```bash
git add CarrierWave/Services/LoggingSessionManager.swift
git commit -m "feat(spots): auto-attach spot comments to matching QSOs"
```

---

## Task 7: Add QRT Spot Setting

**Files:**
- Modify: `CarrierWave/Views/Settings/SettingsView.swift`

**Step 1: Add AppStorage for QRT setting**

In `SettingsView.swift`, find the `@AppStorage("potaAutoSpotEnabled")` line (around line 63) and add below it:

```swift
@AppStorage("potaAutoSpotEnabled") private var potaAutoSpotEnabled = false
@AppStorage("potaQRTSpotEnabled") private var potaQRTSpotEnabled = true
```

**Step 2: Add toggle to potaSection**

Find the `potaSection` computed property (around line 295) and add the QRT toggle:

```swift
private var potaSection: some View {
    Section {
        Toggle("Auto-spot every 10 minutes", isOn: $potaAutoSpotEnabled)
        Toggle("Post QRT when ending session", isOn: $potaQRTSpotEnabled)
    } header: {
        Text("POTA Activations")
    } footer: {
        Text(
            "Auto-spot posts your frequency to POTA every 10 minutes. "
                + "QRT spot notifies hunters when you end your activation."
        )
    }
}
```

**Step 3: Commit**

```bash
git add CarrierWave/Views/Settings/SettingsView.swift
git commit -m "feat(settings): add QRT spot toggle for POTA activations"
```

---

## Task 8: Implement QRT Spot on Session End

**Files:**
- Modify: `CarrierWave/Services/LoggingSessionManager.swift`

**Step 1: Add potaQRTSpotEnabled property**

After `potaAutoSpotEnabled` (around line 518), add:

```swift
/// Whether QRT spotting is enabled (from settings)
private var potaQRTSpotEnabled: Bool {
    UserDefaults.standard.bool(forKey: "potaQRTSpotEnabled")
}
```

Note: The default is handled by the `@AppStorage` in SettingsView which defaults to `true`.

**Step 2: Add postQRTSpotIfNeeded method**

Add this method after `postSpot()` (around line 555):

```swift
/// Post a QRT spot if enabled and the session had spots
private func postQRTSpotIfNeeded() async {
    guard potaQRTSpotEnabled,
          let session = activeSession,
          session.activationType == .pota,
          let parkRef = session.parkReference,
          let freq = session.frequency,
          !session.myCallsign.isEmpty
    else {
        return
    }

    // Check if this activation has any spots on POTA
    do {
        let potaClient = POTAClient(authService: POTAAuthService())
        let comments = try await potaClient.fetchSpotComments(
            activator: session.myCallsign,
            parkRef: parkRef
        )

        // If there are any spots/comments, the activation was spotted
        guard !comments.isEmpty else {
            SyncDebugLog.shared.info(
                "No spots found for \(parkRef), skipping QRT spot",
                service: .pota
            )
            return
        }

        // Post QRT spot
        _ = try await potaClient.postSpot(
            callsign: session.myCallsign,
            reference: parkRef,
            frequency: freq * 1_000,
            mode: session.mode,
            comments: "QRT"
        )

        SyncDebugLog.shared.info("QRT spot posted for \(parkRef)", service: .pota)
    } catch {
        SyncDebugLog.shared.warning(
            "Failed to post QRT spot: \(error.localizedDescription)",
            service: .pota
        )
    }
}
```

**Step 3: Call postQRTSpotIfNeeded from endSession**

Modify `endSession()` to call the QRT spot method before cleanup. The method needs to become async-aware. Find `endSession()` (around line 100) and add the QRT call at the beginning:

```swift
/// End the current session
func endSession() {
    guard let session = activeSession else {
        return
    }

    // Post QRT spot before cleanup (fire and forget)
    Task {
        await postQRTSpotIfNeeded()
    }

    session.end()
    activeSession = nil
    // ... rest of existing cleanup
```

**Step 4: Commit**

```bash
git add CarrierWave/Services/LoggingSessionManager.swift
git commit -m "feat(spots): post QRT spot when ending POTA session"
```

---

## Task 9: Update POTASpotsView to Pass User Callsign

**Files:**
- Modify: `CarrierWave/Views/Logger/POTASpotsView.swift`
- Modify: `CarrierWave/Views/Logger/LoggerView.swift`

**Step 1: Add userCallsign parameter to POTASpotsView init**

In `POTASpotsView.swift`, update the init (around line 12):

```swift
init(
    userCallsign: String? = nil,
    initialBand: String? = nil,
    initialMode: String? = nil,
    onDismiss: @escaping () -> Void,
    onSelectSpot: ((POTASpot) -> Void)? = nil
) {
    self.userCallsign = userCallsign
    self.onDismiss = onDismiss
    self.onSelectSpot = onSelectSpot
    _bandFilter = State(initialValue: BandFilter.from(bandName: initialBand))
    _modeFilter = State(initialValue: ModeFilter.from(modeName: initialMode))
}
```

Add the property after the `let onSelectSpot` line:

```swift
let onDismiss: () -> Void
let onSelectSpot: ((POTASpot) -> Void)?
let userCallsign: String?
```

**Step 2: Pass userCallsign to POTASpotRow**

Find the `spotsList` computed property where `POTASpotRow` is used (around line 247) and update:

```swift
POTASpotRow(spot: spot, userCallsign: userCallsign) {
    onSelectSpot?(spot)
}
```

**Step 3: Update LoggerView call site**

In `LoggerView.swift` (around line 567), update the POTASpotsView call:

```swift
POTASpotsView(
    userCallsign: sessionManager?.activeSession?.myCallsign,
    initialBand: sessionManager?.activeSession?.band,
    initialMode: sessionManager?.activeSession?.mode,
    onDismiss: { showPOTAPanel = false },
    onSelectSpot: { spot in
```

**Step 4: Update Preview**

In `POTASpotsView.swift`, update the preview (around line 311):

```swift
#Preview {
    POTASpotsView(
        userCallsign: "W1AW",
        initialBand: "20m",
        initialMode: "CW",
        onDismiss: {}
    )
    .frame(height: 500)
    .padding()
}
```

**Step 5: Commit**

```bash
git add CarrierWave/Views/Logger/POTASpotsView.swift CarrierWave/Views/Logger/LoggerView.swift
git commit -m "feat(spots): pass user callsign through to POTASpotRow for self-spot detection"
```

---

## Task 10: Update FILE_INDEX.md and CHANGELOG.md

**Files:**
- Modify: `docs/FILE_INDEX.md` (no changes needed - no new files)
- Modify: `CHANGELOG.md`

**Step 1: Update CHANGELOG.md**

Add to the `[Unreleased]` section:

```markdown
### Added
- Spot age color coding: green (<2m), blue (2-10m), orange (10-30m), gray (>30m)
- "SELF" badge on spots where the activator matches your callsign
- Auto-attach POTA spot comments to matching QSOs as notes
- QRT spot posted automatically when ending POTA session (if session was spotted)
- Setting to enable/disable QRT spotting (Settings → POTA Activations)
```

**Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: add spot improvements to changelog"
```

---

## Final Verification

After all tasks are complete:

1. **Ask user to build**: Request user run `make build` to verify compilation
2. **Manual testing**: Ask user to test each feature:
   - Start a POTA session, check spot age colors update
   - Self-spot and verify "SELF" badge appears
   - Log a QSO, have that callsign's spot comment appear, verify note attachment
   - End session and verify QRT spot is posted (check POTA website)
3. **Settings**: Verify QRT toggle appears in Settings → POTA Activations
