# qsy:// URI Scheme Specification

**Version:** 0.1.0 (Draft)
**Status:** Proposal
**Date:** 2026-03-05

## Overview

`qsy://` is a vendor-neutral URI scheme for amateur radio logging applications. The name comes from the Q-code **QSY** — "change your transmitting frequency" — reflecting the scheme's purpose of directing apps to a specific station, frequency, or action.

It enables interoperability between spot aggregators, band maps, cluster clients, CAT control software, and logging apps on any platform.

Any application may register as a handler for `qsy://` URIs. When multiple handlers exist, the operating system's default app selection applies.

## URI Format

```
qsy://<action>?<parameters>
```

Actions define the intent. Parameters are standard URL query parameters (percent-encoded).

## Actions

### `spot` — Pre-fill a QSO from a spot

Opens the logging app with a new QSO form pre-filled from spot data. The QSO is **not** saved automatically — the operator confirms and completes the entry.

```
qsy://spot?callsign=W1AW&freq=14074000&mode=FT8
```

**Required parameters:** `callsign`, `freq`

**Use cases:**
- Spot aggregator sends a DX spot to a logging app
- Band map click opens logger pre-filled
- Alert service (HamAlert, etc.) triggers logging

### `tune` — Tune radio to frequency/mode

Requests the receiving app to tune a connected radio (via CAT control) to the specified frequency and mode. No QSO form is opened unless the app chooses to.

```
qsy://tune?freq=14074000&mode=FT8
```

**Required parameters:** `freq`

**Use cases:**
- Spot tool sends "tune to this station"
- Band plan reference app sends a frequency
- Scheduled activity reminder triggers tune

### `lookup` — Look up a callsign

Opens callsign lookup/details for the specified callsign. No QSO form is opened.

```
qsy://lookup?callsign=W1AW
```

**Required parameters:** `callsign`

**Use cases:**
- QRZ/HamDB link opens in a logging app's lookup view
- Callsign mentioned in chat/email opens lookup

### `import` — Import QSO data

Imports QSO records from an ADIF source. The source may be a URL to fetch or a reference to a local file.

```
qsy://import?url=https%3A%2F%2Fexample.com%2Flog.adi
qsy://import?url=file%3A%2F%2F%2Fpath%2Fto%2Flog.adi
```

**Required parameters:** `url`

**Optional parameters:** `format` (default: `adif`)

**Use cases:**
- Web service offers "Open in logger" link
- Email attachment handler
- Contest log exchange

### `log` — Record a completed QSO

Sends a fully-specified QSO record to be saved. The receiving app **should** present the record for confirmation before saving, but may save directly if the operator has configured auto-accept.

```
qsy://log?callsign=W1AW&freq=14074000&mode=FT8&rst_sent=599&rst_rcvd=599&time=20260305T1430Z
```

**Required parameters:** `callsign`, `freq`, `mode`

**Use cases:**
- Contest logging app sends QSO to general logger
- Digital mode decoder (WSJT-X, etc.) sends decoded QSO
- Automated logging from SDR software

## Parameters

### Identification

| Parameter | Type | Description | ADIF Field |
|-----------|------|-------------|------------|
| `callsign` | string | Callsign of the station being worked | `CALL` |
| `op` | string | Operator's own callsign (if different from station) | `OPERATOR` |
| `station` | string | Station callsign (if portable, club, etc.) | `STATION_CALLSIGN` |

### Frequency & Mode

| Parameter | Type | Description | ADIF Field |
|-----------|------|-------------|------------|
| `freq` | integer | Frequency in Hz | `FREQ` (converted to MHz) |
| `mode` | string | ADIF mode value (e.g., `FT8`, `SSB`, `CW`) | `MODE` |
| `submode` | string | ADIF submode value (e.g., `USB`, `LSB`) | `SUBMODE` |
| `band` | string | Band name (e.g., `20m`, `2m`). Informational; `freq` takes precedence if both present. | `BAND` |

### Power

| Parameter | Type | Description | ADIF Field |
|-----------|------|-------------|------------|
| `tx_power` | number | Transmit power in watts | `TX_PWR` |

### Signal Reports

| Parameter | Type | Description | ADIF Field |
|-----------|------|-------------|------------|
| `rst_sent` | string | RST/signal report sent | `RST_SENT` |
| `rst_rcvd` | string | RST/signal report received | `RST_RCVD` |

### Location

| Parameter | Type | Description | ADIF Field |
|-----------|------|-------------|------------|
| `grid` | string | Maidenhead grid locator of the worked station | `GRIDSQUARE` |
| `my_grid` | string | Operator's grid locator | `MY_GRIDSQUARE` |

### Activation References

Activation references support multiple simultaneous activations via comma-separated values. When multiple values are present, `ref` and `ref_type` are positionally paired (first ref with first ref_type, etc.).

| Parameter | Type | Description | ADIF Field |
|-----------|------|-------------|------------|
| `ref` | string | Activation reference(s), comma-separated (e.g., `K-1234` or `K-1234,W6/CT-001`) | `SIG_INFO` |
| `ref_type` | string | Reference program(s), comma-separated (e.g., `pota` or `pota,sota`) | `SIG` |
| `my_ref` | string | Operator's activation reference(s), comma-separated | `MY_SIG_INFO` |
| `my_ref_type` | string | Operator's reference program(s), comma-separated | `MY_SIG` |

**Example — dual POTA/SOTA activation:**
```
ref=K-1234,W6/CT-001&ref_type=pota,sota
```

Receivers that only support a single reference SHOULD use the first value and ignore the rest.

### Time

| Parameter | Type | Description | ADIF Field |
|-----------|------|-------------|------------|
| `time` | string | ISO 8601 UTC timestamp (e.g., `20260305T1430Z`) | `QSO_DATE` + `TIME_ON` |

### Contest

| Parameter | Type | Description | ADIF Field |
|-----------|------|-------------|------------|
| `contest` | string | Contest ID (e.g., `CQ-WPX-CW`) | `CONTEST_ID` |
| `srx` | string | Serial/exchange received | `SRX_STRING` |
| `stx` | string | Serial/exchange sent | `STX_STRING` |

### Metadata

| Parameter | Type | Description |
|-----------|------|-------------|
| `source` | string | Originating application or service identifier |
| `comment` | string | Free-text comment to pre-fill |

## Encoding Rules

1. All parameter values MUST be percent-encoded per [RFC 3986](https://datatracker.ietf.org/doc/html/rfc3986).
2. Frequency (`freq`) is always an integer in **hertz**. No decimal points.
3. Mode and submode values MUST use [ADIF mode enumeration](https://adif.org/314/ADIF_314.htm#Mode_Enumeration) strings.
4. Time values use compact ISO 8601 in UTC: `YYYYMMDDTHHmmZ` or `YYYYMMDDTHHmmSSZ`.
5. Callsigns SHOULD be uppercase but receivers MUST accept any case.
6. Unknown parameters MUST be ignored by the receiver (forward compatibility).
7. Comma-separated values (activation references) MUST NOT contain unescaped commas within individual values.

## Receiver Behavior

1. **Unknown actions:** If a receiver does not support an action, it SHOULD open to its default view and MAY display a notice.
2. **Missing optional parameters:** Receivers fill in defaults or leave fields empty.
3. **Conflicting parameters:** If `freq` and `band` disagree, `freq` wins.
4. **Security:** Receivers MUST NOT auto-save QSOs from `spot` actions. The `log` action MAY auto-save only if the operator has explicitly opted in.
5. **Validation:** Receivers SHOULD validate callsign format and frequency range before pre-filling.
6. **Multiple references:** Receivers that support only a single activation reference SHOULD use the first comma-separated value and silently ignore additional values.

## Platform Registration

### iOS / macOS

Apps register the scheme in `Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>qsy</string>
    </array>
    <key>CFBundleURLName</key>
    <string>org.qsy.uri</string>
  </dict>
</array>
```

Handle in SwiftUI with `.onOpenURL { url in ... }`.

### Android

Register in `AndroidManifest.xml`:

```xml
<intent-filter>
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="qsy" />
</intent-filter>
```

### Desktop (Windows / Linux / macOS)

Register the `qsy://` protocol handler via OS-specific mechanisms (Windows Registry, `xdg-mime`, Launch Services).

## Examples

DX spot from cluster:
```
qsy://spot?callsign=JA1ABC&freq=21074000&mode=FT8&grid=PM95&source=dxcluster
```

POTA spot with activation reference:
```
qsy://spot?callsign=W4EF&freq=7074000&mode=FT8&ref=K-1234&ref_type=pota&source=pota
```

Dual POTA/SOTA activation:
```
qsy://spot?callsign=W4EF&freq=7074000&mode=FT8&ref=K-1234,W6/CT-001&ref_type=pota,sota
```

QRP station with power:
```
qsy://spot?callsign=KD2UJK&freq=7030000&mode=CW&tx_power=5&source=sotawatch
```

Tune radio to a CW frequency:
```
qsy://tune?freq=14035000&mode=CW
```

Complete contest QSO:
```
qsy://log?callsign=K3LR&freq=14000000&mode=CW&rst_sent=599&rst_rcvd=599&contest=CQ-WPX-CW&stx=001&srx=123&time=20260305T1430Z
```

Import from URL:
```
qsy://import?url=https%3A%2F%2Fpota.app%2Fexport%2FN3JSV.adi
```

Callsign lookup:
```
qsy://lookup?callsign=W1AW
```

## Versioning

This specification follows [Semantic Versioning](https://semver.org/). The version is informational — there is no version negotiation in the URI itself. Forward compatibility is maintained by the "ignore unknown parameters" rule.

## License

This specification is released under [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) — public domain, no rights reserved. Anyone may implement, extend, or redistribute without restriction.
