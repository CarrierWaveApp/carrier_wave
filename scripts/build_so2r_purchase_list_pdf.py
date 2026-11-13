#!/usr/bin/env python3
"""
Generate the SO2R Box purchase list PDF.

Source of truth: docs/schematics/so2r-box/BOM.md (parts list) and REVIEW.md
(part substitutions / sourcing fixes flagged by the multi-agent design review).

Two vendors only — DigiKey (parametric parts) and Amazon (modules, hardware,
assortment kits) — to satisfy the "fewest vendors" requirement. Consumables
(wire, solder, enclosures, cables) are listed without price estimates because
they were not on the original BOM.
"""

from urllib.parse import quote_plus
from reportlab.lib import colors
from reportlab.lib.pagesizes import LETTER
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle,
    PageBreak, KeepTogether,
)


def dk(mfr_pn):
    return f"https://www.digikey.com/en/products/filter?keywords={quote_plus(mfr_pn)}"


def amzn(query):
    return f"https://www.amazon.com/s?k={quote_plus(query)}"


# ---------- Styles ----------

styles = getSampleStyleSheet()
styles.add(ParagraphStyle(
    name="Body", parent=styles["BodyText"], fontSize=9, leading=11,
))
styles.add(ParagraphStyle(
    name="Cell", parent=styles["BodyText"], fontSize=8, leading=10,
))
styles.add(ParagraphStyle(
    name="CellRight", parent=styles["BodyText"], fontSize=8, leading=10,
    alignment=2,
))
styles.add(ParagraphStyle(
    name="H2", parent=styles["Heading2"], fontSize=13, leading=16,
    spaceBefore=10, spaceAfter=6,
))
styles.add(ParagraphStyle(
    name="H3", parent=styles["Heading3"], fontSize=11, leading=14,
    spaceBefore=8, spaceAfter=4,
))
styles.add(ParagraphStyle(
    name="Caption", parent=styles["BodyText"], fontSize=8, leading=10,
    textColor=colors.grey,
))


def link(url, label):
    return (
        f'<link href="{url}"><font color="#1155cc"><u>{label}</u></font></link>'
    )


def P(text, style="Body"):
    return Paragraph(text, styles[style])


def cell(text):
    return Paragraph(text, styles["Cell"])


def cell_r(text):
    return Paragraph(text, styles["CellRight"])


# ---------- Data ----------
# Each row: (qty, description, mfr_pn_or_keyword, vendor_link, unit_price, ext_price, note)
# REVIEW substitutions are baked in. Original BOM part is shown in the note column
# when a substitution was made.

dk_control_ics = [
    # (qty, desc, search_text, link_label, unit, ext, note)
    (3, "CD4051BE 8:1 analog mux (DIP-16)", "CD4051BE", 0.57, 1.71, ""),
    (1, "CD4052BE dual 4:1 analog mux (DIP-16)", "CD4052BE", 0.63, 0.63, ""),
    (1, "SN74HCT595N 8-bit shift reg (DIP-16)", "SN74HCT595N", 0.66, 0.66,
     "REVIEW B6: HCT (TTL) variant — 74HC595N at 5V will not latch reliably from 3.3V GPIO"),
    (1, "MCP6002-I/P dual op-amp (DIP-8)", "MCP6002-I/P", 0.68, 0.68, ""),
    (1, "INA333P instrumentation amp (DIP-8)", "INA333P", 5.00, 5.00,
     "REVIEW B4: replaces INA128PA (NRND, out-of-spec at 3.3V single supply)"),
    (4, "THAT1646P14-U balanced line driver (DIP-8)", "THAT1646P14-U", 5.10, 20.40,
     "BOM doc-only fix: actually DIP-8 not DIP-14"),
    (1, "TC7660HCPA -5V charge pump (DIP-8)", "TC7660HCPA", 2.50, 2.50,
     "REVIEW B2: replaces ICL7660CPA+ (20mA limit too low for 4x THAT1646)"),
    (4, "MAX3232ECPE+ RS-232 transceiver (DIP-16)", "MAX3232ECPE+", 2.13, 8.52, ""),
    (2, "P82B96PN I2C bus buffer (DIP-8)", "P82B96PN", 1.26, 2.52,
     "REVIEW B7 + sourcing: DIP-8 (not -D SOIC). 1x control + 1x RF box."),
    (8, "LTV-817 optocoupler (DIP-4)", "LTV-817", 0.23, 1.84,
     "Consider PC817XB (CTR>=130%) per REVIEW major issue"),
]

dk_control_conn = [
    (1, "XLR female panel jack (mic in)", "NC3FD-LX", 3.50, 3.50, ""),
    (4, "XLR male panel jack (mic out x4)", "NC3MD-LX", 3.60, 14.40, ""),
    (4, "DE-9 female panel mount, solder cup (CAT RS-232)", "L77SDE09SOJ4F", 1.55, 6.20, ""),
    (3, "USB-C panel receptacle, 5-pin", "USB4105-GF-A", 2.50, 7.50,
     "REVIEW sourcing: replaces UJ20-AF-3-SMT-TR (mid-mount SMT, not panel)"),
    (11, "3.5mm TRS panel-mount jack (HP + CW key + radio audio)", "35RAPC3BH4", 2.50, 27.50,
     "Single-SKU consolidation per BOM tip: TRS for everything; mono signals leave Ring open"),
    (1, "RJ45 panel mount jack (Neutrik)", "NE8FDP", 5.00, 5.00,
     "REVIEW sourcing: replaces 54602-908LF (PCB-mount, not panel)"),
    (8, "2-pin PCB header 2.54mm (PTT + TX-INH)", "0022232021", 0.25, 2.00, ""),
    (1, "10kohm stereo audio-taper pot, 6mm shaft", "PTV09A-4025F-A103", 2.75, 2.75,
     "REVIEW sourcing: -A103 = log audio taper (BOM listed -B103 = linear)"),
]

dk_rf_box = [
    (2, "MCP23017-E/SP 16-bit I2C GPIO expander (DIP-28)", "MCP23017-E/SP", 1.46, 2.92, ""),
    (3, "ULN2803AN 8-ch Darlington driver (DIP-18)", "ULN2803AN", 0.73, 2.19, ""),
    (1, "L7805CV 5V regulator (TO-220)", "L7805CV", 0.61, 0.61, ""),
    (18, "Omron G2RL-1-E-CF 12V SPDT PCB relay", "G2RL-1-E-CF-DC12", 4.56, 82.08,
     "Verify -DC12 suffix (12V coil)"),
]

dk_passives = [
    (18, "51 ohm 1W metal-oxide resistor", "MOX1CT52R510J", 0.30, 5.40,
     "RF box NC-side termination — must be 1W. Yageo MOX1 series or similar."),
]

dk_bpf_mod = [
    (9, "2N7000 N-channel MOSFET (TO-92)", "2N7000", 0.24, 2.16, ""),
    (9, "1N4148 signal diode (DO-35)", "1N4148", 0.04, 0.36, ""),
    (1, "9-position 0.1in header (BPF mod harness, both ends)", "PRT-09377", 1.50, 1.50,
     "Either end; cut from a 40-pin breakaway header"),
]

amzn_modules = [
    (1, "Heltec WiFi LoRa 32 V3 (ESP32-S3, USB-C)", "Heltec WiFi LoRa 32 V3 ESP32-S3", 12.00, 12.00,
     "Confirm V3 (ESP32-S3) not V2 (ESP32). REVIEW B5: buzz-test GPIO 33-38 vs PSRAM before layout."),
    (2, "CJMCU-752 SC16IS752 dual UART breakout", "CJMCU-752 SC16IS752 breakout", 7.00, 14.00, ""),
    (3, "CP2102N USB-UART module (USB-C)", "CP2102N USB-C module", 2.50, 7.50,
     "Counterfeit risk — REVIEW suggests Adafruit/Sparkfun if reliability matters"),
    (1, "WS2812B 5mm/8mm through-hole pack (>=4)", "WS2812B 5mm through hole", 5.00, 5.00,
     "Sold in packs of 10-20; lowest single-pack price ~$5"),
]

amzn_hardware = [
    (1, "16mm momentary push button, white cap (4-pack)", "16mm momentary push button white", 8.00, 8.00,
     "BOM specs 4 individual @ $2 — 4-pack lands at the same total"),
    (1, "12V 1A wall adapter, 2.1mm center-positive", "12V 1A power supply 2.1mm center positive", 7.00, 7.00,
     "REVIEW: prefer 3-prong/earthed unit; bond chassis to mains earth"),
    (4, "SO-239 UHF panel-mount jack", "SO-239 panel mount UHF connector", 2.50, 10.00, ""),
    (18, "SMA or BNC panel-mount jack (match BPF modules)", "SMA panel mount bulkhead jack 50 ohm", 1.00, 18.00,
     "9 per radio x 2 radios. Pick the connector your BPF-8As use."),
    (1, "525-pc 1/4W metal-film resistor assortment", "1/4W metal film resistor assortment kit 525", 7.00, 7.00,
     "Covers 300/470/1k/4.7k/5.1k/10k/22k/100k from BOM passives table"),
    (1, "Ceramic capacitor assortment (>=100nF qty 100)", "ceramic capacitor assortment kit 0.1uF", 8.00, 8.00,
     "Bulk 100nF for IC bypass — BOM calls for ~40+"),
    (1, "Electrolytic capacitor kit (10/100/1000uF, 16-25V)", "electrolytic capacitor assortment kit", 8.00, 8.00,
     "Covers 10uF/100uF/1000uF rows in BOM"),
    (1, "Small perfboard / proto board pack", "perfboard prototyping board pack", 5.00, 5.00,
     "Covers BPF-8A mod MOSFET board + spares for control/RF box"),
    (1, "Ribbon cable (28-30cm) + JST-XH 9-pin pair", "JST XH 9 pin connector ribbon cable", 5.00, 5.00,
     "BPF-8A mod harness"),
]

# ---------- Totals ----------

def section_total(rows):
    return sum(r[4] for r in rows)


totals = {
    "DigiKey - Control Box ICs":   section_total(dk_control_ics),
    "DigiKey - Connectors/Hardware": section_total(dk_control_conn),
    "DigiKey - RF Box":            section_total(dk_rf_box),
    "DigiKey - Passives (51R 1W)": section_total(dk_passives),
    "DigiKey - BPF-8A Mod":        section_total(dk_bpf_mod),
    "Amazon - Modules":            section_total(amzn_modules),
    "Amazon - Hardware/Kits":      section_total(amzn_hardware),
}
dk_total = (
    totals["DigiKey - Control Box ICs"]
    + totals["DigiKey - Connectors/Hardware"]
    + totals["DigiKey - RF Box"]
    + totals["DigiKey - Passives (51R 1W)"]
    + totals["DigiKey - BPF-8A Mod"]
)
amzn_total = totals["Amazon - Modules"] + totals["Amazon - Hardware/Kits"]
grand_total = dk_total + amzn_total


# ---------- Table builder ----------

def make_table(rows, vendor):
    """vendor is 'digikey' or 'amazon' to pick link style."""
    header = [
        cell("<b>Qty</b>"), cell("<b>Description</b>"),
        cell("<b>Mfr PN / Search</b>"),
        cell_r("<b>Unit</b>"), cell_r("<b>Ext</b>"),
        cell("<b>Notes</b>"),
    ]
    data = [header]
    for qty, desc, key, unit, ext, note in rows:
        url = dk(key) if vendor == "digikey" else amzn(key)
        data.append([
            cell_r(str(qty)),
            cell(desc),
            cell(link(url, key)),
            cell_r(f"${unit:.2f}"),
            cell_r(f"${ext:.2f}"),
            cell(note),
        ])
    # Subtotal row
    sub = sum(r[4] for r in rows)
    data.append([
        cell(""), cell(""), cell_r("<b>Subtotal</b>"),
        cell(""), cell_r(f"<b>${sub:.2f}</b>"), cell(""),
    ])
    t = Table(data, colWidths=[
        0.35*inch, 2.4*inch, 1.5*inch, 0.55*inch, 0.55*inch, 1.95*inch,
    ], repeatRows=1)
    t.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -2), 0.25, colors.grey),
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e8e8e8")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LINEABOVE", (0, -1), (-1, -1), 0.6, colors.black),
        ("BACKGROUND", (0, -1), (-1, -1), colors.HexColor("#f6f6f6")),
    ]))
    return t


# ---------- Document ----------

def build(out_path):
    doc = SimpleDocTemplate(
        out_path, pagesize=LETTER,
        leftMargin=0.6*inch, rightMargin=0.6*inch,
        topMargin=0.6*inch, bottomMargin=0.6*inch,
        title="SO2R Box - Consolidated Purchase List",
        author="Carrier Wave",
    )
    flow = []

    # ---- Title block ----
    flow.append(Paragraph(
        "<b>SO2R Box &mdash; Consolidated Purchase List</b>",
        ParagraphStyle("T", parent=styles["Title"], fontSize=18, leading=22),
    ))
    flow.append(Paragraph(
        "Two-vendor consolidation (DigiKey + Amazon). All part-number cells are "
        "clickable and resolve to the vendor search/listing for that part. "
        "Substitutions called out in <i>REVIEW.md</i> (multi-agent design review on "
        "<font face='Courier'>claude/analyze-so2r-build-plan-0xj7Q</font>) are baked in; the "
        "Notes column flags each swap.",
        styles["Body"],
    ))
    flow.append(Spacer(1, 6))

    # ---- Summary ----
    flow.append(P("<b>Cost summary</b>", "H2"))
    summary_rows = [
        ["Section", "Subtotal"],
        ["DigiKey - Control box ICs & modules",    f"${totals['DigiKey - Control Box ICs']:.2f}"],
        ["DigiKey - Connectors & hardware",        f"${totals['DigiKey - Connectors/Hardware']:.2f}"],
        ["DigiKey - RF box ICs, regulator, relays", f"${totals['DigiKey - RF Box']:.2f}"],
        ["DigiKey - 51 ohm 1W RF terminations",    f"${totals['DigiKey - Passives (51R 1W)']:.2f}"],
        ["DigiKey - BPF-8A modification parts",    f"${totals['DigiKey - BPF-8A Mod']:.2f}"],
        ["DigiKey subtotal",                       f"${dk_total:.2f}"],
        ["Amazon - Pre-built modules",             f"${totals['Amazon - Modules']:.2f}"],
        ["Amazon - Hardware, kits, adapters",      f"${totals['Amazon - Hardware/Kits']:.2f}"],
        ["Amazon subtotal",                        f"${amzn_total:.2f}"],
        ["Parts grand total (pre-tax, pre-shipping)", f"${grand_total:.2f}"],
    ]
    st = Table(summary_rows, colWidths=[4.6*inch, 1.2*inch])
    st.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -1), 0.25, colors.grey),
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e8e8e8")),
        ("FONTNAME", (0, 6), (-1, 6), "Helvetica-Bold"),
        ("FONTNAME", (0, 9), (-1, 9), "Helvetica-Bold"),
        ("FONTNAME", (0, 10), (-1, 10), "Helvetica-Bold"),
        ("BACKGROUND", (0, 6), (-1, 6), colors.HexColor("#f6f6f6")),
        ("BACKGROUND", (0, 9), (-1, 9), colors.HexColor("#f6f6f6")),
        ("BACKGROUND", (0, 10), (-1, 10), colors.HexColor("#fff5cc")),
        ("ALIGN", (1, 0), (1, -1), "RIGHT"),
        ("FONTSIZE", (0, 0), (-1, -1), 9),
    ]))
    flow.append(st)
    flow.append(Spacer(1, 6))
    flow.append(Paragraph(
        "<b>Note on totals:</b> the original BOM totalled ~$297. The substitutions "
        "in this list (INA333P, TC7660HCPA, USB4105-GF-A, NE8FDP, P82B96PN x2, "
        "74HCT595N, A-taper pot) net to roughly +$5 over the BOM. The REVIEW's "
        "headline ~$580 delivered figure adds enclosures, mains-earthed PSU, PCB "
        "fab, hardware, shipping, and tax &mdash; none of those line items appear on "
        "the original BOM, so they are <b>not priced here</b>; see &ldquo;Consumables &amp; "
        "build supplies&rdquo; below for the generic shopping list.",
        styles["Caption"],
    ))

    # ---- DigiKey order ----
    flow.append(PageBreak())
    flow.append(P("<b>DigiKey order</b>", "H2"))
    flow.append(Paragraph(
        f"All ICs, semiconductors, parametric resistors, relays, panel "
        f"connectors. Single order &mdash; DigiKey ships orders &gt; $100 free in the "
        f"US (DigiKey subtotal here is <b>${dk_total:.2f}</b>). Click any "
        f"part number to jump to that part's DigiKey search.",
        styles["Body"],
    ))

    flow.append(P("Control box &mdash; ICs &amp; semiconductors", "H3"))
    flow.append(make_table(dk_control_ics, "digikey"))
    flow.append(Spacer(1, 6))

    flow.append(P("Control box &mdash; panel connectors &amp; hardware", "H3"))
    flow.append(make_table(dk_control_conn, "digikey"))
    flow.append(Spacer(1, 6))

    flow.append(P("RF box &mdash; ICs, regulator, relays", "H3"))
    flow.append(make_table(dk_rf_box, "digikey"))
    flow.append(Spacer(1, 6))

    flow.append(P("RF box &mdash; 51 ohm 1W terminations", "H3"))
    flow.append(make_table(dk_passives, "digikey"))
    flow.append(Spacer(1, 6))

    flow.append(P("BPF-8A modification (per modified unit)", "H3"))
    flow.append(make_table(dk_bpf_mod, "digikey"))

    # ---- Amazon order ----
    flow.append(PageBreak())
    flow.append(P("<b>Amazon order</b>", "H2"))
    flow.append(Paragraph(
        f"Pre-built modules (impossible or impractical to hand-solder), "
        f"connectors that ship cheaper from import sellers, and bulk passive "
        f"assortment kits that beat per-line DigiKey pricing. Amazon subtotal: "
        f"<b>${amzn_total:.2f}</b>. AliExpress is typically 30-50% cheaper on "
        f"these items at the cost of 2-4 week lead time &mdash; same search "
        f"terms apply.",
        styles["Body"],
    ))

    flow.append(P("Pre-built modules", "H3"))
    flow.append(make_table(amzn_modules, "amazon"))
    flow.append(Spacer(1, 6))

    flow.append(P("Hardware, kits, adapters", "H3"))
    flow.append(make_table(amzn_hardware, "amazon"))

    # ---- REVIEW advisory ----
    flow.append(PageBreak())
    flow.append(P("<b>Pre-power-on advisory parts (from REVIEW.md)</b>", "H2"))
    flow.append(Paragraph(
        "These items are <b>not on the original BOM</b> and are therefore not "
        "priced or totalled. They are the additional parts the multi-agent "
        "review flagged as required before first power-on or before contest "
        "use. Source from DigiKey on the same order to avoid a second shipment.",
        styles["Body"],
    ))
    advisory_rows = [
        [cell("<b>Issue</b>"), cell("<b>Add</b>"), cell("<b>Reason</b>")],
        [cell("B3 - INA333 DC return"),
         cell(link(dk("CFR-25JB-52-100K"), "2x 100k 1/4W (already in passive kit)")),
         cell("IA inputs need DC bias return to REF; resistor kit covers this.")],
        [cell("B6 - WS2812B level shift"),
         cell(link(dk("SN74AHCT125N"), "1x SN74AHCT125N (DIP-14)")),
         cell("Mandatory 3.3V->5V level shift ahead of NeoPixel chain.")],
        [cell("B8 - I2C cable surge"),
         cell(link(dk("SP0503BAHTG"), "2x SP0503BAHTG TVS array")),
         cell("One at each end of the inter-box Cat5e for SDA2/SCL2 ESD protection.")],
        [cell("B8 - Phantom-power protection"),
         cell(link(dk("ECE-A1JN470U"), "8x 47uF 63V bipolar + 8x 5.6V zener")),
         cell("Block 48V phantom backwards into THAT1646 outputs (4 jacks x 2 pins).")],
        [cell("Major - PTT watchdog"),
         cell(link(dk("NE555P"), "1x NE555P (DIP-8)")),
         cell("Hardware monostable kills PTT after ~30s if firmware hangs.")],
        [cell("Major - +12V protection"),
         cell(link(dk("SMAJ30A"), "1x SMAJ30A TVS + 2A polyfuse")),
         cell("Surge clamp + reset fuse on the barrel jack.")],
        [cell("Major - BPF-8A interlock"),
         cell(link(dk("SN74HC138N"), "1x SN74HC138N (DIP-16)")),
         cell("1-of-N decoder so a stuck I2C bit cannot enable two filters at once.")],
    ]
    at = Table(advisory_rows, colWidths=[1.6*inch, 2.6*inch, 3.1*inch])
    at.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -1), 0.25, colors.grey),
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e8e8e8")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
    ]))
    flow.append(at)

    # ---- Consumables ----
    flow.append(Spacer(1, 12))
    flow.append(P("<b>Consumables &amp; build supplies (general suggestions, unpriced)</b>", "H2"))
    flow.append(Paragraph(
        "Not on the original BOM, so no price estimate is given. Substitute "
        "whatever you already have on the bench. The list assumes you are "
        "starting from zero.",
        styles["Body"],
    ))

    consumables = [
        ("Enclosures",
         "Two project boxes (control box + RF box). Hammond 1455-series extruded "
         "aluminium is the typical choice; size to fit ~150 nets across ~50 ICs in "
         "the control box and 18 relays + 4 SO-239 in the RF box. Earthed metal "
         "chassis preferred for RF immunity and mains-earth bond."),
        ("PCB fabrication",
         "REVIEW recommends a single-sided JLCPCB run instead of perfboard. KiCad "
         "netlist already exists at docs/schematics/so2r-box/so2r-box.net (after "
         "fixing the P82B96 pinout). Approx 5 boards from JLC are typical "
         "low-volume fab."),
        ("Solder, flux, wick",
         "Lead-free or 60/40 rosin-core, 0.6-0.8 mm. No-clean flux pen. Solder "
         "wick for rework."),
        ("Hookup wire",
         "22-24 AWG stranded silicone, 4-6 colours. ~3 m each. 18 AWG for the "
         "+12 V power rail."),
        ("Heat-shrink, cable lacing",
         "2:1 ratio, mixed-diameter pack. Spiral wrap or lacing for harnesses."),
        ("Cat5e patch cable",
         "1-3 m solid-core for the I2C/UART link between the two boxes (RJ45 to "
         "RJ45). Keep it short enough that the 4.7 k pull-ups stay inside the "
         "159 ns rise budget the design verified."),
        ("Radio-side cabling",
         "4x DB9 male-male RS-232 cables (CAT, length per shack), 3x USB-C cables "
         "(CAT-USB), 4x 3.5 mm TRS patch (radio audio in), 1x 3.5 mm TS (foot-PTT), "
         "4x mic XLR patch cables (operator headsets to mic-out jacks)."),
        ("Standoffs &amp; fasteners",
         "M3 brass standoff kit (5/8/10 mm), M3 + M2.5 machine screws, panel-jack "
         "lock washers, rubber feet."),
        ("IC sockets",
         "DIP-8/14/16/18/28 machine-pin sockets for every through-hole IC. "
         "Cheap insurance for a hand-built rework cycle."),
        ("Bench supplies",
         "Isopropyl alcohol (>=99%) for flux clean-up, anti-static mat/strap, "
         "labelmaker tape, ferrite clip-ons (one per panel 3.5 mm jack &mdash; "
         "REVIEW minor item)."),
        ("Test gear (likely already on the bench)",
         "Multimeter, oscilloscope or USB logic analyser (for I2C bring-up), 50 ohm "
         "dummy load + power meter (mandatory before the first relay click test "
         "with an antenna connected)."),
    ]
    for title, body in consumables:
        flow.append(Paragraph(f"<b>{title}.</b> {body}", styles["Body"]))
        flow.append(Spacer(1, 3))

    # ---- Footer notes ----
    flow.append(Spacer(1, 10))
    flow.append(P("<b>Ordering notes</b>", "H3"))
    flow.append(Paragraph(
        "&bull; <b>One DigiKey order, one Amazon order.</b> Two vendors total. "
        "Tax and shipping will add ~5-10% on top of the parts subtotal.<br/>"
        "&bull; <b>Verify before paying.</b> DigiKey small-quantity prices drift; "
        "the figures here come from the BOM's May 2026 estimates. Click each "
        "link and re-check stock.<br/>"
        "&bull; <b>Sourcing fallbacks for counterfeits.</b> If the Amazon "
        "CP2102N modules look dubious on arrival, swap for "
        + link(dk("CP2102N-MINIEK"), "Silicon Labs CP2102N-MINIEK") +
        " (DigiKey, ~$15 each) &mdash; same chip, guaranteed authentic.<br/>"
        "&bull; <b>Heltec V3 GPIO conflict.</b> REVIEW B5 says GPIO 33-38 may be "
        "PSRAM on most current production. Buzz the Heltec out before laying out "
        "the control board; if reserved, pivot to "
        + link(dk("ESP32-S3-WROOM-1U-N16R8"), "ESP32-S3-WROOM-1U-N16R8") +
        " on DigiKey instead.",
        styles["Body"],
    ))

    doc.build(flow)


if __name__ == "__main__":
    out = "/home/user/carrier_wave/docs/schematics/so2r-box/PURCHASE_LIST.pdf"
    build(out)
    print(f"Wrote {out}")
