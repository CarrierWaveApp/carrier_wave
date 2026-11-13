# Carrier Wave Manual Design

## Overview

A Hugo-based documentation site for Carrier Wave, an iOS app for amateur radio QSO logging. Three documents serve different audiences from the same content base.

## Personas

### Riley the Ragchewer (Quick Start)
- Has used N3FJP, Logger32, or HAMRS before
- Knows ADIF, understands RST reports
- Wants to get logging fast
- Question: "How do I log a QSO? How do I sync to QRZ?"

### Pat the New Tech (Beginner's Guide)
- Just passed Technician exam
- Heard "you should keep a log" but doesn't know why
- Confused by acronyms (QSO, RST, DXCC, POTA)
- Question: "What is a logbook? Why do I need one?"

### Alex the Activator (Reference Manual)
- Runs POTA activations, maybe contests
- Wants to understand every feature and edge case
- Will actually read query language syntax
- Question: "What's the exact behavior when I have duplicate QSOs?"

## Site Structure

### URL Structure
```
/                       → Landing page with audience selector
/quickstart/            → Quick Start Guide (Riley)
/guide/                 → Beginner's Guide (Pat)
/reference/             → Reference Manual (Alex)
/reference/logger/
/reference/dashboard/
/reference/logs-search/
... (all 14 sections)
/glossary/              → Shared glossary, linked from all three
```

### Landing Page
Three cards with persona-appropriate copy:
- "I've used loggers before" → `/quickstart/`
- "I'm new to logging" → `/guide/`
- "Show me everything" → `/reference/`

### Navigation
- Top bar: Logo + "Quick Start | Guide | Reference | Glossary"
- Left sidebar: Section-specific TOC (collapses on mobile)
- Right sidebar: On-page headings (reference manual only)
- Footer: Link to changelog, app store, support

## Document Specifications

### Quick Start Guide (~800 words, single page)

**Tone:** Terse, assumes ham radio knowledge, no acronym definitions.

1. **Download & First Launch** (~100 words)
   - App Store link, initial permissions

2. **Connect Your Services** (~200 words)
   - Settings → Services walkthrough
   - QRZ, POTA, LoFi, LoTW, HAMRS overview
   - "Set up at least QRZ to get started"

3. **Log Your First QSO** (~200 words)
   - Logger tab, session settings
   - Callsign, RST, optional fields
   - Save - done
   - Quick Entry mode mention

4. **Verify Sync** (~150 words)
   - Dashboard service status indicators
   - What colored dots mean
   - Link to Troubleshooting

5. **Next Steps** (~150 words)
   - Links to POTA workflow, query syntax, CW transcription
   - Links to other guides

### Beginner's Guide (~2500 words, 6 pages)

**Tone:** Warm, encouraging, explains jargon inline.

1. **What is a Logbook?** (~300 words)
   - Radio diary concept
   - Paper vs digital vs cloud-synced
   - Historical context

2. **The Anatomy of a Contact** (~400 words)
   - Callsigns, time (UTC), frequency, band, mode
   - RST system explained
   - Screenshot: Logger screen with callouts

3. **Why Log to the Cloud?** (~400 words)
   - Contact confirmation concept
   - Awards and achievements
   - Backup and access
   - Services overview: QRZ, LoTW, POTA, LoFi

4. **Setting Up Carrier Wave** (~500 words)
   - Profile setup
   - Connecting services
   - Sync direction table
   - Screenshot: Settings screen

5. **Logging Your First Contact** (~500 words)
   - Step-by-step with screenshots
   - Field explanations
   - Save and sync

6. **Understanding Your Dashboard** (~400 words)
   - Stats interpretation
   - Service status indicators
   - First stats celebration

### Reference Manual (~8000-10000 words, 14 sections)

**Tone:** Precise, comprehensive, technical where needed.

| # | Section | Key Content |
|---|---------|-------------|
| 1 | Logger | QSO entry fields, session settings, quick entry syntax, duplicate detection, band plan validation, callsign lookup |
| 2 | Dashboard & Statistics | Stat categories, drill-down behavior, streak logic, background computation |
| 3 | Logs & Search | Query language syntax, field names, operators, date formats, wildcards, examples |
| 4 | POTA Activations | Park grouping, upload workflow, activation metadata, park search, nearby discovery |
| 5 | Settings & Services | Each service auth flow, sync directions, credential storage |
| 6 | Service Sync Flow | Timing diagram, batch behavior, conflict resolution, retry logic, per-service quirks |
| 7 | iCloud Sync | What syncs, device handoff, conflict troubleshooting |
| 8 | Spot Monitoring | RBN spots, POTA spots, P2P, solar/weather, refresh intervals, filtering |
| 9 | Challenges | Joining, progress tracking, leaderboard, participation rules |
| 10 | Activity Feed | Achievement detection logic, sharing, filtering |
| 11 | CW Transcription | Audio setup, frequency tracking, WPM detection, transcript view, auto-fill |
| 12 | Troubleshooting | Sync logs location, diagnostic info, bug reports, common issues |
| 13 | Glossary | Alphabetical, ~50-75 terms, cross-linked |
| 14 | What's New | Version history highlights, link to full changelog |

**Each section includes:**
- Feature overview (what and why)
- Screenshots with annotations
- Step-by-step procedures where applicable
- Edge cases and known limitations
- Related sections (cross-links)

## Visual Design

### Color Palette

Derived from app icon (purple/magenta gradient with waveform).

| Role | Light Mode | Dark Mode |
|------|------------|-----------|
| Primary | `#9B4DCA` | `#B06DD4` |
| Accent | `#C94BC4` | `#D76BD2` |
| Background | `#FFFFFF` | `#1A1A1E` |
| Surface | `#F5F5F7` | `#2C2C30` |
| Text | `#1D1D1F` | `#F5F5F7` |
| Text Secondary | `#6E6E73` | `#A1A1A6` |

### Typography
- Headings: SF Pro Display (system-ui fallback)
- Body: SF Pro Text
- Code/technical: SF Mono

### Components
- Gradient header bar (purple → magenta)
- Screenshots: rounded corners (12px), subtle border for light backgrounds
- Callout boxes (tips, warnings, notes) - color-coded
- Code blocks with syntax highlighting
- Tables with alternating row colors

### Theme Toggle
- Persistent switch in header
- Respects system preference on first visit
- Light + dark mode support

## Screenshot Strategy

### Capture Setup
- Device: iPhone 15 Pro (Simulator)
- Mode: Dark mode only
- Scale: @2x for Retina
- Tool: `xcrun simctl io booted screenshot`

### Sample Data
Seed Simulator with:
- ~50-75 QSOs across 30 days
- Multiple bands (20m, 40m, 15m, 2m)
- Multiple modes (SSB, CW, FT8, FM)
- 5-10 POTA activations
- US and DX contacts mix
- Duplicate scenarios
- Callsigns: W1AW, K6TEST, VE3XYZ, JA1ABC, etc.

### Screenshot List (~25-30 captures)

| Screen | Used In |
|--------|---------|
| Logger (empty session) | Quick Start, Reference |
| Logger (mid-QSO entry) | Beginner's Guide, Reference |
| Logger (quick entry mode) | Reference |
| Dashboard (populated) | All three |
| Dashboard drill-down | Reference |
| Logs list | Beginner's Guide, Reference |
| Search with query | Reference |
| POTA activations list | Reference |
| Park search | Reference |
| Settings main | Beginner's Guide, Reference |
| Service auth (QRZ) | Quick Start, Reference |
| Sync status indicators | Quick Start, Reference |
| Spot monitoring panel | Reference |
| CW transcription active | Reference |
| Troubleshooting/sync logs | Reference |

### Post-processing
- Numbered callouts for annotations
- Subtle white border for light mode display
- Tools: Figma or ImageMagick

## PDF Generation

### Approach
Print stylesheet (`@media print`) in Hugo - users do browser Print → Save as PDF.

### Print-specific Adjustments
- Hide navigation
- Adjust margins
- Page breaks before major sections
- Table of contents with page numbers
- Links show URL in parentheses
- Code blocks don't break across pages
- Footer: "Carrier Wave Manual • carrierwave.app"
- Dark screenshots get subtle white border for print contrast

## Project Structure

```
/carrier_wave_manual
├── config.toml
├── content/
│   ├── _index.md              (landing page)
│   ├── quickstart.md          (single page)
│   ├── guide/
│   │   ├── _index.md
│   │   ├── what-is-logbook.md
│   │   ├── anatomy-of-contact.md
│   │   ├── why-cloud.md
│   │   ├── setup.md
│   │   ├── first-contact.md
│   │   └── dashboard.md
│   └── reference/
│       ├── _index.md
│       ├── logger.md
│       ├── dashboard.md
│       ├── logs-search.md
│       ├── pota.md
│       ├── settings.md
│       ├── sync-flow.md
│       ├── icloud.md
│       ├── spots.md
│       ├── challenges.md
│       ├── activity.md
│       ├── cw-transcription.md
│       └── troubleshooting.md
├── content/glossary.md
├── static/
│   ├── images/
│   │   └── screenshots/
│   └── icon.png
├── layouts/
│   ├── _default/
│   ├── partials/
│   └── shortcodes/
│       └── term.html          (glossary tooltip)
├── assets/
│   └── css/
│       ├── carrier-wave.css
│       └── print.css
└── data/
    └── glossary.yaml          (shared glossary source)
```

### Glossary Implementation
- Single YAML file as data source
- Rendered as standalone page at `/glossary/`
- Shortcode `{{</* term "QSO" */>}}` auto-links and shows tooltip on hover
