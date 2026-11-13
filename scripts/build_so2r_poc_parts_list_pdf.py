#!/usr/bin/env python3
"""
Generate the SO2R Box proof-of-concept (POC) parts-list PDF.

Goal: smallest Amazon-only / Prime-eligible parts list that lets you validate
the SO2R box's core control plane (ESP32 + I2C + relays + buttons + LEDs)
and the audio-mux concept on a breadboard before committing to the full
$325 kit. Skips everything that's only needed in the final boxed build:
balanced mic chain, RS-232 transceivers, ±5V rail, RF connectors, panel
hardware, enclosures, the 18 Omron relays.
"""

from urllib.parse import quote_plus
from reportlab.lib import colors
from reportlab.lib.pagesizes import LETTER
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak,
)


def amzn(query):
    return f"https://www.amazon.com/s?k={quote_plus(query)}"


styles = getSampleStyleSheet()
styles.add(ParagraphStyle(name="Body", parent=styles["BodyText"], fontSize=9, leading=11))
styles.add(ParagraphStyle(name="Cell", parent=styles["BodyText"], fontSize=8, leading=10))
styles.add(ParagraphStyle(name="CellR", parent=styles["BodyText"], fontSize=8, leading=10, alignment=2))
styles.add(ParagraphStyle(name="H2", parent=styles["Heading2"], fontSize=13, leading=16, spaceBefore=10, spaceAfter=6))
styles.add(ParagraphStyle(name="H3", parent=styles["Heading3"], fontSize=11, leading=14, spaceBefore=8, spaceAfter=4))
styles.add(ParagraphStyle(name="Caption", parent=styles["BodyText"], fontSize=8, leading=10, textColor=colors.grey))


def link(url, label):
    return f'<link href="{url}"><font color="#1155cc"><u>{label}</u></font></link>'


def C(text): return Paragraph(text, styles["Cell"])
def CR(text): return Paragraph(text, styles["CellR"])
def P(text, style="Body"): return Paragraph(text, styles[style])


# (qty, description, amazon_search, unit_price, ext_price, purpose)
core_parts = [
    (1, "Heltec WiFi LoRa 32 V3 (ESP32-S3, USB-C, built-in OLED)",
     "Heltec WiFi LoRa 32 V3 ESP32-S3", 15.00, 15.00,
     "The MCU. Same board the final build uses — POC firmware moves over unchanged."),
    (1, "Half-size solderless breadboard, 2-pack",
     "half size breadboard 400 tie points 2 pack", 8.00, 8.00,
     "One for the MCU + I2C bus, one for the audio mux experiment."),
    (1, "Dupont jumper wire kit (M-M, M-F, F-F, ~120 pcs)",
     "dupont jumper wires kit male female 120 pieces", 8.00, 8.00,
     "All inter-board wiring on the breadboard."),
    (1, "MCP23017 I2C 16-bit GPIO expander breakout",
     "MCP23017 I2C breakout module", 8.00, 8.00,
     "Validates the I2C control plane. Same chip the RF box uses to drive 18 relays — POC drives 8."),
    (1, "8-channel 5V relay module (opto-isolated)",
     "8 channel 5V relay module opto isolated", 10.00, 10.00,
     "Stand-in for the 18x Omron G2RL. Coils are 5V (powered from USB 5V or a 5V USB charger - NOT from the 12V adapter below). Opto inputs accept the Heltec's 3.3V GPIO directly."),
    (1, "Tactile push-button assortment (12mm, breadboard-friendly)",
     "tactile push button 12mm breadboard assortment", 6.00, 6.00,
     "Four buttons = the four panel buttons (Radio Select x2, Band -, Band +)."),
    (1, "WS2812B 5mm through-hole RGB LED, 10-pack",
     "WS2812B 5mm through hole RGB LED 10 pack", 7.00, 7.00,
     "Four LEDs = panel status. Confirms the level-shifter requirement (REVIEW B6) for yourself."),
    (1, "CP2102N USB-C to UART module",
     "CP2102N USB-C UART bridge module", 7.00, 7.00,
     "Validates one CAT-USB path to a real radio. Buy one, prove the path, then order the other two."),
    (1, "12V / 1A wall adapter, 2.1mm center-positive",
     "12V 1A power supply 2.1mm center positive", 8.00, 8.00,
     "Reserved for the final build (the real G2RL relays are 12V coil). NOT used for the POC - it would burn the 5V module's coils. Roll forward to the real RF box."),
    (1, "2.1mm DC barrel jack to screw-terminal adapter, 5-pack",
     "2.1mm DC barrel jack screw terminal adapter", 6.00, 6.00,
     "Lets the wall adapter plug into a breadboard rail. Easier than chopping the cable."),
]

stretch_parts = [
    (1, "CD4051BE 8:1 analog mux, DIP-16, 5-pack",
     "CD4051BE DIP16 5 pack", 7.00, 7.00,
     "Audio routing POC. Three address pins from the ESP32 select 1 of 8 inputs."),
    (1, "Resistor assortment, 1/4W metal-film, 525 piece",
     "1/4W metal film resistor assortment kit 525", 7.00, 7.00,
     "Pull-ups, current-limit on LEDs, audio bias. Covers every value the final BOM needs."),
    (1, "Ceramic capacitor assortment (>=100nF qty 100)",
     "ceramic capacitor assortment kit 0.1uF", 8.00, 8.00,
     "100nF IC bypass on every chip — bring up the I2C bus cleanly the first time."),
    (1, "3.5mm TRS panel jack to bare wire, breakout 5-pack",
     "3.5mm audio jack breakout module 5 pack", 8.00, 8.00,
     "Patch a phone's audio into the CD4051 input + a headphone into the output to hear the mux switch."),
    (1, "USB logic analyzer, 8-channel, 24 MHz (Saleae-clone)",
     "USB logic analyzer 8 channel 24MHz", 12.00, 12.00,
     "Pulseview / Sigrok compatible. Indispensable for I2C and WS2812B bring-up. Skip if you already own one."),
]


def table_for(rows):
    head = [C("<b>Qty</b>"), C("<b>Item</b>"), C("<b>Search</b>"),
            CR("<b>Unit</b>"), CR("<b>Ext</b>"), C("<b>Why you need it</b>")]
    data = [head]
    for qty, desc, q, unit, ext, purpose in rows:
        data.append([CR(str(qty)), C(desc), C(link(amzn(q), q)),
                     CR(f"${unit:.2f}"), CR(f"${ext:.2f}"), C(purpose)])
    sub = sum(r[4] for r in rows)
    data.append([C(""), C(""), CR("<b>Subtotal</b>"), C(""),
                 CR(f"<b>${sub:.2f}</b>"), C("")])
    t = Table(data, colWidths=[0.35*inch, 2.1*inch, 1.55*inch, 0.55*inch, 0.55*inch, 2.2*inch], repeatRows=1)
    t.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -2), 0.25, colors.grey),
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e8e8e8")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LINEABOVE", (0, -1), (-1, -1), 0.6, colors.black),
        ("BACKGROUND", (0, -1), (-1, -1), colors.HexColor("#f6f6f6")),
    ]))
    return t


def build(out_path):
    doc = SimpleDocTemplate(
        out_path, pagesize=LETTER,
        leftMargin=0.6*inch, rightMargin=0.6*inch,
        topMargin=0.6*inch, bottomMargin=0.6*inch,
        title="SO2R Box - POC Parts List",
        author="Carrier Wave",
    )
    flow = []

    flow.append(Paragraph(
        "<b>SO2R Box &mdash; Proof-of-Concept Parts List</b>",
        ParagraphStyle("T", parent=styles["Title"], fontSize=18, leading=22),
    ))
    flow.append(Paragraph(
        "Bench-only POC. Every line is an Amazon search and is expected to be "
        "Prime-eligible from a major US warehouse (ELEGOO, SunFounder, "
        "Adafruit, HiLetgo, AZDelivery typically ship Prime). All wiring is "
        "on a breadboard &mdash; no soldering, no enclosure, no panel hardware. "
        "Skips the entire balanced audio chain, RS-232 transceivers, the &plusmn;5V "
        "rail, all 18 Omron RF relays, and every panel-mount connector.",
        styles["Body"],
    ))
    flow.append(Spacer(1, 4))

    core_total = sum(r[4] for r in core_parts)
    stretch_total = sum(r[4] for r in stretch_parts)
    flow.append(Paragraph(
        f"<b>Core POC subtotal: ${core_total:.2f}</b> &nbsp;&middot;&nbsp; "
        f"Stretch (audio mux + bring-up tools) adds ${stretch_total:.2f} &nbsp;&middot;&nbsp; "
        f"Everything: <b>${core_total + stretch_total:.2f}</b>.",
        styles["Body"],
    ))

    flow.append(P("What this POC proves", "H3"))
    flow.append(Paragraph(
        "&bull; <b>I2C control plane.</b> Heltec ESP32-S3 -> MCP23017 -> 8-ch relay module &mdash; "
        "the exact topology the RF box uses, scaled to 8 relays instead of 18.<br/>"
        "&bull; <b>Operator interface.</b> Four tactile buttons + four WS2812B LEDs + the Heltec's "
        "built-in OLED &mdash; renders status, accepts band/radio commands.<br/>"
        "&bull; <b>CAT-USB path.</b> One CP2102N module talking to a real radio over USB-C, "
        "validating the rig-control libraries before you order three of them.<br/>"
        "&bull; <b>Audio mux concept (stretch).</b> A single CD4051 fed from a phone's audio out "
        "into a headphone, with three GPIO lines selecting one of eight inputs &mdash; same chip the "
        "final design uses three of.<br/>"
        "&bull; <b>REVIEW B6 firsthand.</b> Drive the WS2812B chain directly from 3.3V GPIO and "
        "watch the colours go wrong &mdash; cheap, memorable proof that the level shifter is mandatory.",
        styles["Body"],
    ))

    flow.append(P("Core POC parts", "H2"))
    flow.append(table_for(core_parts))

    flow.append(P("Stretch parts (audio mux + bring-up tools)", "H2"))
    flow.append(table_for(stretch_parts))

    flow.append(P("Not included on purpose", "H3"))
    flow.append(Paragraph(
        "&bull; <b>Omron G2RL relays ($82).</b> The relay module above is functionally identical for "
        "logic-validation; you only need the real Omrons when you wire actual RF.<br/>"
        "&bull; <b>THAT1646 + INA333 + TC7660H mic chain (~$30).</b> Audio in/out can be POCed with "
        "a phone and headphones into the CD4051 &mdash; the balanced chain is a separate POC.<br/>"
        "&bull; <b>MAX3232 RS-232 quartet (~$9).</b> Use USB-CAT (CP2102N) against a USB-capable "
        "radio for POC; RS-232 is just a level translation that adds nothing architecturally.<br/>"
        "&bull; <b>SC16IS752 UART expanders (~$14).</b> Heltec native UARTs + USB CDC give you "
        "three CAT paths for free &mdash; enough to prove SO2R control of two radios.<br/>"
        "&bull; <b>P82B96 + Cat5e inter-box link (~$5).</b> Run everything on one breadboard; the "
        "two-box split is a packaging decision, not an architectural one.<br/>"
        "&bull; <b>BPF-8A modification parts (~$10).</b> Defer until you've validated the band-switch "
        "command pipeline against the 8-ch relay module.<br/>"
        "&bull; <b>All panel-mount connectors, the enclosure, the PCB.</b> Bench POC. Breadboard only.",
        styles["Body"],
    ))

    flow.append(P("Suggested POC milestones (4 evenings)", "H3"))
    flow.append(Paragraph(
        "<b>1. Blink + OLED + button (1 hr).</b> Flash the Heltec, light an LED on the integrated "
        "OLED, read a button. Confirms the toolchain.<br/>"
        "<b>2. I2C bring-up (1-2 hrs).</b> Probe MCP23017 from the ESP32, click each relay on the "
        "8-ch module in sequence. Verify ULN2803 isn't needed for the POC (the relay module has its "
        "own driver transistors).<br/>"
        "<b>3. Panel UI (1 evening).</b> Four buttons -> band/radio state machine. Four WS2812B "
        "LEDs reflect state. OLED shows current band + active radio.<br/>"
        "<b>4. CAT control (1 evening).</b> CP2102N to a real radio's USB-CAT port. Implement "
        "frequency/band read + PTT through your chosen rig-control library. <i>This is the riskiest "
        "leg of the build &mdash; do it before committing to the rest of the BOM.</i><br/>"
        "<b>5. (Stretch) Audio mux (1 evening).</b> CD4051 between a phone and a headphone. Address "
        "lines from three GPIOs. Listen for the click-through on each channel select.",
        styles["Body"],
    ))

    flow.append(P("Prime/shipping notes", "H3"))
    flow.append(Paragraph(
        "Search URLs above intentionally show multiple sellers per item so you can pick the "
        "fastest-arriving Prime listing on the day. Counterfeit risk is real for the CP2102N and "
        "MCP23017 &mdash; if the module behaves strangely on the bench, swap to an Adafruit-branded "
        "listing (same Amazon site, costs ~2x) rather than re-debugging your firmware. Total POC "
        "weight is well under 1kg; a single Amazon Prime order usually consolidates to 1-2 "
        "deliveries.",
        styles["Body"],
    ))

    doc.build(flow)


if __name__ == "__main__":
    out = "/home/user/carrier_wave/docs/schematics/so2r-box/POC_PARTS_LIST.pdf"
    build(out)
    print(f"Wrote {out}")
