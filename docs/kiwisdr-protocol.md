# KiwiSDR WebSocket Protocol

Reference specification derived from [kiwiclient](https://github.com/jks-prv/kiwiclient), the canonical Python client for KiwiSDR receivers.

## Connection Establishment

### WebSocket URL Format

```
ws://<host>:<port>/<timestamp>/<stream_type>
```

| Component | Description | Example |
|-----------|-------------|---------|
| `host` | KiwiSDR hostname or IP | `192.168.1.82` |
| `port` | Default `8073` | `8073` |
| `timestamp` | Unix timestamp in **seconds** (integer) | `1707350400` |
| `stream_type` | `SND` (audio) or `W/F` (waterfall) | `SND` |

**Examples:**
```
ws://my-kiwi.example.com:8073/1707350400/SND
ws://192.168.1.82:8073/1707350400/W/F
```

> **Note:** There is no `/kiwi/` path prefix. The path is `/<timestamp>/<stream_type>` directly.

### WebSocket Handshake

Standard RFC 6455 (HyBi-13) upgrade:
- Client sends masked frames (`mask_send=True`)
- Server sends unmasked frames (`unmask_receive=False`)
- Redirect responses (`301`, `307`, `308`) include a `Location` header to follow

## Connection Lifecycle

```
1. TCP Connect          → socket to host:port
2. WebSocket Upgrade    → HTTP 101 Switching Protocols
3. Authentication       → SET auth t=kiwi p=<password>
4. Server Config        ← Server sends MSG with sample_rate, version, etc.
5. Rate Acknowledgment  → SET AR OK in=<rate> out=<rate>
6. Identity             → SET ident_user=<name>
7. Compression          → SET compression=<0|1>
8. Tune                 → SET mod=<mode> low_cut=<lc> high_cut=<hc> freq=<kHz>
9. AGC                  → SET agc=1 hang=0 thresh=-100 slope=6 decay=1000 manGain=50
10. Streaming           ← Server sends continuous SND binary frames
11. Keepalive Loop      → SET keepalive (every ~5-10 seconds)
12. Disconnect          → WebSocket close frame (status 1001)
```

## Client-to-Server Commands

All commands are plain text strings sent as WebSocket text frames.

### Authentication

```
SET auth t=kiwi p=<password>
SET auth t=kiwi p=#              (no password)
SET auth t=admin p=<password>    (admin access)
```

Optional time-limit password: `SET auth t=kiwi p=<password> ipl=<tlimit_password>`

### Identity

```
SET ident_user=<username>
SET geo=<location_string>
```

### Frequency and Mode

```
SET mod=<mode> low_cut=<Hz> high_cut=<Hz> freq=<kHz_float>
```

**Mode values and default passbands:**

| Mode | Low Cut (Hz) | High Cut (Hz) | Description |
|------|-------------|---------------|-------------|
| `am` | -4900 | 4900 | AM |
| `amn` | -2500 | 2500 | AM Narrow |
| `lsb` | -2700 | -300 | Lower Sideband |
| `usb` | 300 | 2700 | Upper Sideband |
| `cw` | 300 | 700 | CW |
| `cwn` | 470 | 530 | CW Narrow |
| `nbfm` | -6000 | 6000 | Narrow FM |
| `iq` | -5000 | 5000 | IQ (stereo) |
| `drm` | -5000 | 5000 | DRM (stereo) |

### AGC

```
SET agc=<0|1> hang=<0|1> thresh=<int> slope=<int> decay=<int> manGain=<int>
```

### Compression

```
SET compression=0    (raw PCM, 16-bit signed)
SET compression=1    (IMA ADPCM, 4:1 compression)
```

### Rate Acknowledgment

```
SET AR OK in=<input_rate> out=<output_rate>
```

Sent after receiving `sample_rate` from the server.

### Keepalive

```
SET keepalive
```

The reference client sends this at ~1 Hz. In practice, any interval under 60 seconds prevents server timeout.

### Squelch

```
SET squelch=<0|1> max=<int>
```

## Server-to-Client Messages

### Text Messages (MSG format)

Server text messages follow the format: `MSG key1=value1 key2=value2 ...`

**Configuration messages (sent after auth):**

| Key | Value | Description |
|-----|-------|-------------|
| `sample_rate` | float (e.g., `12001.135`) | Exact sample rate from ADC clock |
| `audio_rate` | int (e.g., `12000`) | Nominal audio rate |
| `center_freq` | int (Hz) | Server center frequency |
| `bandwidth` | int (Hz) | Server bandwidth |
| `version_maj` | int | Server major version |
| `version_min` | int | Server minor version |
| `rx_chans` | int | Number of receiver channels |
| `load_cfg` | URL-encoded JSON | Full server configuration |
| `client_public_ip` | IP string | Client's public IP |
| `freq_offset` | float (kHz) | Frequency offset (transverter) |

**Authentication result:**

| Key | Value | Description |
|-----|-------|-------------|
| `badp` | `0` | Authentication successful |
| `badp` | `1` | Bad password OR all channels busy |
| `badp` | `2` | Still determining local interface |
| `badp` | `3` | Admin not allowed from this IP |
| `badp` | `4` | No admin password set |
| `badp` | `5` | No multiple connections from same IP |
| `badp` | `6` | Database update in progress |
| `badp` | `7` | Another admin connection open |

**Error/status messages:**

| Key | Description |
|-----|-------------|
| `too_busy` | All client slots taken (value = slot count) |
| `redirect` | Redirect to another server (value = URL) |
| `down` | Server is down |
| `inactivity_timeout` | Connection timed out |

**Streaming status:**

| Key | Description |
|-----|-------------|
| `audio_adpcm_state` | `<index>,<prev>` — preset ADPCM decoder state |

### Binary Messages (Audio Frames)

Audio frames use the `SND` tag prefix:

```
Offset  Size   Type              Field
------  ----   ----              -----
0       3      ASCII             "SND" (0x53, 0x4E, 0x44)
3       1      uint8             flags
4       4      uint32 (LE)       sequence number
8       2      uint16 (BE)       S-meter raw value
10      N      varies            audio data payload
```

**Flag bits:**

| Bit | Mask | Name | Description |
|-----|------|------|-------------|
| 1 | `0x02` | `SND_FLAG_ADC_OVFL` | ADC overflow detected |
| 3 | `0x08` | `SND_FLAG_STEREO` | Stereo/IQ mode data |
| 4 | `0x10` | `SND_FLAG_COMPRESSED` | IMA ADPCM compressed |
| 7 | `0x80` | `SND_FLAG_LITTLE_ENDIAN` | Little-endian PCM samples |

**S-meter conversion:**
```
rssi_dBm = 0.1 * raw_smeter - 127.0
```

**Stereo/GPS prefix (when `SND_FLAG_STEREO` is set):**

Before audio data, there is a 10-byte GPS header:
```
Offset  Size   Type        Field
------  ----   ----        -----
0       1      uint8       last_gps_solution
1       1      uint8       padding
2       4      uint32(LE)  gpssec
6       4      uint32(LE)  gpsnsec
```

**Audio payload:**
- **Uncompressed:** 16-bit signed integer PCM. Endianness from `SND_FLAG_LITTLE_ENDIAN`.
- **Compressed (ADPCM):** IMA-ADPCM encoded. Each byte = 2 samples (low nibble first).

## IMA ADPCM Decoding

State variables: `index` (step table position, 0-88) and `prev` (previous sample).

**Step Size Table (89 entries):**
```
7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31,
34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130,
143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449,
494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411,
1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026,
4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487,
12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794,
32767
```

**Index Adjustment Table:**
```
-1, -1, -1, -1, 2, 4, 6, 8,
-1, -1, -1, -1, 2, 4, 6, 8
```

**Per-nibble decode:**
```
step = stepSizeTable[index]
index = clamp(index + indexAdjustTable[code], 0, 88)
diff = step >> 3
if (code & 1): diff += step >> 2
if (code & 2): diff += step >> 1
if (code & 4): diff += step
if (code & 8): diff = -diff
sample = clamp(prev + diff, -32768, 32767)
prev = sample
```

## Waterfall Binary Frames

```
Offset  Size   Type           Field
------  ----   ----           -----
0       3      ASCII          "W/F"
3       1      uint8          padding
4       4      uint32 (LE)    x_bin_server
8       4      uint32 (LE)    flags_x_zoom_server
12      4      uint32 (LE)    sequence number
16      N      uint8[]        pixel data (typically 1024 bins)
```

dBm conversion: `-(255 - value) - 13`

Discard first 2 frames (sequence < 2) as startup artifacts.

## Reconnection Behavior

| Error | Strategy |
|-------|----------|
| Server terminated connection | Wait 5s, retry |
| Too busy | Respect busy_timeout, retry up to busy_retries |
| Redirect | Parse host:port from redirect value, reconnect |
| Time limit | Terminate, do not retry |
| Bad password | Terminate, do not retry |

## Minimal Audio Connection Example

```python
# 1. Connect
uri = '/%d/%s' % (int(time.time()), 'SND')
# WebSocket handshake to host:port with uri

# 2. Authenticate
send('SET auth t=kiwi p=#')

# 3. Wait for sample_rate MSG, then acknowledge
send('SET AR OK in=12000 out=12000')

# 4. Identify
send('SET ident_user=MyApp')

# 5. Set compression
send('SET compression=1')    # ADPCM

# 6. Tune
send('SET mod=usb low_cut=300 high_cut=2700 freq=14074.000')

# 7. AGC
send('SET agc=1 hang=0 thresh=-100 slope=6 decay=1000 manGain=50')

# 8. Receive loop with keepalive
while connected:
    msg = receive()
    if binary and starts with "SND":
        decode_audio(msg)
    send_keepalive_if_due()
```
