# SMS Spotting Integration Guide (iOS)

Carrier Wave can let operators submit POTA and SOTA spots via SMS through a Twilio webhook. This is useful when operating in areas with cellular service but no data/internet — a common scenario at remote parks and summits.

## How It Works

```
┌──────────┐   SMS    ┌─────────┐  POST /v1/twilio/sms  ┌──────────────┐   POST   ┌────────────┐
│  iPhone   │────────▶│  Twilio  │─────────────────────▶│  Challenges  │────────▶│  POTA.app  │
│  (no data)│         │  (SMS)   │   (form-encoded)      │  Server      │   or    │  or SOTA   │
└──────────┘         └─────────┘                        └──────────────┘         └────────────┘
                                                              ▲
                                                              │ POST /v1/spot-markers
┌──────────┐                                                  │ (one-time setup)
│  iPhone   │─────────────────────────────────────────────────┘
│  (w/ data)│
└──────────┘
```

1. **Setup (one-time, with data):** The app calls `POST /v1/spot-markers` to generate a 6-character marker code (e.g. `ABC123`). The app stores and displays this code to the user.
2. **In the field (SMS only):** The operator texts their spot to the configured Twilio phone number using the format: `MARKER REFERENCE FREQ MODE [COMMENTS]`
3. **Server receives the webhook:** Twilio forwards the SMS as a form-encoded POST to `/v1/twilio/sms`. The server looks up the marker to identify the callsign, determines POTA vs SOTA from the reference format, and posts to the appropriate API.
4. **Confirmation SMS:** The server returns TwiML XML, and Twilio sends a confirmation SMS back to the operator.

## Server Endpoints

### Generate Spot Marker

```
POST /v1/spot-markers
Authorization: Bearer fd_xxx
```

No request body. Creates a new marker and replaces any existing marker for the callsign.

**Response (201 Created):**

```json
{
  "data": {
    "marker": "ABC123",
    "callsign": "W6JSV",
    "createdAt": "2026-03-27T12:00:00Z"
  }
}
```

The marker is a 6-character alphanumeric code using an unambiguous character set (no `0/O`, `1/I/L`).

### Twilio SMS Webhook

```
POST /v1/twilio/sms
Content-Type: application/x-www-form-urlencoded
```

This endpoint is called by Twilio, not by the app directly. Configure it as the webhook URL in your Twilio phone number settings.

**Response:** TwiML XML (Twilio renders this as an SMS reply to the sender).

## SMS Format

```
MARKER REFERENCE FREQUENCY MODE [COMMENTS]
```

| Field | Required | Description | Examples |
|-------|----------|-------------|----------|
| `MARKER` | Yes | 6-char code from `/v1/spot-markers` | `ABC123` |
| `REFERENCE` | Yes | Park or summit reference | `K-1234`, `W7W/KI-001` |
| `FREQUENCY` | Yes | Frequency in kHz or MHz | `14.062`, `7074` |
| `MODE` | Yes | Operating mode | `CW`, `SSB`, `FT8` |
| `COMMENTS` | No | Free-text comments | `calling cq` |

### POTA vs SOTA Detection

The server determines which API to use based on the reference format:

- **POTA** — reference does NOT contain `/` (e.g. `K-1234`, `VE-0401`)
  → Posts to `https://api.pota.app/spot` (v1)
- **SOTA** — reference contains `/` (e.g. `W7W/KI-001`, `G/LD-001`)
  → Posts to `https://api2.sota.org.uk/api/spots` (v2)

### Example SMS Messages

```
ABC123 K-1234 14.062 CW calling cq
ABC123 VE-0401 7074 FT8
ABC123 W7W/KI-001 14.285 SSB on the summit
```

## iOS Implementation

### 1. SpotMarker Model

```swift
struct SpotMarker: Codable {
    let marker: String
    let callsign: String
    let createdAt: Date
}

struct SpotMarkerResponse: Codable {
    let data: SpotMarker
}
```

### 2. Generate Marker (Networking)

```swift
func generateSpotMarker() async throws -> SpotMarker {
    var request = URLRequest(url: baseURL.appendingPathComponent("v1/spot-markers"))
    request.httpMethod = "POST"
    request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 201 else {
        throw SpotMarkerError.generationFailed
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(SpotMarkerResponse.self, from: data).data
}
```

### 3. Store the Marker

Store the marker in `UserDefaults` or Keychain alongside the device token. The marker persists until the user generates a new one.

```swift
@AppStorage("spotMarker") private var spotMarker: String?
@AppStorage("spotMarkerCallsign") private var spotMarkerCallsign: String?
```

### 4. Settings UI

Add a section in the app's settings or spotting configuration:

```swift
Section("SMS Spotting") {
    if let marker = spotMarker {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your SMS Marker")
                .font(.headline)
            Text(marker)
                .font(.system(.title, design: .monospaced))
                .bold()
                .textSelection(.enabled)

            Text("Text to: \(twilioPhoneNumber)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Format: \(marker) K-1234 14.062 CW")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Button("Generate New Marker") {
            Task { await regenerateMarker() }
        }
    } else {
        Button("Set Up SMS Spotting") {
            Task { await regenerateMarker() }
        }
    }
}
```

### 5. Quick-Compose SMS (Optional)

If the user is about to go off-grid, offer a pre-composed SMS shortcut using `MFMessageComposeViewController`:

```swift
import MessageUI

func composeSMSSpot(
    marker: String,
    reference: String,
    frequency: String,
    mode: String,
    comments: String? = nil
) -> MFMessageComposeViewController? {
    guard MFMessageComposeViewController.canSendText() else { return nil }

    let vc = MFMessageComposeViewController()
    vc.recipients = [twilioPhoneNumber]

    var body = "\(marker) \(reference) \(frequency) \(mode)"
    if let comments, !comments.isEmpty {
        body += " \(comments)"
    }
    vc.body = body
    return vc
}
```

### 6. Onboarding / Help Text

Explain the feature to users:

> **Spot via SMS when you have no data**
>
> 1. Tap "Set Up SMS Spotting" while you have internet
> 2. Note your 6-character marker code (e.g. ABC123)
> 3. When in the field with no data, text your spot to (555) 123-4567:
>    `ABC123 K-1234 14.062 CW`
> 4. You'll get a confirmation text back when the spot is posted
>
> Your marker stays the same until you generate a new one. Works for both POTA parks and SOTA summits.

## Twilio Configuration

To enable the webhook, configure a Twilio phone number:

1. Purchase a phone number in the [Twilio Console](https://console.twilio.com/)
2. Under **Messaging** → **A message comes in**, set:
   - Webhook URL: `https://your-server.example.com/v1/twilio/sms`
   - HTTP method: `POST`
3. Save the configuration

The server responds with TwiML, so Twilio will automatically send the reply SMS.

## Error Handling

| Scenario | SMS Reply |
|----------|-----------|
| Invalid format (< 4 parts) | "Error processing your spot. Check your message format: MARKER REFERENCE FREQ MODE [COMMENTS]" |
| Unknown marker code | Same error message (no info leak) |
| POTA/SOTA API failure | Same error message |
| Success | "Spot posted! POTA K-1234 on 14.062 CW by W6JSV" |

The server intentionally does not distinguish error types in the SMS reply to avoid leaking information about valid/invalid markers to unknown senders.

## Security Considerations

- **Markers are not secrets** — they are short codes meant to be typed into an SMS. Anyone who knows a marker can spot as that callsign. This is acceptable because:
  - The marker is only shared with the operator themselves
  - SMS spotting is a convenience feature, not a security-critical operation
  - Spots are public information already
- **No Twilio signature validation** is implemented yet. For production, add [Twilio request validation](https://www.twilio.com/docs/usage/security#validating-requests) to verify incoming webhooks are genuinely from Twilio.
- Generating a new marker invalidates the old one (one active marker per callsign).
