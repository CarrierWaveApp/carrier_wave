# Icom RS-BA1 WiFi Protocol Reference

Byte-level specification for the UDP protocol used by the IC-705 (and IC-7610,
IC-9700, etc.) for WiFi CAT control. Reconstructed from
[kappanhang](https://github.com/nonoo/kappanhang) (Go),
[icom-lan](https://github.com/morozsm/icom-lan) (Python), and verified against
a live IC-705 trace.

## Overview

Three independent UDP streams, each on its own port:

| Port  | Name    | Purpose                            |
|-------|---------|------------------------------------|
| 50001 | Control | Login, auth, stream negotiation    |
| 50002 | Serial  | CI-V command tunneling             |
| 50003 | Audio   | PCM audio RX/TX (not implemented)  |

Each stream has its own connection handshake (pkt3/pkt4/pkt6), its own pkt0
sequence counter for reliable delivery, and its own pkt7 keepalive counter.

## Packet Header (16 bytes)

All packets share this header:

```
Offset  Size  Endian  Field
0-3     4     LE      Total packet length (only byte 0 matters for <256B)
4       1     —       Packet type
5       1     —       Subtype (usually 0x00)
6-7     2     LE      Sequence number
8-11    4     BE      Sender SID (local)
12-15   4     BE      Receiver SID (remote)
```

### Session ID Construction

`localSID` is constructed from the local IP address and port:

```
localSID = (ip_as_uint32 << 16) | (local_port & 0xFFFF)
```

`remoteSID` is extracted from the radio's pkt4 response (bytes 8-11).

## Packet Types

### Pkt3 — "Are You There?" (16 bytes)

```
[0]  = 0x10        Length
[4]  = 0x03        Type
[6-7]= 0x00,0x00   Fixed seq (not tracked)
[8-11]  localSID
[12-15] remoteSID   (0x00000000 on first send)
```

**Sent twice** (identical copies). All untracked control packets are sent twice
for redundancy.

### Pkt4 — "I Am Here" (16 bytes, radio → client)

```
[4]  = 0x04        Type
[8-11]  remoteSID   Radio's SID — store this
[12-15] localSID    Client's SID echoed back
```

### Pkt5 — Disconnect (16 bytes)

```
[4]  = 0x05        Type
[6-7]= 0x00,0x00   Fixed seq
```

Sent twice. kappanhang waits 500ms after disconnect for retransmit drain.

### Pkt6 — "Are You Ready?" (16 bytes)

```
[4]  = 0x06        Type
[6]  = 0x01        Fixed seq (not 0x00)
[7]  = 0x00
```

Sent twice. Radio echoes back with same prefix.

### Pkt7 — Ping/Keepalive (21 bytes)

```
[0]  = 0x15        Length (21)
[4]  = 0x07        Type
[6-7]  seq LE      Pkt7-specific counter (separate from pkt0)
[8-11]  localSID
[12-15] remoteSID
[16] = 0x00        Request (client→radio) or 0x01 (reply)
[17-20]            Reply ID (random + seq + 0x06)
```

| Stream  | Start seq | Interval | Timeout |
|---------|-----------|----------|---------|
| Control | 2         | 3s       | 3s      |
| Serial  | 1         | 3s       | 3s      |
| Audio   | 1         | 3s       | 3s      |

When receiving a pkt7 request from the radio (byte 0 = 0x00), reply with byte
16 = 0x01, echo back the reply ID and seq, swap the SIDs.

## Reliable Delivery (Pkt0)

The pkt0 system provides reliable delivery for "tracked" packets (login, auth,
connInfo, CI-V data, idle). Each stream has an independent pkt0 counter.

### How Tracked Sending Works

1. `pkt0.sendSeq` starts at **1** (initialized after connection setup).
2. `sendTrackedPacket(pkt)` **overwrites bytes 6-7** of the packet with
   `sendSeq` (LE), stores the complete packet in `txSeqBuf`, sends it, and
   increments `sendSeq`.
3. The caller does not need to set bytes 6-7 — they are always overwritten.

### Idle Pkt0 (16 bytes)

```
[0]  = 0x10        Length
[4]  = 0x00        Type
[6-7]  sendSeq LE  (filled by tracked send)
```

Idle packets are tracked (increment sendSeq, stored in txSeqBuf). Sent:
- Every 100ms after any tracked send.
- Every 1s if no tracked packet has been sent recently.
- Started after the first auth packet is sent.

### Retransmit Request (type 0x01)

**Single packet** (16 bytes):

```
[0]  = 0x10
[4]  = 0x01        Retransmit request
[6-7]  reqSeq LE   Sequence to retransmit
```

**Range request** (24+ bytes):

```
[0]  = 0x18+       Length
[4]  = 0x01
[16-17] startSeq LE
[18-19] endSeq LE
(additional 4-byte range pairs follow)
```

Both are sent twice. On receiving a retransmit request, look up the seq in
`txSeqBuf` and resend the original packet **twice**. If not found, send an idle
with that seq number (twice).

### Pkt0 Dispatch Priority

In the receive loop, packets are handled in this order:

1. **pkt7**: Handled and consumed (not forwarded to application).
2. **pkt0 (idle/retransmit)**: Handled, then forwarded.
3. **Everything else**: Forwarded to application.

## Data Sub-Header (bytes 16+)

Tracked DATA packets (login, auth, connInfo) share a sub-header starting at
byte 16:

```
Offset  Size  Endian  Field
16-19   4     BE      Payload size = total_length - 16
20      1     —       Direction: 0x01=client→radio, 0x02=radio→client
21      1     —       Request type (see below)
22      1     —       0x00
23      1     —       authInnerSeq low byte
24      1     —       authInnerSeq high byte
25      1     —       0x00
26-27   2     —       Token/auth start ID
```

**Request types** (byte 21):

| Value | Meaning              |
|-------|----------------------|
| 0x00  | Login                |
| 0x01  | Deauthenticate       |
| 0x02  | Token ACK (1st auth) |
| 0x03  | ConnInfo             |
| 0x05  | Reauth / Token renew |

**authInnerSeq** is a separate counter (starts at 0) shared across login, auth,
and connInfo sends. It increments with each send.

## Control Stream — Full Handshake

Port 50001. The following sequence is mandatory and strict-order.

### Step 1: Connection Setup

```
Client: pkt3 x2  (remoteSID = 0)
Radio:  pkt4      (extract remoteSID from bytes 8-11)
Client: pkt6 x2
Radio:  pkt6 echo
```

### Step 2: Initialize Pkt0

Set `pkt0.sendSeq = 1`. All subsequent tracked packets use this counter.

### Step 3: Login (128 bytes, 0x80)

```
Offset  Value           Field
0       0x80            Total length (128)
6-7     sendSeq LE      Filled by tracked send (seq=1)
8-11    localSID BE
12-15   remoteSID BE
16-19   0x00000070 BE   Payload size (128-16=112=0x70)
20      0x01            Direction (client)
21      0x00            Request type (login)
23      authInnerSeq    Low byte (starts at 0)
24      authInnerSeq>>8 High byte
26-27   random 2 bytes  Auth start ID
64-79   passcode(username)
80-95   passcode(password)
96-103  "icom-cw\0"     Client identifier
```

### Step 4: Login Response (96 bytes, 0x60, radio → client)

```
0       0x60            Total length (96)
8-11    remoteSID
12-15   localSID
26-31   authID          6-byte auth token (first 2 bytes match auth start ID)
48-51   status          0xFFFFFFFE = bad credentials; 0x00000000 = OK
64+     connection type "FTTH", "WFVIEW", etc. (null-terminated)
```

If bytes 48-51 = `FF FF FF FE`, authentication failed — wrong username/password.

### Step 5: Start Pkt7

Start pkt7 keepalives on the control stream (first seq = 2).

### Step 6: First Auth (64 bytes, 0x40)

```
Offset  Value           Field
0       0x40            Total length (64)
6-7     sendSeq LE      Tracked send
8-15    SIDs
16-19   0x00000030 BE   Payload size (64-16=48=0x30)
20      0x01            Direction (client)
21      0x02            Request type (first auth)
23-24   authInnerSeq    (now = 1)
26-31   authID          From login response
```

### Step 7: Start Pkt0 Periodic Idle

Begin sending idle pkt0 packets periodically.

### Step 8: Second Auth (64 bytes, 0x40)

Same as Step 6 but byte 21 = `0x05` (reauth). authInnerSeq = 2.

### Step 9: Async — Wait for 0xA8 and Auth Confirm

Two things arrive asynchronously (either order):

**Auth confirm** (64 bytes, 0x40, radio → client):
- Byte 20 = 0x02 (radio direction)
- Byte 21 = 0x05 → auth is confirmed (`authOk = true`)

**0xA8 metadata** (168 bytes, radio → client):
- Bytes 66-81: `a8replyID` (16 bytes) — **must be stored**
- Bytes 82+: radio name (e.g. "X-IC-705"), audio driver name

Once **both** `authOk` AND `a8replyID` are received, proceed to Step 10.

### Step 10: ConnInfo Request (144 bytes, 0x90)

```
Offset  Value               Field
0       0x90                Total length (144)
6-7     sendSeq LE          Tracked send
8-15    SIDs
16-19   0x00000080 BE       Payload size (144-16=128=0x80)
20      0x01                Direction (client)
21      0x03                Request type (conninfo)
23-24   authInnerSeq        (now = 3)
26-31   authID
32-47   a8replyID           16 bytes from 0xA8 response
48-63   zeros
64-71   "IC-705\0\0"        Radio name (null-padded to 32 bytes)
72-95   zeros
96-111  passcode(username)
112     0x01                RX enable
113     0x01                TX enable
114     0x04                RX codec (PCM 1ch 16-bit)
115     0x04                TX codec
116-117 0x0000
118-119 sample rate BE      e.g. 0xBB80 (48000) or 0x2EE0 (12000)
120-121 0x0000
122-123 sample rate BE      (repeated)
124-125 0x0000
126-127 serial port BE      0xC352 (50002)
128-129 0x0000
130-131 audio port BE       0xC353 (50003)
132-133 0x0000
134-135 TX buf length ms BE e.g. 0x012C (300)
136     0x01
137-143 zeros
```

### Step 11: ConnInfo Response (144 bytes, 0x90, radio → client)

```
8-11    new remoteSID       Client MUST update
12-15   new localSID        Client MUST update
26-31   new authID          Client MUST update
64-95   device name         Null-terminated (e.g. "IC-705")
96      0x01                Success flag (MUST be 1)
100+    "icom-cw\0"         Client name echoed back
```

After receiving this response, update `remoteSID`, `localSID`, and `authID`.
Then open the serial and audio streams.

### Step 12: Periodic Reauth

Every **60 seconds**, send auth with magic = 0x05 (same as Step 8). 3-second
timeout for response. On timeout: warning only (non-fatal).

### Disconnect

```
1. Send auth with magic = 0x01 (deauthenticate)
2. Wait 500ms for retransmit drain
3. Send pkt5 x2
```

## Status Packet (80 bytes, 0x50, radio → client)

```
48-50   0xFF,0xFF,0xFF      Auth failure
48-50   0x00,0x00,0x00 + byte 64 = 0x01  Radio disconnected
```

## Serial Stream (Port 50002)

After the control stream grants access (0x90 connInfo response), open the
serial stream:

### Connection Setup

Same as control: pkt3 x2 → pkt4 → pkt6 x2 → pkt6 ack.

Initialize pkt0 (sendSeq=1), start pkt7 (seq=1), start periodic idle.

### Open Command (22 bytes, 0x16)

```
Offset  Value           Field
0       0x16            Total length (22)
6-7     sendSeq LE      Tracked send
8-15    SIDs
16      0xC0            Serial control marker
17      0x01            Payload length (1 byte)
18      0x00
19-20   civDataSeq BE   Serial-specific sequence (starts at 0)
21      0x05            Open magic
```

Close: same packet but byte 21 = `0x00`.

> **Critical**: Byte 16 must be `0xC0` (control) for open/close. `0xC1` is the
> data marker — using it for open will be silently ignored.

### CI-V Data Packet (21+N bytes)

```
Offset  Value           Field
0       21+N            Total length
6-7     sendSeq LE      Tracked send (pkt0 seq)
8-15    SIDs
16      0xC1            Serial data marker
17      N               CI-V payload length
18      0x00
19-20   civDataSeq BE   Serial-specific sequence
21+     N bytes         Raw CI-V frame
```

### Receiving CI-V Data

Identify by `byte[16] == 0xC1`. Validate: `byte[0] - 0x15 == byte[17]`
(total length minus header = payload length). Extract CI-V payload from byte 21.

### Sequence Counters (Serial Stream)

The serial stream has **two independent** sequence counters:

| Counter      | Location  | Start | Purpose              |
|-------------|-----------|-------|----------------------|
| pkt0.sendSeq| bytes 6-7 LE | 1  | Reliable delivery    |
| civDataSeq  | bytes 19-20 BE| 0  | CI-V frame ordering  |

Both increment independently. `pkt0.sendSeq` is shared with idle/open/close
packets. `civDataSeq` only increments with CI-V data sends and open/close.

## CI-V Frame Format

```
FE FE <to> <from> <cmd> [<subcmd>] [<data...>] FD
```

| Field      | Value |
|------------|-------|
| Preamble   | `FE FE` (some radios send >2 preamble bytes) |
| Controller | `0xE0` |
| IC-705     | `0xA4` |
| Terminator | `0xFD` |
| ACK        | cmd = `0xFB` |
| NAK        | cmd = `0xFA` |

### Common Commands

| Command     | Purpose                |
|-------------|------------------------|
| `0x03`      | Read frequency         |
| `0x04`      | Read mode              |
| `0x05` + 5B | Set frequency (BCD)   |
| `0x06` + 1B | Set mode              |
| `0x15 0x02` | Read S-meter           |
| `0x19 0x00` | Read radio ID          |
| `0x1C 0x00` | PTT control            |
| `0x17`      | Send CW text           |
| `0x17 0xFF` | Abort CW               |

### BCD Frequency Encoding

5-byte BCD, LSB first, 1 Hz resolution:

```
14.100.000 MHz = 00 00 10 41 00
 7.074.000 MHz = 00 40 07 07 00
```

Each byte encodes two BCD digits: low nibble first.

### Mode Bytes

| Byte | Mode   |
|------|--------|
| 0x00 | LSB    |
| 0x01 | USB    |
| 0x02 | AM     |
| 0x03 | CW     |
| 0x04 | RTTY   |
| 0x05 | FM     |
| 0x06 | WFM    |
| 0x07 | CW-R   |
| 0x08 | RTTY-R |

## Passcode Encoding

Credentials are obfuscated via a position-dependent substitution cipher:

```
for i in 0..<min(len(input), 16):
    p = ASCII(input[i]) + i
    if p > 126: p = 32 + (p % 127)
    output[i] = LOOKUP_TABLE[p]
// Remaining bytes zero-padded to 16
```

The lookup table (95 entries, mapping ASCII 32-126) is identical across all
implementations — derived from kappanhang `passcode.go`.

## Sequence Counter Summary

| Counter          | Scope        | Start | Encoding  | Purpose              |
|-----------------|--------------|-------|-----------|----------------------|
| pkt0.sendSeq    | Per stream   | 1     | LE @ 6-7  | Reliable delivery    |
| pkt7.sendSeq    | Per stream   | 1 or 2| LE @ 6-7  | Keepalive            |
| authInnerSeq    | Control only | 0     | LE @ 23-24| Login/auth/connInfo  |
| civDataSeq      | Serial only  | 0     | BE @ 19-20| CI-V frame ordering  |

These are all independent. pkt3/pkt6/pkt5 use **fixed** sequence values (not
any counter).

## Timing Summary

| Mechanism              | Interval   | Timeout    |
|------------------------|------------|------------|
| Pkt7 ping (client)     | 3 seconds  | 3 seconds  |
| Pkt0 idle (active)     | 100ms      | —          |
| Pkt0 idle (quiescent)  | 1 second   | —          |
| Missed keepalive limit | 3 misses   | ~9 seconds |
| Reauth                 | 60 seconds | 3 seconds  |
| ConnInfo timeout       | 5 seconds  | Fatal      |
| Reconnect cooldown     | 65 seconds | IC-705 specific |

## IC-705 AP Mode

### Radio Setup

All settings are under `MENU » SET > WLAN Set`:

| Setting | Path | Value |
|---------|------|-------|
| Enable WiFi | WLAN | ON |
| Enable remote control | Remote Settings > Network Control | ON |
| Set credentials | Remote Settings > Network User1 | username + password |
| AP mode | Connection Settings > Access Point | (select) |
| Network name (SSID) | Network Name | (your SSID) |

### AP Mode Details

In Access Point mode, the IC-705 broadcasts its own 2.4 GHz WiFi network:
- Default IP: `192.168.59.1`
- The client joins the radio's WiFi and connects to `192.168.59.1:50001`

In Station mode, the radio joins an existing WiFi network. Find the radio's IP
via `MENU » SET > WLAN Set > Connection Settings > DHCP`.

### AP Mode Protocol Differences

The IC-705 may send a short 16-byte type-0x02 login confirmation instead of the
full 96-byte 0x60 response. In this case, skip the auth challenge and 0xA8/0x90
exchange — go directly to opening the CI-V stream.

### Known Quirks

The IC-705's network stack has known bugs (per kappanhang). A 65-second cooldown
between reconnection attempts is recommended to avoid the radio killing the
audio stream. The radio cannot connect to 5 GHz networks.

## References

- [kappanhang](https://github.com/nonoo/kappanhang) — Go, most detailed
- [icom-lan](https://github.com/morozsm/icom-lan) — Python, second reference
- [wfview](https://gitlab.com/eliggett/wfview) — C++ (udphandler.cpp)
- [rs-ba1-rev-engineering group](https://groups.io/g/rs-ba1-rev-engineering)
