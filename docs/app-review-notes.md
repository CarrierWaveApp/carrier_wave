# App Store Review Notes

Notes for Apple App Store review submission.

## App Transport Security (ATS) Exception

**Justification for `NSAllowsArbitraryLoads = true`:**

Carrier Wave connects to KiwiSDR amateur radio receivers — community-hosted software-defined radio servers scattered worldwide. These receivers are operated by individual ham radio operators on residential internet connections with dynamic IPs and non-standard ports. The KiwiSDR directory (kiwisdr.com) lists 500+ receivers, and new ones appear and disappear regularly.

It is not feasible to enumerate these hosts as ATS exception domains because:
- Hosts are dynamic (residential IPs, DDNS hostnames)
- New receivers are added by community members daily
- Many receivers use raw HTTP WebSocket connections on non-standard ports
- The app discovers receivers at runtime from the public KiwiSDR directory

The app uses HTTPS for all first-party API communication (QRZ, POTA, LoFi, LoTW, Club Log, activities server). Only KiwiSDR WebSocket connections use HTTP.

## Background Audio

**Justification for `UIBackgroundModes: audio`:**

Carrier Wave uses background audio for two features:

1. **CW Morse Code Decoding** — The app captures microphone audio to decode CW (Morse code) transmissions in real time. Users place their device near their radio and the app decodes the audio continuously. This requires uninterrupted microphone access.

2. **WebSDR Streaming** — The app streams live audio from remote KiwiSDR software-defined radio receivers via WebSocket. Users listen to amateur radio bands through their device while logging contacts. Interrupting the audio stream would disconnect the WebSocket.

Both features require continuous audio processing that cannot be deferred or batched.

## Export Compliance

The app uses only standard HTTPS (TLS) provided by the iOS networking stack for API communication. No custom encryption algorithms are implemented. `ITSAppUsesNonExemptEncryption` is set to `false`.

## Demo Instructions

Carrier Wave is an amateur radio logging app. You do not need a ham radio license or equipment to test basic functionality:

1. **Launch** — On first launch, you can skip the intro tour and onboarding, or enter any callsign (e.g., "W1AW") to set up a profile.

2. **Dashboard** — The main dashboard shows QSO statistics (will be empty for a new install) and sync service status.

3. **Logger** — Tap the Logger tab to start a logging session. Choose any mode (CW, SSB, FT8) and frequency. You can log test contacts by typing any callsign.

4. **POTA** — If testing POTA features, you can enter a park reference (e.g., "US-0001") when starting a session.

5. **Settings** — Settings contains sync service configuration, logger preferences, and the About section with privacy policy and attributions.

6. **Community Features** — Settings > Activities allows enabling community features (challenges, friends, activity feed). Account deletion is available in this section.

7. **Widgets** — The app includes home screen and lock screen widgets for solar conditions, radio spots, session status, and statistics.

**Note:** QRZ, POTA, LoTW, and Club Log sync features require valid accounts on those services. The app functions fully without any sync services connected.
