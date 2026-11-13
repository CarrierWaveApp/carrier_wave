#!/usr/bin/env python3
"""
IC-705 WiFi Protocol Diagnostic Tool v3.1
==========================================
Connects to an Icom IC-705 (or similar) over WiFi using the RS-BA1 UDP protocol,
captures the full handshake and CI-V exchange, and dumps diagnostic information.

Protocol reconstructed from kappanhang (Go) and icom-lan (Python) reference
implementations with byte-level verification.

No external dependencies — uses only Python standard library.

Usage:
    python3 ic705_diag.py [--ip 192.168.59.1] --user <username> --pass <password>

Prerequisites:
    1. Enable WiFi: MENU > SET > WLAN Set > WLAN > ON
    2. Enable remote control: MENU > SET > WLAN Set > Remote Settings >
       Network Control > ON
    3. Set credentials: MENU > SET > WLAN Set > Remote Settings >
       Network User1 > set username and password
    4. For AP mode: MENU > SET > WLAN Set > Connection Settings >
       select "Access Point"
       For Station mode: connect radio to your WiFi network via
       Connection Settings > Access Point
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import platform
import select
import socket
import struct
import sys
import textwrap
import time
import traceback

# ─── RS-BA1 Protocol Constants ───────────────────────────────────────────────

CONTROL_PORT = 50001
SERIAL_PORT = 50002
AUDIO_PORT = 50003

# CI-V constants
CIV_PREAMBLE = 0xFE
CIV_TERMINATOR = 0xFD
CIV_CONTROLLER = 0xE0
IC705_ADDR = 0xA4

CIV_READ_FREQ = 0x03
CIV_READ_MODE = 0x04
CIV_ACK = 0xFB
CIV_NAK = 0xFA

CIV_MODES = {
    0x00: "LSB", 0x01: "USB", 0x02: "AM", 0x03: "CW",
    0x04: "RTTY", 0x05: "FM", 0x06: "WFM", 0x07: "CW-R", 0x08: "RTTY-R",
}

# ─── Passcode Encoding ──────────────────────────────────────────────────────

PASSCODE_TABLE = {
    32: 0x47, 33: 0x5D, 34: 0x4C, 35: 0x42, 36: 0x66,
    37: 0x20, 38: 0x23, 39: 0x46, 40: 0x4E, 41: 0x57,
    42: 0x45, 43: 0x3D, 44: 0x67, 45: 0x76, 46: 0x60,
    47: 0x41, 48: 0x62, 49: 0x39, 50: 0x59, 51: 0x2D,
    52: 0x68, 53: 0x7E, 54: 0x7C, 55: 0x65, 56: 0x7D,
    57: 0x49, 58: 0x29, 59: 0x72, 60: 0x73, 61: 0x78,
    62: 0x21, 63: 0x6E, 64: 0x5A, 65: 0x5E, 66: 0x4A,
    67: 0x3E, 68: 0x71, 69: 0x2C, 70: 0x2A, 71: 0x54,
    72: 0x3C, 73: 0x3A, 74: 0x63, 75: 0x4F, 76: 0x43,
    77: 0x75, 78: 0x27, 79: 0x79, 80: 0x5B, 81: 0x35,
    82: 0x70, 83: 0x48, 84: 0x6B, 85: 0x56, 86: 0x6F,
    87: 0x34, 88: 0x32, 89: 0x6C, 90: 0x30, 91: 0x61,
    92: 0x6D, 93: 0x7B, 94: 0x2F, 95: 0x4B, 96: 0x64,
    97: 0x38, 98: 0x2B, 99: 0x2E, 100: 0x50, 101: 0x40,
    102: 0x3F, 103: 0x55, 104: 0x33, 105: 0x37, 106: 0x25,
    107: 0x77, 108: 0x24, 109: 0x26, 110: 0x74, 111: 0x6A,
    112: 0x28, 113: 0x53, 114: 0x4D, 115: 0x69, 116: 0x22,
    117: 0x5C, 118: 0x44, 119: 0x31, 120: 0x36, 121: 0x58,
    122: 0x3B, 123: 0x7A, 124: 0x51, 125: 0x5F, 126: 0x52,
}


def encode_passcode(text: str) -> bytes:
    """RS-BA1 passcode substitution cipher (position-dependent)."""
    result = bytearray(16)
    for idx, ch in enumerate(text[:16]):
        pos = ord(ch) + idx
        if pos > 126:
            pos = 32 + (pos % 127)
        result[idx] = PASSCODE_TABLE.get(pos, 0)
    return bytes(result)


# ─── Binary Helpers ──────────────────────────────────────────────────────────

def w32be(buf: bytearray, off: int, val: int) -> None:
    struct.pack_into(">I", buf, off, val)


def r32be(data: bytes, off: int) -> int:
    return struct.unpack_from(">I", data, off)[0]


def w16le(buf: bytearray, off: int, val: int) -> None:
    struct.pack_into("<H", buf, off, val)


def r16le(data: bytes, off: int) -> int:
    return struct.unpack_from("<H", data, off)[0]


def w16be(buf: bytearray, off: int, val: int) -> None:
    struct.pack_into(">H", buf, off, val)


def hex_dump(data: bytes, prefix: str = "  ") -> str:
    lines = []
    for i in range(0, len(data), 16):
        chunk = data[i:i + 16]
        hx = " ".join(f"{b:02X}" for b in chunk)
        asc = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        lines.append(f"{prefix}{i:04X}  {hx:<48s}  {asc}")
    return "\n".join(lines)


def parse_bcd_freq(data: bytes) -> int | None:
    if len(data) < 5:
        return None
    freq = 0
    mult = 1
    for i in range(5):
        lo = data[i] & 0x0F
        hi = (data[i] >> 4) & 0x0F
        if lo > 9 or hi > 9:
            return None
        freq += lo * mult
        mult *= 10
        freq += hi * mult
        mult *= 10
    return freq


def format_freq(hz: int) -> str:
    mhz = hz / 1_000_000
    return f"{mhz:.3f} MHz" if hz % 1000 == 0 else f"{mhz:.6f} MHz"


# ─── Diagnostic Logger ───────────────────────────────────────────────────────

class DiagLog:
    def __init__(self):
        self.entries: list[dict] = []
        self.start_time = time.monotonic()
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def log(self, direction: str, label: str, data: bytes | None = None,
            detail: str = "") -> None:
        elapsed = time.monotonic() - self.start_time
        entry = {"time": f"{elapsed:.3f}s", "dir": direction, "label": label,
                 "size": len(data) if data else 0, "detail": detail}
        if data:
            entry["hex"] = data.hex()
        self.entries.append(entry)
        arrow = {"TX": ">>>", "RX": "<<<", "--": "---"}.get(direction, "   ")
        sz = f"({len(data)}B)" if data else ""
        det = f" — {detail}" if detail else ""
        print(f"  [{elapsed:7.3f}s] {arrow} {label} {sz}{det}")
        if data and len(data) <= 256:
            print(hex_dump(data))

    def error(self, msg: str) -> None:
        self.errors.append(msg)
        print(f"  [ERROR] {msg}")

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)
        print(f"  [WARN]  {msg}")

    def info(self, msg: str) -> None:
        print(f"  [INFO]  {msg}")


# ─── UDP Socket ──────────────────────────────────────────────────────────────

class UDPSock:
    def __init__(self, host: str, port: int):
        self.host = host
        self.port = port
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setblocking(False)
        # kappanhang: DialUDP binds local port = remote port
        try:
            self.sock.bind(("", port))
        except OSError:
            self.sock.bind(("", 0))
        self.local_port = self.sock.getsockname()[1]

    def send(self, data: bytes | bytearray) -> None:
        self.sock.sendto(bytes(data), (self.host, self.port))

    def recv(self, timeout: float = 3.0) -> bytes | None:
        ready, _, _ = select.select([self.sock], [], [], timeout)
        if ready:
            data, _ = self.sock.recvfrom(8192)
            return data
        return None

    def recv_all(self, timeout: float = 1.0) -> list[bytes]:
        packets = []
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            ready, _, _ = select.select([self.sock], [], [], min(remaining, 0.1))
            if ready:
                data, _ = self.sock.recvfrom(8192)
                packets.append(data)
            elif packets:
                break
        return packets

    def drain(self, timeout: float = 0.3) -> list[bytes]:
        return self.recv_all(timeout=timeout)

    def close(self) -> None:
        self.sock.close()


# ─── Protocol Engine ─────────────────────────────────────────────────────────
#
# Packet header (all packets, 16 bytes):
#   [0-3]   Total length (LE uint32, but <256 so only byte 0 matters)
#   [4]     Packet type (0x00=data, 0x01=retransmit, 0x03=AYT, 0x04=IAH,
#                         0x05=disconnect, 0x06=AYR, 0x07=ping)
#   [5]     Subtype (usually 0x00)
#   [6-7]   Sequence (LE uint16)
#   [8-11]  Sender SID (BE uint32)
#   [12-15] Receiver SID (BE uint32)
#
# Data sub-header (tracked packets: login, auth, connInfo — bytes 16+):
#   [16-19] Payload size (BE uint32) = total_length - 16
#   [20]    Direction: 0x01=client, 0x02=radio, 0x03=conninfo
#   [21]    Request type: 0x00=login, 0x02=token_ack(auth), 0x03=conninfo,
#                          0x01=deauth, 0x05=reauth
#   [22]    0x00
#   [23]    authInnerSeq low byte
#   [24]    authInnerSeq high byte
#   [25]    0x00
#   [26-27] Token request ID / random (LE)
#
# ─────────────────────────────────────────────────────────────────────────────

class IC705Diag:
    def __init__(self, ip: str, username: str, password: str):
        self.ip = ip
        self.username = username
        self.password = password
        self.log = DiagLog()

        self.local_sid = 0
        self.remote_sid = 0
        # CIV port has its OWN remoteSID from its own pkt3/pkt4 exchange
        self.civ_remote_sid = 0
        # Tracked packet seq (pkt0.sendSeq) — starts at 1 per kappanhang
        self.tracked_seq = 1
        # Separate pkt7 seq
        self.ping_seq = 2  # kappanhang: control stream pkt7 starts at 2
        # CI-V tracked seq (separate stream)
        self.civ_tracked_seq = 1
        # CI-V inner data seq (serial sendSeq, BE at bytes 19-20)
        self.civ_data_seq = 0
        # Auth inner seq (shared across login/auth/connInfo)
        self.auth_inner_seq = 0
        self.auth_id = b"\x00" * 6
        self.a8_reply_id = b"\x00" * 16
        # Auth confirmed flag
        self.auth_ok = False

        # TX buffer for retransmit: seq -> packet bytes
        self.tx_buf: dict[int, bytes] = {}

        self.ctrl: UDPSock | None = None
        self.civ: UDPSock | None = None

    # ── Tracked send ──

    def _send_tracked(self, sock: UDPSock, pkt: bytearray,
                      is_civ: bool = False) -> None:
        """Send a tracked packet: overwrite bytes 6-7 with seq, store in tx_buf."""
        if is_civ:
            seq = self.civ_tracked_seq
            self.civ_tracked_seq += 1
        else:
            seq = self.tracked_seq
            self.tracked_seq += 1
        w16le(pkt, 6, seq)
        stored = bytes(pkt)
        self.tx_buf[seq] = stored
        sock.send(stored)

    # ── Packet builders ──
    # Each matches kappanhang source byte-for-byte.

    def _pkt3(self) -> bytearray:
        """ARE_YOU_THERE — 16 bytes, fixed seq 0x0000."""
        p = bytearray(16)
        p[0] = 0x10; p[4] = 0x03
        # bytes 6-7 = 0x0000 (fixed, not tracked)
        w32be(p, 8, self.local_sid)
        w32be(p, 12, self.remote_sid)
        return p

    def _pkt4_remote_sid(self, resp: bytes) -> int:
        """Extract remote SID from pkt4 response (bytes 8-11)."""
        return r32be(resp, 8)

    def _pkt5(self) -> bytearray:
        """DISCONNECT — 16 bytes, fixed seq 0x0000. Sent twice."""
        p = bytearray(16)
        p[0] = 0x10; p[4] = 0x05
        w32be(p, 8, self.local_sid)
        w32be(p, 12, self.remote_sid)
        return p

    def _pkt6(self) -> bytearray:
        """ARE_YOU_READY — 16 bytes, fixed seq 0x0001."""
        p = bytearray(16)
        p[0] = 0x10; p[4] = 0x06; p[6] = 0x01
        w32be(p, 8, self.local_sid)
        w32be(p, 12, self.remote_sid)
        return p

    def _pkt7(self) -> bytearray:
        """PING — 21 bytes, own seq counter."""
        p = bytearray(21)
        p[0] = 0x15; p[4] = 0x07
        seq = self.ping_seq
        self.ping_seq += 1
        w16le(p, 6, seq)
        w32be(p, 8, self.local_sid)
        w32be(p, 12, self.remote_sid)
        p[16] = 0x00  # request
        p[17] = os.urandom(1)[0]
        p[18] = seq & 0xFF
        p[19] = (seq >> 8) & 0xFF
        p[20] = 0x06
        return p

    def _idle(self) -> bytearray:
        """Idle pkt0 — 16 bytes, tracked seq. Type 0x00."""
        p = bytearray(16)
        p[0] = 0x10
        # bytes 6-7 filled by _send_tracked
        w32be(p, 8, self.local_sid)
        w32be(p, 12, self.remote_sid)
        return p

    def _civ_idle(self) -> bytearray:
        """Idle pkt0 on CIV port — 16 bytes, CIV tracked seq."""
        p = bytearray(16)
        p[0] = 0x10
        w32be(p, 8, self.local_sid)
        w32be(p, 12, self.civ_remote_sid)
        return p

    def _login(self) -> bytearray:
        """Login — 128 bytes (0x80). Tracked.
        Verified against kappanhang controlstream.go sendPktLogin() and
        icom-lan _control.py LoginPacket.
        """
        auth_start = os.urandom(2)
        p = bytearray(128)
        p[0] = 0x80  # total length
        # [4-5] = 0x00 (DATA type)
        # [6-7] filled by _send_tracked
        w32be(p, 8, self.local_sid)
        w32be(p, 12, self.remote_sid)
        # Data sub-header: payload size (BE) = 128 - 16 = 112 = 0x70
        p[19] = 0x70
        # Direction = 0x01 (client)
        p[20] = 0x01
        # Request type = 0x00 (login)
        # p[21] = 0x00  # already zero
        # Auth inner seq at bytes 23-24 (LE per kappanhang)
        p[23] = self.auth_inner_seq & 0xFF
        p[24] = (self.auth_inner_seq >> 8) & 0xFF
        self.auth_inner_seq += 1
        # Random auth start ID at bytes 26-27
        p[26] = auth_start[0]
        p[27] = auth_start[1]
        # Encoded credentials
        p[64:80] = encode_passcode(self.username)
        p[80:96] = encode_passcode(self.password)
        # Client name
        p[96:104] = b"icom-cw\x00"
        return p

    def _auth(self, magic: int) -> bytearray:
        """Auth — 64 bytes (0x40). Tracked.
        magic: 0x01=deauth, 0x02=first auth, 0x05=reauth.
        Verified against kappanhang controlstream.go sendPktAuth().
        """
        p = bytearray(64)
        p[0] = 0x40  # total length
        # [6-7] filled by _send_tracked
        w32be(p, 8, self.local_sid)
        w32be(p, 12, self.remote_sid)
        # Payload size (BE) = 64 - 16 = 48 = 0x30
        p[19] = 0x30
        # Direction = 0x01
        p[20] = 0x01
        # Magic (0x02 or 0x05)
        p[21] = magic
        # Auth inner seq at 23-24
        p[23] = self.auth_inner_seq & 0xFF
        p[24] = (self.auth_inner_seq >> 8) & 0xFF
        self.auth_inner_seq += 1
        # AuthID at 26-31
        p[26:32] = self.auth_id[:6]
        return p

    def _conn_info(self) -> bytearray:
        """ConnInfo — 144 bytes (0x90). Tracked.
        Verified against kappanhang controlstream.go sendRequestSerialAndAudio().
        Byte-for-byte match with Go source literal.
        """
        p = bytearray(144)
        p[0] = 0x90  # total length = 144
        # [6-7] filled by _send_tracked
        w32be(p, 8, self.local_sid)
        w32be(p, 12, self.remote_sid)
        # Payload size (BE) = 144 - 16 = 128 = 0x80
        p[19] = 0x80
        # Direction = 0x01, request type = 0x03 (conninfo)
        p[20] = 0x01
        p[21] = 0x03
        # Auth inner seq at 23-24
        p[23] = self.auth_inner_seq & 0xFF
        p[24] = (self.auth_inner_seq >> 8) & 0xFF
        self.auth_inner_seq += 1
        # AuthID at 26-31
        p[26:32] = self.auth_id[:6]
        # a8replyID at 32-47
        p[32:48] = self.a8_reply_id[:16]
        # Padding 48-63 (zeros)
        # Radio name at 64-95 ("IC-705" null-padded to 32)
        p[64:72] = b"IC-705\x00\x00"
        # Encoded username at 96-111
        p[96:112] = encode_passcode(self.username)
        # Audio: RX enable, TX enable, RX codec, TX codec
        p[112] = 0x01  # RX enable
        p[113] = 0x01  # TX enable
        p[114] = 0x04  # RX codec (PCM 1ch 16-bit)
        p[115] = 0x04  # TX codec
        # Sample rate (48000 = 0xBB80) at 118-119 and 122-123 (BE)
        # Bytes 116-117 = 0x0000
        w16be(p, 118, 48000)
        # Bytes 120-121 = 0x0000
        w16be(p, 122, 48000)
        # Bytes 124-125 = 0x0000
        w16be(p, 126, SERIAL_PORT)  # serial port (BE)
        # Bytes 128-129 = 0x0000
        w16be(p, 130, AUDIO_PORT)  # audio port (BE)
        # Bytes 132-133 = 0x0000
        w16be(p, 134, 300)  # TX buffer length ms
        p[136] = 0x01
        # 137-143 = zeros
        return p

    def _civ_open(self) -> bytearray:
        """CIV stream open — 22 bytes (0x16). Tracked on CIV port.
        Uses civ_remote_sid (from CIV port's own pkt4), NOT control port's.
        """
        p = bytearray(22)
        p[0] = 0x16  # total length = 22
        # [6-7] filled by _send_tracked(is_civ=True)
        w32be(p, 8, self.local_sid)
        w32be(p, 12, self.civ_remote_sid)
        p[16] = 0xC0  # serial control marker
        p[17] = 0x01  # payload length (1 byte of magic follows)
        # p[18] = 0x00
        # Serial data seq at 19-20 (BE)
        p[19] = (self.civ_data_seq >> 8) & 0xFF
        p[20] = self.civ_data_seq & 0xFF
        self.civ_data_seq += 1
        p[21] = 0x05  # open magic
        return p

    def _civ_close(self) -> bytearray:
        """CIV stream close — 22 bytes. Same as open but magic=0x00."""
        p = bytearray(22)
        p[0] = 0x16
        w32be(p, 8, self.local_sid)
        w32be(p, 12, self.civ_remote_sid)
        p[16] = 0xC0
        p[17] = 0x01
        p[19] = (self.civ_data_seq >> 8) & 0xFF
        p[20] = self.civ_data_seq & 0xFF
        self.civ_data_seq += 1
        p[21] = 0x00  # close magic
        return p

    def _civ_data(self, payload: bytes) -> bytearray:
        """CIV data packet — (21+N) bytes. Tracked on CIV port."""
        total = 21 + len(payload)
        p = bytearray(total)
        p[0] = total & 0xFF
        # [6-7] filled by _send_tracked(is_civ=True)
        w32be(p, 8, self.local_sid)
        w32be(p, 12, self.civ_remote_sid)
        p[16] = 0xC1  # serial data marker
        p[17] = len(payload) & 0xFF
        # p[18] = 0x00
        p[19] = (self.civ_data_seq >> 8) & 0xFF
        p[20] = self.civ_data_seq & 0xFF
        self.civ_data_seq += 1
        p[21:] = payload
        return p

    def _civ_frame(self, cmd: int, data: list[int] | None = None) -> bytes:
        frame = [CIV_PREAMBLE, CIV_PREAMBLE, IC705_ADDR, CIV_CONTROLLER, cmd]
        if data:
            frame.extend(data)
        frame.append(CIV_TERMINATOR)
        return bytes(frame)

    # ── Receive helpers ──

    def _handle_retransmit(self, pkt: bytes, sock: UDPSock) -> None:
        """Handle a retransmit request from the radio (type 0x01)."""
        if len(pkt) == 16:
            # Single seq retransmit
            req_seq = r16le(pkt, 6)
            if req_seq in self.tx_buf:
                self.log.log("--", f"retransmit req seq={req_seq}: resending original x2")
                sock.send(self.tx_buf[req_seq])
                sock.send(self.tx_buf[req_seq])
            else:
                # Send idle with that seq (kappanhang fallback)
                idle = bytearray(16)
                idle[0] = 0x10
                w16le(idle, 6, req_seq)
                w32be(idle, 8, self.local_sid)
                w32be(idle, 12, self.remote_sid)
                self.log.log("--", f"retransmit req seq={req_seq}: no buffer, idle x2")
                sock.send(idle)
                sock.send(idle)
        elif len(pkt) >= 20:
            # Range retransmit — handle each pair
            for off in range(16, len(pkt), 4):
                if off + 3 >= len(pkt):
                    break
                start = r16le(pkt, off)
                end = r16le(pkt, off + 2)
                for seq in range(start, end + 1):
                    if seq in self.tx_buf:
                        sock.send(self.tx_buf[seq])
                        sock.send(self.tx_buf[seq])

    def _handle_pkt7(self, pkt: bytes, sock: UDPSock) -> None:
        """Reply to a pkt7 ping from the radio."""
        if len(pkt) < 21:
            return
        reply = bytearray(pkt)
        reply[0] = 0x00  # kappanhang: radio requests have byte 0 = 0x00
        reply[16] = 0x01  # reply flag
        # Swap SIDs
        w32be(reply, 8, self.local_sid)
        w32be(reply, 12, self.remote_sid)
        sock.send(reply)

    def _is_pkt7(self, pkt: bytes) -> bool:
        return (len(pkt) == 21 and pkt[1:6] == b"\x00\x00\x00\x07\x00")

    def _is_pkt0(self, pkt: bytes) -> bool:
        if len(pkt) < 16:
            return False
        return (pkt[0:6] in (b"\x10\x00\x00\x00\x00\x00",
                             b"\x10\x00\x00\x00\x01\x00",
                             b"\x18\x00\x00\x00\x01\x00"))

    def _recv_ctrl(self, timeout: float = 5.0, min_size: int = 16,
                   accept_sizes: set[int] | None = None,
                   accept_headers: set[int] | None = None) -> bytes | None:
        """Receive from control, handling pkt7/pkt0 inline.
        accept_sizes: accept packet of exact size.
        accept_headers: accept packet with byte[0] in set.
        """
        deadline = time.monotonic() + timeout
        accept_sizes = accept_sizes or set()
        accept_headers = accept_headers or set()
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return None
            pkt = self.ctrl.recv(timeout=min(remaining, 0.5))
            if pkt is None:
                continue

            # Handle pkt7 (consume, don't return)
            if self._is_pkt7(pkt):
                self._handle_pkt7(pkt, self.ctrl)
                continue

            # Handle pkt0 retransmit requests
            if self._is_pkt0(pkt) and len(pkt) >= 16 and pkt[4] == 0x01:
                self._handle_retransmit(pkt, self.ctrl)
                continue

            # Skip idle pkt0
            if self._is_pkt0(pkt) and pkt[4] == 0x00:
                continue

            # Check accept criteria
            if accept_headers and pkt[0] in accept_headers:
                return pkt
            if accept_sizes and len(pkt) in accept_sizes:
                return pkt
            if len(pkt) >= min_size:
                return pkt

            self.log.log("RX", f"skip ({len(pkt)}B, hdr=0x{pkt[0]:02X})", pkt)

    # ── CI-V parsing ──

    def _extract_civ_frames(self, data: bytes) -> list[dict]:
        frames = []
        buf = list(data)
        pos = 0
        while pos < len(buf):
            start = None
            while pos + 1 < len(buf):
                if buf[pos] == CIV_PREAMBLE and buf[pos + 1] == CIV_PREAMBLE:
                    start = pos
                    while start + 2 < len(buf) and buf[start + 2] == CIV_PREAMBLE:
                        start += 1
                    break
                pos += 1
            if start is None:
                break
            if start + 5 >= len(buf):
                break
            try:
                end = buf.index(CIV_TERMINATOR, start + 4)
            except ValueError:
                break
            frames.append({
                "to": buf[start + 2], "from": buf[start + 3],
                "command": buf[start + 4],
                "data": bytes(buf[start + 5:end]),
                "raw": bytes(buf[start:end + 1]),
            })
            pos = end + 1
        return frames

    def _parse_civ_pkt(self, pkt: bytes) -> dict:
        parsed: dict = {"packet_size": len(pkt)}
        if len(pkt) < 22:
            parsed["error"] = "too short"
            return parsed
        marker = pkt[16]
        parsed["marker"] = f"0x{marker:02X}"
        if marker == 0xC1:
            parsed["payload_len"] = pkt[17]
            parsed["inner_seq"] = (pkt[19] << 8) | pkt[20]
            civ = pkt[21:]
            parsed["civ_raw"] = civ.hex()
            parsed["frames"] = []
            for fr in self._extract_civ_frames(civ):
                fd: dict = {
                    "to": f"0x{fr['to']:02X}", "from": f"0x{fr['from']:02X}",
                    "command": f"0x{fr['command']:02X}",
                    "data_hex": fr["data"].hex(), "raw_hex": fr["raw"].hex(),
                }
                if fr["command"] == CIV_ACK:
                    fd["type"] = "ACK"
                elif fr["command"] == CIV_NAK:
                    fd["type"] = "NAK"
                elif fr["command"] in (CIV_READ_FREQ, 0x05):
                    freq = parse_bcd_freq(fr["data"])
                    if freq is not None:
                        fd["frequency_hz"] = freq
                        fd["frequency"] = format_freq(freq)
                        parsed["frequency_hz"] = freq
                elif fr["command"] in (CIV_READ_MODE, 0x06):
                    if fr["data"]:
                        mb = fr["data"][0]
                        fd["mode"] = CIV_MODES.get(mb, f"0x{mb:02X}")
                        parsed["mode"] = fd["mode"]
                parsed["frames"].append(fd)
        elif marker == 0xC0:
            parsed["type"] = "control"
        return parsed

    # ── Main diagnostic sequence ──

    def run(self) -> dict:
        report = {
            "tool_version": "3.1.0",
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "system": {
                "os": platform.system(), "os_version": platform.version(),
                "python": platform.python_version(), "machine": platform.machine(),
            },
            "config": {"ip": self.ip, "username": self.username,
                       "password_length": len(self.password),
                       "control_port": CONTROL_PORT, "serial_port": SERIAL_PORT},
        }
        results = {}
        try:
            print("\n=== Phase 1: Network Reachability ===")
            results["reachability"] = self._phase_reachability()
            if not results["reachability"].get("ok"):
                report.update(results=results, log=self.log.entries,
                              errors=self.log.errors, warnings=self.log.warnings)
                return report

            print("\n=== Phase 2: Login ===")
            results["login"] = self._phase_login()
            if not results["login"].get("ok"):
                report.update(results=results, log=self.log.entries,
                              errors=self.log.errors, warnings=self.log.warnings)
                return report

            print("\n=== Phase 3: Auth Challenge ===")
            results["auth"] = self._phase_auth()

            print("\n=== Phase 4: Stream Negotiation (0xA8/0x90) ===")
            results["streams"] = self._phase_streams()

            print("\n=== Phase 5: CI-V Stream ===")
            results["civ"] = self._phase_civ_open()

            if results["civ"].get("ok"):
                print("\n=== Phase 6: CI-V Commands ===")
                results["civ_commands"] = self._phase_civ_commands()

            print("\n=== Phase 7: Keepalive ===")
            results["keepalive"] = self._phase_keepalive()

            print("\n=== Phase 8: Unsolicited (5s) ===")
            results["unsolicited"] = self._phase_unsolicited()

        except Exception as exc:
            self.log.error(f"Exception: {exc}")
            results["exception"] = {"type": type(exc).__name__,
                                     "message": str(exc),
                                     "traceback": traceback.format_exc()}
        finally:
            print("\n=== Cleanup ===")
            self._disconnect()

        report.update(results=results, log=self.log.entries,
                      errors=self.log.errors, warnings=self.log.warnings)
        return report

    def _phase_reachability(self) -> dict:
        result: dict = {"ip": self.ip, "ok": False}
        try:
            self.ctrl = UDPSock(self.ip, CONTROL_PORT)
            self.civ = UDPSock(self.ip, SERIAL_PORT)
            result["local_ctrl_port"] = self.ctrl.local_port
            result["local_civ_port"] = self.civ.local_port

            # Build localSID: (IP << 16) | port per kappanhang
            try:
                local_ip = socket.gethostbyname(socket.gethostname())
            except Exception:
                local_ip = "127.0.0.1"
            parts = local_ip.split(".")
            ip_int = (int(parts[0]) << 24 | int(parts[1]) << 16
                      | int(parts[2]) << 8 | int(parts[3]))
            self.local_sid = ((ip_int << 16) | (self.ctrl.local_port & 0xFFFF)) & 0xFFFFFFFF
            result["local_sid"] = f"0x{self.local_sid:08X}"
            self.log.info(f"Local SID: 0x{self.local_sid:08X} ({local_ip}:{self.ctrl.local_port})")

            # pkt3 x2 (kappanhang sends same packet twice)
            p3 = self._pkt3()
            self.log.log("TX", "pkt3 x2", bytes(p3))
            self.ctrl.send(p3)
            self.ctrl.send(p3)

            # Wait for pkt4
            resp = self.ctrl.recv(timeout=5.0)
            if resp and len(resp) >= 16 and resp[4] == 0x04:
                self.log.log("RX", f"pkt4 ({len(resp)}B)", resp)
                self.remote_sid = self._pkt4_remote_sid(resp)
                result["remote_sid"] = f"0x{self.remote_sid:08X}"
                result["ok"] = True
                self.log.info(f"Remote SID: 0x{self.remote_sid:08X}")
                self.ctrl.drain()
            else:
                self.log.error("No pkt4 response within 5s")
                if resp:
                    self.log.log("RX", f"unexpected ({len(resp)}B)", resp)

            # pkt6 x2
            if result["ok"]:
                p6 = self._pkt6()
                self.log.log("TX", "pkt6 x2", bytes(p6))
                self.ctrl.send(p6)
                self.ctrl.send(p6)
                # kappanhang: expect(16, [0x10,0x00,0x00,0x00,0x06,0x00,0x01,0x00])
                p6r = self._recv_ctrl(timeout=3.0, accept_sizes={16})
                if p6r and len(p6r) == 16 and p6r[4] == 0x06:
                    self.log.log("RX", f"pkt6 ack ({len(p6r)}B)", p6r)
                    result["pkt6_ok"] = True
                else:
                    self.log.warn("No pkt6 ack (continuing)")
                    result["pkt6_ok"] = False
                self.ctrl.drain()

        except OSError as exc:
            self.log.error(f"Socket error: {exc}")
            result["error"] = str(exc)
        return result

    def _phase_login(self) -> dict:
        result: dict = {"ok": False}

        login = self._login()
        self.log.log("TX", f"login ({len(login)}B)", bytes(login),
                      detail=f"user={self.username}")
        self._send_tracked(self.ctrl, login)

        # kappanhang: expect(96, [0x60,0x00,0x00,0x00,0x00,0x00,0x01,0x00])
        # Also accept short 16B type-0x02 (IC-705 AP mode) and 80B 0x50 (failure)
        resp = self._recv_ctrl(timeout=5.0, accept_sizes={96, 80, 16},
                                accept_headers={0x60, 0x50})
        if resp is None:
            self.log.error("No login response within 5 seconds")
            self.log.info("Radio silently dropped login — likely malformed packet")
            return result

        self.log.log("RX", f"login resp ({len(resp)}B, hdr=0x{resp[0]:02X})", resp)
        result["response_size"] = len(resp)
        result["response_header"] = f"0x{resp[0]:02X}"

        # Check 0x50 auth failure
        if resp[0] == 0x50 and len(resp) >= 51:
            if resp[48] == 0xFF and resp[49] == 0xFF and resp[50] == 0xFF:
                self.log.error("Auth failed (0x50 response, bytes 48-50 = FF FF FF)")
                result["auth_failed"] = True
                return result

        # Check 0x60 login success (96 bytes)
        if resp[0] == 0x60 and len(resp) == 96:
            # Check credential rejection
            if resp[48:52] == b"\xFF\xFF\xFF\xFE":
                self.log.error("Invalid username/password (bytes 48-51 = FFFFFFFE)")
                result["bad_credentials"] = True
                return result
            # Extract authID
            self.auth_id = bytes(resp[26:32])
            result["auth_id"] = self.auth_id.hex()
            result["auth_mode"] = "full_rsba1"
            result["ok"] = True
            self.log.info(f"Login OK — authID: {self.auth_id.hex()}")

            # Extract radio info from offset 64
            try:
                name = resp[64:80].split(b"\x00")[0].decode("ascii", errors="replace")
                if name:
                    result["connection_type"] = name
                    self.log.info(f"Connection type: {name}")
            except Exception:
                pass
            return result

        # Short 16B confirm (IC-705 AP mode)
        if len(resp) == 16 and resp[4] == 0x02:
            self.log.info("Short login confirm (IC-705 AP mode)")
            result["auth_mode"] = "ap_short"
            result["ok"] = True
            return result

        self.log.error(f"Unexpected login response: {len(resp)}B, hdr=0x{resp[0]:02X}")
        return result

    def _phase_auth(self) -> dict:
        result: dict = {"ok": False}

        # Auth(0x02) — first auth
        a1 = self._auth(0x02)
        self.log.log("TX", "auth(0x02)", bytes(a1))
        self._send_tracked(self.ctrl, a1)

        # Start pkt0 periodic idle
        idle = self._idle()
        self._send_tracked(self.ctrl, idle)

        # Auth(0x05) — second auth
        a2 = self._auth(0x05)
        self.log.log("TX", "auth(0x05)", bytes(a2))
        self._send_tracked(self.ctrl, a2)

        # kappanhang: auth confirm (0x40) and 0xA8 arrive ASYNCHRONOUSLY.
        # We must wait for BOTH before sending connInfo.
        # Loop receiving packets until we have both or timeout.
        self.log.info("Waiting for auth confirm (0x40) and 0xA8 metadata...")
        deadline = time.monotonic() + 10.0
        while time.monotonic() < deadline:
            if self.auth_ok and self.a8_reply_id != b"\x00" * 16:
                break
            pkt = self._recv_ctrl(timeout=1.0,
                                   accept_headers={0x40, 0xA8, 0x50})
            if pkt is None:
                idle = self._idle()
                self._send_tracked(self.ctrl, idle)
                continue

            self.log.log("RX", f"({len(pkt)}B, hdr=0x{pkt[0]:02X})", pkt)

            if pkt[0] == 0x40 and len(pkt) == 64:
                if pkt[21] == 0x05:
                    self.auth_ok = True
                    self.log.info("Auth confirmed (0x40, byte 21 = 0x05)")
                else:
                    self.log.log("--", f"0x40 with byte 21 = 0x{pkt[21]:02X}")

            elif pkt[0] == 0xA8 and len(pkt) >= 82:
                self.a8_reply_id = bytes(pkt[66:82])
                result["a8_reply_id"] = self.a8_reply_id.hex()
                self.log.info(f"0xA8 received — a8replyID: {self.a8_reply_id.hex()}")
                if len(pkt) > 98:
                    try:
                        name = pkt[82:114].split(b"\x00")[0].decode("ascii", errors="replace")
                        if name:
                            result["radio_name"] = name
                            self.log.info(f"Radio: {name}")
                    except Exception:
                        pass

            elif pkt[0] == 0x50:
                self.log.log("--", f"Status 0x50 ({len(pkt)}B)", pkt)

        result["auth_ok"] = self.auth_ok
        result["got_a8"] = self.a8_reply_id != b"\x00" * 16
        result["ok"] = self.auth_ok and result["got_a8"]

        if not self.auth_ok:
            self.log.error("Auth not confirmed within 10s")
        if not result["got_a8"]:
            self.log.warn("No 0xA8 within 10s")

        return result

    def _phase_streams(self) -> dict:
        result: dict = {"got_a8": True, "conn_info_ok": False}

        # Send 0x90 connInfo (only reached if auth_ok AND got_a8)
        ci = self._conn_info()
        self.log.log("TX", f"connInfo ({len(ci)}B)", bytes(ci))
        self._send_tracked(self.ctrl, ci)

        # Wait for 0x90 response with byte 96 == 0x01.
        # The radio may send multiple packets: its own 0x90 (byte96=0),
        # a 0x50 status, then the grant 0x90 (byte96=1).
        # Also handle 0x40 auth confirms and 0x50 status packets inline.
        deadline = time.monotonic() + 10.0
        while time.monotonic() < deadline:
            pkt = self._recv_ctrl(timeout=1.0,
                                   accept_headers={0x90, 0x50, 0x40})
            if pkt is None:
                idle = self._idle()
                self._send_tracked(self.ctrl, idle)
                continue

            self.log.log("RX", f"({len(pkt)}B, hdr=0x{pkt[0]:02X})", pkt)

            if pkt[0] == 0x90 and len(pkt) == 144:
                result["conn_info_size"] = len(pkt)
                if pkt[96] == 0x01:
                    self.log.info("ConnInfo SUCCESS (byte 96 = 0x01)")
                    result["conn_info_ok"] = True
                    # Update SIDs and authID per kappanhang
                    new_remote = r32be(pkt, 8)
                    new_local = r32be(pkt, 12)
                    if new_remote:
                        self.remote_sid = new_remote
                    if new_local:
                        self.local_sid = new_local
                    self.log.info(f"SIDs updated: local=0x{self.local_sid:08X} "
                                  f"remote=0x{self.remote_sid:08X}")
                    if len(pkt) >= 32:
                        self.auth_id = bytes(pkt[26:32])
                        self.log.info(f"AuthID updated: {self.auth_id.hex()}")
                    try:
                        name = pkt[64:96].split(b"\x00")[0].decode("ascii", errors="replace")
                        if name:
                            result["device_name"] = name
                            self.log.info(f"Device: {name}")
                    except Exception:
                        pass
                    break
                else:
                    self.log.log("--", f"0x90 with byte 96 = 0x{pkt[96]:02X} (not grant yet)")

            elif pkt[0] == 0x50 and len(pkt) >= 68:
                # Status packet — extract CI-V and audio ports
                civ_port = (pkt[0x42] << 8) | pkt[0x43] if len(pkt) > 0x43 else 0
                audio_port = (pkt[0x46] << 8) | pkt[0x47] if len(pkt) > 0x47 else 0
                result["status_civ_port"] = civ_port
                result["status_audio_port"] = audio_port
                self.log.info(f"Status 0x50: CI-V port={civ_port}, audio port={audio_port}")

            elif pkt[0] == 0x40 and len(pkt) == 64:
                self.log.log("--", "Late auth confirm")

        if not result["conn_info_ok"]:
            self.log.error("ConnInfo grant not received within 10s")

        return result

    def _phase_civ_open(self) -> dict:
        result: dict = {"ok": False}

        # CIV port: pkt3 x2 -> pkt4 -> pkt6 x2 -> pkt6 ack
        # Uses control port's remoteSID for initial pkt3 (remoteSID=0 would also work)
        p3 = bytearray(16)
        p3[0] = 0x10; p3[4] = 0x03
        w32be(p3, 8, self.local_sid)
        w32be(p3, 12, self.remote_sid)
        self.log.log("TX", "CIV pkt3 x2", bytes(p3))
        self.civ.send(p3)
        self.civ.send(p3)

        resp = self.civ.recv(timeout=3.0)
        if resp and len(resp) >= 16:
            self.log.log("RX", f"CIV pkt4 ({len(resp)}B)", resp)
            # Extract CIV port's OWN remoteSID — different from control port!
            self.civ_remote_sid = r32be(resp, 8)
            result["civ_remote_sid"] = f"0x{self.civ_remote_sid:08X}"
            self.log.info(f"CIV remoteSID: 0x{self.civ_remote_sid:08X} "
                          f"(control was 0x{self.remote_sid:08X})")
        else:
            self.log.error("No CIV pkt4 response")
            return result
        self.civ.drain()

        p6 = bytearray(16)
        p6[0] = 0x10; p6[4] = 0x06; p6[6] = 0x01
        w32be(p6, 8, self.local_sid)
        w32be(p6, 12, self.civ_remote_sid)
        self.log.log("TX", "CIV pkt6 x2", bytes(p6))
        self.civ.send(p6)
        self.civ.send(p6)
        self.civ.drain()

        # Open CIV stream
        op = self._civ_open()
        self.log.log("TX", "CIV open (0xC0/0x05)", bytes(op))
        self._send_tracked(self.civ, op, is_civ=True)

        time.sleep(0.3)
        resps = self.civ.recv_all(timeout=1.0)
        for rx in resps:
            self.log.log("RX", f"CIV open resp ({len(rx)}B)", rx)
        result["ok"] = True
        result["responses"] = len(resps)
        self.log.info("CI-V stream opened")
        return result

    def _phase_civ_commands(self) -> dict:
        result = {}

        for label, cmd, sub in [("Read Freq", CIV_READ_FREQ, None),
                                  ("Read Mode", CIV_READ_MODE, None),
                                  ("Read S-Meter", 0x15, [0x02]),
                                  ("Read ID", 0x19, [0x00])]:
            print(f"  --- {label} ---")
            frame = self._civ_frame(cmd, sub)
            pkt = self._civ_data(frame)
            self.log.log("TX", f"CI-V {label}", bytes(pkt),
                          detail=f"frame: {frame.hex()}")
            self._send_tracked(self.civ, pkt, is_civ=True)

            cmd_result: dict = {"sent": True, "responses": []}
            resps = self.civ.recv_all(timeout=2.0)
            for rx in resps:
                self.log.log("RX", f"{label} resp ({len(rx)}B)", rx)
                parsed = self._parse_civ_pkt(rx)
                cmd_result["responses"].append(parsed)
                if parsed.get("frequency_hz"):
                    cmd_result["frequency"] = format_freq(parsed["frequency_hz"])
                    self.log.info(f"Frequency: {cmd_result['frequency']}")
                if parsed.get("mode"):
                    cmd_result["mode"] = parsed["mode"]
                    self.log.info(f"Mode: {parsed['mode']}")
            if not resps:
                self.log.warn(f"No response to {label}")
            result[label.lower().replace(" ", "_")] = cmd_result
            time.sleep(0.3)

            # Keep control alive
            idle = self._idle()
            self._send_tracked(self.ctrl, idle)

        return result

    def _phase_keepalive(self) -> dict:
        result: dict = {"pings": []}
        for i in range(3):
            p7 = self._pkt7()
            t0 = time.monotonic()
            self.log.log("TX", f"pkt7 #{i + 1}", bytes(p7))
            self.ctrl.send(p7)

            resp = self.ctrl.recv(timeout=3.0)
            rtt = (time.monotonic() - t0) * 1000
            pr: dict = {"index": i + 1, "rtt_ms": round(rtt, 1)}
            if resp:
                self.log.log("RX", f"pkt7 reply ({len(resp)}B, {rtt:.1f}ms)", resp)
                pr["ok"] = True
                pr["reply_size"] = len(resp)
            else:
                self.log.warn(f"No pkt7 reply ({rtt:.0f}ms)")
                pr["ok"] = False
            result["pings"].append(pr)

            # Idle on both ports
            idle = self._idle()
            self._send_tracked(self.ctrl, idle)
            ci = self._civ_idle()
            self._send_tracked(self.civ, ci, is_civ=True)
            time.sleep(1.0)

        # Re-auth test
        print("  --- Re-Auth ---")
        ra = self._auth(0x05)
        self.log.log("TX", "reauth(0x05)", bytes(ra))
        self._send_tracked(self.ctrl, ra)
        resp = self.ctrl.recv(timeout=3.0)
        if resp:
            self.log.log("RX", f"reauth resp ({len(resp)}B)", resp)
            result["reauth_ok"] = True
        else:
            self.log.warn("No reauth response")
            result["reauth_ok"] = False

        return result

    def _phase_unsolicited(self) -> dict:
        result: dict = {"packets": [], "civ_frames": []}
        deadline = time.monotonic() + 5.0
        while time.monotonic() < deadline:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            pkt = self.civ.recv(timeout=min(remaining, 0.5))
            if pkt:
                self.log.log("RX", f"unsolicited ({len(pkt)}B)", pkt)
                parsed = self._parse_civ_pkt(pkt)
                result["packets"].append(parsed)
                if "frames" in parsed:
                    result["civ_frames"].extend(parsed["frames"])
            idle = self._idle()
            self._send_tracked(self.ctrl, idle)

        result["total_packets"] = len(result["packets"])
        result["total_civ_frames"] = len(result["civ_frames"])
        self.log.info(f"Captured {result['total_packets']} packets, "
                      f"{result['total_civ_frames']} CI-V frames")
        return result

    def _disconnect(self) -> None:
        try:
            if self.civ:
                cl = self._civ_close()
                self.log.log("TX", "CIV close", bytes(cl))
                self._send_tracked(self.civ, cl, is_civ=True)
                time.sleep(0.1)
            if self.ctrl:
                # Deauth
                da = self._auth(0x01)
                self.log.log("TX", "deauth(0x01)", bytes(da))
                self._send_tracked(self.ctrl, da)
                time.sleep(0.1)
                # Disconnect
                p5 = self._pkt5()
                self.log.log("TX", "pkt5 disconnect x2", bytes(p5))
                self.ctrl.send(p5)
                self.ctrl.send(p5)
                time.sleep(0.5)  # kappanhang waits 500ms for retransmit drain
                self.ctrl.close()
            if self.civ:
                self.civ.close()
        except Exception as exc:
            self.log.warn(f"Disconnect error: {exc}")


# ─── Main ────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="IC-705 WiFi Protocol Diagnostic Tool v3.1",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent("""\
            Radio setup (MENU > SET > WLAN Set):
              1. WLAN > ON
              2. Remote Settings > Network Control > ON
              3. Remote Settings > Network User1 > set username & password
              4. Connection Settings > Access Point (for AP mode)

            Then connect your computer to the radio's WiFi and run:
              python3 ic705_diag.py --user <username> --pass <password>

            For Station mode (radio on your home network):
              python3 ic705_diag.py --ip <radio_ip> --user <username> --pass <password>
        """),
    )
    parser.add_argument("--ip", default="192.168.59.1",
                        help="Radio IP (default: 192.168.59.1 for AP mode)")
    parser.add_argument("--user", required=True, help="RS-BA1 username")
    parser.add_argument("--pass", dest="password", required=True, help="RS-BA1 password")
    args = parser.parse_args()

    print("=" * 60)
    print("  IC-705 WiFi Protocol Diagnostic Tool v3.1")
    print("  Carrier Wave — https://carrierwave.app")
    print("=" * 60)
    print(f"\n  Target: {args.ip}:{CONTROL_PORT}/{SERIAL_PORT}")
    print(f"  User:   {args.user}")
    print(f"  Time:   {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

    diag = IC705Diag(args.ip, args.user, args.password)
    report = diag.run()

    # Summary
    print("\n" + "=" * 60)
    print("  DIAGNOSTIC SUMMARY")
    print("=" * 60)

    res = report.get("results", {})
    checks = [
        ("UDP Reachable", res.get("reachability", {}).get("ok", False)),
        ("Login", res.get("login", {}).get("ok", False)),
        ("Auth Mode", res.get("login", {}).get("auth_mode", "N/A")),
        ("Auth Challenge", res.get("auth", {}).get("ok", False)),
        ("Got 0xA8", res.get("streams", {}).get("got_a8", False)),
        ("ConnInfo 0x90", res.get("streams", {}).get("conn_info_ok", False)),
        ("CI-V Stream", res.get("civ", {}).get("ok", False)),
        ("Read Freq", bool(res.get("civ_commands", {}).get("read_freq", {}).get("responses"))),
        ("Read Mode", bool(res.get("civ_commands", {}).get("read_mode", {}).get("responses"))),
        ("Keepalive", all(p.get("ok") for p in res.get("keepalive", {}).get("pings", [{}]))),
    ]
    for label, val in checks:
        status = ("PASS" if val else "FAIL") if isinstance(val, bool) else str(val)
        print(f"  {label:<20s} {status}")

    if report.get("errors"):
        print(f"\n  ERRORS ({len(report['errors'])}):")
        for err in report["errors"]:
            print(f"    - {err}")
    if report.get("warnings"):
        print(f"\n  WARNINGS ({len(report['warnings'])}):")
        for wrn in report["warnings"]:
            print(f"    - {wrn}")

    ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"ic705_diag_{ts}.json"
    with open(filename, "w") as fh:
        json.dump(report, fh, indent=2, default=str)

    print(f"\n  Report saved: {filename}")
    print(f"  Send this file to the Carrier Wave developers.")
    print("=" * 60)


if __name__ == "__main__":
    main()
