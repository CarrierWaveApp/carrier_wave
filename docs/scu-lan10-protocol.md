# SCU-LAN10 Network Protocol

Protocol specification for the Yaesu SCU-LAN10 Network Remote Control System, reverse-engineered from packet captures between the FT-Control iOS app and SCU-LAN10 hardware.

## Overview

The SCU-LAN10 provides remote control of Yaesu transceivers (FTDX101MP/D, FTDX10, FT-710) over LAN or Internet. All communication uses **UDP** on 4 ports. All packets share a common framing and encryption scheme.

## Supported Transceivers

| Radio | Firmware Required |
|-------|-------------------|
| FTDX101MP/D | MAIN V01-14+, DISPLAY V01-06+, SDR V02-03+ |
| FTDX10 | MAIN V01-01+, DISPLAY V01-01+, SDR V01-00+ |
| FT-710 | MAIN V01-11+, DISPLAY V01-08+, SDR V01-04+ |

Required radio settings: CAT RATE 38400bps (115200 over LAN), CAT TIME OUT TIMER 10ms, CAT RTS ON.

## Network Architecture

| Port | Default | Function | Data Direction |
|------|---------|----------|----------------|
| Control | 50000 | Authentication, session management, keepalives | Bidirectional |
| CAT | 50001 | Radio control commands (Yaesu CAT protocol) | Bidirectional |
| Audio | 50002 | PCM/µ-Law audio streaming | Bidirectional |
| Scope | 50003 | Spectrum/waterfall data | Server → Client (data), Client → Server (keepalives) |

The Control Port is configurable (range 49990-50009). Other ports are independently configurable in the same range. Factory default assignment is Control+0 through Control+3.

## Packet Framing

All packets on all 4 ports share the same framing:

```
┌──────────┬──────────────┬────────────┬──────────────────────────┐
│  Magic   │  Length (LE)  │    Type    │         Payload          │
│  2 bytes │   2 bytes     │   2 bytes  │     variable             │
│  5A 5A   │  includes     │   00 01    │                          │
│          │  type+payload │            │                          │
└──────────┴──────────────┴────────────┴──────────────────────────┘
```

- **Magic**: Always `0x5A 0x5A` ("ZZ")
- **Length**: Little-endian uint16. Counts `sizeof(Type) + sizeof(Payload)` = `len(payload) + 2`
- **Type**: Always `0x00 0x01` in observed traffic
- **Payload**: Encrypted data (see below)

## Payload Encryption

All payloads use the same encryption scheme. Every payload has an 8-byte header followed by encrypted data:

```
┌───────┬───────────┬──────────────┬─────┬──────────┬──────────────────┐
│ Seq   │  ID (2B)  │ Counter (3B) │ Key │ Key Dup  │  Encrypted Data  │
│ 1 byte│  2 bytes  │  3 bytes     │ 1B  │  1 byte  │    variable      │
│  [0]  │  [1..2]   │  [3..5]      │ [5] │   [6]    │    [8..]         │
└───────┴───────────┴──────────────┴─────┴──────────┴──────────────────┘
```

- **Byte 0 (Seq)**: Sequence/frame identifier
- **Bytes 1-2 (ID)**: Packet identifier (varies per packet type)
- **Bytes 3-4**: Counter-related (derived from byte 5)
- **Byte 5 (Key)**: The per-packet XOR key used for encryption
- **Byte 6 (Key Dup)**: Equal to byte 5 for scope data; may differ for other packet types
- **Byte 7**: Counter-related

### Decryption Formula

```
plaintext[i] = encrypted[i] XOR key XOR g(i)
```

Where `key` is payload byte 5, and `g(i)` is a position-dependent scramble:

```
g(i) = (4 * (i / 4) + 6 + offset[i % 4]) & 0xFF

offset = [0, 0xFF, 0xFE, 5]   // equivalently: [0, -1, -2, +5] mod 256
```

Expanded `g(i)` for the first 16 positions:

| i | g(i) |
|---|------|
| 0 | 0x06 |
| 1 | 0x05 |
| 2 | 0x04 |
| 3 | 0x0B |
| 4 | 0x0A |
| 5 | 0x09 |
| 6 | 0x08 |
| 7 | 0x0F |
| 8 | 0x0E |
| 9 | 0x0D |
| 10 | 0x0C |
| 11 | 0x13 |
| 12 | 0x12 |
| 13 | 0x11 |
| 14 | 0x10 |
| 15 | 0x17 |

The `g(i)` table can be precomputed for the maximum payload size (4096 for scope data). Encryption uses the same formula (symmetric XOR).

### Counter

Bytes 3-5 of the header form a 3-byte counter that increments by approximately `0x5F5E61` per packet (not exactly constant — varies by ±0x0800). This counter is shared across all ports within a session. It likely functions as a nonce or sequence check but is not required for decryption.

## Connection Establishment

### Sequence Diagram

```
Client                                          SCU-LAN10
  │                                                │
  │──── 5× keepalive (0x04040404) ────────────────>│  (Control port)
  │──── Auth packet (user + password) ────────────>│  (Control port)
  │                                                │
  │<─── Auth response (session_id + caps) ─────────│  (Control port)
  │                                                │
  │──── Continuation (session_id + 51 C3) ────────>│  (Control port)
  │<─── Ack ───────────────────────────────────────│  (Control port)
  │                                                │
  │  ┌─── For each port (CAT, Audio, Scope): ───┐ │
  │  │                                           │ │
  │  │──── Port init (session_id) ──────────────>│ │  (Target port)
  │  │──── Port setup (session_id + port_id) ───>│ │  (Control port)
  │  │<─── Port ack ────────────────────────────│ │  (Target port)
  │  │<─── Control ack ────────────────────────│ │  (Control port)
  │  │                                           │ │
  │  └───────────────────────────────────────────┘ │
  │                                                │
  │──── CAT: "FA;" (read frequency) ──────────────>│  (CAT port)
  │<─── CAT: "FA007007000;" ───────────────────────│  (CAT port)
  │                                                │
  │<═══ Scope data (25 packets/sec) ═══════════════│  (Scope port)
  │<═══ Audio data (~100 packets/sec) ═════════════│  (Audio port)
  │                                                │
  │──── Keepalives (1/sec, all ports) ────────────>│
  │<─── Keepalive responses ───────────────────────│
```

### Phase 1: Initial Keepalives

Send 5 keepalive packets to the Control port. These are fixed values (identical across all sessions):

```python
# Plaintext for all 5: [0x04, 0x04, 0x04, 0x04]
# Headers are fixed (captured values):
init_packets = [
    "5a5a0e00000101a0a15e585d595a5b585956",
    "5a5a0e000001024042bdbbbebab9b8bbbab5",
    "5a5a0e00000103e0e31c1a1f1b18191a1b14",
    "5a5a0e0000010480847b7d787c7f7e7d7c73",
    "5a5a0e000001052025dadcd9dddedfdcddd2",
]
```

The server does not respond to these. They prime the connection before authentication.

### Phase 2: Authentication

Send one auth packet to the Control port:

**Plaintext format** (68 bytes):
```
┌────────────┬────────────────────────┬────────────────────────┐
│  Prefix    │   Username             │   Password             │
│  01 00     │   33 bytes, null-pad   │   33 bytes, null-pad   │
│  (2 bytes) │                        │                        │
└────────────┴────────────────────────┴────────────────────────┘
```

- Username: ASCII, max 32 characters, null-padded to 33 bytes
- Password: ASCII, max 32 characters, null-padded to 33 bytes
- Factory defaults: user=`defaultuser`, password=`defaultuser`
- Encrypted with `key=0x3A` and header `06 C0 C6 39 39 3A 7E 3D`

**Server response** (28 bytes total, 14 bytes decrypted data):
```
Decrypted: [session_id, 0, 0, 0, 0, 0, 0, 0, 0, 0x01, 0x25, 0x01, 0x3F, 0x51]
```

- **Byte 0**: Session ID — a unique value assigned by the server (e.g., 0x22, 0x24, 0x26). Must be echoed in all subsequent packets.
- **Bytes 9-13**: Capability/version fields (observed constant: `01 25 01 3F 51`)

### Phase 3: Continuation

Send continuation packet echoing the session ID:

**Plaintext** (10 bytes):
```
[session_id, 0x00, 0x00, 0x00, 0x51, 0xC3, 0x00, 0x96, 0x00, 0x00]
```

- Header: `07 60 66 98 9A 9B 91 9C` (key=0x9B)
- Bytes 4-7 (`51 C3 00 96`) appear to be fixed capability fields

Server responds with a keepalive ack.

### Phase 4: Port Initialization

Each of the 3 data ports (CAT, Audio, Scope) requires two packets:

1. **Port init**: Send `[session_id, 0, 0, 0]` **to the target port** — this associates the client's UDP source port with the session
2. **Port setup**: Send `[session_id, 0, 0, 0, port_id, 0xC3]` **to the Control port** — this tells the SCU-LAN10 to start streaming on that port

| Port | Port ID | Init Header | Setup Header |
|------|---------|-------------|--------------|
| CAT (50001) | 0x52 | `080009f7f2f4f0f3` | `09a0ab5654555352` |
| Audio (50002) | 0x53 | `0a4048b5b0b6b2b1` | `0be0ed1416171110` |
| Scope (50003) | — | `0c808a7376707477` | (keepalive only) |

The server responds on both the target port and the control port, confirming the association.

After all ports are initialized, send initial keepalives on each port (plaintext `[0, 0, 0, 0]`) and optionally the first CAT command.

## Keepalives

All 4 ports require keepalive packets at approximately **1-second intervals**. Failure to send keepalives results in session termination.

**Keepalive plaintext**: `[0x04, 0x04, 0x04, 0x04]` (for initial handshake) or `[0x00, 0x00, 0x00, 0x00]` (for ongoing keepalives).

The server responds to control port keepalives with 15-byte packets (7 bytes decrypted data). Data port keepalives receive periodic acks.

## Scope Data (Port 50003)

### Packet Format

Each scope data packet is **4110 bytes** total:

```
┌──────────┬──────────┬──────────┬──────────────────┬──────────────────────┐
│  Magic   │  Length   │  Type    │  Header (8B)     │  Spectrum Data       │
│  5A 5A   │  0A 10   │  00 01   │  seq/key/counter │  4096 bytes          │
│  2 bytes │  2 bytes  │  2 bytes │  8 bytes         │  (encrypted)         │
└──────────┴──────────┴──────────┴──────────────────┴──────────────────────┘
```

- Length: `0x100A` = 4106 = 2 (type) + 8 (header) + 4096 (data)
- Rate: ~25 packets/second (~40ms interval)
- Each packet is one complete spectrum sweep line

### Decrypted Spectrum Data

After decryption, the 4096 bytes represent amplitude values for frequency bins:

| Value | Meaning |
|-------|---------|
| 0 | No data (unused bins beyond scope span) |
| 1-127 | Strong signal (lower = stronger) |
| 128 | Mid-point |
| 200-240 | Noise floor (typical) |
| 255 | Weakest measurable signal |

The number of **active bins** (non-zero) depends on the scope span setting. For a 200kHz span, approximately 3000-3100 bins are active, with the remainder zero-padded.

**Bin-to-frequency mapping**: The active bins span the configured scope frequency range (e.g., center ± span/2). Linear mapping from bin index to frequency.

### Waterfall Rendering

To render a waterfall display:
1. Decrypt each scope packet to get 4096 amplitude values
2. Find the active range (first non-zero to last non-zero bin)
3. Map amplitude values to colors (inverted: lower value = stronger signal = brighter color)
4. Scroll the display vertically, adding each new sweep line at the top

## CAT Protocol (Port 50001)

CAT commands are tunneled through the encryption layer. The decrypted payload format for CAT data:

```
[session_id, 0x00, 0x00, 0x00, flag1, flag2, flag3, flag4, ...CAT command bytes...]
```

- Bytes 0-3: Session prefix (`[session_id, 0, 0, 0]`)
- Bytes 4-7: Flags (observed: `01 00 00 00` for commands, varies for responses)
- Bytes 8+: Standard Yaesu CAT command in ASCII, semicolon-terminated

**Example**: Reading the VFO-A frequency:
```
Command:  FA;
Response: FA007007000;     (7.007000 MHz)
```

The CAT command set is documented in the FTDX101MP/D and FTDX10 CAT Operation Reference Manuals. Key commands for scope control:

| Command | Description |
|---------|-------------|
| `FA` | VFO-A frequency (9 digits, Hz) |
| `FB` | VFO-B frequency |
| `MD0` | Operating mode (MAIN) |
| `SS` | Spectrum scope settings (span, speed, color, mode) |
| `SM0` | S-meter reading (MAIN, 0-255) |
| `IF` | Composite information |
| `ID` | Radio identification (0670=FTDX10, 0681=FTDX101D, 0682=FTDX101MP) |

## Audio Protocol (Port 50002)

Audio data uses the same encryption framing. Decrypted audio payloads contain:

- Bytes 0-3: Sequence/format header
- Bytes 4+: Audio samples

**Audio quality options** (configured in Connection Setup):

| Format | Sample Rate | Description |
|--------|-------------|-------------|
| PCM(16kHz) | 16,000 Hz | Default, uncompressed |
| PCM(8kHz) | 8,000 Hz | Lower quality |
| µ-Law(16kHz) | 16,000 Hz | Compressed |
| µ-Law(8kHz) | 8,000 Hz | Compressed |

Audio buffer sizes: Send 200ms (default), Receive 100ms (default).

## Session Lifecycle

```
Connect → Authenticate → Init Ports → Stream Data ←→ Keepalives → Disconnect
```

- Sessions are **exclusive** — only one client can connect at a time
- Session IDs increment with each new connection (observed: 0x22, 0x24, 0x26, 0x27, 0x28, 0x29)
- If keepalives stop, the SCU-LAN10 terminates the session after a timeout
- Reconnecting requires the full auth sequence; there is no session resumption

## Implementation Notes

### Precomputing the g(i) Table

```swift
var gTable = [UInt8](repeating: 0, count: 4096)
let offsets: [Int] = [0, 0xFF, 0xFE, 5]
for i in 0..<4096 {
    let group = i / 4
    let base = (4 * group + 6) & 0xFF
    gTable[i] = UInt8((base + offsets[i % 4]) & 0xFF)
}
```

### Decrypting a Scope Packet

```swift
func decryptScopePayload(_ payload: Data) -> [UInt8] {
    guard payload.count >= 4104 else { return [] }
    let key = payload[5]
    var spectrum = [UInt8](repeating: 0, count: 4096)
    for i in 0..<4096 {
        spectrum[i] = payload[8 + i] ^ key ^ gTable[i]
    }
    return spectrum
}
```

### NAT/Firewall Considerations

- All 4 UDP ports (50000-50003) must be forwarded through the router
- The SCU-LAN10 responds to the client's source IP:port, so NAT traversal works naturally for outbound connections
- Some routers may require UDP timeout settings >60s to maintain the session
- IPv6 is not supported

## References

- SCU-LAN10 Installation Manual (Yaesu, Rev. 2503-E)
- SCU-LAN10 Operation Manual (Yaesu, Rev. 2012-B)
- FTDX10 Operation Manual (Yaesu)
- FTDX101MP/D CAT Operation Reference Manual (Yaesu, Rev. 2308-L)
