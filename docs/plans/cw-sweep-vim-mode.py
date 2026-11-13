#!/usr/bin/env python3
"""Generate CW Sweep Vim Mode design document PDF."""

from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.colors import HexColor, black, white
from reportlab.lib.units import inch
from reportlab.lib.enums import TA_LEFT, TA_CENTER
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
    PageBreak,
    KeepTogether,
)

# ── Colors ──────────────────────────────────────────────────────────────

DARK_BG = HexColor("#1e1e2e")
ACCENT = HexColor("#89b4fa")
ACCENT_DIM = HexColor("#45475a")
GREEN = HexColor("#a6e3a1")
YELLOW = HexColor("#f9e2af")
RED = HexColor("#f38ba8")
MAUVE = HexColor("#cba6f7")
TEXT_PRIMARY = HexColor("#2d2d2d")
TEXT_SECONDARY = HexColor("#555555")
HEADING_COLOR = HexColor("#1a1a2e")
TABLE_HEADER_BG = HexColor("#1a1a2e")
TABLE_ALT_BG = HexColor("#f0f4ff")
TABLE_BORDER = HexColor("#d0d7e5")
RULE_COLOR = HexColor("#c0c8d8")
CODE_BG = HexColor("#f5f5fa")
CALLOUT_BG = HexColor("#eef2ff")
CALLOUT_BORDER = HexColor("#89b4fa")

# ── Styles ──────────────────────────────────────────────────────────────

styles = getSampleStyleSheet()

style_title = ParagraphStyle(
    "DocTitle",
    fontName="Helvetica-Bold",
    fontSize=28,
    leading=34,
    textColor=HEADING_COLOR,
    spaceAfter=4,
)

style_subtitle = ParagraphStyle(
    "DocSubtitle",
    fontName="Helvetica",
    fontSize=14,
    leading=18,
    textColor=TEXT_SECONDARY,
    spaceAfter=24,
)

style_h1 = ParagraphStyle(
    "H1",
    fontName="Helvetica-Bold",
    fontSize=20,
    leading=26,
    textColor=HEADING_COLOR,
    spaceBefore=24,
    spaceAfter=10,
)

style_h2 = ParagraphStyle(
    "H2",
    fontName="Helvetica-Bold",
    fontSize=15,
    leading=20,
    textColor=HEADING_COLOR,
    spaceBefore=18,
    spaceAfter=8,
)

style_h3 = ParagraphStyle(
    "H3",
    fontName="Helvetica-Bold",
    fontSize=12,
    leading=16,
    textColor=TEXT_SECONDARY,
    spaceBefore=12,
    spaceAfter=6,
)

style_body = ParagraphStyle(
    "Body",
    fontName="Helvetica",
    fontSize=10.5,
    leading=15,
    textColor=TEXT_PRIMARY,
    spaceAfter=8,
)

style_bullet = ParagraphStyle(
    "Bullet",
    fontName="Helvetica",
    fontSize=10.5,
    leading=15,
    textColor=TEXT_PRIMARY,
    leftIndent=18,
    spaceAfter=4,
    bulletIndent=6,
)

style_code = ParagraphStyle(
    "Code",
    fontName="Courier",
    fontSize=9.5,
    leading=14,
    textColor=HexColor("#333344"),
    leftIndent=12,
    spaceAfter=3,
)

style_code_comment = ParagraphStyle(
    "CodeComment",
    fontName="Courier-Oblique",
    fontSize=9.5,
    leading=14,
    textColor=TEXT_SECONDARY,
    leftIndent=12,
    spaceAfter=3,
)

style_callout = ParagraphStyle(
    "Callout",
    fontName="Helvetica-Oblique",
    fontSize=10,
    leading=14,
    textColor=TEXT_SECONDARY,
    leftIndent=16,
    rightIndent=16,
    spaceBefore=8,
    spaceAfter=12,
)

style_table_header = ParagraphStyle(
    "TableHeader",
    fontName="Helvetica-Bold",
    fontSize=9.5,
    leading=13,
    textColor=white,
)

style_table_cell = ParagraphStyle(
    "TableCell",
    fontName="Helvetica",
    fontSize=9.5,
    leading=13,
    textColor=TEXT_PRIMARY,
)

style_table_code = ParagraphStyle(
    "TableCode",
    fontName="Courier-Bold",
    fontSize=9.5,
    leading=13,
    textColor=HEADING_COLOR,
)

style_footer = ParagraphStyle(
    "Footer",
    fontName="Helvetica",
    fontSize=8,
    textColor=TEXT_SECONDARY,
    alignment=TA_CENTER,
)


# ── Helpers ─────────────────────────────────────────────────────────────


def header_footer(canvas_obj, doc):
    """Draw page header rule and footer."""
    canvas_obj.saveState()
    w, h = letter
    # Header rule
    canvas_obj.setStrokeColor(RULE_COLOR)
    canvas_obj.setLineWidth(0.5)
    canvas_obj.line(inch, h - 0.7 * inch, w - inch, h - 0.7 * inch)
    # Header text
    canvas_obj.setFont("Helvetica", 8)
    canvas_obj.setFillColor(TEXT_SECONDARY)
    canvas_obj.drawString(inch, h - 0.62 * inch, "CW Sweep — Vim Mode Design")
    canvas_obj.drawRightString(
        w - inch, h - 0.62 * inch, "Carrier Wave Project"
    )
    # Footer
    canvas_obj.setStrokeColor(RULE_COLOR)
    canvas_obj.line(inch, 0.75 * inch, w - inch, 0.75 * inch)
    canvas_obj.drawCentredString(w / 2, 0.55 * inch, f"— {doc.page} —")
    canvas_obj.restoreState()


def make_table(headers, rows, col_widths=None):
    """Create a styled table."""
    header_cells = [
        Paragraph(h, style_table_header) for h in headers
    ]
    data = [header_cells]
    for row in rows:
        cells = []
        for i, cell in enumerate(row):
            cleaned = cell.replace("`", "")
            if i == 0 and "`" in cell:
                cells.append(
                    Paragraph(cleaned, style_table_code)
                )
            else:
                cells.append(Paragraph(cleaned, style_table_cell))
        data.append(cells)

    ncols = len(headers)
    if col_widths is None:
        avail = 6.5 * inch
        col_widths = [avail / ncols] * ncols

    tbl = Table(data, colWidths=col_widths, repeatRows=1)

    cmd = [
        ("BACKGROUND", (0, 0), (-1, 0), TABLE_HEADER_BG),
        ("TEXTCOLOR", (0, 0), (-1, 0), white),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 9.5),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("LEFTPADDING", (0, 0), (-1, -1), 8),
        ("RIGHTPADDING", (0, 0), (-1, -1), 8),
        ("GRID", (0, 0), (-1, -1), 0.5, TABLE_BORDER),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [white, TABLE_ALT_BG]),
    ]
    tbl.setStyle(TableStyle(cmd))
    return tbl


def code_block(lines):
    """Return a list of code-line Paragraphs wrapped in a background table."""
    paras = []
    for line in lines:
        if line.lstrip().startswith("#") or line.lstrip().startswith("—"):
            paras.append(Paragraph(line, style_code_comment))
        else:
            paras.append(Paragraph(line.replace(" ", "&nbsp;"), style_code))
    # Wrap in a shaded box
    inner = [[p] for p in paras]
    tbl = Table(inner, colWidths=[6.3 * inch])
    tbl.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), CODE_BG),
                ("LEFTPADDING", (0, 0), (-1, -1), 10),
                ("RIGHTPADDING", (0, 0), (-1, -1), 10),
                ("TOPPADDING", (0, 0), (0, 0), 8),
                ("BOTTOMPADDING", (-1, -1), (-1, -1), 8),
                ("TOPPADDING", (0, 1), (-1, -1), 0),
                ("BOTTOMPADDING", (0, 0), (-1, -2), 0),
                ("BOX", (0, 0), (-1, -1), 0.5, TABLE_BORDER),
            ]
        )
    )
    return tbl


def rule():
    """Horizontal rule."""
    tbl = Table([[""]], colWidths=[6.5 * inch], rowHeights=[1])
    tbl.setStyle(
        TableStyle(
            [("LINEBELOW", (0, 0), (-1, -1), 0.5, RULE_COLOR)]
        )
    )
    return tbl


def bullet(text):
    return Paragraph(f"•&nbsp;&nbsp;{text}", style_bullet)


# ── Document ────────────────────────────────────────────────────────────

output_path = "/Users/jsvana/projects/carrier_wave/docs/plans/cw-sweep-vim-mode.pdf"

doc = BaseDocTemplate(
    output_path,
    pagesize=letter,
    leftMargin=inch,
    rightMargin=inch,
    topMargin=inch,
    bottomMargin=inch,
)

frame = Frame(
    inch,
    inch,
    letter[0] - 2 * inch,
    letter[1] - 2 * inch,
    id="main",
)
doc.addPageTemplates(
    [PageTemplate(id="main", frames=[frame], onPage=header_footer)]
)

story = []

# ── Title Page ──────────────────────────────────────────────────────────

story.append(Spacer(1, 1.5 * inch))
story.append(Paragraph("Vim Mode for CW Sweep", style_title))
story.append(
    Paragraph(
        "A composable command language for keyboard-driven ham radio operating",
        style_subtitle,
    )
)
story.append(rule())
story.append(Spacer(1, 18))
story.append(
    Paragraph(
        "CW Sweep is a macOS companion app for Carrier Wave that aggregates DX cluster spots, "
        "RBN data, POTA/SOTA/WWFF spots, and provides QSO logging with radio control. "
        "This document proposes a vim-inspired modal interface that replaces scattered keyboard "
        "shortcuts with a composable command language — giving operators fast, mouse-free "
        "workflows built from a small vocabulary of operations.",
        style_body,
    )
)
story.append(Spacer(1, 12))
story.append(
    Paragraph(
        "<b>Date:</b>&nbsp;&nbsp;March 2026&nbsp;&nbsp;&nbsp;&nbsp;"
        "<b>Status:</b>&nbsp;&nbsp;Design Proposal&nbsp;&nbsp;&nbsp;&nbsp;"
        "<b>Author:</b>&nbsp;&nbsp;Jay Svana",
        ParagraphStyle(
            "Meta",
            fontName="Helvetica",
            fontSize=10,
            leading=14,
            textColor=TEXT_SECONDARY,
        ),
    )
)

# ── Design Philosophy ───────────────────────────────────────────────────

story.append(PageBreak())
story.append(Paragraph("Design Philosophy", style_h1))
story.append(
    Paragraph(
        "Vim is not a collection of keyboard shortcuts. It is a <b>composable language</b> "
        "where a small set of operators, motions, and modifiers combine into hundreds of "
        "distinct commands. You learn ~20 words and speak in sentences.",
        style_body,
    )
)

story.append(Paragraph("Core Principles", style_h2))
story.append(
    bullet(
        "<b>Modes separate intent.</b> Navigation keys and text-entry keys "
        "occupy the same keys without conflict because the mode disambiguates."
    )
)
story.append(
    bullet(
        "<b>Operators + motions compose.</b> <font face='Courier'>d3w</font> = "
        "\"delete 3 words.\" You learn operators and motions independently, "
        "then combine them freely."
    )
)
story.append(
    bullet(
        "<b>Counts multiply.</b> <font face='Courier'>5j</font> = \"down 5 items.\" "
        "Any motion accepts a numeric prefix."
    )
)
story.append(
    bullet(
        "<b>Marks bookmark positions.</b> Save a location, jump elsewhere, return instantly."
    )
)
story.append(
    bullet(
        "<b>Dot-repeat replays the last action.</b> The most common operation in any "
        "workflow is \"do that again.\""
    )
)
story.append(
    bullet(
        "<b>Macros record and replay sequences.</b> For repetitive multi-step workflows."
    )
)

story.append(Spacer(1, 8))
story.append(
    Paragraph(
        "For ham radio, this maps naturally: <b>the operator (verb) is what you do — tune, "
        "log, spot, lookup. The motion (noun) is what you do it to — the selected spot, "
        "a band, a frequency.</b> The interface becomes a conversation: "
        "\"tune to the selected spot\" is just <font face='Courier'>t</font>.",
        style_callout,
    )
)

# ── Modes ───────────────────────────────────────────────────────────────

story.append(Paragraph("Modes", style_h1))
story.append(
    Paragraph(
        "Four modes, shown in the status bar. The current mode determines what every "
        "key does. There is never ambiguity.",
        style_body,
    )
)

story.append(
    make_table(
        ["Mode", "Purpose", "Entry", "Exit"],
        [
            [
                "`Normal`",
                "Navigate spots, control radio, issue commands. Default mode — where you spend most time between QSOs.",
                "Escape from any mode",
                "—",
            ],
            [
                "`Entry`",
                "Type QSO data into the entry field. Like vim's Insert mode. "
                "Escape ALWAYS exits — even if the quick entry text field has focus, "
                "Escape leaves the field and returns to Normal mode.",
                "i (insert) or Return on a spot",
                "Escape (cancel) or Return (log QSO)",
            ],
            [
                "`Command`",
                "System commands, radio configuration, CW memories. Like vim's Ex mode.",
                ": (colon)",
                "Escape (cancel) or Return (execute)",
            ],
            [
                "`Search`",
                "Filter spots by callsign, band, mode, source, needed status. Results narrow live as you type.",
                "/ (slash)",
                "Escape (clear filter) or Return (lock filter)",
            ],
        ],
        col_widths=[0.9 * inch, 2.4 * inch, 1.6 * inch, 1.6 * inch],
    )
)

story.append(Spacer(1, 8))
story.append(Paragraph("Mode Transitions", style_h3))
story.append(
    code_block(
        [
            "Normal ──i──▶ Entry ──Esc──▶ Normal",
            "Normal ──:──▶ Command ──Esc──▶ Normal",
            "Normal ──/──▶ Search ──Esc──▶ Normal",
            "Entry ──Return──▶ Normal (QSO logged)",
            "Command ──Return──▶ Normal (command executed)",
            "Search ──Return──▶ Normal (filter locked)",
        ]
    )
)

# ── The Language ────────────────────────────────────────────────────────

story.append(PageBreak())
story.append(Paragraph("The Command Language", style_h1))

# Motions
story.append(Paragraph("Motions — Where to Go", style_h2))
story.append(
    Paragraph(
        "Motions move your selection through lists, bands, and panes. "
        "All motions accept a numeric count prefix.",
        style_body,
    )
)
story.append(
    make_table(
        ["Key", "Motion", "With Count"],
        [
            ["`j` / `k`", "Next / previous item in focused list", "3j = down 3 items"],
            ["`J` / `K`", "Next / previous band on the radio", "— (one band at a time)"],
            ["`gg`", "Jump to top of list", "—"],
            ["`G`", "Jump to bottom of list", "—"],
            ["`n` / `N`", "Next / previous search result", "—"],
            ["`Tab`", "Cycle focus to next pane", "—"],
            ["`g1`–`g4`", "Focus pane by number (see Focus section)", "—"],
        ],
        col_widths=[1.1 * inch, 3.0 * inch, 2.4 * inch],
    )
)

# Operators
story.append(Spacer(1, 6))
story.append(Paragraph("Operators — What to Do", style_h2))
story.append(
    Paragraph(
        "Operators act on the current selection. Most are single-key in Normal mode. "
        "Some accept a motion to specify a target.",
        style_body,
    )
)
story.append(
    make_table(
        ["Key", "Operator", "Behavior"],
        [
            [
                "`t`",
                "Tune",
                "Tune the radio to the selected spot's frequency and mode. "
                "The most common single operation — equivalent to vim's motion commands.",
            ],
            [
                "`i`",
                "Insert (Log)",
                "Enter Entry mode. If a spot is selected, pre-fills callsign, frequency, "
                "and mode from the spot. If no spot, opens a blank entry.",
            ],
            [
                "`?`",
                "Lookup",
                "Query QRZ/callbook for the selected callsign. Opens info panel.",
            ],
            [
                "`x`",
                "Dismiss",
                "Remove the selected spot from the list (hides, does not delete).",
            ],
            [
                "`s`",
                "Spot",
                "Spot the current station on the DX cluster. Uses current radio "
                "frequency and the callsign from the entry field or selection.",
            ],
            [
                "`.`",
                "Repeat",
                "Repeat the last compound action. For logging, replays the full "
                "i...Return cycle with the same defaults (RST, mode, exchange template). "
                "For tune, re-tunes to the same frequency. Does NOT repeat motions.",
            ],
            [
                "`u`",
                "Undo",
                "Undo the last action — unlog a QSO, un-dismiss a spot, un-tune. "
                "Essential safety net. Multiple presses undo further back.",
            ],
            [
                "`S`",
                "Split toggle",
                "Toggle split operation on/off. When split is active, TX frequency "
                "is independent from RX. Status bar shows both RX and TX frequencies.",
            ],
            [
                "`+` / `-`",
                "WPM speed",
                "Step CW keying speed up/down by 2 WPM. Accepts count: 5+ = up 10 WPM. "
                "Works in Normal mode for zero-friction speed changes during a QSO.",
            ],
            [
                "`f`",
                "Frequency",
                "Direct frequency entry. Type f14023.5 Return to tune to that frequency. "
                "Faster than command mode for quick QSY.",
            ],
            [
                "`a`",
                "Append notes",
                "Open multi-line notes editor for the selected QSO in the log. "
                "Regular text editing (not modal). Escape closes and saves.",
            ],
            [
                "`F1`–`F6`",
                "CW memories",
                "Send WinKeyer memory 1–6 directly from Normal mode. "
                "F1=CQ, F2=exchange, F3=TU, F4=my call, F5=his call, F6=AGN by convention. "
                "Also works in Entry mode.",
            ],
            [
                "`Ctrl+C`",
                "Abort CW",
                "Immediately stop CW transmission. Works in all modes. "
                "Does not change mode — only interrupts the keyer.",
            ],
        ],
        col_widths=[0.7 * inch, 1.1 * inch, 4.7 * inch],
    )
)

# Marks
story.append(Spacer(1, 6))
story.append(Paragraph("Marks — Frequency Bookmarks", style_h2))
story.append(
    Paragraph(
        "Marks save the current radio frequency and mode for instant recall. "
        "This is one of the most valuable features for Search &amp; Pounce operating, "
        "where you constantly flip between your CQ frequency and DX spots.",
        style_body,
    )
)
story.append(
    make_table(
        ["Key", "Action", "Example"],
        [
            [
                "`ma`–`mz`",
                "Mark current frequency as letter",
                "ma — save 14.074 MHz as mark 'a'",
            ],
            [
                "`'a`–`'z`",
                "Tune to marked frequency",
                "'a — return to 14.074 MHz",
            ],
            [
                "`''`",
                "Return to previous frequency",
                "Tune to a spot, then '' to jump back. Like vim's jump-back.",
            ],
        ],
        col_widths=[1.2 * inch, 2.2 * inch, 3.1 * inch],
    )
)

# Macros
story.append(Spacer(1, 6))
story.append(Paragraph("Macros — Record and Replay", style_h2))
story.append(
    Paragraph(
        "Macros record a sequence of keystrokes for replay. Useful for repetitive "
        "multi-step workflows like working a pile-up with a fixed exchange.",
        style_body,
    )
)
story.append(
    make_table(
        ["Key", "Action"],
        [
            ["`qa`–`qz`", "Start recording macro into register a–z"],
            ["`q`", "Stop recording (when recording is active)"],
            ["`@a`–`@z`", "Replay macro from register a–z"],
        ],
        col_widths=[1.5 * inch, 5.0 * inch],
    )
)
story.append(Spacer(1, 6))
story.append(
    Paragraph(
        "<b>State machine:</b> <font face='Courier'>q</font> has two states. "
        "When NOT recording, <font face='Courier'>q</font> waits for a register "
        "letter (a–z) — bare <font face='Courier'>q</font> without a following "
        "letter does nothing (times out after 1 second). When recording IS active, "
        "bare <font face='Courier'>q</font> stops recording immediately. The status "
        "bar shows <font face='Courier'>recording @a</font> during recording so "
        "the user always knows the current state.",
        style_body,
    )
)

# ── Focus and Selection ─────────────────────────────────────────────────

story.append(PageBreak())
story.append(Paragraph("Focus and Selection", style_h1))
story.append(
    Paragraph(
        "CW Sweep shows multiple panes simultaneously — spots, log, band map, cluster. "
        "Vim mode needs unambiguous focus so <font face='Courier'>j/k</font> always "
        "controls exactly one list.",
        style_body,
    )
)

story.append(Paragraph("Focus Rules", style_h2))
story.append(
    bullet(
        "<b>Exactly one pane has focus at all times.</b> The focused pane has a visible "
        "accent border or highlight."
    )
)
story.append(
    bullet(
        "<b>Tab cycles focus</b> between visible panes in a consistent order "
        "(spots → log → band map → cluster)."
    )
)
story.append(
    bullet(
        "<b>g + number jumps directly:</b> <font face='Courier'>g1</font> = spots, "
        "<font face='Courier'>g2</font> = log, <font face='Courier'>g3</font> = band map, "
        "<font face='Courier'>g4</font> = cluster. Uses the <font face='Courier'>g</font> "
        "prefix (like vim's <font face='Courier'>gt</font> for tabs) to avoid conflict "
        "with numeric count prefixes. The mapping is shown in each pane's header as a subtle badge."
    )
)
story.append(
    bullet(
        "<b>The focused pane's selected item is \"the selection\"</b> for all operators. "
        "When you press <font face='Courier'>t</font>, you tune to whatever is selected "
        "in the focused pane — a spot in the spot list, a callsign in the band map, etc."
    )
)

story.append(Paragraph("Escape is Sacred", style_h2))
story.append(
    Paragraph(
        "Escape <b>always</b> returns to Normal mode, no matter where focus is. "
        "If the quick entry text field is focused and has text in it, Escape clears "
        "the text and exits back to Normal mode. If a Search or Command prompt is "
        "active, Escape dismisses it. There is never a state where Escape does not "
        "return you to Normal mode. This is the single most important invariant of "
        "the modal system — the user must always have a reliable escape hatch.",
        style_body,
    )
)
story.append(
    Paragraph(
        "This mirrors vim exactly: no matter how deep you are in insert mode, visual "
        "mode, or command-line mode, Escape takes you home.",
        style_callout,
    )
)

story.append(Paragraph("Visual Indicators", style_h2))
story.append(
    bullet(
        "<b>Mode badge</b> in the status bar: <font face='Courier' color='#a6e3a1'>"
        "NORMAL</font>, <font face='Courier' color='#f9e2af'>ENTRY</font>, "
        "<font face='Courier' color='#89b4fa'>COMMAND</font>, "
        "<font face='Courier' color='#cba6f7'>SEARCH</font>"
    )
)
story.append(
    bullet(
        "<b>Focused pane border</b> — a subtle accent-colored border on the active pane."
    )
)
story.append(
    bullet(
        "<b>Selected item highlight</b> — the current item in the focused list has a "
        "distinct selection highlight, visible even when the pane is not focused "
        "(dimmed vs. bright)."
    )
)
story.append(
    bullet(
        "<b>Pending operator indicator</b> — when a multi-key sequence is in progress "
        "(e.g., after pressing <font face='Courier'>m</font> waiting for the register "
        "letter), show the pending keys in the status bar."
    )
)

# ── Band Map ────────────────────────────────────────────────────────────

story.append(Paragraph("Band Map Integration", style_h2))
story.append(
    Paragraph(
        "The band map is a Normal-mode navigable pane. When focused:",
        style_body,
    )
)
story.append(
    bullet(
        "<font face='Courier'>j/k</font> moves the selection between spots on the "
        "current band, ordered by frequency."
    )
)
story.append(
    bullet(
        "<font face='Courier'>J/K</font> changes the displayed band."
    )
)
story.append(
    bullet(
        "<font face='Courier'>t</font> tunes to the selected spot's exact frequency."
    )
)
story.append(
    bullet(
        "<font face='Courier'>i</font> enters Entry mode pre-filled from the "
        "selected band map spot."
    )
)
story.append(
    bullet(
        "The current radio frequency is always shown as a marker on the band map, "
        "distinct from the selection cursor."
    )
)

# ── Search / Filter ─────────────────────────────────────────────────────

story.append(PageBreak())
story.append(Paragraph("Search and Filtering", style_h1))
story.append(
    Paragraph(
        "<font face='Courier'>/</font> enters Search mode, which acts as a live filter "
        "on the focused spot list. Terms are space-separated and combine as AND filters. "
        "Results narrow in real time as you type.",
        style_body,
    )
)

story.append(Paragraph("Filter Language", style_h2))
story.append(
    make_table(
        ["Input", "Filter", "Example"],
        [
            ["`cw`", "Mode filter", "/cw — show only CW spots"],
            ["`20m` or `14`", "Band filter", "/20m — show only 20-meter spots"],
            ["`pota`", "Source filter", "/pota — show only POTA spots"],
            ["`new`", "Needed status", "/new — only new DXCC or band slots"],
            ["`ja`", "Callsign prefix", "/ja — callsigns starting with JA (Japan)"],
            [
                "Combined",
                "AND logic",
                "/cw 20m new — CW spots on 20m that are new entities",
            ],
        ],
        col_widths=[1.4 * inch, 1.4 * inch, 3.7 * inch],
    )
)

story.append(Spacer(1, 6))
story.append(
    Paragraph(
        "<b>Escape</b> clears the filter and returns to Normal mode. "
        "<b>Return</b> locks the current filter (persists while you navigate) "
        "and returns to Normal mode. <font face='Courier'>n/N</font> in Normal mode "
        "cycles through locked filter results.",
        style_body,
    )
)
story.append(Spacer(1, 4))
story.append(Paragraph("Disambiguation", style_h3))
story.append(
    Paragraph(
        "Filter terms may collide with callsign prefixes (e.g., \"CW\" is both a mode "
        "and a callsign prefix). Resolution order: (1) known keywords (mode names, band "
        "names, source names, <font face='Courier'>new</font>, <font face='Courier'>dupe"
        "</font>) are matched first; (2) everything else is treated as a callsign prefix "
        "filter. To force callsign interpretation of a keyword, prefix with "
        "<font face='Courier'>call:</font> (e.g., <font face='Courier'>/call:cw</font> "
        "for callsigns starting with CW). To force a specific filter type, use "
        "<font face='Courier'>mode:</font>, <font face='Courier'>band:</font>, "
        "<font face='Courier'>src:</font> prefixes.",
        style_body,
    )
)

story.append(Paragraph("Extended Filters", style_h3))
story.append(
    make_table(
        ["Input", "Filter", "Example"],
        [
            ["`dupe`", "Already-worked callsigns", "/dupe — show only dupes (for review)"],
            ["`need:40m`", "Needed on specific band", "/need:40m — entities I need on 40m"],
            ["`need:cw`", "Needed on specific mode", "/need:cw — entities I need on CW"],
            ["`sota`", "SOTA spots", "/sota — show SOTA spots"],
            ["`mult`", "New multiplier (contest)", "/mult — show new contest multipliers"],
            ["`confirmed`", "Confirmed vs. worked", "/new excludes confirmed; /confirmed shows only confirmed"],
        ],
        col_widths=[1.4 * inch, 1.8 * inch, 3.3 * inch],
    )
)

# ── Command Mode ────────────────────────────────────────────────────────

story.append(Paragraph("Command Mode", style_h1))
story.append(
    Paragraph(
        "<font face='Courier'>:</font> opens the command line at the bottom of the "
        "window. Commands handle system operations, radio configuration, and CW sending "
        "— anything that doesn't fit the operator model.",
        style_body,
    )
)

story.append(Paragraph("Radio &amp; Configuration", style_h2))
story.append(
    make_table(
        ["Command", "Action"],
        [
            ["`connect w3lpl`", "Connect to DX cluster node"],
            ["`disconnect`", "Disconnect from cluster"],
            ["`set wpm 25`", "Set CW keying speed (WPM)"],
            ["`set power 100`", "Set power level"],
            ["`role hunter`", "Switch to Hunter role"],
            ["`role activator`", "Switch to Activator role"],
            ["`park K-1234`", "Set POTA park for activation"],
            ["`summit W4C/CM-001`", "Set SOTA summit for activation"],
            ["`split up 2`", "Set TX offset to +2 kHz (split operation)"],
            ["`split off`", "Disable split operation"],
            ["`export adif`", "Export log as ADIF"],
            ["`import adif`", "Import ADIF file"],
        ],
        col_widths=[2.0 * inch, 4.5 * inch],
    )
)

story.append(Spacer(1, 6))
story.append(Paragraph("CW Sending (via WinKeyer)", style_h2))
story.append(
    Paragraph(
        "CW memories are sent through command mode. Stored memories are addressed "
        "by number; freeform text can be sent directly.",
        style_body,
    )
)
story.append(
    make_table(
        ["Command", "Action"],
        [
            ["`cq`", "Send CQ memory (memory 1 by convention)"],
            ["`send 1`–`send 6`", "Send stored WinKeyer memory by number"],
            ["`send TU 73`", "Send freeform CW text"],
            ["`wpm 22`", "Adjust WinKeyer speed (alias for set wpm)"],
            ["`agn`", "Send AGN (\"again\" — ask for repeat)"],
            ["`tu`", "Send TU (\"thank you\" — end of QSO)"],
        ],
        col_widths=[2.0 * inch, 4.5 * inch],
    )
)

story.append(Spacer(1, 6))
story.append(Paragraph("Cluster Commands", style_h2))
story.append(
    make_table(
        ["Command", "Action"],
        [
            ["`dx`", "Show recent DX (SH/DX on cluster)"],
            ["`wwv`", "Show solar conditions (SH/WWV)"],
            ["`skimmer`", "Toggle skimmer mode (SET/SKIMMER)"],
            ["`raw &lt;text&gt;`", "Send raw cluster command"],
        ],
        col_widths=[2.0 * inch, 4.5 * inch],
    )
)

story.append(Spacer(1, 6))
story.append(Paragraph("Activation Lifecycle", style_h2))
story.append(
    make_table(
        ["Command", "Action"],
        [
            ["`spot`", "Self-spot on POTA/SOTA — auto-fills park/summit, freq, mode from current state"],
            ["`spot CQ 40m SSB`", "Self-spot with custom comment"],
            ["`respot`", "Re-spot with same comment (updates frequency if changed)"],
            ["`rove K-5678`", "End current park/summit session, begin new one — clean session boundary"],
            ["`end`", "End current activation session"],
            ["`upload`", "Upload ADIF to POTA/SOTA/LoTW"],
        ],
        col_widths=[2.0 * inch, 4.5 * inch],
    )
)

story.append(Spacer(1, 6))
story.append(Paragraph("Alerts", style_h2))
story.append(
    Paragraph(
        "DX chasing is interrupt-driven. Alerts notify when needed entities appear, "
        "even when the operator is not actively browsing spots.",
        style_body,
    )
)
story.append(
    make_table(
        ["Command", "Action"],
        [
            ["`alert add P5`", "Alert on any P5 (North Korea) spot on any band/mode"],
            ["`alert add 3Y cw 40m`", "Alert on specific prefix/mode/band combination"],
            ["`alert list`", "Show all configured alerts"],
            ["`alert clear`", "Remove all alerts"],
        ],
        col_widths=[2.0 * inch, 4.5 * inch],
    )
)
story.append(
    Paragraph(
        "When an alert fires: prominent visual notification (pulsing border, highlighted row), "
        "audio alert, and macOS notification (works even when CW Sweep is not focused). "
        "Press <font face='Courier'>ga</font> in Normal mode to jump to the most recent "
        "alert spot. Alert priority tiers: all-time new entity (urgent) > new band slot "
        "(important) > new mode slot (normal).",
        style_body,
    )
)

story.append(Spacer(1, 6))
story.append(Paragraph("SSB Voice Keyer", style_h2))
story.append(
    make_table(
        ["Command", "Action"],
        [
            ["`voice 1`–`voice 6`", "Play recorded voice memory (SSB equivalent of CW memories)"],
            ["`voice record 1`", "Record a new voice memory into slot 1"],
        ],
        col_widths=[2.0 * inch, 4.5 * inch],
    )
)

# ── Workflows ───────────────────────────────────────────────────────────

story.append(PageBreak())
story.append(Paragraph("Workflow Examples", style_h1))
story.append(
    Paragraph(
        "These workflows demonstrate how the command language composes "
        "into natural operating patterns.",
        style_body,
    )
)

story.append(Paragraph("Hunt &amp; Pounce (S&amp;P)", style_h2))
story.append(
    Paragraph(
        "The most common DX workflow: scan spots, find something interesting, "
        "tune, call, log, repeat.",
        style_body,
    )
)
story.append(
    code_block(
        [
            "/cw 20m new       # filter: CW, 20m, new entities only",
            "j j j             # browse down through filtered spots",
            "t                 # tune radio to selected spot",
            "i                 # enter Entry mode (callsign pre-filled)",
            "599               # type RST",
            "Return            # log QSO → back to Normal",
            "j                 # next spot",
            "t                 # tune",
            "i Return          # log (pre-filled, default RST)",
        ]
    )
)

story.append(Spacer(1, 12))
story.append(Paragraph("S&amp;P with Frequency Bookmark", style_h2))
story.append(
    Paragraph(
        "You're CQing on a frequency but want to chase DX spots. "
        "Marks let you jump away and return instantly.",
        style_body,
    )
)
story.append(
    code_block(
        [
            "ma                # mark current CQ frequency as 'a'",
            "/new 20m          # filter to new entities on 20m",
            "j j               # find an interesting spot",
            "t                 # tune to spot",
            "i Return          # log the QSO",
            "''                # jump back to previous frequency",
            "#— or —",
            "'a                # jump back to mark 'a' (your CQ freq)",
        ]
    )
)

story.append(Spacer(1, 12))
story.append(Paragraph("DX Chase with Split", style_h2))
story.append(
    Paragraph(
        "A rare station appears on the cluster. The reality: tune, listen for their "
        "pattern, set split, call in the pile-up, then log when you get through.",
        style_body,
    )
)
story.append(
    code_block(
        [
            "/5a1a             # search for the rare callsign",
            "t                 # tune to their RX frequency",
            "# LISTEN — figure out split, pattern, timing",
            "S                 # enable split mode",
            ":split up 2       # set TX offset +2 kHz",
            "+                 # bump up WPM for the pile-up",
            "# Call and wait... adjust TX freq as needed",
            "- -               # slow down when DX comes back to you",
            "i                 # entry mode — callsign pre-filled",
            "599               # type RST",
            "Return            # log the QSO",
            "S                 # disable split",
        ]
    )
)
story.append(
    Paragraph(
        "Note: the gap between tuning and logging can be seconds or 45 minutes. "
        "The spot comment often contains \"UP 1-5\" — the <font face='Courier'>t</font> "
        "operator parses this and auto-enables split with the indicated offset when possible.",
        style_callout,
    )
)

story.append(Spacer(1, 12))
story.append(Paragraph("POTA Activation (Run Mode)", style_h2))
story.append(
    Paragraph(
        "Running a POTA activation: set up, CQ, log callers in rapid succession.",
        style_body,
    )
)
story.append(
    code_block(
        [
            ":role activator   # switch to activator role",
            ":park K-1234      # set park reference",
            ":cq               # send CQ via WinKeyer",
            "i                 # entry mode",
            "W4ABC 599         # type caller's info",
            "Return            # log → back to Normal",
            ":tu               # send TU via WinKeyer",
            ":cq               # send CQ again",
            "i W1XYZ Return    # log next caller",
        ]
    )
)

story.append(Spacer(1, 12))
story.append(Paragraph("Contest-Style Rapid Logging", style_h2))
story.append(
    Paragraph(
        "When running a frequency in a contest, the sent exchange is fixed (your zone, "
        "state, or serial) but the received exchange changes every QSO. CW Sweep "
        "distinguishes sent vs. received exchange fields.",
        style_body,
    )
)
story.append(
    code_block(
        [
            "# CQ WW example — your zone is 05, received zone varies",
            "i                 # entry mode",
            "K4ABC 599 05      # callsign, RST, their zone",
            "Return            # log",
            "i W1DEF 599 02    # next caller — different zone",
            "Return            # log",
            "i N3GHI 599 05    # another",
            "Return            # log",
            "# RST (599) carries over; received exchange must be typed each time",
        ]
    )
)
story.append(Spacer(1, 8))
story.append(Paragraph("ESM (Enter Sends Message)", style_h3))
story.append(
    Paragraph(
        "For CW contests, Entry mode supports ESM — Enter becomes context-aware based "
        "on QSO state. First Return with a callsign typed: sends your call + exchange via "
        "WinKeyer. Second Return after receiving their exchange: sends TU/QSL and logs. "
        "This eliminates the need for separate <font face='Courier'>:cq</font> and "
        "<font face='Courier'>:tu</font> commands during run operation, reducing each QSO "
        "to: type callsign → Return → type exchange → Return. ESM is enabled via "
        "<font face='Courier'>:set esm on</font>.",
        style_body,
    )
)

# ── Split Operation ─────────────────────────────────────────────────────

story.append(PageBreak())
story.append(Paragraph("Split Operation", style_h1))
story.append(
    Paragraph(
        "Split is not an edge case — for DX chasing above 200 confirmed entities, "
        "the majority of new ones are worked split. The design must treat split as "
        "a first-class operating mode, not an afterthought.",
        style_body,
    )
)
story.append(Paragraph("How Split Works", style_h2))
story.append(
    bullet(
        "<b>S</b> in Normal mode toggles split on/off. When active, the status bar "
        "shows both RX and TX frequencies (e.g., <font face='Courier'>RX 14.025 | "
        "TX 14.027</font>)."
    )
)
story.append(
    bullet(
        "<b>+/-</b> with split active adjusts the TX frequency offset (1 kHz steps for "
        "SSB, 500 Hz for CW). Without split, +/- adjusts WPM."
    )
)
story.append(
    bullet(
        "<b>:split up N</b> sets TX offset to +N kHz. <b>:split dn N</b> for down."
    )
)
story.append(
    bullet(
        "<b>Auto-split from spots:</b> when <font face='Courier'>t</font> tunes to a "
        "spot whose comment contains \"UP 2\" or \"UP 1-5\", split is automatically enabled "
        "and TX offset is set to the indicated value (midpoint for ranges)."
    )
)
story.append(
    bullet(
        "<b>Band map shows both:</b> the RX frequency marker and TX frequency marker are "
        "visually distinct. Other callers visible on RBN/skimmer appear as marks so you "
        "can see where the pile-up is relative to the DX station's listening range."
    )
)

# ── DXCC Tracking ──────────────────────────────────────────────────────

story.append(Paragraph("DXCC and Need Status", style_h1))
story.append(
    Paragraph(
        "Spot need status goes beyond simple new/not-new. DX chasers require granular "
        "tracking across bands, modes, and confirmation status.",
        style_body,
    )
)
story.append(Paragraph("Visual Indicators in Spot List", style_h2))
story.append(
    make_table(
        ["Color", "Status", "Meaning"],
        [
            ["Bright red/highlight", "All-time new", "Never worked this entity on any band/mode"],
            ["Orange", "New band slot", "Worked on other bands but not this one"],
            ["Yellow", "New mode slot", "Worked on this band in other modes but not this one"],
            ["Dim green", "Worked, not confirmed", "QSO in log but no LoTW/QSL match yet"],
            ["Gray/dim", "Confirmed", "Already confirmed — low priority"],
        ],
        col_widths=[1.5 * inch, 1.5 * inch, 3.5 * inch],
    )
)
story.append(
    Paragraph(
        "These colors apply to spot rows without filtering — the operator sees need status "
        "at a glance on every spot. The <font face='Courier'>?</font> lookup shows a full "
        "band/mode matrix for the entity: a grid showing Confirmed/Worked/Needed for each "
        "band-mode combination.",
        style_body,
    )
)
story.append(Paragraph("Dupe Checking", style_h2))
story.append(
    Paragraph(
        "Spots for already-worked callsigns are visually flagged (struck through or badged). "
        "In Entry mode, typing a callsign that exists in today's log shows a \"DUPE\" warning. "
        "The warning does not prevent logging — in some cases (e.g., different band) the "
        "contact is valid. The <font face='Courier'>?</font> operator on a worked callsign "
        "shows \"B4: 2024-03-15 20m CW\" with previous QSO details.",
        style_body,
    )
)

# ── Notes / Free-text ──────────────────────────────────────────────────

story.append(Paragraph("Notes and Free-Text Logging", style_h1))
story.append(
    Paragraph(
        "Not all QSOs are rapid-fire. Ragchew operators may spend 45 minutes in a single QSO "
        "and want to record conversation details, equipment notes, or personal information. "
        "The Entry mode quick-entry field is not designed for this.",
        style_body,
    )
)
story.append(Paragraph("The Notes Editor", style_h2))
story.append(
    bullet(
        "<b>a</b> (append) in Normal mode with a log entry selected opens a multi-line "
        "notes editor for that QSO."
    )
)
story.append(
    bullet(
        "The notes editor uses <b>regular text editing</b> — not modal, not vim-keyed. "
        "Arrow keys, backspace, selection, copy/paste all work normally. This is deliberate: "
        "free-text writing should not fight with the modal system."
    )
)
story.append(
    bullet(
        "<b>Escape</b> closes the notes editor and saves. The Escape-is-Sacred invariant "
        "still holds — Escape always returns to Normal mode."
    )
)
story.append(
    bullet(
        "Notes can also be opened via <font face='Courier'>:notes</font> in Command mode, "
        "which opens notes for the most recently logged QSO."
    )
)
story.append(
    bullet(
        "During Entry mode, a park/summit reference for the other station (P2P/S2S) can "
        "be entered inline: <font face='Courier'>W4ABC 599 P:K-5678</font> or "
        "<font face='Courier'>W4ABC 599 S:W4C/CM-001</font>."
    )
)

# ── Digital Modes note ──────────────────────────────────────────────────
# Digital modes (FT8/FT4, JS8Call) are deferred to v2+.
# The interaction model is fundamentally different — WSJT-X owns the radio
# and handles exchanges. Vim mode for digital would act as a strategic
# overlay rather than a tactical executor. See Review Findings for details.

# ── Discoverability ────────────────────────────────────────────────────

story.append(PageBreak())
story.append(Paragraph("Discoverability", style_h1))
story.append(
    Paragraph(
        "Vim's learning curve is its biggest criticism. CW Sweep mitigates this "
        "with layered discovery that doesn't get in the way of experienced users.",
        style_body,
    )
)

story.append(Paragraph("Help Overlay", style_h2))
story.append(
    bullet(
        "<b>F1 or :help</b> opens a translucent overlay showing all commands "
        "available in the current mode."
    )
)
story.append(
    bullet(
        "The overlay is context-sensitive: in Normal mode it shows operators and motions; "
        "in Command mode it shows available commands."
    )
)
story.append(
    bullet(
        "Dismisses on any keypress (the keypress is consumed, not acted upon)."
    )
)

story.append(Paragraph("Status Bar Hints", style_h2))
story.append(
    bullet(
        "<b>Pending key display:</b> after pressing <font face='Courier'>m</font>, "
        "the status bar shows <font face='Courier'>m_</font> indicating it's waiting "
        "for a register letter."
    )
)
story.append(
    bullet(
        "<b>Mode badge:</b> always visible, color-coded."
    )
)
story.append(
    bullet(
        "<b>Last command echo:</b> the status bar briefly shows a description of "
        "the last executed command (e.g., \"Tuned to 14.025 MHz\" or "
        "\"Marked freq as 'a'\")."
    )
)

story.append(Paragraph("Progressive Learning", style_h2))
story.append(
    bullet(
        "<b>Level 1 — Survive:</b> learn 5 keys — <font face='Courier'>j k t i Esc</font>. "
        "You can browse spots, tune, log QSOs, and escape."
    )
)
story.append(
    bullet(
        "<b>Level 2 — Efficient:</b> add <font face='Courier'>/ ? . '' Tab</font>. "
        "Filtering, lookup, repeat, jump-back, pane switching."
    )
)
story.append(
    bullet(
        "<b>Level 3 — Power:</b> marks (<font face='Courier'>m/'</font>), macros "
        "(<font face='Courier'>q/@</font>), command mode (<font face='Courier'>:</font>)."
    )
)
story.append(Spacer(1, 8))
story.append(
    Paragraph(
        "A first-time user who knows only j, k, t, i, and Escape can operate the entire "
        "application. Every additional command they learn makes them faster, but nothing "
        "is required beyond those five keys.",
        style_callout,
    )
)

# ── Transition / Coexistence ─────────────────────────────────────────────

story.append(Paragraph("Coexistence with Existing UI", style_h1))
story.append(
    Paragraph(
        "Vim mode does not replace the existing interface. It layers on top of it.",
        style_body,
    )
)
story.append(
    bullet(
        "<b>Toggle:</b> Vim mode is enabled/disabled in Settings. When disabled, "
        "the app behaves exactly as it does today."
    )
)
story.append(
    bullet(
        "<b>Mouse still works:</b> clicking a spot selects it. Double-click still "
        "tunes. The mouse and keyboard are complementary, not exclusive."
    )
)
story.append(
    bullet(
        "<b>Menu shortcuts preserved:</b> Cmd+K (command palette), Cmd+Shift+P "
        "(radio palette), and other system shortcuts work in all modes."
    )
)
story.append(
    bullet(
        "<b>Palettes remain available:</b> the command palette and radio palette "
        "serve as the \"GUI alternative\" to Command mode and Search mode. "
        "Power users may prefer vim mode; others may prefer the palettes."
    )
)

# ── Appendix ────────────────────────────────────────────────────────────

story.append(PageBreak())
story.append(Paragraph("Appendix: Complete Key Reference", style_h1))

story.append(Paragraph("Normal Mode", style_h2))
story.append(
    make_table(
        ["Key", "Action"],
        [
            ["`j` / `k`", "Move selection down / up in focused list"],
            ["`J` / `K`", "Change band down / up on the radio"],
            ["`gg`", "Jump to top of list"],
            ["`G`", "Jump to bottom of list"],
            ["`n` / `N`", "Next / previous search result"],
            ["`Tab`", "Cycle focus to next pane"],
            ["`g1`–`g4`", "Focus pane by number (g prefix avoids count conflict)"],
            ["`t`", "Tune radio to selected item"],
            ["`i`", "Enter Entry mode (pre-fill from selection if available)"],
            ["`a`", "Append notes — open multi-line editor for selected QSO"],
            ["`?`", "Lookup selected callsign on QRZ"],
            ["`x`", "Dismiss selected spot"],
            ["`s`", "Spot current station on cluster"],
            ["`u`", "Undo last action"],
            ["`S`", "Toggle split operation on/off"],
            ["`f`", "Direct frequency entry (f14023.5 Return)"],
            ["`.`", "Repeat last compound action"],
            ["`+` / `-`", "WPM speed up/down (or TX offset when split active)"],
            ["`F1`–`F6`", "Send CW memory 1–6 via WinKeyer"],
            ["`ga`", "Jump to most recent alert spot"],
            ["`ma`–`mz`", "Mark current frequency"],
            ["`'a`–`'z`", "Jump to marked frequency"],
            ["`''`", "Jump to previous frequency"],
            ["`qa`–`qz`", "Start recording macro"],
            ["`q`", "Stop recording macro"],
            ["`@a`–`@z`", "Replay macro"],
            ["`/`", "Enter Search mode"],
            ["`:`", "Enter Command mode"],
            ["`Ctrl+C`", "Abort CW transmission (works in all modes)"],
            ["`Ctrl+F1`", "Show help overlay"],
            ["`Esc`", "Clear pending input / return to default state"],
        ],
        col_widths=[1.5 * inch, 5.0 * inch],
    )
)

story.append(Spacer(1, 8))
story.append(Paragraph("Entry Mode", style_h2))
story.append(
    make_table(
        ["Key", "Action"],
        [
            ["Any text", "Types into QSO entry field"],
            ["`Return`", "Log QSO and return to Normal mode"],
            ["`Escape`", "Cancel entry and return to Normal mode"],
            ["`Up` / `Down`", "Navigate entry history"],
        ],
        col_widths=[1.5 * inch, 5.0 * inch],
    )
)

story.append(Spacer(1, 8))
story.append(Paragraph("Search Mode", style_h2))
story.append(
    make_table(
        ["Key", "Action"],
        [
            ["Any text", "Filters spot list in real time"],
            ["`Return`", "Lock filter and return to Normal mode"],
            ["`Escape`", "Clear filter and return to Normal mode"],
        ],
        col_widths=[1.5 * inch, 5.0 * inch],
    )
)

story.append(Spacer(1, 8))
story.append(Paragraph("Command Mode", style_h2))
story.append(
    make_table(
        ["Key", "Action"],
        [
            ["Any text", "Types into command line"],
            ["`Return`", "Execute command and return to Normal mode"],
            ["`Escape`", "Cancel and return to Normal mode"],
            ["`Tab`", "Auto-complete command"],
            ["`Up` / `Down`", "Navigate command history"],
        ],
        col_widths=[1.5 * inch, 5.0 * inch],
    )
)

# ── Review Findings ─────────────────────────────────────────────────────

story.append(PageBreak())
story.append(Paragraph("Appendix: Review Findings", style_h1))
story.append(
    Paragraph(
        "This design was reviewed by five operator personas: CW contester (20+ year "
        "veteran, vim user), POTA activator (3-4 activations/week, non-vim user), "
        "DX chaser (310 confirmed, pushing for Honor Roll), casual ragchewer/SOTA "
        "activator (General class, 3 years), and FT8/digital operator (280 DXCC on digital). "
        "The following summarizes their findings and the design changes made in response.",
        style_body,
    )
)

story.append(Paragraph("Changes Made", style_h2))
story.append(
    make_table(
        ["Finding", "Resolution"],
        [
            ["Split operation completely absent",
             "Added Split Operation section, S toggle, +/- TX offset, :split commands, auto-split from spot comments"],
            ["No undo",
             "Added u operator for undoing logs, dismissals, and tunes"],
            ["No dupe checking",
             "Added Dupe Checking section with visual flagging and Entry mode warnings"],
            ["Number keys conflict with count prefix",
             "Changed pane focus from 1-4 to g1-g4 (like vim's gt for tabs)"],
            ["q state machine ambiguous",
             "Added explicit state machine documentation in Macros section"],
            ["Dot-repeat semantics vague",
             "Clarified: replays full compound action, not individual motions"],
            ["Filter terms collide with callsigns",
             "Added Disambiguation section with prefix syntax (mode:, band:, call:)"],
            ["Contest logging workflow wrong — exchange varies per QSO",
             "Rewrote with distinct sent/received exchange, added ESM description"],
            ["DX chase workflow naive — no listening, no split",
             "Replaced with realistic DX Chase with Split workflow"],
            ["No F-key CW memories in Normal mode",
             "Added F1-F6 as Normal mode operators for WinKeyer memories"],
            ["No WPM speed control in Normal mode",
             "Added +/- operators with count support"],
            ["No notes/free-text for ragchewing",
             "Added Notes section with a operator and multi-line editor"],
            ["No SOTA support",
             "Added :summit command alongside :park"],
            ["No POTA self-spotting with comments",
             "Added :spot, :respot, :rove commands in Activation Lifecycle"],
            ["No P2P/S2S park/summit entry on QSOs",
             "Added P:K-XXXX and S:XX/XX-XXX inline syntax in Entry mode"],
            ["FT8 workflow fundamentally different",
             "Deferred to v2+ — digital modes need a strategic overlay model, not tactical control"],
            ["No alert/notification for rare DX",
             "Added Alerts commands and ga jump-to-alert operator"],
            ["No SSB voice keyer",
             "Added :voice commands for SSB memory playback"],
            ["DXCC tracking too shallow",
             "Added DXCC and Need Status section with granular band/mode/confirmation indicators"],
            ["No direct frequency entry",
             "Added f operator for typing a frequency directly"],
        ],
        col_widths=[2.8 * inch, 3.7 * inch],
    )
)

story.append(Spacer(1, 12))
story.append(Paragraph("Open Questions from Review", style_h2))
story.append(
    bullet(
        "<b>SO2R (second radio):</b> serious contesters run two radios. How should vim mode "
        "switch context between radios? Proposal: <font face='Courier'>Ctrl+A/Ctrl+B</font> "
        "to toggle active radio, or <font face='Courier'>:radio 1/:radio 2</font>. Deferred "
        "to v2."
    )
)
story.append(
    bullet(
        "<b>ESM detail design:</b> Enter Sends Message is the most important contest feature. "
        "The QSO state machine (callsign entered → exchange sent → exchange received → logged) "
        "needs detailed specification. Deferred to implementation design."
    )
)
story.append(
    bullet(
        "<b>Net operations:</b> casual operators who check into nets have no spot-driven "
        "workflow at all. Proposal: <font face='Courier'>:net add \"Tuesday 80m\" 3920 LSB"
        "</font> for net frequency presets. Deferred — low overlap with vim mode's strengths."
    )
)
story.append(
    bullet(
        "<b>JS8Call integration:</b> JS8Call's slow-chat model maps well to Entry mode. "
        "Worth exploring but niche. Deferred."
    )
)
story.append(
    bullet(
        "<b>Compact layout for field use:</b> POTA activators on laptops need a minimal layout. "
        "Proposal: <font face='Courier'>:layout compact</font> to hide non-essential panes. "
        "Orthogonal to vim mode itself."
    )
)
story.append(
    bullet(
        "<b>CW abort key:</b> <font face='Courier'>Ctrl+C</font> immediately stops CW "
        "transmission without changing mode. Matches the terminal interrupt convention. "
        "Works in all modes — Normal, Entry, Command."
    )
)

story.append(Spacer(1, 12))
story.append(Paragraph("Reviewer Consensus", style_h2))
story.append(
    Paragraph(
        "<b>Universally praised:</b> frequency marks (ma/'a/''), progressive learning tiers, "
        "composable search/filter language, Escape-is-Sacred invariant. The contester noted "
        "these ideas are genuinely novel in contest software.",
        style_body,
    )
)
story.append(
    Paragraph(
        "<b>Design scope:</b> the original design was a strong foundation for casual DX "
        "chasing and POTA hunting. The additions above extend it to cover contesting (ESM, "
        "split, F-keys), serious DX chasing (DXCC matrix, alerts, split), and casual operating "
        "(notes, SOTA). Digital modes (FT8/FT4, JS8Call) are deferred to v2+. The five-key "
        "survival kit (j, k, t, i, Esc) remains the entry point for all operator types.",
        style_body,
    )
)

# ── Build ───────────────────────────────────────────────────────────────

doc.build(story)
print(f"PDF written to {output_path}")
