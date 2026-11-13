#!/usr/bin/env python3
"""
Generate the SO2R Box POC bench plan PDF.

A standalone, step-by-step plan to retire the architectural risk in the SO2R
box design using the parts in POC_PARTS_LIST.pdf, on a breadboard, over ~4
evenings. Each milestone lists wiring, the test you actually run, the
success criterion, and the most common failure mode to look out for.
"""

from reportlab.lib import colors
from reportlab.lib.pagesizes import LETTER
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak,
    KeepTogether,
)


styles = getSampleStyleSheet()
styles.add(ParagraphStyle(name="Body", parent=styles["BodyText"], fontSize=9.5, leading=12))
styles.add(ParagraphStyle(name="Cell", parent=styles["BodyText"], fontSize=8.5, leading=10.5))
styles.add(ParagraphStyle(name="CellMono", parent=styles["BodyText"], fontSize=8, leading=10, fontName="Courier"))
styles.add(ParagraphStyle(name="H2", parent=styles["Heading2"], fontSize=14, leading=17, spaceBefore=12, spaceAfter=4))
styles.add(ParagraphStyle(name="H3", parent=styles["Heading3"], fontSize=11.5, leading=14, spaceBefore=8, spaceAfter=3))
styles.add(ParagraphStyle(name="H4", parent=styles["Heading4"], fontSize=10, leading=12, spaceBefore=6, spaceAfter=2, textColor=colors.HexColor("#444")))
styles.add(ParagraphStyle(name="Caption", parent=styles["BodyText"], fontSize=8, leading=10, textColor=colors.grey))
styles.add(ParagraphStyle(name="Mono", parent=styles["BodyText"], fontSize=8.5, leading=11, fontName="Courier", leftIndent=10))


def P(text, style="Body"): return Paragraph(text, styles[style])
def C(t): return Paragraph(t, styles["Cell"])
def Cm(t): return Paragraph(t, styles["CellMono"])


def wiring_table(rows):
    """rows: list of (from, to, note) tuples; first row is header."""
    head = [C("<b>From</b>"), C("<b>To</b>"), C("<b>Notes</b>")]
    data = [head] + [[Cm(a), Cm(b), C(c)] for a, b, c in rows]
    t = Table(data, colWidths=[2.0*inch, 2.0*inch, 3.2*inch], repeatRows=1)
    t.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -1), 0.25, colors.grey),
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e8e8e8")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
    ]))
    return t


def milestone_block(num, title, evening, parts, goal, wiring, steps, success, gotchas):
    """Build the visual block for one milestone."""
    flow = []
    flow.append(P(f"<b>Milestone {num} &mdash; {title}</b>", "H2"))
    flow.append(P(f"<i>Time budget:</i> {evening}", "Caption"))

    flow.append(P("Parts in play", "H4"))
    flow.append(P(parts))

    flow.append(P("Goal", "H4"))
    flow.append(P(goal))

    if wiring:
        flow.append(P("Wiring", "H4"))
        flow.append(wiring_table(wiring))

    flow.append(P("What you actually do", "H4"))
    for i, s in enumerate(steps, 1):
        flow.append(P(f"<b>{i}.</b> {s}"))

    flow.append(P("Success criterion", "H4"))
    flow.append(P(success))

    flow.append(P("Failure modes to watch for", "H4"))
    for g in gotchas:
        flow.append(P(f"&bull; {g}"))

    flow.append(Spacer(1, 8))
    return flow


def build(out_path):
    doc = SimpleDocTemplate(
        out_path, pagesize=LETTER,
        leftMargin=0.6*inch, rightMargin=0.6*inch,
        topMargin=0.55*inch, bottomMargin=0.55*inch,
        title="SO2R Box - POC Bench Plan",
        author="Carrier Wave",
    )
    flow = []

    flow.append(Paragraph(
        "<b>SO2R Box &mdash; POC Bench Plan</b>",
        ParagraphStyle("T", parent=styles["Title"], fontSize=18, leading=22),
    ))
    flow.append(P(
        "Five milestones, ~4 evenings, to retire the architectural risk in the "
        "SO2R box design before committing to the full $325 BOM. Companion to "
        "<font face='Courier'>POC_PARTS_LIST.pdf</font>. Bench-only, breadboard-only, no "
        "soldering iron required until milestone 4."
    ))
    flow.append(Spacer(1, 6))

    flow.append(P("How to use this plan", "H3"))
    flow.append(P(
        "Each milestone names the wires you push into the breadboard, the test you "
        "actually run, the one signal that proves it worked, and the failure mode "
        "you are most likely to chase. <b>Milestone 4 (CAT control) is the riskiest "
        "leg of the entire build</b> &mdash; if a particular radio refuses to talk over "
        "USB-CDC, you want to know now, not after $325 of parts have arrived. "
        "Treat each milestone as a stop-gate: don't move forward until its success "
        "criterion is met."
    ))

    flow.append(P("Heltec V3 pin map used throughout", "H3"))
    flow.append(P(
        "Pin assignments avoid the GPIO 33-38 PSRAM range called out in REVIEW B5. "
        "Confirm with a multimeter on your actual board before wiring &mdash; "
        "Heltec sometimes ships with PSRAM and sometimes without."
    ))
    pinmap = [
        (C("<b>Heltec pin</b>"), C("<b>Role</b>"), C("<b>Used in milestone</b>")),
        (Cm("GPIO 41 (SDA)"),  C("I2C SDA to MCP23017"),               C("2, 3, 5")),
        (Cm("GPIO 42 (SCL)"),  C("I2C SCL to MCP23017"),               C("2, 3, 5")),
        (Cm("GPIO 17 (TX1)"),  C("UART1 TX to CP2102N RX"),            C("4")),
        (Cm("GPIO 18 (RX1)"),  C("UART1 RX from CP2102N TX"),          C("4")),
        (Cm("GPIO 4 - 7"),     C("4x button inputs (INPUT_PULLUP)"),   C("1, 3")),
        (Cm("GPIO 21"),        C("WS2812B data line (3.3V drive)"),    C("3")),
        (Cm("GPIO 8, 9, 10"),  C("CD4051 address A, B, C"),            C("5")),
        (Cm("Built-in OLED"),  C("SSD1306 on I2C0 (separate from MCP)"), C("1, 3, 4")),
    ]
    pt = Table(pinmap, colWidths=[1.3*inch, 3.0*inch, 2.9*inch])
    pt.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -1), 0.25, colors.grey),
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e8e8e8")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
    ]))
    flow.append(pt)

    flow.append(PageBreak())

    # ---- Milestone 1 ----
    flow += milestone_block(
        1, "Blink + OLED + button", "~1 hour",
        parts="Heltec V3, USB-C cable, breadboard, 1x tactile button, 1x WS2812B 5mm.",
        goal=(
            "Confirm the toolchain: Arduino-IDE or PlatformIO can compile, flash, "
            "open the serial monitor, drive the built-in OLED, read a GPIO, and "
            "drive one NeoPixel from 3.3V. Establishes that the next four evenings "
            "are about <i>circuit</i> debugging, not toolchain debugging."
        ),
        wiring=[
            ("Heltec USB-C",       "Laptop",                "Power + serial monitor."),
            ("Button leg 1",       "Heltec GPIO 4",          "Other leg to GND. Use INPUT_PULLUP."),
            ("WS2812B pin 1 (DIN)", "Heltec GPIO 21",        "Drive directly from 3.3V — yes, it will work badly. That's the point."),
            ("WS2812B pin 2 (+5V)", "Heltec 5V (USB) pin",   "USB bus voltage is fine for one LED."),
            ("WS2812B pin 4 (GND)", "Heltec GND",             ""),
        ],
        steps=[
            "Install the Heltec ESP32 board package (Heltec docs link is in their GitHub).",
            "Flash the stock <font face='Courier'>OLED_Hello</font> example. Verify the OLED prints text.",
            "Add code: on button press, increment a counter on the OLED and cycle the WS2812B through red &rarr; green &rarr; blue &rarr; off.",
            "Open the serial monitor at 115200. Print the button-press count to USB-CDC.",
            "Touch the WS2812B with a finger while it's running &mdash; warm-finger trick: heat shifts the threshold, the LED will start dropping pixels or glitching. <b>This is REVIEW B6 in person.</b>",
        ],
        success=(
            "OLED shows a button-press counter that increments on every press. WS2812B "
            "responds &mdash; even if colours are wrong &mdash; on every press. Serial monitor "
            "prints to laptop. You have personally seen the WS2812B misbehave from a 3.3V "
            "drive."
        ),
        gotchas=[
            "Heltec V2 vs V3 confusion: V2 is plain ESP32, V3 is ESP32-S3. Different board package, different pin map. The USB connector is the giveaway &mdash; V3 has USB-C.",
            "If the OLED is dark, the Heltec's <font face='Courier'>Vext</font> pin needs to be pulled LOW first to enable the OLED rail. Heltec's library handles this; bare ESP-IDF doesn't.",
            "If the serial monitor opens then closes immediately on flash, you've selected the USB-CDC port; close all serial windows during flash, reopen after.",
        ],
    )

    flow.append(PageBreak())

    # ---- Milestone 2 ----
    flow += milestone_block(
        2, "I2C bring-up + relay click test", "~1-2 hours",
        parts=(
            "Heltec V3, MCP23017 breakout, 8-channel <b>5V</b> relay module, breadboard, "
            "jumper wires. <b>No 12V supply yet</b> &mdash; the 12V wall adapter is reserved "
            "for the final build with the real G2RL-1-E-CF-DC12 relays (12V coils). "
            "The POC relay module's coils are 5V, so the bench supply for this "
            "milestone is just the laptop's USB."
        ),
        goal=(
            "Validate the I2C control plane that runs the entire RF box. Click each "
            "of the eight relays on/off from the ESP32 with no glitches, no relay "
            "chatter on power-up, no I2C bus hangs. This is the architectural "
            "linchpin &mdash; if it works at 8 channels on a breadboard, it will work at "
            "18 channels on a PCB."
        ),
        wiring=[
            ("Heltec GPIO 41 (SDA)", "MCP23017 SDA + 4.7k to 3V3", "Pull-up is mandatory; some breakouts include it on-board."),
            ("Heltec GPIO 42 (SCL)", "MCP23017 SCL + 4.7k to 3V3", "Same as above."),
            ("Heltec 3V3",          "MCP23017 VDD",                "Logic supply for the GPIO expander."),
            ("Heltec 5V (USB pin)", "Relay module VCC + JD-VCC",   "Option A: single 5V rail off USB powers logic + coils. Leave the JD-VCC jumper installed. 1 coil ~70 mA; running all 8 = ~560 mA, which is above the 500 mA USB-host limit &mdash; do the stress test under Option B."),
            ("(optional) 5V USB charger -> USB-A breakout", "Relay module JD-VCC (jumper PULLED)", "Option B: separate 5V coil rail. Mirrors the final RF box topology (logic and coil rails isolated so a coil collapse can't dip the MCU). Use this for the 60s stress test."),
            ("Heltec GND",          "MCP23017 GND + relay module GND", "Common ground &mdash; mandatory even under Option B."),
            ("MCP23017 A0/A1/A2",   "GND",                              "I2C address = 0x20."),
            ("MCP23017 GPB0-7",     "Relay module IN1-IN8",             "Drive the opto-isolator inputs directly from 3.3V. The opto's current-limit resistor handles the level mismatch."),
        ],
        steps=[
            "Wire Option A first (everything off the Heltec's USB 5V rail). Power on with USB &mdash; relay module status LEDs light, coils should NOT energise yet.",
            "Run an I2C scanner sketch. Expect to find 0x20 (MCP23017) and 0x3C (the on-board OLED).",
            "Configure MCP23017 GPB as outputs (IODIRB = 0x00). Write 0x00 to OLATB. Watch for relay chatter &mdash; if any relay clicks on its own, the MCP outputs powered up high-impedance and the inputs floated. This is the issue REVIEW flags about the ULN2803A power-up state, manifesting here on the relay-module clones. Add 10k pull-downs to GND on IN1-IN8.",
            "<b>Polarity check.</b> Most 8-ch relay modules are active-low (IN pulled to GND energises the relay). Write 0x01 to OLATB &mdash; if relay 1 clicks, the module is active-high; if relay 1 stays put but the OTHER seven click, it's active-low. Note the polarity and invert the bitmask in firmware accordingly.",
            "Walk a single bit through GPB0..GPB7 with a 200 ms delay (binary 0x01, 0x02, 0x04, ... 0x80, with the polarity correction from the previous step). Each relay clicks in sequence.",
            "Switch to Option B for the stress test: plug the relay module's JD-VCC into a 5V USB charger via a USB-A breakout, pull the JD-VCC jumper. Run a tight loop toggling all 8 outputs as fast as the I2C bus allows for 60 seconds. Verify no missed clicks, no MCU brown-out (USB rail no longer collapses under coil inrush).",
            "(If you bought the logic analyzer) Capture SDA/SCL during the walking-bit sequence and confirm clean rise edges, no NACKs.",
        ],
        success=(
            "All 8 relays click on command, in any order, with no chatter on power-up "
            "or power-down, sustained for 60+ seconds of stress testing under "
            "Option B (separate coil supply). I2C scan shows exactly the expected "
            "devices. Polarity is documented in firmware."
        ),
        gotchas=[
            "<b>Do not feed 12V into a 5V relay module's JD-VCC.</b> The 5V coils will overheat and stick closed within minutes. The 12V adapter from POC_PARTS_LIST belongs in the final-build pile, not on this bench.",
            "Counterfeit MCP23017s exist on Amazon. Symptom: I2C scan finds 0x20 but writes to GPIO have no effect. Swap to an Adafruit-branded listing.",
            "Relay-module JD-VCC jumper: Option A leaves it installed (one rail), Option B pulls it (two rails). Pick one explicitly; halfway between the two creates a short.",
            "If 3.3V GPIO won't reliably drive the opto inputs (a few clones use a too-large current-limit resistor sized for 5V logic), the workaround is to keep VCC at 5V from USB &mdash; the opto LED then has the full 5V across the resistor when the IN pin is pulled low by the MCP, and reliably illuminates regardless of the 3.3V high level on the IN net.",
            "Cheap modules sometimes ship with the wrong relay populated. Read the relay can &mdash; you want SRD-05VDC-SL-C (or similar 5V-coil part). If you see SRD-12VDC on the can, the module was mis-shipped; do NOT power it from USB.",
        ],
    )

    flow.append(PageBreak())

    # ---- Milestone 3 ----
    flow += milestone_block(
        3, "Panel UI + state machine", "~1 evening",
        parts="Everything from milestone 2, plus 4x tactile buttons, 4x WS2812B 5mm.",
        goal=(
            "Wire up a working operator panel: four buttons (Radio Select x2, Band-, Band+), "
            "four WS2812B status LEDs, plus the Heltec OLED showing current band + active "
            "radio. Pressing buttons commands relay clicks. This is the milestone where "
            "the SO2R box stops being a parts pile and starts feeling like the actual product."
        ),
        wiring=[
            ("4x button leg 1",  "Heltec GPIO 4, 5, 6, 7",   "INPUT_PULLUP. Other leg of each button to GND. Add 10 nF GPIO-to-GND for RF immunity per REVIEW minor item."),
            ("WS2812B chain DIN", "Heltec GPIO 21",         "First LED's DIN; subsequent LEDs daisy-chain DOUT -> DIN."),
            ("WS2812B +5V",      "Heltec 5V",                "100 uF bulk cap across the LED supply, close to the first LED."),
            ("MCP23017 -> relays", "(as milestone 2)",        ""),
        ],
        steps=[
            "Implement a state machine: state = (active_radio: 1|2, band: 160m..10m). Buttons mutate state.",
            "On state change, write a new bit pattern to MCP23017 OLATB &mdash; mapping bands 160m..10m to GPB0..GPB7.",
            "Drive the four WS2812B LEDs to reflect: active radio (1 LED), PTT state (1 LED), band group (low/high/WARC; 2 LEDs).",
            "Update the OLED on every state change: line 1 = 'RIG 1' / 'RIG 2', line 2 = current band, line 3 = 'PTT' indicator.",
            "(REVIEW B6 again) Pull the WS2812B +5V down to 3.3V on the chain &mdash; watch colours go wrong. Now you have visceral proof you need the 74AHCT125 level shifter in the final build.",
            "Debounce: confirm rapid button mashing produces exactly the intended state transitions, not skips or doubles. ~20-50 ms software debounce is usually enough.",
        ],
        success=(
            "Pressing any button reliably triggers (a) a relay click corresponding to "
            "the new band, (b) the correct OLED state, (c) the correct WS2812B colour. "
            "Each happens within 50 ms of the press. No button mash produces wrong state."
        ),
        gotchas=[
            "WS2812B chain timing is RMT-driven on ESP32-S3. The Arduino library 'FastLED' uses RMT under the hood; if you see corrupted colours <i>only</i> after a serial print or WiFi join, you've collided with RMT &mdash; pin the LED task to core 0 or switch to the I2S-driven driver.",
            "Buttons against rotating-field interference (i.e. when you eventually use this near a transmitter): a 10 nF GPIO-to-GND on each input is the difference between a clean POC and a panel that fires phantom presses.",
        ],
    )

    flow.append(PageBreak())

    # ---- Milestone 4 (PIVOTED) ----
    # The original M4 ("ESP32 talks CAT to the radio") was tried on the bench
    # and abandoned after the topology proved impossible for modern radios.
    # See the deprecation block first, then the new M4 spec.

    flow.append(P("<b>Milestone 4 &mdash; original scope (DEPRECATED)</b>", "H2"))
    flow.append(P(
        "<i>Was:</i> &ldquo;ESP32 talks CAT directly to the radio via an external "
        "CP2102N USB-C UART module.&rdquo; Phases A (UART loopback) and B (PC "
        "&harr; radio direct with Hamlib) passed cleanly. <b>Phase C failed for "
        "fundamental topology reasons</b> against the Yaesu FTX-1 Optima (and any "
        "modern transceiver):"
    ))
    flow.append(P(
        "&bull; <b>The radio's USB-CAT port is a USB device port</b>, not a host. "
        "Two USB devices cannot communicate without an intermediate host. A "
        "CP2102N plugged into the radio's USB jack does nothing - the radio "
        "won't enumerate it. The original wiring diagram was physically "
        "impossible to use."
    ))
    flow.append(P(
        "&bull; <b>The radio's hardware-UART CAT port (CAT-3 on a mini-DIN-10 "
        "TUNER/LINEAR jack) is 5V CMOS</b>, above the ESP32-S3's 3.3V V<sub>IH</sub> "
        "headroom on TX and above the chip's 3.3V absolute-max on RX. Direct "
        "wiring needs a bidirectional level shifter (TXS0108E or BSS138 board) "
        "plus a custom mini-DIN-10 cable - not cheaper than abandoning the path."
    ))
    flow.append(P(
        "&bull; <b>A CP2102N cannot bridge UART &harr; UART.</b> It converts USB &harr; "
        "UART. To bridge between an ESP32 UART and a radio UART you need a host "
        "in the middle (a PC) - which is exactly what the new M4 architecture "
        "embraces."
    ))
    flow.append(Spacer(1, 8))

    flow += milestone_block(
        4, "PC &harr; box USB-CDC protocol (NEW SCOPE)", "~1 evening",
        parts=(
            "Heltec V3 (powered via its onboard USB-C / CP2102N - "
            "<b>no external CP2102N needed</b>), the PC running CW Sweep or the "
            "Python bench client (<font face='Courier'>scripts/so2r_client.py</font>), "
            "a real HF radio if you want to close the integration loop, otherwise "
            "the MCP23017 + relay module from M2 is enough."
        ),
        goal=(
            "<b>Prove the PC-driven control plane.</b> All CAT lives on the PC "
            "(Hamlib / rigctld / Sweep's RadioManager); the box is a smart "
            "USB-CDC peripheral that owns the antenna relay matrix, PTT lines, "
            "audio routing, and panel UI. The PC tells the box which band each "
            "radio is on; the box reports panel button events back to the PC. "
            "This decouples the box from per-vendor CAT protocols and matches the "
            "topology constraints of real radios."
        ),
        wiring=[
            ("Heltec USB-C",      "Mac USB port",          "Onboard CP2102N is the PC link. No external UART hardware."),
            ("(MCP23017 + relay module)", "(as M2 wiring)", "Unchanged from milestone 2."),
            ("Radio CAT cables",  "Mac (separately)",       "Each radio talks CAT to the PC directly via its own cable/library. Not connected to the box at all."),
        ],
        steps=[
            "Phase A &mdash; protocol smoke test on the bench. With the box flashed and the MCP23017 + relay module wired (M2 state), run <font face='Courier'>uv run scripts/so2r_client.py</font> on the Mac. Type <font face='Courier'>ping</font> -> expect <font face='Courier'>PONG</font>. Type <font face='Courier'>state</font> -> see active radio, both bands, both PTT flags, relay mask. This proves the USB-CDC link + parser on both sides.",
            "Phase B &mdash; relay drive via protocol. From the client, run <font face='Courier'>band 1 20m</font>, <font face='Courier'>band 1 40m</font>, <font face='Courier'>band 1 15m</font> in sequence; verify the matching relay clicks on the M2 hardware. Then <font face='Courier'>band 2 80m</font> and verify the radio-2 antenna relay clicks instead (when the active radio switches). Proves the per-radio state model is correctly wired through to the MCP23017 outputs.",
            "Phase C &mdash; panel events. Press BTN1-BTN4 on the panel. Each press should arrive at the client as an unsolicited <font face='Courier'>EVT BTN n PRESS</font> line, and any operator-driven state change (e.g. cycling the band) should arrive as <font face='Courier'>EVT STATE BAND1=20m</font>. Confirm the client's state model stays synchronised after panel-driven changes.",
            "Phase D &mdash; PC-driven frequency follow. Tell the client a frequency (<font face='Courier'>freq 1 14250</font>) and verify it derives the band correctly and pushes the right <font face='Courier'>BAND</font> command. This is the building block for Sweep's eventual integration: any radio frequency change Sweep observes via Hamlib &rarr; <font face='Courier'>set_band_from_frequency()</font> &rarr; the box's relay matrix follows.",
            "Phase E &mdash; PTT round trip. <font face='Courier'>ptt 1 on</font> / <font face='Courier'>ptt 1 off</font>; verify the box accepts and reports state. In v1 the PTT state is logical only (no hardware drive yet); when PTT-out pins are wired in a later milestone, the firmware just adds GPIO drive at the right point and the protocol is unchanged.",
        ],
        success=(
            "PC client can query and mutate the box's state over USB-CDC, the "
            "MCP23017 relay outputs follow band commands within ~10 ms, panel "
            "button presses arrive at the PC as <font face='Courier'>EVT</font> "
            "lines, and the client's state mirror stays consistent with the box "
            "after any combination of PC-driven and operator-driven changes. "
            "<b>No external CP2102N module, no per-radio CAT cabling to the "
            "box, no level shifters.</b>"
        ),
        gotchas=[
            "The 8-band slot model on the box (160/80/40/20/15/10/WARC/BYP) is narrower than Hamlib's full band list. The Python client's <font face='Courier'>band_for_frequency()</font> maps 30m/17m/12m/60m to WARC and 6m/2m/70cm to BYP. If you operate WARC bands competitively, the box's antenna matrix will need a wiring revision later.",
            "Asynchronous EVT lines and synchronous OK / ERR / PONG replies share the same USB-CDC stream. The Python client uses a reader thread to split them; if you re-implement on another stack (Swift / Rust) the same dispatch discipline applies - don't try to do blocking reads from the main loop.",
            "When the box boots, it emits <font face='Courier'>EVT BOOT version=N</font>. The client should treat that as a hint to re-query <font face='Courier'>STATE</font> on connect so its mirror is correct even if the box reset out from under it.",
            "The Heltec's onboard CP2102N enumerates as <font face='Courier'>/dev/cu.usbserial-XXXX</font> on macOS, NOT <font face='Courier'>usbmodem</font>. <font face='Courier'>scripts/so2r_client.py</font> auto-detects this prefix; if you symlink or rename the device the auto-detect will miss it.",
        ],
    )

    flow.append(PageBreak())

    # ---- Milestone 5 ----
    flow += milestone_block(
        5, "Audio mux click-through (STRETCH)", "~1 evening",
        parts="Heltec V3, 1x CD4051BE (DIP-16), 2x 3.5mm audio jack breakouts, smartphone, headphones.",
        goal=(
            "Prove the CD4051 analog mux concept: a single 8:1 mux fed from one source, "
            "with three GPIO lines selecting one of eight inputs (only one used for "
            "POC), output piped to a headphone. Click-free switching at audio rates."
        ),
        wiring=[
            ("Phone audio out",       "CD4051 X0 (pin 13)",   "One channel only; ground both phone L/R and the breadboard ground."),
            ("Heltec GPIO 8, 9, 10",  "CD4051 A, B, C (pins 11, 10, 9)", "Address inputs."),
            ("CD4051 INH (pin 6)",    "GND",                   "Enable the mux."),
            ("CD4051 VDD (pin 16)",   "Heltec 3V3",            "Single-supply operation; audio rides on a virtual ground."),
            ("CD4051 VEE/VSS (pins 7, 8)", "GND",              ""),
            ("CD4051 X (pin 3)",       "Headphone tip",        "Series 10 uF cap, then 10 k to GND on the headphone side &mdash; this is REVIEW's audio coupling reminder in miniature."),
        ],
        steps=[
            "Play a continuous tone from the phone (any frequency-generator app).",
            "Set CD4051 address to 0 (A=B=C=0) &mdash; X0 connects to the X common pin. Tone should be audible in the headphone.",
            "Switch the address to 1, 2, 3 &mdash; tone should go silent (no input wired to those channels).",
            "Switch back to 0 &mdash; tone returns. Listen for a click or pop on the transition; CD4051 'break-before-make' should give a clean silence on the inactive channels.",
            "Optional: wire a second source (a function generator or another phone) to X1, alternate addresses, listen for the mux switching between the two sources without obvious clicks.",
        ],
        success=(
            "Tone is audible only when the address selects the input that has signal "
            "on it. Switching between channels produces no audible click. Audio "
            "quality is acceptable for monitoring (POC quality; final build has the "
            "MCP6002/NJM4556 headphone driver)."
        ),
        gotchas=[
            "CD4051 needs the audio to ride <i>between</i> its VDD and VSS rails. Phone audio is typically AC-coupled around 0V &mdash; the negative half-cycle will be clipped. For POC this is fine (you'll still hear the tone, just distorted on negative peaks); for the final build the design uses a buffered virtual ground at VDD/2 (REVIEW's TLE2426 recommendation).",
            "If you hear strong hum, you forgot to common the phone's ground to the breadboard ground.",
            "If you hear nothing on any address, your phone's headphone-out auto-detected the load as too low. Add a 33 k from input to ground to raise the impedance.",
        ],
    )

    flow.append(PageBreak())

    # ---- Final ----
    flow.append(P("After all milestones pass", "H2"))
    flow.append(P(
        "You now know, with bench evidence, that:"
    ))
    flow.append(P("&bull; The I2C control plane works at 8 channels and will scale to 18."))
    flow.append(P("&bull; The Heltec V3 GPIO assignments you picked don't collide with PSRAM on your specific board (REVIEW B5)."))
    flow.append(P("&bull; WS2812B at 3.3V is unreliable &mdash; the 74AHCT125 in the final BOM is genuinely required (REVIEW B6)."))
    flow.append(P("&bull; Your specific radio talks CAT cleanly over USB-CDC through the CP2102N."))
    flow.append(P("&bull; The CD4051 mux concept is sound."))
    flow.append(Spacer(1, 4))
    flow.append(P("<b>Now is the right time to order the full $325 BOM.</b>"))
    flow.append(Spacer(1, 8))

    flow.append(P("If any milestone fails", "H3"))
    flow.append(P(
        "Stop. Don't order the full BOM until you understand why. A failure here costs $5 "
        "and an evening; a failure after $325 of parts arrive costs days and may require "
        "a re-spin of the PCB design."
    ))

    flow.append(P("Bench-safety reminders", "H3"))
    flow.append(P("&bull; Use a dummy load every time you key PTT during milestone 4. Never into an antenna."))
    flow.append(P("&bull; The 12V wall-wart adapter has no isolation &mdash; respect it as if it were mains."))
    flow.append(P("&bull; Anti-static wrist strap when handling the CD4051 and MCP23017 directly &mdash; both are CMOS and the breakout boards don't protect the IC pins you wire to."))

    doc.build(flow)


if __name__ == "__main__":
    out = "/home/user/carrier_wave/docs/schematics/so2r-box/POC_BENCH_PLAN.pdf"
    build(out)
    print(f"Wrote {out}")
