---
title: "Logging Your First Contact"
description: "Step-by-step guide to recording a QSO"
weight: 5
---

You've set up the app. Now let's log a contact.

## Start a Session

Tap the **Logger** tab, then **Start Session**. A wizard lets you configure:

1. **Mode** — SSB, FM, CW, FT8, or others
2. **Frequency** — Optional at first; you can set it later if you're scanning around
3. **Activation Type** — Casual, POTA (pick a park from a searchable list or find nearby parks via GPS), or SOTA
4. **Equipment** — Radio, antenna, key, and microphone
5. **Power** — Transmit power in watts

Tap **Save as Defaults** so you don't reconfigure every time.

{{< callout "tip" "Live Activity" >}}
When a session starts, Carrier Wave can show a Live Activity on your lock screen and Dynamic Island — see your session status without opening the app.
{{< /callout >}}

## Enter the Contact

### 1. Callsign

Type the other station's call. As you type, Carrier Wave looks them up — their name, location, and grid appear in an info card. A badge shows if you've worked them before.

### 2. Signal Reports

Enter RST Sent (what you told them) and RST Received (what they told you). Fields show placeholder hints (599 for CW, 59 for voice).

### 3. Optional Fields

Tap the chevron to expand: state/province, park reference, summit, grid square, and notes.

### 4. Log It

Tap **LOG**. Your contact is saved locally and queued for cloud sync. The callsign field auto-focuses for your next contact.

## Quick Entry

For rapid logging, type everything in one line:

```
K6TEST 599 CA US-0189
```

Color-coded tokens show how each piece will be parsed — callsign, RST, state, park reference. Anything unrecognized becomes a note.

## Watch It Sync

On the **Dashboard**, colored dots show service status: green (synced), yellow (syncing), red (error). Your {{< term "QSO" >}} reaches the cloud within seconds.

## Duplicate Detection

Same station, same band, same date? Carrier Wave blocks the duplicate. Different band or different date? No warning — those are valid separate contacts.

## Photos, Video, and Sharing

Attach **photos** to your session — your setup, the park sign, the view. After the session, create a **video export** showing your contacts on a map timeline, or generate a **brag sheet** stat card. Both are great for sharing on social media.

You can also export your session as a **Cabrillo** file for contest submissions.

## What's Next?

Congratulations on your first logged {{< term "QSO" >}}! Next, let's explore [your Dashboard](/guide/dashboard/) to understand your statistics.
