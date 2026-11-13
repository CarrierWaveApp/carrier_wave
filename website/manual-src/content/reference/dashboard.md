---
title: "Home"
description: "Home hero card, activity grid, statistics, streaks, conditions, and service status"
weight: 2
showToc: true
---

Home provides a comprehensive overview of your logging activity, streaks, propagation conditions, and service status.

## Home Hero Card

A full-width card is pinned to the top of Home and cannot be hidden.

**When a session is open (active or paused):** The card shows a single prominent **Resume** row with the session title so you can jump back in with one tap.

**When idle:** The card shows two tiles — **Start Session** and **Hunt Spots**. Hunters see Hunt Spots first. Tapping Hunt Spots uses the same flow as the Hunter Log widget, including first-time setup.

## Activity Grid

A GitHub-style activity visualization appears below the hero card on Home, showing 26-52 weeks of history depending on screen width (full year on iPad or landscape orientation).

Each cell represents one day:

- **Green** - Day with {{< term "activation" >}} contacts
- **Blue** - Day with {{< term "Activity Log" >}} entries
- **Diagonal split** - Day with both activations and activity log entries
- **Gray** - No activity

Tap any cell to open the **Day Summary** — a full screen for that UTC day with:

- A hero row showing the date plus QSO, session, and DXCC / states / bands / modes counts
- Band and mode pills with per-band / per-mode counts
- A swipeable **Insights** carousel (map + US states mosaic) covering every QSO on the day, not just hunter contacts
- A band timeline showing when contacts happened across the day
- A **Sessions** section listing every {{< term "Activation" >}} or other session that overlapped the day. Sessions that straddle UTC midnight are sliced on both days with a `continued` / `continues` chip. Each card drills into the full session detail view.
- A virtual card for Hunter Log entries and another for any orphan ("loose") QSOs

Long-press a cell instead of tapping to get the old popover (date + activation/hunter counts) without leaving the dashboard.

## Configurable Metrics Card

Choose 1-2 key metrics to display on your dashboard card. Configure the displayed metrics in Settings -> Dashboard Metrics.

### Streak Metrics

- **On-Air** - Consecutive days with any {{< term "QSO" >}}
- **Activation** - Consecutive days with {{< term "POTA" >}} activations
- **Hunter** - Consecutive days worked {{< term "POTA" >}} activators
- **CW** - Consecutive days using CW mode
- **Phone** - Consecutive days using phone modes ({{< term "SSB" >}}, {{< term "FM" >}}, {{< term "AM" >}})
- **Digital** - Consecutive days using digital modes

### Count Metrics

- QSOs per week/month/year
- Activations per week/month/year
- Hunts per week/month/year
- New {{< term "DXCC" >}} entities this period

## Statistics Grid

The main statistics display shows your {{< term "QSO" >}} counts across multiple dimensions:

### By Band

Total contacts per amateur band:

- **HF bands:** 160m, 80m, 60m, 40m, 30m, 20m, 17m, 15m, 12m, 10m
- **VHF/UHF:** 6m, 2m, 1.25m, 70cm, 33cm, 23cm

### By Mode

Contacts grouped by operating mode:

- Voice: {{< term "SSB" >}}, {{< term "CW" >}}, {{< term "FM" >}}, {{< term "AM" >}}
- Digital: {{< term "FT8" >}}, {{< term "FT4" >}}, {{< term "RTTY" >}}, {{< term "PSK31" >}}, and more

### By Country/DXCC

Unique {{< term "DXCC" >}} entities worked. The count represents distinct entities, not total {{< term "QSO" >}}s.

### Additional Statistics

- **Grid Squares** - Unique {{< term "Maidenhead grid" >}} squares worked
- **States** - US states and Canadian provinces
- **Parks Activated** - {{< term "POTA" >}} parks with valid activations
- **Parks Worked** - {{< term "POTA" >}} parks contacted as hunter
- **QRZ QSL Confirmed** - Confirmations received via {{< term "QRZ.com" >}}
- **LoTW Confirmed** - Confirmations via {{< term "LoTW" >}}

## Drill-Down Views

Tap any statistic to see the underlying contacts:

- Tap a band count to see all {{< term "QSO" >}}s on that band
- Tap a mode count to filter by that mode
- Tap a country to see contacts with that {{< term "DXCC" >}} entity
- Tap any aggregated count to view matching records

Within drill-down views:

- Sort by date, callsign, frequency, or other fields
- Apply additional filters
- Expand individual rows to show full {{< term "QSO" >}} details

## Streaks

The Dashboard displays your current streak and all-time best for comparison.

### Streak Types

- **On-Air** - Any {{< term "QSO" >}} logged
- **Activation** - {{< term "POTA" >}} activations
- **Hunter** - Worked {{< term "POTA" >}} activators
- **CW** - Contacts using CW mode
- **Phone** - Contacts using voice modes
- **Digital** - Contacts using digital modes

All streaks use UTC day boundaries. Missing a day resets the counter to zero.

### Streak Detail View

Tap a streak to view:

- Mode and band breakdowns
- Historical date ranges for the streak
- All-time best streak comparison

## Equipment Usage Card

The Equipment Usage card displays statistics about your gear:

- **Most-used radio** and total QSOs with each rig
- **Antenna breakdown** showing contacts per antenna
- **Key/mic usage** for CW and voice modes

Tap the card to drill down into equipment-specific QSO lists. This helps you track which gear gets the most use and correlate equipment with operating performance.

## Friends on Air

The Friends on Air card surfaces real-time spot data for your accepted friends:

- **Active friends** currently spotted on POTA or RBN
- **Frequency, mode, and park reference** for each friend
- **Tap to tune** - opens the Logger pre-filled with the friend's frequency

This card only appears when you have friends configured and at least one is currently active.

### Friend Activity Feed

Below the Friends on Air card, a compact activity feed shows recent notable achievements from your friends (new DXCC, activations completed, streak milestones). Tap any entry to view the friend's profile.

## Getting Started Card

After first-launch onboarding, a **Getting Started** card appears on Home to guide you through connecting optional services and discovering features. The card includes a link to **Explore Features** — a curated gallery of marquee features with navigation hints and enable toggles for hidden experiments. See [Tours & Onboarding — Getting Started Card](/reference/onboarding/#getting-started-card) for details.

## Show More Cards Footer

A dashed-outline row at the bottom of the visible cards opens the customize sheet and lists the categories of cards you have hidden (for example, "stats, social, tools"). This gives you a clear signal that more cards are available without having to discover the toolbar slider. The footer disappears once every available card is visible.

## Callsign Lookup Card

The Callsign Lookup card (in the Tools section) combines callsign profile lookup and RBN spot monitoring in a single card:

- **Search field** — Enter any callsign to look up
- **"Check my callsign" shortcut** — One-tap lookup of your own callsign using your configured operating call
- **Profile card** — Name, emoji flag, grid, QTH, last-contact enrichment from QRZ/HamDB
- **RBN spots** — Inline spot list and mini-map showing where your signal (or the looked-up station) is being received

A single **Clear** button resets both the profile and spots. Hide or show this card from **Dashboard > Customize**.

## Smart Spot Needs Dashboard

The Needs dashboard card shows a summary of currently active spots that match your configured need categories:

- **Count of matching spots** across all need categories
- **Top needs** showing the most relevant spots (new DXCC, WAS, POTA parks)
- **Tap to expand** into the full [Smart Spot Needs](/reference/smart-needs/) view

Configure need categories in Settings -> Smart Needs or see the dedicated [Smart Spot Needs](/reference/smart-needs/) page.

## POTA Awards Progress

Track your progress toward POTA awards directly from Home:

- **Activator awards** (Bronze: 10 parks, Silver: 50, Gold: 100, Platinum: 250, Sapphire: 500)
- **Hunter awards** based on unique parks worked
- **Progress bar** showing how close you are to the next tier

Tap the card to view a detailed breakdown of parks activated and hunted.

## Band Openings Card

The Band Openings card provides a quick assessment of current HF propagation:

- **Band-by-region grid** showing which bands are open to which geographic areas
- **Color-coded cells** (green = open, yellow = marginal, gray = closed)
- **Data sourced** from RBN spot density and PSK Reporter coverage

Tap the card to view the full conditions history timeline.

## Active DXpeditions Card

Shows currently active DXpeditions with:

- **Entity and callsign** of the DXpedition
- **Bands and modes** they're reported on
- **"Needed" badge** if the entity matches your DXCC needs

Data is sourced from DX cluster feeds. Tap a DXpedition to view frequencies and spot history.

## On Air Card

The On Air card provides a unified view of current operating conditions:

- **Solar conditions** (K-index, SFI, A-index sparklines)
- **Band conditions summary** (Good/Fair/Poor per band)
- **Weather** at your QTH
- **Active spots count** and friend activity indicator

**Spot rows on the card:** For non-hunters, the inline POTA, SOTA, and Friends-on-air rows collapse to a single count summary line (for example, "2 friends on air · 5 POTA · 3 SOTA"). The full rows with callsign badges and tap-to-spot actions are one tap away on the On Air sheet — tap anywhere on the card to open it. Hunters keep the **Open Hunter Log** link on the card itself.

This card consolidates multiple data sources into a single glanceable view.

## Professional Statistician Mode

When enabled in Settings -> POTA -> Professional Statistician Mode, Home gains additional statistical depth:

- **Distribution charts** for QSO timing, distance, and signal reports
- **Box plots** for RST and distance metrics
- **Cumulative distribution functions** (CDF) for key operating metrics
- **Statistical summary tables** with median, mean, standard deviation, and percentiles

This mode is designed for operators who want rigorous quantitative analysis of their operating patterns.

## Conditions Card

A compact conditions card shows recent propagation and environmental data:

- **Sparkline** - Visual trend of recent solar and weather metrics
- **Latest values** - Current K-index, {{< term "SFI" >}}, A-index
- **Link to history** - Tap to view full conditions timeline

### Conditions History View

The full conditions view displays:

- **Timeline chart** - Hourly solar conditions over time
- **By-location chart** - Conditions logged at different operating locations

Hourly solar conditions are polled in the background when enabled in Settings.

## Activity Log Card

The Activity Log card displays:

- **Setup prompt** - Appears if {{< term "Activity Log" >}} not yet configured
- **Today's stats** - {{< term "QSO" >}} count and other metrics when active

Tap the card to open today's {{< term "Activity Log" >}} detail view.

## Service Status

All configured services appear in a compact vertical list:

| Status | Meaning |
|--------|---------|
| **Green** | Synced - all {{< term "QSO" >}}s uploaded |
| **Yellow** | Syncing - upload or download in progress |
| **Red** | Error - last sync failed |
| **Gray** | Not configured or disabled |

Pending upload counts display next to each service.

### Service Detail Sheet

Tap any service to open its detail sheet showing:

- Full statistics (total {{< term "QSO" >}}s, pending uploads)
- Manual sync trigger
- Force Re-download button
- {{< term "Sync report" >}} with reconciliation details
- Error details (if applicable)

Supported services: {{< term "QRZ.com" >}}, {{< term "POTA" >}}, {{< term "LoFi" >}}, {{< term "LoTW" >}}, {{< term "HAMRS" >}}, {{< term "Club Log" >}}, eQSL

## Sync Reports

Per-service sync reports visualize the sync process as a funnel:

1. **Fetched** - Records downloaded from service
2. **Validated** - Records passing validation
3. **Changes Applied** - New or updated records imported
4. **Uploaded** - Local records sent to service

Each phase displays:

- Status badges (success, warning, error)
- Record counts
- Reconciliation details

Sync reports persist across app launches.

## Background Computation

Statistics are computed on a background thread to keep the app responsive:

1. Cached statistics display immediately on opening Home
2. A background task recomputes current totals
3. Display updates when computation completes

For large logs (thousands of {{< term "QSO" >}}s), a progress bar appears during recomputation.

## Pull to Refresh

Pull down on Home to trigger:

- Statistics recomputation
- Sync check for all services

## iPad Layout

On iPad or in landscape orientation:

- **Statistics grid** - All six primary stats display in a single row
- **Activity grid** - Shows up to 52 weeks (full year)

## See Also

- [Explore Features](/reference/explore/) - Curated gallery of marquee features
- [Logs & Search](/reference/logs-search/) - Query your contacts directly
- [Service Sync Flow](/reference/sync-flow/) - Understand sync timing and behavior
- [Settings & Services](/reference/settings/) - Configure service connections
- [Activity Log](/reference/activity-log/) - Daily QSO tracking for hunters
- [Smart Spot Needs](/reference/smart-needs/) - Configure need-based spot matching
- [Brag Sheets & Share Cards](/reference/brag-sheets/) - Share your statistics
