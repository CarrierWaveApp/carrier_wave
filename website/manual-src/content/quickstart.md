---
title: "Quick Start"
description: "Get logging in 5 minutes"
weight: 1
---

You've used loggers before. Here's how to get on the air with Carrier Wave.

## Download & First Launch

[Download Carrier Wave from the App Store](https://apps.apple.com/app/carrier-wave). The onboarding tour walks you through:

1. Enter your callsign — Carrier Wave pulls your profile from HamDB
2. Connect your services (details below)
3. Optionally enable community features (friends, challenges, activity feed)

The app asks for location permission to auto-determine your {{< term "Grid Square" >}}.

## Connect Your Services

Open **Settings** (gear icon) and scroll to **Services**. Connect at least one:

| Service | What it does |
|---------|--------------|
| **QRZ.com** | Callsign lookups, bidirectional logbook sync |
| **POTA** | Park activation uploads, job tracking |
| **Ham2K LoFi** | Cross-device sync |
| **LoTW** | Confirmation downloads (upload via TQSL) |
| **Club Log** | Bidirectional ADIF sync |
| **HAMRS** | Bidirectional HAMRS cloud sync |
| **eQSL** | Bidirectional eQSL sync |

Start with QRZ — enter your username and password. Credentials are stored in iOS Keychain.

## Log Your First QSO

1. Tap the **Logger** tab
2. Tap **Start Session** — the wizard prompts for mode, frequency, and activation type (Casual, {{< term "POTA" >}}, {{< term "SOTA" >}})
3. Select your **equipment** — radio, antenna, key, mic, power. These propagate to every {{< term "QSO" >}} in the session and export as `MY_RIG` in ADIF
4. Enter the callsign — QRZ lookup fires automatically
5. Enter RST sent/received (defaults pre-filled: 59 for phone, 599 for CW/digital)
6. Tap **LOG**

Your {{< term "QSO" >}} is logged locally and queued for sync. The callsign field auto-refocuses for the next contact.

{{< callout "tip" "Quick Entry Mode" >}}
Type a complete contact in one line:
`K6TEST 599 CA` or `AJ7CM 579 WA US-0189` — color-coded token badges preview how each component will be parsed before you log.
{{< /callout >}}

{{< callout "tip" "Session Photos" >}}
Attach photos to individual QSOs or to the session itself. Great for documenting field setups and activations.
{{< /callout >}}

## Set Up Your Radio

Carrier Wave supports BLE radio control for Icom, Kenwood, Elecraft, and Yaesu rigs. Once paired, the app reads frequency and mode directly from your radio — no manual entry needed.

1. Go to **Settings → Radio Control**
2. Tap **Scan** to discover nearby BLE-enabled radios
3. Select your rig and pair

When connected, frequency and mode changes on the radio are reflected in the logger automatically, and the `RIG` command lets you switch equipment mid-session.

## Try FT8

Carrier Wave includes a full FT8 operating suite:

- **Live waterfall** display with auto-decoding
- **Conversation tracking** — follow QSOs in progress
- **TX control** with auto-sequencing for hands-off operation
- **PSK Reporter** integration — see "Who Heard Me?" after your session

Start an FT8 session from the Logger tab, select FT8 mode, and the waterfall appears automatically. See [FT8 Reference](/reference/ft8/) for the full guide.

{{< callout "tip" "CW Operators" >}}
The **CW Transcription** tab provides real-time Morse decoding using a Goertzel filter with WPM detection and auto-fill. See [CW Transcription](/reference/cw-transcription/).
{{< /callout >}}

## Verify Sync

Check the **Dashboard** tab. Service status indicators show:

- **Green** — synced and current
- **Yellow** — sync in progress
- **Red** — sync error (tap for details)

If you see issues, check [Troubleshooting](/reference/troubleshooting/).

## What's Next

Carrier Wave goes deep. Here's what else is available:

**Activations & Programs:**
- [POTA Activations](/reference/pota/) — Park uploads, rove mode, rove stop batch grid editing, P2P hunting
- [SOTA/WWFF Support](/reference/activations/) — Summit and flora/fauna reference tracking
- [Agents on Air](/reference/activations/) — AoA activity program with code exchange tracking
- [Contests](/reference/contests/) — WA7BNM contest calendar with templates, Cabrillo export

**Maps & Spots:**
- [Azimuthal Map](/reference/map/) — Canvas-rendered projection with antenna pattern overlays and spots heatmap
- [Smart Spot Needs](/reference/spots/) — Background engine matching spots to your DXCC/WAS/POTA needs, with HamAlert export
- [Band Openings](/reference/dashboard/) — Per-band propagation conditions on your dashboard
- [DXpedition Calendar](/reference/dashboard/) — Active DXpeditions from Ham365

**Receivers & Digital:**
- [WebSDR Integration](/reference/websdr/) — KiwiSDR receivers with recording, QSY detection, clip export
- [FT8 Suite](/reference/ft8/) — Waterfall, decoding, auto-sequencing, PSK Reporter
- [CW Transcription](/reference/cw-transcription/) — Real-time decoding with Goertzel filter

**Sessions & Sharing:**
- [Session Timeline & Replay](/reference/logger/) — Map-based chronological QSO replay with slider
- [Video Export](/reference/video-export/) — Generate highlight videos with map animation
- [Brag Sheets](/reference/brag-sheets/) — Weekly/monthly/all-time shareable stat cards
- [Share Cards](/reference/brag-sheets/) — Branded activation cards, daily activity cards, recording clips
- [Band Plan Chart](/reference/settings/) — ARRL-style band allocation display

**Social & Community:**
- [Clubs & Friends](/reference/community/) — Leaderboards, activity feeds, friends on air dashboard
- [Challenges](/reference/community/#challenges) — Browse, join, and track challenge progress
- [Events](/reference/events/) — Discover and submit ham radio events on a map

**Platform Features:**
- [Live Activity / Dynamic Island](/reference/widgets/) — Active session on your lock screen
- [watchOS Companion](/reference/widgets/) — Solar, spots, stats, quick session start from your wrist
- [Widgets](/reference/widgets/) — Solar conditions, spots, and stats on your home screen

**Data & Backup:**
- [Backup & Restore](/reference/icloud/) — Manual backups with iCloud Drive mirroring
- [Search & Filters](/reference/logs-search/) — Query your log history with a powerful query language
- [Professional Statistician Mode](/reference/dashboard/) — Advanced box plots and distribution analysis

For deeper understanding of logging concepts, see the [Beginner's Guide](/guide/).

For complete documentation of every feature, see the [Reference Manual](/reference/).
