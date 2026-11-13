---
title: "Video Export"
description: "Animated session replay videos with map, toasts, and audio"
weight: 14.5
showToc: true
---

Video Export generates animated videos of your logging sessions, showing QSOs plotted on a map over time with toast-style notifications for each contact.

## Overview

Video export creates a shareable video that replays your session chronologically:

- **Map animation** showing QSO arcs appearing as contacts were made
- **Toast notifications** for each QSO with callsign, RST, and park reference
- **Timeline progress** bar showing position within the session
- **Statistics overlay** with running QSO count and rate

## Rendering Modes

### Real-Time Mode

Plays back the session at actual speed (1 second of video = 1 second of real time):

- **Best for:** Short sessions (under 30 minutes)
- **Duration:** Matches your actual session length
- **Gaps compressed** - Periods of inactivity (>2 minutes) are compressed to 2-second transitions
- **Band changes** shown as smooth frequency transitions

### Highlight Mode

Condenses the session into a fixed-duration video:

- **Best for:** Long sessions or activations spanning hours
- **Duration:** 30-60 seconds (configurable)
- **QSO pacing** - Each QSO gets equal screen time
- **Key moments** - Band changes, milestones (10th QSO, P2P), and equipment changes are highlighted
- **Statistics card** at the end summarizing the session

## Map Animation

### QSO Arcs

As each QSO appears in the timeline:

1. An arc draws from your station to the contacted station's location
2. A marker appears at the contact's location
3. The arc fades to a lower opacity after a few seconds
4. Previous arcs remain visible as a faded trail

### Map Styles

Choose from several map styles for the video background:

- **Standard** - Apple Maps standard style
- **Satellite** - Satellite imagery
- **Dark** - Dark-themed map (good for social media)
- **Muted** - Subtle gray tones to emphasize QSO arcs

### Map Zoom

The map automatically zooms to fit:

- **Initially** zoomed to show your station location
- **Progressively zooms out** as contacts reach further distances
- **Smooth transitions** between zoom levels

## Toast Notifications

Each QSO triggers a toast notification overlay:

- **Callsign** prominently displayed
- **RST** sent and received
- **Band and mode**
- **Park reference** (for POTA contacts)
- **Distance** from your station
- **Country flag** for DX contacts

Toasts appear from the bottom of the screen and auto-dismiss after 2 seconds (real-time mode) or based on pacing (highlight mode).

## Audio Options

### No Audio (Default)

Silent video suitable for adding your own music or narration.

### Session Recording Audio

If you have a WebSDR recording for the session, overlay the recording audio on the video:

- Audio is synchronized to the video timeline
- QSO moments are aligned with the corresponding audio
- Gaps in the recording are filled with silence

### Background Music

Select from built-in ambient tracks:

- **Radio static** - Atmospheric HF receiver background
- **CW practice** - Generated CW audio at configurable WPM
- **None** - Silent

## Export Settings

### Resolution

- **1080p** (1920x1080) - Standard HD, smaller file
- **4K** (3840x2160) - Ultra HD, larger file but sharper

### Frame Rate

- **30 fps** - Standard, smaller file
- **60 fps** - Smoother animation, larger file

### Duration (Highlight Mode)

Set target video duration: 15, 30, 45, or 60 seconds.

## Thermal Monitoring

Video rendering is computationally intensive. Carrier Wave monitors device temperature during export:

- **Temperature indicator** shows device thermal state
- **Auto-pause** if the device reaches thermal throttling threshold
- **Resume** when the device cools down
- **Progress bar** shows rendering percentage

### Performance Tips

- Connect to power during long renders
- Close other apps to free memory
- 4K renders take approximately 2-4x longer than 1080p
- Real-time mode for long sessions produces very large files; consider highlight mode

## Export Process

1. Open a session detail view
2. Tap **Video Export** (or share menu -> Video)
3. Select rendering mode (Real-Time or Highlight)
4. Configure map style, audio, and resolution
5. Tap **Render Video**
6. Wait for rendering to complete (progress bar shown)
7. Preview the video
8. Share via the iOS share sheet or save to Photos

## See Also

- [Logger](/reference/logger/) - Session management
- [POTA Activations](/reference/pota/) - Activation detail with video export
- [Brag Sheets & Share Cards](/reference/brag-sheets/) - Static image alternative
- [Export & Sharing](/reference/export/) - All export formats
- [WebSDR Integration](/reference/websdr/) - Session recordings for audio overlay
