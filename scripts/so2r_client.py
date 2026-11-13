#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pyserial"]
# ///
"""
SO2R Box PC-side client.

The SO2R box (Heltec ESP32-S3) acts as a USB-CDC peripheral that drives the
HF antenna relay matrix, panel UI, and audio routing. CAT control of the
radios lives on the PC (Hamlib / rigctld / Sweep) - the box does NOT talk to
radios directly. The PC tells the box which antenna / PTT / audio routing to
apply, and the box reports panel button events back.

This module provides:
  * BoxClient    - high-level state-aware client
  * SerialTransport / MockTransport - swappable transports
  * Wire protocol parser (encode commands, decode OK/ERR/PONG, decode EVT)
  * Python port of BandUtilities.deriveBand() so PCs can derive bands from
    frequencies without round-tripping through Swift
  * An interactive CLI (run this file directly)

Eventual Swift integration: the matching Swift code in
  swift/macos/CWSweep/Services/SO2RBox/  (TBD)
will reuse the existing RadioManager slot model (.a and .b map to radio 1
and radio 2) and call BandUtilities.deriveBand() in CarrierWaveCore. This
Python client is the bench-testing tool; the Swift code is the production
runtime in CW Sweep.

Wire protocol v1 - see docs/schematics/so2r-box/POC_BENCH_PLAN.pdf (M4):
  PC -> box  : ASCII commands, one per line, '\\n' terminated.
  Box -> PC  : 'OK [data]' / 'ERR <reason>' / 'PONG' replies, and
               unsolicited 'EVT <kind> ...' lines on operator action.
"""

from __future__ import annotations

import argparse
import glob
import re
import sys
import threading
import time
from dataclasses import dataclass, field
from queue import Empty, Queue
from typing import Callable, Optional

import serial  # type: ignore  # pyserial


# ----------------------------------------------------------------------------
# Bands - port of CarrierWaveCore/BandUtilities.swift::deriveBand
# Plus mapping into the 8 band slots the SO2R box firmware understands.
# ----------------------------------------------------------------------------

# Box knows these 8 band names (matches firmware BAND_NAMES[]):
BOX_BANDS: tuple[str, ...] = (
    "160m", "80m", "40m", "20m", "15m", "10m", "WARC", "BYP",
)

# Bands recognised by CarrierWaveCore::BandUtilities. WARC subset, 60m, and
# VHF/UHF are mapped onto the box's 8 slots below.
_FULL_BAND_RANGES_MHZ: list[tuple[str, float, float]] = [
    ("160m", 1.8,    2.0),
    ("80m",  3.5,    4.0),
    ("60m",  5.3,    5.4),
    ("40m",  7.0,    7.3),
    ("30m",  10.1,   10.15),
    ("20m",  14.0,   14.35),
    ("17m",  18.068, 18.168),
    ("15m",  21.0,   21.45),
    ("12m",  24.89,  24.99),
    ("10m",  28.0,   29.7),
    ("6m",   50.0,   54.0),
    ("2m",   144.0,  148.0),
    ("70cm", 420.0,  450.0),
]

# Bands the box has a real antenna-relay slot for vs ones that fall into the
# WARC group vs ones that bypass entirely.
_WARC_SET = {"30m", "17m", "12m", "60m"}
_BYP_SET  = {"6m", "2m", "70cm"}


def derive_band(frequency_khz: Optional[float]) -> Optional[str]:
    """Return the full CarrierWaveCore band name (e.g. '20m', '17m') for a
    frequency in kHz, or None if outside any amateur band. Mirrors
    BandUtilities.deriveBand(from:) byte-for-byte."""
    if frequency_khz is None:
        return None
    mhz = frequency_khz / 1000.0
    for name, lo, hi in _FULL_BAND_RANGES_MHZ:
        if lo <= mhz < hi:
            return name
    return None


def map_to_box_band(full_band: Optional[str]) -> str:
    """Map a CarrierWaveCore band name into one of the 8 box slots."""
    if full_band is None:
        return "BYP"
    if full_band in _WARC_SET:
        return "WARC"
    if full_band in _BYP_SET:
        return "BYP"
    if full_band in BOX_BANDS:
        return full_band
    return "BYP"


def band_for_frequency(frequency_khz: Optional[float]) -> str:
    """Convenience: frequency_kHz -> box band slot directly."""
    return map_to_box_band(derive_band(frequency_khz))


# ----------------------------------------------------------------------------
# Wire protocol
# ----------------------------------------------------------------------------

@dataclass
class BoxState:
    """Mirror of the box's internal state as last reported."""
    active_radio: int = 1
    bands: tuple[str, str] = ("160m", "160m")   # (radio1, radio2)
    ptt:   tuple[bool, bool] = (False, False)    # (radio1, radio2)
    relays: int = 0x00
    connected: bool = False
    firmware_version: Optional[int] = None


# Parsed responses

@dataclass
class Reply:
    kind: str          # "OK" | "ERR" | "PONG"
    body: str          # raw payload after "OK " etc.
    raw: str           # original line


@dataclass
class Event:
    """Async event from the box."""
    kind: str          # "BOOT" | "BTN" | "STATE"
    body: str
    raw: str


# Regexes for parsing replies

_STATE_KV = re.compile(r"(\w+)=(\S+)")


def parse_state_payload(body: str) -> dict[str, str]:
    """Parse 'RADIO=1 BAND1=20m BAND2=40m PTT1=OFF PTT2=OFF RELAYS=0x08'."""
    return dict(_STATE_KV.findall(body))


def encode_command(kind: str, *args: str) -> bytes:
    """Encode a single command line for transmission."""
    line = " ".join((kind, *args)).strip()
    return (line + "\n").encode("ascii", errors="replace")


# ----------------------------------------------------------------------------
# Transports
# ----------------------------------------------------------------------------

class Transport:
    """Abstract: send bytes, yield lines."""

    def open(self) -> None: ...
    def close(self) -> None: ...
    def write_line(self, line: bytes) -> None: ...
    def read_line(self, timeout: float = 1.0) -> Optional[str]: ...
    @property
    def is_open(self) -> bool: ...


class SerialTransport(Transport):
    """Real USB-CDC connection to the Heltec via /dev/cu.usbserial-*"""

    def __init__(self, port: str, baud: int = 115200):
        self.port = port
        self.baud = baud
        self._ser: Optional[serial.Serial] = None
        self._buf = b""

    def open(self) -> None:
        self._ser = serial.Serial(self.port, self.baud, timeout=0.1)
        time.sleep(0.2)  # give USB-CDC time to settle
        self._ser.reset_input_buffer()

    def close(self) -> None:
        if self._ser:
            self._ser.close()
            self._ser = None

    def write_line(self, line: bytes) -> None:
        if not self._ser:
            raise RuntimeError("transport not open")
        self._ser.write(line)

    def read_line(self, timeout: float = 1.0) -> Optional[str]:
        """Read one '\\n'-terminated line. Returns None on timeout."""
        if not self._ser:
            raise RuntimeError("transport not open")
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            chunk = self._ser.read(self._ser.in_waiting or 1)
            if chunk:
                self._buf += chunk
                if b"\n" in self._buf:
                    line, _, self._buf = self._buf.partition(b"\n")
                    return line.decode("ascii", errors="replace").rstrip("\r")
            else:
                time.sleep(0.01)
        return None

    @property
    def is_open(self) -> bool:
        return self._ser is not None and self._ser.is_open


class MockTransport(Transport):
    """In-process fake box for unit testing the client without hardware.

    Implements just enough of the protocol to round-trip the commands the
    client sends. Useful both for CI and for sanity-checking that the
    protocol implementation here matches the spec before the firmware-side
    Claude has finished its half.
    """

    def __init__(self) -> None:
        self._open = False
        self._state = BoxState(
            active_radio=1,
            bands=("160m", "160m"),
            ptt=(False, False),
            relays=0x01,
            connected=True,
            firmware_version=1,
        )
        self._inbox: Queue[str] = Queue()

    def open(self) -> None:
        self._open = True
        self._inbox.put("EVT BOOT version=1")

    def close(self) -> None:
        self._open = False

    @property
    def is_open(self) -> bool:
        return self._open

    def write_line(self, line: bytes) -> None:
        if not self._open:
            raise RuntimeError("transport not open")
        text = line.decode("ascii", errors="replace").strip()
        self._inbox.put(self._handle(text))

    def read_line(self, timeout: float = 1.0) -> Optional[str]:
        try:
            return self._inbox.get(timeout=timeout)
        except Empty:
            return None

    # Mock helpers
    def inject_event(self, line: str) -> None:
        """Drop an EVT line into the queue, simulating panel action."""
        self._inbox.put(line)

    def _handle(self, line: str) -> str:
        if not line:
            return "ERR empty"
        head, *rest = line.split()
        head_u = head.upper()
        if head_u == "PING":
            return "PONG"
        if head_u in ("?", "HELP"):
            return "OK commands=PING,STATE,RADIO,BAND,RELAYS,PTT,RESET,HELP"
        if head_u == "STATE":
            s = self._state
            return (
                f"OK RADIO={s.active_radio} "
                f"BAND1={s.bands[0]} BAND2={s.bands[1]} "
                f"PTT1={'ON' if s.ptt[0] else 'OFF'} "
                f"PTT2={'ON' if s.ptt[1] else 'OFF'} "
                f"RELAYS=0x{s.relays:02X}"
            )
        if head_u == "RADIO":
            if not rest or rest[0] not in ("1", "2"):
                return "ERR usage: RADIO <1|2>"
            self._state.active_radio = int(rest[0])
            return "OK"
        if head_u == "BAND":
            if len(rest) != 2 or rest[0] not in ("1", "2") or rest[1] not in BOX_BANDS:
                return "ERR usage: BAND <1|2> <" + "|".join(BOX_BANDS) + ">"
            idx = int(rest[0]) - 1
            new = list(self._state.bands)
            new[idx] = rest[1]
            self._state.bands = (new[0], new[1])
            # mock antenna relay drive
            self._state.relays = 1 << BOX_BANDS.index(new[self._state.active_radio - 1])
            return "OK"
        if head_u == "RELAYS":
            if not rest:
                return "ERR usage: RELAYS <0xNN>"
            try:
                self._state.relays = int(rest[0], 0) & 0xFF
                return "OK"
            except ValueError:
                return "ERR not a number"
        if head_u == "PTT":
            if len(rest) != 2 or rest[0] not in ("1", "2") or rest[1].upper() not in ("ON", "OFF"):
                return "ERR usage: PTT <1|2> <ON|OFF>"
            idx = int(rest[0]) - 1
            new = list(self._state.ptt)
            new[idx] = rest[1].upper() == "ON"
            self._state.ptt = (new[0], new[1])
            return "OK"
        if head_u == "RESET":
            self._state = BoxState(
                active_radio=1,
                bands=("160m", "160m"),
                ptt=(False, False),
                relays=0x01,
                connected=True,
                firmware_version=1,
            )
            return "OK reset"
        return f"ERR unknown {head}"


# ----------------------------------------------------------------------------
# BoxClient - the high-level API
# ----------------------------------------------------------------------------

EventCallback = Callable[[Event], None]


class BoxClient:
    """Synchronous request/response + background event listener.

    Usage::

        with BoxClient.auto() as box:
            box.ping()
            state = box.query_state()
            box.set_band(1, "20m")
            box.on_event(lambda e: print("EVT:", e.raw))
            ...

    The event-listener thread runs continuously while the client is open and
    dispatches any incoming line that isn't a synchronous reply to the
    callback list. Synchronous calls block until they get OK / ERR / PONG.
    """

    def __init__(self, transport: Transport):
        self.transport = transport
        self.state = BoxState()
        self._event_callbacks: list[EventCallback] = []
        self._reply_queue: Queue[Reply] = Queue()
        self._reader_thread: Optional[threading.Thread] = None
        self._stop = threading.Event()
        self._lock = threading.Lock()   # serialise outgoing commands

    # -- lifecycle ---------------------------------------------------------

    @classmethod
    def auto(cls, baud: int = 115200) -> BoxClient:
        """Find the first /dev/cu.usbserial* port and connect."""
        ports = sorted(glob.glob("/dev/cu.usbserial*") + glob.glob("/dev/cu.SLAB*"))
        if not ports:
            raise RuntimeError(
                "no /dev/cu.usbserial* device found; plug the Heltec in"
            )
        return cls(SerialTransport(ports[0], baud))

    def open(self) -> None:
        self.transport.open()
        self._stop.clear()
        self._reader_thread = threading.Thread(
            target=self._reader_loop, name="so2r-reader", daemon=True,
        )
        self._reader_thread.start()

    def close(self) -> None:
        self._stop.set()
        if self._reader_thread:
            self._reader_thread.join(timeout=2.0)
            self._reader_thread = None
        self.transport.close()

    def __enter__(self) -> BoxClient:
        self.open()
        return self

    def __exit__(self, *exc) -> None:
        self.close()

    # -- background reader -------------------------------------------------

    def _reader_loop(self) -> None:
        while not self._stop.is_set():
            line = self.transport.read_line(timeout=0.25)
            if line is None:
                continue
            line = line.strip()
            if not line:
                continue
            if line.startswith("EVT "):
                self._dispatch_event(line)
            elif line.startswith(("OK", "ERR", "PONG")):
                kind = line.split(maxsplit=1)[0]
                body = line[len(kind):].lstrip()
                self._reply_queue.put(Reply(kind=kind, body=body, raw=line))
            else:
                # Unsolicited boot banner, debug noise, etc. - treat as event
                self._dispatch_event(f"EVT RAW {line}")

    def _dispatch_event(self, raw: str) -> None:
        # 'EVT BOOT version=1' -> kind='BOOT' body='version=1'
        parts = raw.split(maxsplit=2)
        kind = parts[1] if len(parts) > 1 else ""
        body = parts[2] if len(parts) > 2 else ""
        ev = Event(kind=kind, body=body, raw=raw)
        self._apply_event_to_state(ev)
        for cb in list(self._event_callbacks):
            try:
                cb(ev)
            except Exception as exc:
                # don't let a bad callback kill the reader
                print(f"[so2r] event callback raised {exc!r}", file=sys.stderr)

    def _apply_event_to_state(self, ev: Event) -> None:
        """Mutate self.state when the box reports an operator-driven change."""
        if ev.kind == "BOOT":
            kv = dict(_STATE_KV.findall(ev.body))
            if "version" in kv:
                try:
                    self.state.firmware_version = int(kv["version"])
                except ValueError:
                    pass
            self.state.connected = True
        elif ev.kind == "STATE":
            self._apply_state_kv(dict(_STATE_KV.findall(ev.body)))

    def _apply_state_kv(self, kv: dict[str, str]) -> None:
        if "RADIO" in kv:
            try:
                self.state.active_radio = int(kv["RADIO"])
            except ValueError:
                pass
        bands = list(self.state.bands)
        if "BAND1" in kv: bands[0] = kv["BAND1"]
        if "BAND2" in kv: bands[1] = kv["BAND2"]
        self.state.bands = (bands[0], bands[1])
        ptt = list(self.state.ptt)
        if "PTT1" in kv: ptt[0] = kv["PTT1"].upper() == "ON"
        if "PTT2" in kv: ptt[1] = kv["PTT2"].upper() == "ON"
        self.state.ptt = (ptt[0], ptt[1])
        if "RELAYS" in kv:
            try:
                self.state.relays = int(kv["RELAYS"], 0)
            except ValueError:
                pass

    def on_event(self, callback: EventCallback) -> None:
        """Register a callback for asynchronous events from the box."""
        self._event_callbacks.append(callback)

    # -- synchronous command machinery -------------------------------------

    def _send(self, kind: str, *args: str, timeout: float = 2.0) -> Reply:
        with self._lock:
            # Drain stale replies that may have come in while we weren't asking.
            # (Shouldn't normally happen since each send blocks on its reply,
            # but defensive.)
            while True:
                try:
                    self._reply_queue.get_nowait()
                except Empty:
                    break
            self.transport.write_line(encode_command(kind, *args))
            try:
                reply = self._reply_queue.get(timeout=timeout)
            except Empty as exc:
                raise TimeoutError(f"no reply to {kind} {args} within {timeout}s") from exc
            if reply.kind == "ERR":
                raise RuntimeError(f"box rejected {kind}: {reply.body}")
            return reply

    # -- high-level commands -----------------------------------------------

    def ping(self) -> bool:
        return self._send("PING").kind == "PONG"

    def query_state(self) -> BoxState:
        reply = self._send("STATE")
        self._apply_state_kv(parse_state_payload(reply.body))
        return self.state

    def set_radio(self, n: int) -> None:
        if n not in (1, 2):
            raise ValueError("radio must be 1 or 2")
        self._send("RADIO", str(n))
        self.state.active_radio = n

    def set_band(self, radio: int, band: str) -> None:
        if radio not in (1, 2):
            raise ValueError("radio must be 1 or 2")
        if band not in BOX_BANDS:
            raise ValueError(f"band must be one of {BOX_BANDS}")
        self._send("BAND", str(radio), band)
        bands = list(self.state.bands)
        bands[radio - 1] = band
        self.state.bands = (bands[0], bands[1])

    def set_band_from_frequency(self, radio: int, frequency_khz: float) -> str:
        """Derive the box band from a frequency and push it. Returns the
        band name actually sent."""
        band = band_for_frequency(frequency_khz)
        self.set_band(radio, band)
        return band

    def set_relays(self, mask: int) -> None:
        if not 0 <= mask <= 0xFF:
            raise ValueError("mask must be 0..255")
        self._send("RELAYS", f"0x{mask:02X}")
        self.state.relays = mask

    def set_ptt(self, radio: int, on: bool) -> None:
        if radio not in (1, 2):
            raise ValueError("radio must be 1 or 2")
        self._send("PTT", str(radio), "ON" if on else "OFF")
        ptt = list(self.state.ptt)
        ptt[radio - 1] = on
        self.state.ptt = (ptt[0], ptt[1])

    def reset(self) -> None:
        self._send("RESET")
        self.query_state()


# ----------------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------------

HELP = """\
commands:
  ping                   - PING/PONG round-trip latency check
  state                  - query and print full box state
  radio <1|2>            - set active radio
  band <r> <name>        - set band for radio r; name in 160m/80m/40m/20m/
                           15m/10m/WARC/BYP
  freq <r> <kHz>         - derive band from frequency and set it
  relays <0xNN>          - override the 8-relay mask (bench debug)
  ptt <r> <on|off>       - set PTT state for radio r
  reset                  - restore power-on defaults
  listen [secs]          - dump every line from the box for N seconds (default 10)
  inject <line>          - (mock only) drop an EVT line into the queue
  quit / exit            - close the connection and exit
  help / ?               - this help
"""


def run_cli(client: BoxClient, mock_transport: Optional[MockTransport]) -> None:
    print("SO2R box CLI - 'help' for commands, 'quit' to exit.")

    # Print every event the box sends, prefixed.
    def _print_event(ev: Event) -> None:
        print(f"  <- {ev.raw}")
    client.on_event(_print_event)

    try:
        while True:
            try:
                line = input("so2r> ").strip()
            except (EOFError, KeyboardInterrupt):
                print()
                break
            if not line:
                continue
            if line in ("quit", "exit", "q"):
                break
            if line in ("help", "?"):
                print(HELP)
                continue

            head, *args = line.split()
            try:
                if head == "ping":
                    t0 = time.monotonic()
                    ok = client.ping()
                    dt = (time.monotonic() - t0) * 1000
                    print(f"  {'PONG' if ok else 'no response'}  ({dt:.1f} ms)")
                elif head == "state":
                    s = client.query_state()
                    print(f"  active radio : {s.active_radio}")
                    print(f"  bands        : R1={s.bands[0]}  R2={s.bands[1]}")
                    print(f"  ptt          : R1={'ON' if s.ptt[0] else 'OFF'}  "
                          f"R2={'ON' if s.ptt[1] else 'OFF'}")
                    print(f"  relays       : 0x{s.relays:02X}  "
                          f"({s.relays:08b})")
                    print(f"  firmware     : {s.firmware_version}")
                elif head == "radio" and len(args) == 1:
                    client.set_radio(int(args[0]))
                    print("  ok")
                elif head == "band" and len(args) == 2:
                    client.set_band(int(args[0]), args[1])
                    print("  ok")
                elif head == "freq" and len(args) == 2:
                    band = client.set_band_from_frequency(int(args[0]), float(args[1]))
                    print(f"  -> band {band}")
                elif head == "relays" and len(args) == 1:
                    client.set_relays(int(args[0], 0))
                    print("  ok")
                elif head == "ptt" and len(args) == 2:
                    client.set_ptt(int(args[0]), args[1].lower() == "on")
                    print("  ok")
                elif head == "reset":
                    client.reset()
                    print("  ok")
                elif head == "listen":
                    secs = float(args[0]) if args else 10.0
                    print(f"  listening for {secs}s, press Ctrl-C to stop...")
                    try:
                        time.sleep(secs)
                    except KeyboardInterrupt:
                        print()
                elif head == "inject" and args:
                    if mock_transport is None:
                        print("  ERR inject only works with --mock")
                    else:
                        mock_transport.inject_event(" ".join(args))
                else:
                    print(f"  ERR unknown / bad-args. type 'help'.")
            except (ValueError, RuntimeError, TimeoutError) as exc:
                print(f"  ERR {exc}")
    finally:
        client.close()


def main() -> int:
    parser = argparse.ArgumentParser(description="SO2R box PC-side client")
    parser.add_argument("--port", default=None,
                        help="serial device (default: auto-detect /dev/cu.usbserial*)")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--mock", action="store_true",
                        help="use an in-process mock instead of a real serial port")
    parser.add_argument("--demo", action="store_true",
                        help="run a non-interactive self-test sequence and exit")
    args = parser.parse_args()

    mock_transport: Optional[MockTransport] = None
    if args.mock:
        mock_transport = MockTransport()
        transport: Transport = mock_transport
    elif args.port:
        transport = SerialTransport(args.port, args.baud)
    else:
        try:
            client = BoxClient.auto(args.baud)
        except RuntimeError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 1
        transport = client.transport

    if not args.mock and not args.port:
        # we already built a client via .auto()
        pass
    else:
        client = BoxClient(transport)

    try:
        client.open()
    except (serial.SerialException, OSError) as exc:
        print(f"failed to open transport: {exc}", file=sys.stderr)
        return 1

    if args.demo:
        return _run_demo(client)

    run_cli(client, mock_transport)
    return 0


def _run_demo(client: BoxClient) -> int:
    """Sequence used by Milestone 4 phase A: ping, query, set, query, ptt round-trip."""
    print("== SO2R box demo sequence ==")
    try:
        client.on_event(lambda ev: print(f"  <- {ev.raw}"))
        time.sleep(0.1)
        print("[1] ping ...")
        assert client.ping(), "no PONG"
        print("[2] initial state ...")
        print(f"    {client.query_state()}")
        print("[3] set radio 1 to 20m ...")
        client.set_band(1, "20m")
        print("[4] set radio 2 to 40m ...")
        client.set_band(2, "40m")
        print("[5] re-query state ...")
        print(f"    {client.query_state()}")
        print("[6] frequency -> band for 14250 kHz on radio 1 ...")
        chosen = client.set_band_from_frequency(1, 14_250)
        print(f"    chose band: {chosen}")
        print("[7] PTT on / off cycle on radio 1 ...")
        client.set_ptt(1, True)
        time.sleep(0.2)
        client.set_ptt(1, False)
        print("[8] reset ...")
        client.reset()
        print(f"    final state: {client.query_state()}")
        print("== demo OK ==")
        return 0
    except Exception as exc:
        print(f"demo failed: {exc}", file=sys.stderr)
        return 1
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
