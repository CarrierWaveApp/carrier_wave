# Onboarding Tour Design

## Overview

Carrier Wave's tour system consists of two components:

1. **Intro Tour** - A 5-screen setup funnel shown on first launch (and optionally after major updates)
2. **Contextual Mini-Tours** - Short explanations triggered when users first visit specific features

## Visual Pattern

- Bottom sheet presentation
- Intro tour: Blurred/dimmed background (no data to show yet)
- Contextual mini-tours: Real UI visible behind the sheet
- Consistent UI: Title, body text, optional icon, Next/Skip/Done buttons

## Intro Tour (First Launch)

### Screen 1: Welcome
- **Title**: "Welcome to Carrier Wave"
- **Body**: "Your amateur radio log aggregator. Download QSOs from logging apps and services, then upload them everywhere else - automatically. Carrier Wave doesn't create logs; it syncs them."

### Screen 2: How Sync Works
- **Title**: "One Log, Many Destinations"
- **Body**: "Import QSOs from any source. Carrier Wave deduplicates them (same callsign + band + mode within 5 minutes = one contact) and tracks what's been uploaded where."

### Screen 3: Connect QRZ (Primary CTA)
- **Title**: "Let's Connect Your First Service"
- **Body**: "QRZ.com is the most popular logbook. Enter your credentials to start syncing."
- Shows QRZ username/password fields inline
- Secondary link: "Connect a different service instead" → picker for POTA/LoFi/HAMRS/LoTW

### Screen 4: Service Overview
- **Title**: "More Services Available"
- **Body**: Brief list with one-line descriptions:
  - **POTA** - Upload activations to Parks on the Air
  - **Ham2K LoFi** - Import logs from PoLo app
  - **HAMRS** - Sync with HAMRS logbook
  - **LoTW** - Download QSL confirmations (upload requires TQSL)
- "Configure these anytime in Settings"

### Screen 5: Feedback & Done
- **Title**: "We'd Love Your Feedback"
- **Body**: "Found a bug or have a feature idea? Tap Settings → Report a Bug to send us details. Join our Discord to connect with other users."
- Done button completes the tour

## Contextual Mini-Tours

Each triggers once when the user first navigates to that feature.

### 1. POTA Activations Tab
**Trigger**: First tap on POTA Activations tab

**Screen A**: "Your POTA Activations"
- "QSOs with a park reference are grouped here by park and date. Each group is an activation you can upload to POTA."

**Screen B**: "Uploading to POTA"
- "Tap an activation to review its QSOs, then upload. You need 10+ QSOs for activation credit, but you can upload smaller logs to credit your hunters."

### 2. POTA Account Setup
**Trigger**: First tap on POTA in Settings (or when auth fails)

**Screen A**: "POTA Accounts Explained"
- "POTA has two account systems that can be confusing."

**Screen B**: "Service Login (AWS Cognito)"
- "If you registered years ago, you may have an AWS Cognito login. This is separate from your pota.app account."

**Screen C**: "Creating a pota.app Account"
- "Go to pota.app, create an account with email/password, then link your existing service login in your profile settings. Carrier Wave uses your pota.app credentials."

### 3. Challenges Tab
**Trigger**: First tap on Challenges tab

**Screen A**: "Challenges Coming Soon"
- "We're building something exciting here - track your progress toward awards, compete on leaderboards, and join community events. Stay tuned!"

### 4. Stats Drilldown
**Trigger**: First tap on any stat box on Dashboard

**Screen A**: "Explore Your Stats"
- "Tap any statistic to see the breakdown. Expand individual items to view the QSOs that count toward that total."

### 5. Ham2K LoFi Setup
**Trigger**: First tap on LoFi in Settings

**Screen A**: "Ham2K LoFi"
- "LoFi syncs your logs from the Ham2K Portable Logger (PoLo) app. It's download-only - Carrier Wave imports your PoLo operations."

**Screen B**: "Device Linking"
- "Enter the email address associated with your PoLo account. You'll receive a verification code to link this device."

## Update Prompts

### Triggering Logic
- Compare `lastTourVersion` against current app version
- Define a list of "major" versions that warrant a prompt (e.g., `["2.0", "2.5"]`)
- If current version is in that list and `lastTourVersion` is older, show prompt

### Update Prompt UI
- Alert or small modal: "What's New in Carrier Wave"
- Body: Brief summary of new features (1-3 bullet points)
- Buttons: "Take a Tour" / "Dismiss"

### Scope
- Only show screens relevant to new features
- Don't re-show the full intro tour

## Implementation

### New Files

| File | Purpose |
|------|---------|
| `CarrierWave/Models/TourState.swift` | UserDefaults-backed state tracking |
| `CarrierWave/Views/Tour/TourSheetView.swift` | Reusable bottom sheet component |
| `CarrierWave/Views/Tour/IntroTourView.swift` | Intro tour flow coordinator |
| `CarrierWave/Views/Tour/MiniTourContent.swift` | Content definitions for all mini-tours |

### TourState API

```swift
@Observable
class TourState {
    var hasCompletedIntroTour: Bool
    var lastTourVersion: String
    var seenMiniTours: Set<String>

    func shouldShowIntroTour() -> Bool
    func shouldShowUpdatePrompt(currentVersion: String) -> Bool
    func shouldShowMiniTour(_ id: String) -> Bool
    func markMiniTourSeen(_ id: String)
}
```

### Integration Points

| Location | Action |
|----------|--------|
| `CarrierWaveApp.swift` | Check `shouldShowIntroTour()` on launch |
| `ContentView.swift` | Check `shouldShowUpdatePrompt()` after intro logic |
| `POTAActivationsView.swift` | Show POTA activations mini-tour |
| `SettingsView.swift` (POTA row) | Show POTA account mini-tour |
| `ChallengesView.swift` | Show Challenges mini-tour |
| `DashboardView.swift` (stat tap) | Show stats drilldown mini-tour |
| `SettingsView.swift` (LoFi row) | Show LoFi mini-tour |

### Sheet Presentation Pattern

```swift
.sheet(isPresented: $showMiniTour) {
    TourSheetView(content: .potaActivations)
}
.onAppear {
    if tourState.shouldShowMiniTour("pota_activations") {
        showMiniTour = true
    }
}
```

## Settings & Accessibility

### Settings Integration
- **"Show App Tour"** button in Settings (Help/About section)
- Resets intro tour state and presents it again

### Accessibility
- All tour text readable by VoiceOver
- Bottom sheet traps focus while presented
- "Skip" option always available
- Respect reduced motion preference

### Content Updates
- Tour content hardcoded (not remote)
- Update by modifying source files and shipping app update
- Works offline

### Edge Cases

| Scenario | Behavior |
|----------|----------|
| User skips intro tour | Mark complete, don't nag |
| User dismisses mini-tour mid-flow | Mark as seen, don't re-show |
| App upgrade from pre-tour version | Show intro tour |
| No network during QRZ setup | Allow skip, configure later |
