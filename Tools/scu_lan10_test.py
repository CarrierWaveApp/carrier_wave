#!/usr/bin/env python3
"""
SCU-LAN10 Scope Data Receiver - Protocol Test Script

Connects to a Yaesu SCU-LAN10 network interface and receives/decrypts
spectrum scope data for waterfall display.

Protocol discovered via packet analysis:
- All packets framed as: 5a5a [LE 16-bit length] 0001 [payload]
- 4 UDP ports: Control(50000), CAT(50001), Audio(50002), Scope(50003)
- Scope data: 4110-byte packets, 25/sec, 4096 spectrum amplitude samples
- Decryption: plaintext[i] = encrypted[i] XOR byte6 XOR g(i)
  where g(i) = (4*(i//4) + 6 + [0, 0xFF, 0xFE, 5][i%4]) & 0xFF

Usage:
    python3 scu_lan10_test.py <host> [--port 50000] [--duration 10]
"""

import argparse
import socket
import struct
import sys
import time
import threading
from collections import deque

MAGIC = b'\x5a\x5a'
TYPE_FIELD = b'\x00\x01'

# Precompute the position-dependent scramble table
# g(i) = (4*(i//4) + 6 + offset[i%4]) & 0xFF
G_TABLE = bytearray(8192)  # Large enough for any packet
OFFSETS = [0, 0xFF, 0xFE, 5]
for _i in range(8192):
    _group = _i // 4
    _base = (4 * _group + 6) & 0xFF
    G_TABLE[_i] = (_base + OFFSETS[_i % 4]) & 0xFF


def decrypt_payload(payload: bytes) -> bytes:
    """Decrypt any SCU-LAN10 payload using the universal XOR scheme.

    All packets use the same encryption:
      plaintext[i] = encrypted[i] XOR key XOR g(i)
    where key is payload byte 5, and data starts at byte 8.
    """
    if len(payload) < 9:
        return b''

    key = payload[5]
    data_len = len(payload) - 8
    result = bytearray(data_len)
    for i in range(data_len):
        result[i] = payload[8 + i] ^ key ^ G_TABLE[i]
    return bytes(result)


def encrypt_payload(plaintext: bytes, seq: int, key: int) -> bytes:
    """Encrypt plaintext data into an SCU-LAN10 payload.

    Builds the 8-byte header and encrypts the data.
    The 3-byte counter (bytes 3-5) is derived from the key.
    """
    # Build header: seq(1) + id(2) + counter(2) + key(1) + key_dup(1) + related(1)
    # For simplicity, use key as both bytes 5 and 6, and derive counter
    header = bytearray(8)
    header[0] = seq & 0xFF
    # Bytes 1-4: derived from sequence (observed pattern)
    header[1] = ((seq << 5) | (seq >> 3)) & 0xFF
    header[2] = G_TABLE[0] ^ key  # Makes first g(i) cancel properly
    header[3] = key  # Counter byte (part of 3-byte counter)
    header[4] = key  # Counter byte
    header[5] = key  # XOR key
    header[6] = key  # Key duplicate (same as byte 5 for scope)
    header[7] = key  # Related

    # Encrypt data
    encrypted = bytearray(len(plaintext))
    for i in range(len(plaintext)):
        encrypted[i] = plaintext[i] ^ key ^ G_TABLE[i]

    return bytes(header) + bytes(encrypted)


def build_auth_packet(username: str, password: str) -> bytes:
    """Build an authentication packet with encrypted credentials.

    Format: 0x01 0x00 + username(33 bytes, null-padded) + password(33 bytes, null-padded)
    Encrypted with key from captured header. Uses the exact captured 8-byte header
    since the header generation formula isn't fully understood yet.

    Returns the complete payload (header + encrypted data) ready for framing.
    """
    # Plaintext: 2-byte prefix + 33-byte username + 33-byte password = 68 bytes
    user_bytes = username.encode('ascii')[:33].ljust(33, b'\x00')
    pass_bytes = password.encode('ascii')[:33].ljust(33, b'\x00')
    plaintext = b'\x01\x00' + user_bytes + pass_bytes

    # Use the captured header (includes seq=0x06, key=0x3A at byte 5)
    header = bytes.fromhex("06c0c639393a7e3d")
    key = header[5]  # 0x3A

    # Encrypt
    encrypted = bytearray(len(plaintext))
    for i in range(len(plaintext)):
        encrypted[i] = plaintext[i] ^ key ^ G_TABLE[i]

    return header + bytes(encrypted)


def decrypt_scope_data(payload: bytes) -> bytes:
    """Decrypt a scope payload. Convenience wrapper for spectrum data.

    Returns 4096 bytes of decrypted spectrum data (0=no signal, 255=strong).
    """
    if len(payload) < 4104:
        return b''
    return decrypt_payload(payload)[:4096]


def make_packet(payload: bytes) -> bytes:
    """Wrap payload in 5a5a framing.

    Length field = sizeof(TYPE_FIELD) + sizeof(payload) = len(payload) + 2.
    """
    length = len(payload) + 2  # length includes the 2-byte type field
    return MAGIC + struct.pack('<H', length) + TYPE_FIELD + payload


def print_spectrum_ascii(data: bytes, width: int = 80):
    """Print a single spectrum line as ASCII art."""
    if not data:
        return
    # Find the active portion (non-zero)
    active_end = len(data)
    for i in range(len(data) - 1, -1, -1):
        if data[i] > 0:
            active_end = i + 1
            break
    if active_end == 0:
        return

    step = max(1, active_end // width)
    line = []
    for col in range(min(width, active_end)):
        start = col * step
        end = min(start + step, active_end)
        chunk = data[start:end]
        if chunk:
            val = sum(chunk) // len(chunk)
            if val > 200:
                line.append(' ')
            elif val > 150:
                line.append('.')
            elif val > 100:
                line.append(':')
            elif val > 50:
                line.append('#')
            else:
                line.append('@')
        else:
            line.append(' ')
    print(''.join(line))


class SCULAN10Client:
    """UDP client for the SCU-LAN10 network interface."""

    def __init__(self, host: str, username: str, password: str, control_port: int = 50000):
        self.host = host
        self.username = username
        self.password = password
        self.control_port = control_port
        self.cat_port = control_port + 1
        self.audio_port = control_port + 2
        self.scope_port = control_port + 3

        self.control_sock = None
        self.cat_sock = None
        self.scope_sock = None
        self.audio_sock = None

        self.running = False
        self.scope_lines = deque(maxlen=100)
        self.packets_received = 0
        self._seq = 0

    def _next_seq(self) -> int:
        """Get next sequence number."""
        self._seq += 1
        return self._seq & 0xFF

    def _make_keepalive(self, seq: int, key: int) -> bytes:
        """Build a keepalive packet (4 bytes of 0x04 plaintext)."""
        payload = encrypt_payload(b'\x04\x04\x04\x04', seq, key)
        return MAGIC + struct.pack('<H', len(payload) + 2) + TYPE_FIELD + payload

    def _send_ctrl(self, payload_hex: str):
        """Send a raw hex payload to the control port."""
        self.control_sock.sendto(MAGIC + bytes.fromhex(payload_hex), (self.host, self.control_port))

    def connect(self):
        """Establish connection to the SCU-LAN10."""
        print(f"Connecting to {self.host} as {self.username}...")

        # Create UDP sockets
        self.control_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.control_sock.settimeout(5.0)
        self.cat_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.cat_sock.settimeout(5.0)
        self.scope_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.scope_sock.settimeout(2.0)
        self.audio_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.audio_sock.settimeout(5.0)

        # Bind to any available port
        self.control_sock.bind(('', 0))
        self.cat_sock.bind(('', 0))
        self.scope_sock.bind(('', 0))
        self.audio_sock.bind(('', 0))

        print(f"  Control: local port {self.control_sock.getsockname()[1]}")
        print(f"  CAT:     local port {self.cat_sock.getsockname()[1]}")
        print(f"  Scope:   local port {self.scope_sock.getsockname()[1]}")
        print(f"  Audio:   local port {self.audio_sock.getsockname()[1]}")

        # Connection establishment sequence (from packet capture analysis):
        # 1. Send 5 keepalive packets on control port (handshake init)
        # 2. Send auth packet with encrypted credentials
        # 3. Receive server response
        # 4. Send continuation packets
        # 5. Init CAT, audio, and scope ports

        print("\nSending auth sequence...")

        # Phase 1: 5 keepalive init packets (exact captured bytes - header format not yet decoded)
        init_packets = [
            "0e00000101a0a15e585d595a5b585956",
            "0e000001024042bdbbbebab9b8bbbab5",
            "0e00000103e0e31c1a1f1b18191a1b14",
            "0e0000010480847b7d787c7f7e7d7c73",
            "0e000001052025dadcd9dddedfdcddd2",
        ]
        for idx, pkt_hex in enumerate(init_packets):
            self.control_sock.sendto(MAGIC + bytes.fromhex(pkt_hex), (self.host, self.control_port))
            print(f"  Sent handshake keepalive {idx + 1}/5")
            time.sleep(0.005)

        # Phase 2: Auth packet with credentials
        auth_payload = build_auth_packet(self.username, self.password)
        auth_framed = MAGIC + struct.pack('<H', len(auth_payload) + 2) + TYPE_FIELD + auth_payload
        self.control_sock.sendto(auth_framed, (self.host, self.control_port))
        print(f"  Sent auth packet ({len(auth_framed)} bytes)")

        # Wait for server response and extract session ID
        try:
            data, addr = self.control_sock.recvfrom(4096)
            print(f"  Auth response: {len(data)} bytes from {addr}")

            resp_payload = data[6:]  # after 5a5a + length + type
            resp_dec = decrypt_payload(resp_payload)
            session_id = resp_dec[0]
            print(f"  Session ID: 0x{session_id:02x}")
        except socket.timeout:
            print("  ERROR: No response from control port (timeout)")
            return False

        # Phase 3: Build and send continuation with session ID
        # Plaintext: [session_id, 0x00, 0x00, 0x00, 0x51, 0xC3, 0x00, 0x96, 0x00, 0x00]
        cont_plain = bytes([session_id, 0, 0, 0, 0x51, 0xC3, 0x00, 0x96, 0, 0])
        cont_payload = encrypt_payload(cont_plain, 0x07, 0x9B)
        cont_pkt = MAGIC + struct.pack('<H', len(cont_payload) + 2) + TYPE_FIELD + cont_payload
        self.control_sock.sendto(cont_pkt, (self.host, self.control_port))
        print("  Sent continuation with session ID")

        # Phase 4: Server sends keepalives, we respond with port setup packets
        # Each port setup: wait for server keepalive, send [session_id, 0,0,0, port_id, 0xC3]
        port_ids = [0x51, 0x52, 0x53]  # CAT, Audio, Scope
        port_socks = [self.cat_sock, self.audio_sock, self.scope_sock]
        port_names = ["CAT", "Audio", "Scope"]
        port_targets = [self.cat_port, self.audio_port, self.scope_port]

        seq_counter = 0x08
        for port_id, sock, name, target_port in zip(port_ids, port_socks, port_names, port_targets):
            # Wait for server keepalive on control port
            try:
                data, _ = self.control_sock.recvfrom(4096)
            except socket.timeout:
                print(f"  No keepalive before {name} init")

            # Send keepalive on the port's socket
            ka_plain = b'\x04\x04\x04\x04'
            ka_payload = encrypt_payload(ka_plain, seq_counter, 0xF5)
            ka_pkt = MAGIC + struct.pack('<H', len(ka_payload) + 2) + TYPE_FIELD + ka_payload
            sock.sendto(ka_pkt, (self.host, target_port))
            seq_counter += 1

            # Send port setup on control port
            setup_plain = bytes([session_id, 0, 0, 0, port_id, 0xC3])
            setup_payload = encrypt_payload(setup_plain, seq_counter, 0x55)
            setup_pkt = MAGIC + struct.pack('<H', len(setup_payload) + 2) + TYPE_FIELD + setup_payload
            self.control_sock.sendto(setup_pkt, (self.host, self.control_port))
            seq_counter += 1

            try:
                data, _ = self.control_sock.recvfrom(4096)
            except socket.timeout:
                pass

            print(f"  Initialized {name} port")

        # Send final control keepalive
        final_ka_plain = b'\x04\x04\x04\x04'
        final_payload = encrypt_payload(final_ka_plain, seq_counter, 0x36)
        final_pkt = MAGIC + struct.pack('<H', len(final_payload) + 2) + TYPE_FIELD + final_payload
        self.control_sock.sendto(final_pkt, (self.host, self.control_port))

        # Send scope keepalive/init
        scope_ka_plain = b'\x04\x04\x04\x04'
        scope_payload = encrypt_payload(scope_ka_plain, seq_counter + 1, 0xC9)
        scope_pkt = MAGIC + struct.pack('<H', len(scope_payload) + 2) + TYPE_FIELD + scope_payload
        self.scope_sock.sendto(scope_pkt, (self.host, self.scope_port))

        print("\nConnection sequence complete. Listening for scope data...")
        return True

    def receive_scope_data(self, duration: float = 10.0):
        """Receive and decrypt scope data for the given duration."""
        self.running = True

        # Start keepalive thread
        keepalive_thread = threading.Thread(target=self._keepalive_loop, daemon=True)
        keepalive_thread.start()

        start_time = time.time()
        self.packets_received = 0
        total_bytes = 0

        try:
            while self.running and (time.time() - start_time) < duration:
                try:
                    data, addr = self.scope_sock.recvfrom(8192)
                    total_bytes += len(data)

                    # Validate framing
                    if len(data) < 6 or data[:2] != MAGIC:
                        continue

                    # Parse header
                    payload_len = struct.unpack('<H', data[2:4])[0]
                    if data[4:6] != TYPE_FIELD:
                        continue

                    payload = data[6:]
                    if len(payload) < 4104:
                        # Small packet = keepalive response, not scope data
                        continue

                    # Decrypt spectrum data
                    spectrum = decrypt_scope_data(payload)
                    if spectrum:
                        self.packets_received += 1
                        self.scope_lines.append(spectrum)

                        if self.packets_received % 5 == 0:
                            elapsed = time.time() - start_time
                            rate = self.packets_received / elapsed if elapsed > 0 else 0
                            active_bins = sum(1 for b in spectrum if b > 0)
                            noise_floor = (
                                sum(spectrum[:100]) / 100 if active_bins > 100 else 0
                            )
                            print(
                                f"\r  Scope: {self.packets_received} lines, "
                                f"{rate:.1f} lines/sec, "
                                f"{active_bins} active bins, "
                                f"noise floor ~{noise_floor:.0f}",
                                end='',
                            )

                except socket.timeout:
                    continue

        except KeyboardInterrupt:
            pass
        finally:
            self.running = False

        elapsed = time.time() - start_time
        print(f"\n\nReceived {self.packets_received} scope lines in {elapsed:.1f}s")
        print(f"Total bytes: {total_bytes}")

        if self.scope_lines:
            print("\n=== Last spectrum line (ASCII waterfall) ===")
            print_spectrum_ascii(self.scope_lines[-1])

            # Print stats
            last = self.scope_lines[-1]
            active = sum(1 for b in last if b > 0)
            print(f"\nActive bins: {active}/4096")
            if active > 0:
                active_data = [b for b in last if b > 0]
                print(
                    f"Signal range: {min(active_data)}-{max(active_data)}, "
                    f"mean={sum(active_data) / len(active_data):.1f}"
                )

        return self.packets_received > 0

    def _keepalive_loop(self):
        """Send periodic keepalives on all ports."""
        while self.running:
            time.sleep(1.0)
            try:
                # Control keepalive
                ka = bytes.fromhex("0e00000113c0d32c2a2f2b28292a2b24")
                self.control_sock.sendto(MAGIC + ka, (self.host, self.control_port))

                # CAT keepalive
                ka_cat = bytes.fromhex("0e0000011260738d8b8e8a89888b8a85")
                self.cat_sock.sendto(MAGIC + ka_cat, (self.host, self.cat_port))

                # Audio keepalive
                ka_audio = bytes.fromhex("0e000001150014eaece9edeeefecede2")
                self.audio_sock.sendto(MAGIC + ka_audio, (self.host, self.audio_port))

                # Scope keepalive
                ka_scope = bytes.fromhex("0e00000114a0b24b4d484c4f4e4d4c43")
                self.scope_sock.sendto(MAGIC + ka_scope, (self.host, self.scope_port))

            except Exception as exc:
                print(f"\nKeepalive error: {exc}")

    def close(self):
        """Close all sockets."""
        self.running = False
        for sock in (self.control_sock, self.cat_sock, self.scope_sock, self.audio_sock):
            if sock:
                sock.close()


def test_decrypt_from_capture():
    """Verify decryption against known captured data."""
    print("=== Testing decryption against capture data ===\n")

    # First scope data packet from cap3.pcapng (after 5a5a0a100001)
    test_payload = bytes.fromhex(
        "2241659c189f9f8878727a727a74666a754c745e5a53555e545258"
        "606a59645e68605d686e605745475a5f54555149414051554a5374"
        "784c595473727d7e7c4a4d7b79"
    )
    # We only have the first ~55 bytes, but let's verify those
    key = test_payload[6]  # 0x9f

    print(f"Test payload byte 6 (key): 0x{key:02x}")
    print(f"First 8 data bytes (encrypted): {test_payload[8:16].hex()}")

    decrypted = bytearray()
    for i in range(min(len(test_payload) - 8, 48)):
        decrypted.append(test_payload[8 + i] ^ key ^ G_TABLE[i])

    print(f"First 8 data bytes (decrypted): {bytes(decrypted[:8]).hex()}")
    print(f"Decrypted values: {list(decrypted[:16])}")

    # Expected: noise floor around 220-230
    avg = sum(decrypted) / len(decrypted)
    print(f"Average value: {avg:.1f} (expected ~220-230 for noise floor)")

    if 180 < avg < 250:
        print("PASS: Decryption produces plausible spectrum values")
    else:
        print("WARN: Values outside expected range")

    print()


def main():
    parser = argparse.ArgumentParser(description="SCU-LAN10 Scope Data Receiver")
    parser.add_argument("host", nargs="?", help="SCU-LAN10 hostname or IP")
    parser.add_argument("--user", "-u", default="", help="SCU-LAN10 username")
    parser.add_argument("--password", "-p", default="", help="SCU-LAN10 password")
    parser.add_argument("--port", type=int, default=50000, help="Control port (default 50000)")
    parser.add_argument("--duration", type=float, default=10.0, help="Receive duration in seconds")
    parser.add_argument("--test", action="store_true", help="Run decryption self-test only")

    args = parser.parse_args()

    if args.test:
        test_decrypt_from_capture()
        return

    if not args.host:
        parser.error("host is required (or use --test)")

    if not args.user or not args.password:
        parser.error("--user and --password are required")

    client = SCULAN10Client(args.host, args.user, args.password, args.port)
    try:
        if client.connect():
            success = client.receive_scope_data(args.duration)
            if not success:
                print("\nNo scope data received. The radio may not be streaming,")
                print("or the auth credentials may need updating.")
                print("Try capturing fresh auth packets with Wireshark.")
    except Exception as exc:
        print(f"\nError: {exc}")
        raise
    finally:
        client.close()


if __name__ == "__main__":
    main()
