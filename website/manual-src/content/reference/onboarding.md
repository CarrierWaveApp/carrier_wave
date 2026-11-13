---
title: "Tours & Onboarding"
description: "Intro tour, mini-tours, logger guide, and first-run onboarding flow"
weight: 1
showToc: true
---

Carrier Wave includes guided tours and an onboarding flow to help new users get started quickly and discover features they might otherwise miss.

## Onboarding Flow

### First Launch

Onboarding walks you through a short setup before opening the app.

**Step 1 — Your callsign:**
- **Enter your callsign** — Primary operating callsign
- **Auto-lookup** — Carrier Wave queries QRZ to verify and fetch your name, QTH, and grid square, displayed inline
- **IARU region** — Detected automatically from your callsign and persisted silently (changeable later in Settings)

**Step 2 — How do you operate? (optional):**
Four role cards let you describe your typical operating style:
- **Activator** — You mainly operate from parks, summits, or other references
- **Hunter** — You mainly chase activators
- **A Bit of Everything** — A mix of activating and hunting
- **New to Ham Radio** — You're just getting started

This step is optional and can be skipped. Your choice biases defaults — for example, hunters see Hunt Spots first on the home hero card and land on the Hunter Log — but it never hides features. You can change your selection anytime in **Settings → My Profile → Operating Style** or **Settings → Logger → Operating Style**.

Tap **Get Started** to open the app.

### Getting Started Card

After onboarding, a persistent **Getting Started** card appears on Home. This replaces the old multi-step onboarding flow — optional service connections are now framed by the value they unlock rather than presented as required steps.

Each row explains what the service provides:

- **"Auto-upload confirmations to ARRL"** — Connect LoTW
- **"See DXCC progress and callsign lookups"** — Connect QRZ
- **"Upload logs to Parks on the Air"** — Connect POTA
- **"Join the community"** — Enable community features

The card shows a progress bar. Tap any row to deep-link to the relevant Settings page or the Friends tab. Items tick off automatically as you connect services. The card also links to **Explore Features** — a curated gallery of marquee features and enable toggles for experiments. The card can be dismissed manually or self-hides once all items are complete.

### Returning Users

If you reinstall Carrier Wave or set it up on a new device:

- iCloud sync restores your settings and QSO database
- Service credentials need to be re-entered (stored in device Keychain)
- The onboarding flow detects existing data and skips the callsign step

## Intro Tour

The intro tour provides a guided walkthrough of Carrier Wave's main features. It's offered after onboarding and accessible anytime from **Settings -> Help -> Take the Tour**.

### Tour Stops

The intro tour visits each major area of the app:

1. **Home** - Activity grid, statistics, streaks, service status
2. **Logger** - Starting a session, callsign entry, commands
3. **Logbook** - Searching contacts, session browsing
4. **Spots** - POTA spots, RBN, P2P opportunities
5. **Map** - QSO visualization, park boundaries
6. **Friends** - Friends, challenges, achievements
7. **Settings** - Key configuration options

Each stop highlights the most important features with:

- **Spotlight overlay** pointing to the relevant UI element
- **Brief explanation** (1-2 sentences)
- **Next/Skip/Done** navigation

### Tour Duration

The full intro tour takes approximately 2-3 minutes. You can skip at any point and resume later.

## Logger Tour with KI5GTR Guide

The Logger tour provides an in-depth walkthrough of the logging interface, guided by KI5GTR (the Carrier Wave developer's callsign):

### Tour Content

KI5GTR walks you through a simulated QSO:

1. **Starting a session** - Session wizard, mode/frequency selection
2. **Callsign entry** - Type a callsign, see the QRZ lookup populate
3. **Quick Entry** - Demonstrate the single-line entry format
4. **RST and fields** - How signal reports and optional fields work
5. **Logging the QSO** - Tap the log button, see the toast confirmation
6. **Commands** - Type `SPOT`, `BAND`, `MAP` to see command system
7. **Session management** - End session, view in Logbook tab

### Interactive Elements

The Logger tour uses interactive overlays:

- **Simulated data** populates fields as the tour progresses
- **Animated arrows** point to buttons and fields
- **"Try it yourself"** prompts let you practice each step
- **KI5GTR dialog bubbles** provide context and tips

### Accessing the Logger Tour

- Offered automatically after the first session start wizard
- Available from **Settings -> Help -> Logger Tour**
- Triggered if you tap the **?** icon in the Logger header

## Mini-Tours

Mini-tours are brief, contextual walkthroughs that appear when you first encounter a feature:

### When Mini-Tours Appear

Mini-tours trigger on first use of specific features:

| Feature | Mini-Tour Content |
|---------|------------------|
| **POTA session** | Park entry, spotting, rove mode basics |
| **Activity Log** | Station profiles, quick entry, spot list |
| **CW Transcription** | Audio setup, frequency tracking, auto-fill |
| **FT8 Suite** | Waterfall, decode list, TX control |
| **WebSDR** | Receiver selection, recording, playback |
| **Smart Needs** | Need categories, configuration, alerts |
| **Community** | Friends, challenges, privacy |
| **BLE Radio** | Scanning, pairing, sync behavior |

### Mini-Tour Format

Each mini-tour consists of 3-5 spotlight steps:

1. **Welcome** - Brief description of the feature
2. **Key controls** - Spotlights on the most important UI elements
3. **Quick tip** - One actionable tip for getting the most from the feature
4. **Done** - Dismisses the tour

### Dismissing and Revisiting

- **Dismiss** a mini-tour at any step by tapping "Skip"
- Dismissed tours don't reappear automatically
- **Revisit** any mini-tour from **Settings -> Help -> Feature Tours**
- **Reset all tours** clears the "seen" state for all mini-tours

## Tour Settings

### Settings -> Help

- **Take the Tour** - Start the full intro tour
- **Logger Tour** - Start the Logger-specific tour
- **Feature Tours** - List of all mini-tours with "seen" status
- **Reset All Tours** - Mark all tours as unseen (they'll reappear on next feature use)

### Tour Preferences

- **Show mini-tours** toggle - Disable if you prefer to discover features on your own
- **Tour animation speed** - Normal or Fast for experienced users

## See Also

- [Logger](/reference/logger/) - Full Logger reference
- [Settings & Services](/reference/settings/) - Configuration options
- [Home](/reference/dashboard/) - Home card and statistics
- [Explore Features](/reference/explore/) - Feature gallery and experiment toggles
