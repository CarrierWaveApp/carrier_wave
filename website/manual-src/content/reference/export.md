---
title: "Export & Sharing"
description: "ADIF export, Cabrillo export, share cards, and recording clips"
weight: 15
showToc: true
---

## Overview

Carrier Wave provides multiple ways to export and share your logging data:

- **{{< term "ADIF" >}} file export** for importing into other logging software or online logbooks
- **Cabrillo export** for contest log submissions
- **Activation brag sheets** for sharing POTA activations as attractive image cards
- **Daily activity share cards** for sharing your day's operating summary
- **Session share cards** for individual sessions
- **Recording clip export** with metadata
- **Video export** for animated session replays

All export and sharing features integrate with the iOS share sheet, allowing you to send data via AirDrop, Messages, email, or save to Files and Photos.

## ADIF Export

### What is ADIF Export?

{{< term "ADIF" >}} (Amateur Data Interchange Format) is the standard format for exchanging amateur radio log data. Carrier Wave exports your QSOs as `.adi` files that can be imported into other logging applications or uploaded to online logbooks like QRZ, LoTW, and eQSL.

### Exporting ADIF Files

You can export ADIF files from:

- **Activation detail view** -- Tap the share button in the toolbar to export that activation's QSOs
- **Sessions list** -- Long-press or swipe on a session row to access the export option
- **Logging session manager** -- Export the current session's QSOs

When you export an ADIF file:

1. Carrier Wave generates a properly formatted `.adi` file containing all QSOs for the selected session or activation
2. The iOS share sheet appears with options to:
   - **Share via AirDrop** to nearby devices
   - **Send via Messages or Mail**
   - **Save to Files** for later use
   - **Copy to clipboard** as text

### ADIF File Handling

Carrier Wave properly registers the ADIF UTType (`public.adi-file`) with iOS, ensuring that `.adi` files are recognized correctly when shared via AirDrop. Without this registration, some apps rename `.adi` files to `.txt`, causing import issues. Carrier Wave's implementation prevents this problem.

### What's Included in ADIF Exports

Each exported ADIF file includes:

- All QSO contact information (callsign, date, time, frequency, mode, RST)
- Station information (operator callsign, grid square, power)
- {{< term "POTA" >}} park references (for activations)
- {{< term "SOTA" >}} summit references (when applicable)
- {{< term "WWFF" >}} references (when applicable)
- Equipment information (MY_RIG field)
- Additional fields like comments and equipment notes

## Cabrillo Export

### What is Cabrillo?

Cabrillo is the standard format for submitting contest logs. Unlike ADIF, Cabrillo includes contest-specific exchange information and header fields required by contest sponsors.

### Generating Cabrillo Files

From a contest session's detail view:

1. Tap the **Export** button
2. Select **Cabrillo (.cbr)**
3. Review the generated header (callsign, category, contest name)
4. Share or save the file

### Cabrillo Header Fields

Carrier Wave populates the Cabrillo header from session and contest metadata:

- **CONTEST** - Contest identifier (from WA7BNM calendar)
- **CALLSIGN** - Your operating callsign
- **CATEGORY-OPERATOR** - Single-op, multi-op
- **CATEGORY-BAND** - ALL or specific band
- **CATEGORY-POWER** - QRP, LOW, HIGH
- **CATEGORY-MODE** - CW, SSB, MIXED, etc.
- **CLAIMED-SCORE** - Calculated from QSO data and contest scoring rules

Edit any header field before exporting if the auto-detected values need correction.

See [Contest Support](/reference/contests/) for details on contest logging.

## Share Cards

### Activation Share Cards

Activation share cards (brag sheets) summarize a POTA activation as an attractive image. See [Brag Sheets & Share Cards](/reference/brag-sheets/) for full details on customization, presets, and statistical overlays.

### Activity Share Cards

Daily activity share cards provide a quick summary of your operating day:

- Total QSOs logged
- Bands and modes used
- Activations completed
- Notable contacts or achievements

From the Activity Log view:

1. Find the day you want to share in the daily summary
2. Tap the **share button** next to that day's entry
3. Carrier Wave generates a branded card with your day's statistics
4. Use the iOS share sheet to send it via your preferred method

### Session Share Cards

Generate a share card for any logging session (not just POTA activations):

- Map with QSO locations and arcs
- Session duration and QSO count
- Band and mode breakdown
- Equipment summary

Access from the session detail view via the share button.

### Recording Share Cards

When sharing a WebSDR recording clip, Carrier Wave generates a companion card showing:

- Recording duration and session details
- QSO count during the recording
- Frequency and mode information
- Waveform thumbnail

## Recording Clip Export

Export audio clips from WebSDR recordings as standalone files.

### Creating a Clip

1. Open the recording playback interface
2. Tap the **Share** button
3. Adjust the **range handles** to select the desired time window (default: active QSO start/end)
4. Tap **Export Clip**

### M4A Export with Metadata

Clips are exported as **M4A** files (AAC compressed audio) with embedded metadata:

- **Title** - Callsign and date of the QSO (if applicable)
- **Artist** - Your callsign
- **Album** - Session name
- **Date** - Recording date
- **Comment** - Frequency, mode, and park reference
- **Artwork** - Session share card thumbnail (if generated)

This metadata ensures clips are properly labeled when imported into other apps or shared on social media.

### Sharing Clips

The clip opens the iOS share sheet. Share via:

- AirDrop
- Messages
- Email
- Save to Files
- Save to Voice Memos

## Share Preview and Photos

### Share Card Preview

When generating any share card (brag sheet, activity card, or summary), Carrier Wave presents a rich preview sheet showing:

- The generated card image
- A **ShareLink** button that opens the iOS share sheet with a proper thumbnail
- A **Save to Photos** button for quick saving to your device

This preview allows you to review the card before sharing and ensures the iOS share sheet displays a proper thumbnail image instead of a generic file icon.

### Saving to Photos

The **Save to Photos** button provides one-tap saving to your device's photo library. This is useful for:

- Building a collection of your activation memories
- Archiving statistical summaries
- Sharing later without regenerating the card

## Video Export

Carrier Wave can generate animated videos of your sessions. See [Video Export](/reference/video-export/) for full details on rendering modes, map styles, and export options.

## Tips for Effective Sharing

### Brag Sheet Best Practices

- **Enable Professional Statistician Mode** if you want to showcase detailed analysis
- **Include equipment badges** to share your field setup with others
- **Wait until activation is complete** to ensure all statistics are accurate
- **Check the preview** before sharing to verify all information is correct

### ADIF Export Best Practices

- **Export regularly** to maintain backups of your log data
- **Use consistent filenames** when saving to Files for easy organization
- **Verify import** after uploading to online logbooks to ensure all QSOs transferred correctly

### Files.app Access

Carrier Wave now appears under **Files → On My iPhone → Carrier Wave**, exposing `Documents/QSOLedger/*.adi` for self-service ADIF recovery without the in-app share UI. Useful when you want to AirDrop the safety-ledger ADIFs to a Mac, copy them to iCloud Drive, or pull them into another logger directly. Enabled by `LSSupportsOpeningDocumentsInPlace` + `UIFileSharingEnabled`.

### Cabrillo Export Best Practices

- **Review the header** before submitting to ensure contest category is correct
- **Verify exchange fields** are properly populated for the specific contest
- **Submit promptly** after the contest ends (most sponsors have submission deadlines)

### Social Media Sharing

Carrier Wave's share cards are designed to look great on social media platforms:

- The 16:9 aspect ratio works well on most platforms
- Carrier Wave branding is subtle but professional
- Maps and statistics are easy to read at various sizes
- Colors use high contrast for accessibility

## See Also

- [POTA (Parks on the Air)](/reference/pota/) -- Learn about POTA activations and how they integrate with brag sheets
- [Brag Sheets & Share Cards](/reference/brag-sheets/) -- Detailed customization options for share cards
- [Video Export](/reference/video-export/) -- Animated session replay videos
- [Contest Support](/reference/contests/) -- Contest logging and Cabrillo generation
- [Activity Log](/reference/activity-log/) -- Understand how daily activity is tracked and shared
- [Logs & Search](/reference/logs-search/) - Browse sessions and QSO history
- [Settings](/reference/settings/) -- Configure POTA settings including Professional Statistician Mode and equipment badges
