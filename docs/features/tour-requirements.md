# Tour Requirements

All major and minor features in Carrier Wave must include user-facing tours to help users discover and learn the feature on first use.

## Rule

**Every major or minor feature must have either:**
1. An **intro tour step** (added to `IntroTourView` for features shown during onboarding), OR
2. A **mini tour** (a per-page tour shown on first visit to the feature's view)

Bug fixes, refactors, and internal-only changes do not require tours.

## What Counts as a Major/Minor Feature

- **Major feature:** New tab, new top-level view, new workflow (e.g., Activity Log, CW Transcription, Challenges)
- **Minor feature:** New section within an existing view, new settings page, new capability added to an existing workflow (e.g., quick entry parsing, spot comments, share cards)

## Implementation

### Mini Tours (Most Common)

Mini tours are the standard approach for feature-specific onboarding. They show a multi-page sheet on first visit.

**Steps to add a mini tour:**

1. **Add a case to `TourState.MiniTourID`** in `CarrierWave/Models/TourState.swift`:
   ```swift
   enum MiniTourID: String, CaseIterable {
       // ...existing cases...
       case myNewFeature = "my_new_feature"
   }
   ```

2. **Add tour content** in `CarrierWave/Views/Tour/MiniTourContent.swift`:
   ```swift
   static let myNewFeature: [TourPage] = [
       TourPage(
           icon: "star",
           title: "Welcome to My Feature",
           body: "Description of what this feature does."
       ),
       // 2-5 pages total, each covering one concept
   ]
   ```

3. **Register the content** in `MiniTourContent.pages(for:)`:
   ```swift
   case .myNewFeature: myNewFeature
   ```

4. **Apply the modifier** to the feature's main view:
   ```swift
   MyFeatureView()
       .miniTour(.myNewFeature, tourState: tourState)
   ```

### Intro Tour Steps

For features that are fundamental to the app experience and should be shown during initial onboarding, add steps to `IntroTourView` and `IntroTourStepViews.swift`.

## Guidelines

- **Keep it short:** 2-5 pages per mini tour. Users should be able to complete it in under 30 seconds.
- **One concept per page:** Each `TourPage` should explain one thing.
- **Use SF Symbols:** The `icon` field takes an SF Symbol name. Match the feature's primary icon.
- **Action-oriented language:** "Tap X to do Y" rather than "X is a feature that..."
- **Skip button always available:** Tours use `TourSheetView` which provides Skip and Next buttons. Never use `.interactiveDismissDisabled()` on tours.
- **Show once:** `TourState` tracks seen tours via UserDefaults. Tours only appear on the first visit.
- **Test the flow:** After adding a tour, reset tour state (Settings > Debug > Reset Tours) and verify it appears correctly.

## Existing Tours

| MiniTourID | Feature | Location |
|------------|---------|----------|
| `logger` | QSO Logger | LoggerView |
| `logs` | QSO Logs | LogsContainerView |
| `potaActivations` | POTA Activations | POTAActivationsView |
| `potaAccountSetup` | POTA Account | POTA settings |
| `challenges` | Challenges | ChallengesView |
| `statsDrilldown` | Statistics Detail | StatDetailView |
| `lofiSetup` | LoFi Setup | LoFi settings |
| `activityLog` | Activity Log | ActivityLogView |

## Checklist

When implementing a new feature, verify:
- [ ] Mini tour ID added to `TourState.MiniTourID`
- [ ] Tour content added to `MiniTourContent.swift` (2-5 pages)
- [ ] Content registered in `MiniTourContent.pages(for:)`
- [ ] `.miniTour()` modifier applied to the feature's main view
- [ ] Tour tested by resetting tour state and visiting the feature
