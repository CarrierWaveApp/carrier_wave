# SCU-LAN10 Network Remote Control Protocol

Reverse-engineered from FT-Control ↔ SCU-LAN10 packet captures (76,161 packets across 6 sessions). All formulas verified at 100% accuracy.

## Overview

The Yaesu SCU-LAN10 is a network remote control interface for Yaesu transceivers. It provides CAT control, audio streaming, and spectrum scope data over UDP. The protocol uses 4 UDP ports with XOR-based per-packet encryption.

| Port Offset | Channel | Channel ID | Purpose |
|-------------|---------|------------|---------|
| +0 (50000) | CTRL | 0xFC | Authentication, setup, keepalives |
| +1 (50001) | CAT | 0xFD | Yaesu CAT commands/responses |
| +2 (50002) | AUDIO | 0xFE | Bidirectional audio (mic + speaker) |
| +3 (50003) | SCOPE | 0xFA | Spectrum waterfall data (4096 bins) |

The base port is configurable (default 50000).

## Packet Framing

Every UDP packet follows this structure:

```
┌────────┬───────────┬───────────┬────────────┬──────────────────┐
│ Magic  │ Length    │ Type      │ Header     │ Encrypted Body   │
│ 5A 5A  │ LE16     │ 00 01     │ 8 bytes    │ variable         │
└────────┴───────────┴───────────┴────────────┴──────────────────┘
  2 bytes   2 bytes    2 bytes    8 bytes      N bytes
```

- **Magic**: Always `5A 5A`
- **Length**: Little-endian uint16 = `header_size + body_size + 2` (the +2 accounts for the type field)
- **Type**: Always `00 01`
- **Header**: 8-byte unencrypted metadata (see below)
- **Body**: XOR-encrypted payload

## 8-Byte Header Structure

The header is NOT encrypted. It carries the encryption key, sequence info, channel routing, message type, and body length.

```
┌──────┬──────┬──────┬──────┬──────┬──────┬──────┬──────┐
│  b0  │  b1  │  b2  │  b3  │  b4  │  b5  │  b6  │  b7  │
│ seq  │verify│ chan │const │ type │ key  │len_lo│len_hi│
└──────┴──────┴──────┴──────┴──────┴──────┴──────┴──────┘
```

| Byte | Formula | Description |
|------|---------|-------------|
| b0 | `seq` | Per-channel sequence counter (wraps at 0xFF) |
| b1 | `key ^ seq ^ 0xFC` | Verification/integrity byte |
| b2 | `key ^ channel_id` | Channel identifier (see table above) |
| b3 | `key ^ 0x03` | Constant |
| b4 | `key ^ msg_type` | Message type with direction bit (see below) |
| b5 | `key` | Random per-packet XOR encryption key |
| b6 | `key ^ (body_len & 0xFF)` | Low byte of encrypted body length |
| b7 | `key ^ (0x07 ^ (body_len >> 8))` | High byte of body length XOR'd with 0x07 |

### Message Types (b4 ^ key)

| Value | Direction | Meaning |
|-------|-----------|---------|
| 0x01 | Client→Server | Setup/configuration command |
| 0x03 | Client→Server | Authentication request |
| 0x05 | Client→Server | Keepalive |
| 0x06 | Client→Server | Port initialization ("I'm here") |
| 0x07 | Client→Server | Data (CAT command, audio) |
| 0x81 | Server→Client | Setup acknowledgment |
| 0x83 | Server→Client | Authentication response |
| 0x85 | Server→Client | Keepalive response |
| 0x86 | Server→Client | Port initialization ack |
| 0x87 | Server→Client | Data (CAT response, audio, scope) |

Bit 7 (0x80) indicates server→client direction.

### Sequence Counters

Each channel maintains an independent sequence counter per direction. The counter starts at 0 and wraps at 0xFF. The 5 init keepalive packets use sequences 1–5 (hardcoded). Post-auth ctrl packets continue from 7.

## Encryption

Payload encryption uses XOR with a per-packet key and a position-dependent scramble table.

### Scramble Table (gTable)

```
offsets = [0, 0xFF, 0xFE, 5]
gTable[i] = (4 * (i / 4) + 6 + offsets[i % 4]) & 0xFF
```

First 16 values: `06 05 04 0B 0A 09 08 0F 0E 0D 0C 13 12 11 10 17`

### Encrypt

```
encrypted[i] = plaintext[i] ^ key ^ gTable[i]
```

### Decrypt

```
plaintext[i] = encrypted[i] ^ key ^ gTable[i]
```

The key is extracted from header byte b5. The table covers up to 8192 positions (sufficient for 4096-byte scope data + overhead).

## Session Lifecycle

### Phase 1: Init Keepalives (Client → CTRL)

Client sends exactly 5 hardcoded keepalive packets to the CTRL port. These use fixed keys and sequences (1–5). Payload is `00 00 00 00` (4 bytes).

These packets are identical across every connection and appear to be a wake-up/handshake signal.

### Phase 2: Authentication (Client → CTRL)

Single packet with msg_type=0x03. Payload structure:

```
┌──────┬──────────────────────────────────┬──────────────────────────────────┐
│ 01 00│ Username (33 bytes, null-padded) │ Password (33 bytes, null-padded) │
└──────┴──────────────────────────────────┴──────────────────────────────────┘
  2 bytes           33 bytes                        33 bytes = 68 total
```

Uses seq=0x06, channel=CTRL, key=0x3A (fixed).

### Phase 3: Auth Response (Server → CTRL)

Server responds with a 14-byte payload:

```
┌─────────┬──────────┬───────────────┐
│ session │ 00 (×8)  │ 01 25 01 3F 51│
│  ID     │ padding  │ device info   │
└─────────┴──────────┴───────────────┘
  1 byte    8 bytes     5 bytes
```

The session ID is assigned by the server and increments with each connection. The final 5 bytes (`01 25 01 3F 51`) are constant across all observed sessions — likely firmware/capability identifiers.

### Phase 4: Continuation (Client → CTRL)

Tells the server the client wants to proceed with channel setup.

```
Payload: [SID] 00 00 00 51 C3 00 96 00 00
Channel: CAT (0xFD)     ← channel being configured
MsgType: setup (0x01)
```

- `SID`: Session ID from auth response
- `0x51` ('Q'): Possibly "query" or ctrl-channel setup identifier
- `0xC3`: Command marker (appears in all setup commands)
- `0x96` (150): Configuration value (meaning unknown)

Server responds with a 4-byte ack (`00 00 00 00`) using msg_type=0x81.

### Phase 5: Channel Setup (3 iterations)

Each data channel (CAT, AUDIO, SCOPE) is initialized with two packets:

1. **Port Init**: sent TO the channel's port (msg_type=0x06)
   - Payload: `[SID] 00 00 00`
   - Uses the target channel's ID in b2

2. **Port Setup**: sent TO the CTRL port (msg_type=0x01)
   - Payload: `[SID] 00 00 00 [port_id] C3`
   - Uses the NEXT channel's ID in b2

The setup sequence and b2 channel assignments:

| Step | Destination | b2 Channel | Payload | Purpose |
|------|-------------|------------|---------|---------|
| CAT init | Port 50001 | 0xFD (CAT) | `[SID] 00 00 00` | Register on CAT port |
| CAT setup | Port 50000 | 0xFE (AUDIO) | `[SID] 00 00 00 52 C3` | Tell CTRL about CAT |
| Audio init | Port 50002 | 0xFE (AUDIO) | `[SID] 00 00 00` | Register on audio port |
| Audio setup | Port 50000 | 0xFA (SCOPE) | `[SID] 00 00 00 53 C3` | Tell CTRL about audio |
| Scope init | Port 50003 | 0xFA (SCOPE) | `[SID] 00 00 00` | Register on scope port |

Note: Scope has no explicit setup packet to CTRL — only the port init.

Port identifiers in setup payloads: `0x52` ('R') = CAT, `0x53` ('S') = Audio.

The server acks each init (msg_type=0x86) and setup (msg_type=0x81) with a 4-byte `00 00 00 00` response. ~100–200ms delay between each setup step.

### Phase 6: Initial Keepalives

Client sends keepalives (msg_type=0x05, payload `00 00 00 00`) on all 4 channels.

### Phase 7: First CAT Command

The first CAT command (`FA;` — read VFO-A frequency) is sent during the setup burst. CAT commands are sent **twice** per invocation (UDP redundancy).

## Steady-State Operation

### Keepalives

All 4 channels receive keepalive packets at **1-second intervals**. The 4 keepalives are sent as a burst within ~5ms, every second.

```
Payload: 00 00 00 00
MsgType: 0x05 (keepalive)
```

The server responds to CTRL keepalives with a 1-byte `00` ack (msg_type=0x85).

### CAT Commands

**Client → Server (port 50001):**

```
┌─────────┬──────────┬─────────┬──────────┬──────────────┐
│ session │ 00 00 00 │ cmd_seq │ 00 00 00 │ CAT ASCII    │
│  ID     │ padding  │ counter │ padding  │ e.g. "FA;"   │
└─────────┴──────────┴─────────┴──────────┴──────────────┘
  1 byte    3 bytes    1 byte    3 bytes    variable
```

- `cmd_seq`: Incrementing per-command counter (0x01, 0x02, ...)
- `CAT ASCII`: Standard Yaesu CAT command string
- Every command is sent **twice** for UDP reliability

**Server → Client (port 50001):**

```
┌──────────┬──────────┬──────────────┐
│ resp_seq │ 00 00 00 │ CAT ASCII    │
│ counter  │ padding  │ response     │
└──────────┴──────────┴──────────────┘
  1 byte     3 bytes    variable
```

The server also sends unsolicited CAT data (meter readings: `RM1xxx;` through `RM6xxx;`) continuously.

### Audio Data (port 50002)

**Server → Client**: 664-byte body containing a 24-byte inner header followed by 640 bytes of *interleaved stereo* Int16 LE PCM audio at 16 kHz (160 frames = 10 ms per packet, ~100 fps on the wire). Channel 0 carries speaker audio; channel 1 is near-silent (TX monitor / sub-RX). Layout verified against a live FTDX101MP capture:

| Byte(s) | LE value | Meaning |
|---------|----------|---------|
| 0 | — | `frame_seq` (wraps at 0xFF) |
| 1–3 | `00 01 02` | codec/format ID; byte 2 likely "PCM Int16 LE", byte 3 = channels |
| 4–7 | `0x3E80` | sample rate (16000), padded to u32 |
| 8–15 | zero | reserved |
| 16–17 | `0x07D0` | 2000 (buffer-related parameter) |
| 18–19 | `0x03E8` | 1000 (buffer-related parameter) |
| 20–21 | `0x6464` | levels: 100 / 100 |
| 22–23 | `0x0280` | audio payload byte count (640) |
| 24–663 | — | 160 stereo frames of `[Ch0_lo Ch0_hi Ch1_lo Ch1_hi]` Int16 LE |

**Client → Server**: 668-byte body (microphone audio). Only sent when transmitting.

### Scope/Waterfall Data (port 50003)

**Server → Client**: 4096-byte body. Each byte represents the amplitude of one frequency bin in the spectrum. The data covers the radio's current scope range.

```
Amplitude encoding:
  255 = weakest signal (noise floor)
  0   = strongest signal
  Invert and normalize for display: magnitude = 1.0 - (raw / 255.0)
```

Active bins occupy the first N positions; remaining bytes are zero. The number of active bins depends on the radio's scope span setting.

## Reconnection

The server supports re-authentication while a previous session is still streaming. It assigns incrementing session IDs. The full 7-phase setup sequence is identical for every connection.

## Implementation Notes

- The key can be any random byte — the server extracts it from b5 and validates the other header bytes for consistency
- Init keepalive packets (phase 1) are completely hardcoded with fixed keys — these are identical across all FT-Control versions observed
- The auth packet also uses a fixed key (0x3A) and sequence (0x06)
- After auth, all packets should use dynamically generated headers with random keys
- Header bytes b6/b7 encode the body length — if these don't match the actual encrypted body size, the server may silently drop the packet
