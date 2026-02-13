#!/usr/bin/env python3
"""
KiwiSDR WebSocket connection test script.

Replicates the exact protocol from KiwiSDRClient.swift for debugging
connection issues outside iOS. Connects to a KiwiSDR, performs the full
handshake, tunes to a frequency, and streams a few seconds of audio.

Usage:
    python3 scripts/kiwisdr_test.py [host] [freq_khz]

Examples:
    python3 scripts/kiwisdr_test.py kiwisdr.kfsdr.com 14040
    python3 scripts/kiwisdr_test.py 192.168.1.82 7074
"""

import asyncio
import struct
import sys
import time

# Requires: pip3 install websockets
try:
    import websockets
except ImportError:
    print("ERROR: websockets library required. Install with:")
    print("  pip3 install websockets")
    sys.exit(1)


# -- IMA ADPCM Decoder (mirrors KiwiSDRADPCM.swift) -----------------------

STEP_TABLE = [
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31,
    34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130,
    143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449,
    494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411,
    1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026,
    4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487,
    12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794,
    32767,
]

INDEX_TABLE = [
    -1, -1, -1, -1, 2, 4, 6, 8,
    -1, -1, -1, -1, 2, 4, 6, 8,
]


class ADPCMDecoder:
    def __init__(self):
        self.predictor = 0
        self.step_index = 0

    def decode_nibble(self, nibble):
        step = STEP_TABLE[self.step_index]
        self.step_index = max(0, min(88, self.step_index + INDEX_TABLE[nibble]))

        diff = step >> 3
        if nibble & 4:
            diff += step
        if nibble & 2:
            diff += step >> 1
        if nibble & 1:
            diff += step >> 2
        if nibble & 8:
            self.predictor -= diff
        else:
            self.predictor += diff

        self.predictor = max(-32768, min(32767, self.predictor))
        return self.predictor

    def decode(self, data):
        samples = []
        for byte in data:
            samples.append(self.decode_nibble(byte & 0x0F))
            samples.append(self.decode_nibble(byte >> 4))
        return samples


# -- Protocol helpers ------------------------------------------------------

def parse_msg_value(message, key):
    """Extract a value for a key from 'MSG key=value key2=value2' messages."""
    needle = f"{key}="
    if needle not in message:
        return None
    parts = message.split(needle, 1)
    if len(parts) < 2:
        return None
    return parts[1].split(" ")[0].strip()


def check_server_error(message):
    """Check for error conditions in a server message. Raises on error."""
    badp = parse_msg_value(message, "badp")
    if badp is not None and badp != "0":
        codes = {
            "1": "Bad password or all channels busy",
            "2": "Still determining local interface",
            "3": "Admin not allowed from this IP",
            "4": "No admin password set",
            "5": "No multiple connections from same IP",
            "6": "Database update in progress",
            "7": "Another admin connection open",
        }
        raise ConnectionError(f"Auth failed (badp={badp}): {codes.get(badp, 'unknown')}")

    too_busy = parse_msg_value(message, "too_busy")
    if too_busy is not None and too_busy != "0":
        raise ConnectionError(f"Server too busy ({too_busy} channels in use)")

    if "MSG down" in message:
        raise ConnectionError("Server is down")

    redirect = parse_msg_value(message, "redirect")
    if redirect is not None:
        raise ConnectionError(f"Server redirect to: {redirect}")


def parse_snd_frame(data):
    """Parse a binary SND audio frame. Returns (flags, seq, smeter, audio_data) or None."""
    if len(data) < 10:
        return None
    # Check "SND" header
    if data[0:3] != b"SND":
        return None

    flags = data[3]
    seq = struct.unpack_from("<I", data, 4)[0]
    smeter_raw = struct.unpack_from(">H", data, 8)[0]
    audio_data = data[10:]

    is_compressed = bool(flags & 0x10)
    is_little_endian = bool(flags & 0x80)
    is_iq = bool(flags & 0x08)

    rssi_dbm = 0.1 * smeter_raw - 127.0

    return {
        "flags": flags,
        "seq": seq,
        "smeter_raw": smeter_raw,
        "rssi_dbm": rssi_dbm,
        "compressed": is_compressed,
        "little_endian": is_little_endian,
        "iq": is_iq,
        "audio_bytes": len(audio_data),
    }


# -- Main connection logic -------------------------------------------------

async def test_connection(host, port, freq_khz, mode="cw", duration_sec=5):
    """
    Connect to a KiwiSDR and stream audio, printing diagnostics at each step.
    Mirrors the exact protocol sequence from KiwiSDRClient.swift.
    """
    timestamp = int(time.time())
    url = f"ws://{host}:{port}/{timestamp}/SND"

    print(f"\n{'='*60}")
    print(f"KiwiSDR Connection Test")
    print(f"{'='*60}")
    print(f"  Host:      {host}:{port}")
    print(f"  Frequency: {freq_khz} kHz ({freq_khz/1000:.3f} MHz)")
    print(f"  Mode:      {mode}")
    print(f"  URL:       {url}")
    print(f"  Duration:  {duration_sec}s")
    print(f"{'='*60}\n")

    # Mode passbands (matching KiwiSDRMode in Swift)
    passbands = {
        "cw":   (200, 1000),
        "usb":  (300, 2700),
        "lsb":  (-2700, -300),
        "am":   (-5000, 5000),
        "nbfm": (-6000, 6000),
    }
    low_cut, high_cut = passbands.get(mode, (300, 2700))

    try:
        # Step 1: WebSocket connect
        print("[1/9] Connecting WebSocket...", end=" ", flush=True)
        ws = await asyncio.wait_for(
            websockets.connect(url, ping_interval=None, close_timeout=5),
            timeout=10,
        )
        print("OK")

        # Step 2: Authenticate
        auth_cmd = "SET auth t=kiwi p=#"
        print(f"[2/9] Sending auth: {auth_cmd!r}...", end=" ", flush=True)
        await ws.send(auth_cmd)
        print("sent")

        # Step 3: Wait for sample_rate
        # NOTE: KiwiSDR sends MSG text as binary WebSocket frames, not text.
        # Must decode binary frames as UTF-8 to find MSG content.
        print("[3/9] Waiting for sample_rate...", flush=True)
        sample_rate = None
        for i in range(30):
            msg = await asyncio.wait_for(ws.recv(), timeout=5)
            text = None
            if isinstance(msg, str):
                text = msg
            elif isinstance(msg, bytes):
                # KiwiSDR sends MSG content as binary frames
                try:
                    text = msg.decode("utf-8", errors="replace")
                except Exception:
                    pass

            if text and ("MSG" in text or "=" in text):
                print(f"       <- MSG: {text[:120]}{'...' if len(text) > 120 else ''}")
                check_server_error(text)
                rate = parse_msg_value(text, "sample_rate")
                if rate is not None:
                    sample_rate = float(rate)
                    print(f"       Got sample_rate={sample_rate}")
                    break
            elif isinstance(msg, bytes):
                print(f"       <- BIN: {len(msg)} bytes")
            else:
                print(f"       <- ???: {repr(msg)[:80]}")

        if sample_rate is None:
            print("       FAILED: No sample_rate received in 30 messages")
            await ws.close()
            return False

        # Step 4: Acknowledge rate
        in_rate = int(sample_rate)
        ar_cmd = f"SET AR OK in={in_rate} out={in_rate}"
        print(f"[4/9] Rate ack: {ar_cmd!r}...", end=" ", flush=True)
        await ws.send(ar_cmd)
        print("sent")

        # Step 5: Identify
        ident_cmd = "SET ident_user=CarrierWave-Test"
        print(f"[5/9] Ident: {ident_cmd!r}...", end=" ", flush=True)
        await ws.send(ident_cmd)
        print("sent")

        # Step 6: Compression
        comp_cmd = "SET compression=1"
        print(f"[6/9] Compression: {comp_cmd!r}...", end=" ", flush=True)
        await ws.send(comp_cmd)
        print("sent")

        # Step 7: Tune
        tune_cmd = f"SET mod={mode} low_cut={low_cut} high_cut={high_cut} freq={freq_khz:.3f}"
        print(f"[7/9] Tune: {tune_cmd!r}...", end=" ", flush=True)
        await ws.send(tune_cmd)
        print("sent")

        # Step 8: AGC
        agc_cmd = "SET agc=1 hang=0 thresh=-100 slope=6 decay=1000 manGain=50"
        print(f"[8/9] AGC: {agc_cmd!r}...", end=" ", flush=True)
        await ws.send(agc_cmd)
        print("sent")

        # Step 9: Stream audio
        print(f"\n[9/9] Streaming audio for {duration_sec}s...")
        print(f"       {'seq':>6}  {'bytes':>6}  {'S-meter':>10}  {'RSSI':>8}  {'comp':>4}  notes")
        print(f"       {'-'*6}  {'-'*6}  {'-'*10}  {'-'*8}  {'-'*4}  {'-'*20}")

        decoder = ADPCMDecoder()
        frame_count = 0
        total_samples = 0
        start_time = time.time()
        last_keepalive = start_time

        while time.time() - start_time < duration_sec:
            # Send keepalive every 5 seconds
            now = time.time()
            if now - last_keepalive >= 5:
                await ws.send("SET keepalive")
                last_keepalive = now

            try:
                msg = await asyncio.wait_for(ws.recv(), timeout=3)
            except asyncio.TimeoutError:
                print("       (timeout waiting for message)")
                continue

            # Decode text from either text or binary frames
            text = None
            raw_bytes = None
            if isinstance(msg, str):
                text = msg
            elif isinstance(msg, bytes):
                raw_bytes = msg
                # Check if it's a SND audio frame first
                if len(msg) >= 3 and msg[:3] == b"SND":
                    pass  # handle as audio below
                else:
                    try:
                        text = msg.decode("utf-8", errors="replace")
                    except Exception:
                        pass

            if text:
                print(f"       <- TEXT: {text[:120]}")
                too_busy_val = parse_msg_value(text, "too_busy")
                is_too_busy = too_busy_val is not None and too_busy_val != "0"
                if is_too_busy or "MSG down" == text.strip() or \
                   "MSG inactivity_timeout" in text:
                    print(f"       SERVER DISCONNECT: {text}")
                    break
                # Handle ADPCM state resets
                adpcm_state = parse_msg_value(text, "audio_adpcm_state")
                if adpcm_state:
                    parts = adpcm_state.split(",")
                    if len(parts) == 2:
                        decoder.step_index = max(0, min(88, int(parts[0])))
                        decoder.predictor = int(parts[1])
                        print(f"       (ADPCM state reset: index={decoder.step_index}, pred={decoder.predictor})")

            elif raw_bytes:
                frame = parse_snd_frame(raw_bytes)
                if frame:
                    frame_count += 1
                    notes = ""
                    if frame["iq"]:
                        notes += "IQ "
                    if frame["compressed"]:
                        num_samples = (frame["audio_bytes"]) * 2
                        notes += f"~{num_samples} samples"
                    else:
                        num_samples = frame["audio_bytes"] // 2
                        notes += f"{num_samples} samples"
                    total_samples += num_samples

                    # Print every 10th frame to avoid flooding
                    if frame_count <= 3 or frame_count % 10 == 0:
                        print(
                            f"       {frame['seq']:>6}  "
                            f"{frame['audio_bytes']:>6}  "
                            f"{frame['smeter_raw']:>10}  "
                            f"{frame['rssi_dbm']:>7.1f}  "
                            f"{'yes' if frame['compressed'] else 'no':>4}  "
                            f"{notes}"
                        )
                else:
                    tag = msg[:3] if len(msg) >= 3 else msg
                    print(f"       <- BIN: {len(msg)} bytes (tag={tag!r}, not SND)")

        elapsed = time.time() - start_time

        print(f"\n{'='*60}")
        print(f"Results")
        print(f"{'='*60}")
        print(f"  Frames received: {frame_count}")
        print(f"  Total samples:   {total_samples}")
        print(f"  Duration:        {elapsed:.1f}s")
        if elapsed > 0 and frame_count > 0:
            print(f"  Frame rate:      {frame_count/elapsed:.1f} fps")
            print(f"  Sample rate:     {total_samples/elapsed:.0f} Hz (expected ~{sample_rate:.0f})")
        print(f"{'='*60}")

        await ws.close()
        print("\nConnection closed cleanly.")
        return True

    except ConnectionRefusedError:
        print(f"\nFAILED: Connection refused by {host}:{port}")
        print("  - Is the KiwiSDR running?")
        print("  - Is the port correct?")
        return False

    except asyncio.TimeoutError:
        print("\nFAILED: Connection timed out")
        print("  - Is the host reachable?")
        print("  - Check firewall settings")
        return False

    except ConnectionError as e:
        print(f"\nFAILED: {e}")
        return False

    except websockets.exceptions.InvalidStatusCode as e:
        print(f"\nFAILED: WebSocket upgrade rejected with HTTP {e.status_code}")
        print("  - The server may not support WebSocket at this path")
        return False

    except Exception as e:
        print(f"\nFAILED: {type(e).__name__}: {e}")
        return False


def main():
    host = sys.argv[1] if len(sys.argv) > 1 else "kiwisdr.kfsdr.com"
    port = 8073

    # Allow host:port format
    if ":" in host:
        parts = host.rsplit(":", 1)
        host = parts[0]
        port = int(parts[1])

    freq_khz = float(sys.argv[2]) if len(sys.argv) > 2 else 14040.0
    mode = sys.argv[3] if len(sys.argv) > 3 else "cw"
    duration = int(sys.argv[4]) if len(sys.argv) > 4 else 5

    success = asyncio.run(test_connection(host, port, freq_khz, mode, duration))
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
