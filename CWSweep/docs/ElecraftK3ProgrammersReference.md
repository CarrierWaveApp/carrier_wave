# Elecraft K3S/K3/KX3/KX2 Programmer's Reference

**Rev. G5, Feb. 20, 2019**

> Source: Elecraft K3S/K3/KX3/KX2 Programmer's Reference PDF, text-extracted for CAT command reference.
> For change history, see Appendix A at the end of this document.

---


(For change history, see Appendix A)

1

Command Set Overview
All K3S/K3/KX3/KX2 remote control commands are listed in Table 1. The KX3 and KX2 accept all K3
commands, though some have no functional effect on the KX3/KX2 (*). Some commands are recognized only by
the KX3 or KX2 (**). For K2 commands, see the KIO2 Programmer’s Reference.
Table 1 K3S/K3/KX3 Control Commands. (*) = Not functionally applicable to KX3/KX2.
(**) = KX3/KX2 only. ($) = Add ‘$’ for VFO B/sub RX (VFO B/dual watch for KX3/KX2).
Name
!, @*
AG $
AI
AK **
AN
AP
AR *
BC **
BG
BN $
BR
BW $
CP
CW
DB
DE *
DL
DM
DN/DNB
DS
DT
DV *
EL **
ER
ES
EW
FA
FB
FI *
FN *
FR

Description
Direct DSP control
AF gain
Auto-info mode
ATU network values
Antenna selection
CW APF on/off
RX antenna on/off
Internal use only
Bargraph read
Band number
Baud rate set
Filter bandwidth
Speech compression
CW sidetone pitch
VFO B text
Cmd processing delay
DSP command trace
Internal use only
VFO move down
VFO A text/icons
Data sub-mode
Diversity mode
Error logging on/off
Internal use only
ESSB mode
Internal use only
VFO A frequency
VFO B frequency
I.F. center frequency
Internal use only
Receive VFO select

Name
FT
FW $
GT
IC
ID
IF
IO **
IS
K2
K3
KE **
KS
KT **
KY
LD
LK $
LN *
MC
MD $
MG
ML
MN
MP
MQ **
NB $
NL $
OM
PA $
PC
PN *
PO **

Description
TX VFO select
Filter bandwidth and #
AGC speed and on/off
Icon and misc. status
Radio identification
General information
Internal use only
IF shift
K2 command mode
K3 command mode
Internal use only
Keyer speed
Internal use only
Keyboard CW/DATA
Internal use only
VFO lock (A or B)
Link VFOs
Memory channel
Operating mode
Mic gain
Monitor level
Menu entry number
Menu param read/set
Menu param read/set
Noise blanker on/off
Noise blanker level
Option modules
RX preamp on/off
Power Control
Internal use only
Power output read

Name
PS
RA $
RC
RD
RG $
RO
RT
RU
RV
RX
SB
SD
SM $
SMH *
SP *
SQ $
SW
SWT/H
TB
TE
TM *
TQ
TT
TX
UP/UPB
VX
XF $
XL
XT

Description
Power-on/off control
RX attenuator on/off
RIT/XIT offset clear
RIT down
RF gain
RIT/XIT offset (abs)
RIT on/off
RIT up
Firmware revisions
Enter RX mode
Sub or dual watch
QSK delay
S-meter
High-res S-meter
Internal use only
Squelch level
SWR
Switch tap/hold
Buffered text
TX EQ
TX meter mode
TX query
Text-to-terminal
Exter TX mode
VFO move up
VOX state
XFIL number
Internal use only
XIT on/off

Some commands emulate controls and display elements. For example, the SWT/SWH commands emulate switch
TAP/HOLD, MN accesses menus, DS, DB, and IC read VFO A / B and icons, and BA and BG read bargraphs.
Other commands directly read or modify radio parameters, such as the VFO A and B frequencies (FA and FB).
There is some overlap between emulation and parametric commands. For example, you can select the next
operating mode using an SWT command to virtually "tap" the M O D E switch, or set a specific mode using MD.

Using K3/KX3/KX2 Utility to Test Commands
The Command Tester screen of any K* Utility program can be used to test control commands. You can save
commands (or strings of commands) as macros. A subset of these can be stored in the radio’s EEPROM memory,
where they can be assigned to programmable function switches. See the Command Examples section (page 5).
2

Command Format
Note: In the remainder of this document, K3 references apply to the KX3 and KX2 as well unless otherwise noted.
Commands sent from the computer to the K3 are considered either GETs or SETs. GET commands are used by the
computer to get information from the K3; the K3 will then provide an appropriate response message (RSP). SET
commands are sent by the computer to change the radio's configuration or initiate an event. A SET can be followed
by a GET to verify the new settings, or the auto-info mechanism can be used for confirmation that something has
changed (see AI in the Meta-commands section).
SET commands use 2 or 3 characters, optional data fields, and a terminating semicolon (;). Examples:
KS020;
MD1;

Computer sets CW speed to 20 WPM (data = 020)
Computer selects LSB mode (data = 1)

Many SET commands have a corresponding GET command, which is just the command letters with no data. The
data format of the response message from the K3 (RSP) is usually identical to the format of the SET data.
Exceptions are noted in the command descriptions.
Characters sent to the K3 can use either upper or lower case. The K3 will always respond with upper case, except
when a lower-case character is a place-holder for a special symbol (e.g., the VFO B display command, DB).

Sub Receiver/VFO B Commands ($), Linked VFOs, and Diversity Mode
Some commands target VFO B (and the sub RX, in the case of the K3) if ($) is added after the command prefix.
Examples include AG$, RG$, MD$, BW$, FW$, LK$. This is indicated in the reference section by a $ in the
command title. (Some commands target VFO B itself and do not need the ‘$’, including FB, UPB, DNB, and DB.)
If the VFOs are linked (see LN), commands that affect the VFO A frequency also change VFO B. This includes
FA, UP, DN, RU, RD, and RC. In Diversity mode, BW, FW and MD match the VFO B/sub receiver filter and
mode settings, respectively, to the main receiver.

Extended Commands
Some commands have an extended data format which provides enhanced functionality or backward compatibility
with older software applications. Such commands should be avoided in switch macros because of the need to use a
meta-command to enable extended functionality (see Meta-commands section). Alternatives are available. For
example, the BW (bandwidth) command should be used in macros rather of the legacy FW command, which
depends on meta-command settings.

Response Time
The K3 will typically respond in less than 10 milliseconds. General worst-case latency is around 100 ms, except for
commands that change bands, which can take up to 500 ms.
Since the K3 provides a full-duplex interface, the computer can send the K3 commands at any time. Continuous,
fast polling (< 100 ms per poll for bar graph data in transmit mode, for example) should be carefully tested to
ensure that it isn’t affecting radio operation. Polling during transmit not be used unless necessary.

Busy/Limited Access Indication (?;)
Some commands cannot be safely handled when the K3 is in a busy state, such as transmit, or in a limited-access
state, such as BSET or VFO A/B reverse (REV switch). If a command cannot respond due to such a condition, the
K3 will return “?;”. Future firmware releases will gradually become less restrictive in this regard.
You can use the TQ command to see if the K3 is in transmit mode, and the icon/status command (IC) to check for
BSET mode (byte a, bit 6).
3

Meta-commands: AI, K2 and K3
Meta-commands change the behavior of other commands to provide automatic responses or compatibility with
older application software. In general they should not be embedded in K3 or KX3 front-panel switch macro, as they
may adversely affect software applications that control meta-command modes. The Command Reference section
explains when to use them with specific commands.
AI (Auto-info mode): The AI meta-command can be used to enable automatic responses from the K3 to a
computer in response to K3 front panel control changes by the operator. Application software may use AI1 or AI2
mode as an alternative to continuous polling. (Not appropriate for switch macros.)
AI0, No Auto-info: This is the default. The PC must poll for all radio information using GET commands; the
K3 will not send any information automatically.
AI1, Auto-Info Mode 1: The K3 sends an IF (info) response within 1 second when any frequency or moderelated event occurs, either manually (at the radio itself) or when the PC sends commands. These events
include: band change, mode change, VFO movement, RIT/XIT offset change or clear, and several additional
switches (e.g., A/B, REV, A=B, SPLIT, CW REV, RIT, XIT). IF responses are suppressed during VFO
movement. Notes: (1) putting the K3 into auto-info mode 1 (by sending AI1;) causes an initial IF response.
(2) The K3 can be placed into AI1 mode without a PC by setting CONFIG:AUTOINF to A U T O 1 . The user
may do this to support non-PC devices that make use of auto-info, such as a SteppIR antenna controller.
Application software can check for unexpected IF responses and turn AI off if required.
AI2, Auto-Info Mode 2: The K3 sends an appropriate response (FA, FB, IF, GT, MD, RA, PC, etc.) whenever
any front-panel event occurs. This applies to all of the events mentioned for mode AI1, and ultimately to all
rotary control changes and switch presses. At present only a subset of controls generate responses.
AI3, Combination: This is similar to mode AI2 and is provided only for compatibility with existing programs.
K2 (K2 command mode): The K2 meta-command modifies the set/response format of some commands. Avoid
using this command in switch macros.
K20, K2 Normal mode: This is the default; K2 command extensions are disabled.
K21, K2 Normal/rtty_off: Same as K20, except that MD and IF report RTTY and RTTY-reverse modes as LSB
and USB, respectively. This may be useful with programs that don’t support a separate RTTY mode.
K22, K2 Extended mode: Enables all K2 command extensions.
K23, K2 Extended mode/rtty_off: Enables all K2 extensions, but like K21, alters the MD and IF commands.
K3 (K3 command mode): The K3 meta-command modifies the set/response format of some commands. Avoid
using this command in switch macros.
K30, K3 Normal mode: This is the default; K3 command extensions are disabled.
K31, K3 Extended Mode: Enables all K3 command extensions (see, for example, FW). Typically, K3
applications will place the K3 in K31 mode except when K30 mode is needed due to the use of certain
commands.

4

Command Examples
Macros
Macros – strings containing one or more control commands – can be used to automate K3/KX3/KX2 control
sequences. Table 2 lists some examples. See Creating and Using Macros (page 6) for complete instructions.
Table 2 Sample Macros. These can be altered or combined as needed (see the Command Reference section).
Label
SPLIT+2
EQ MIC1
WEAKSIG
CLEANUP
WWV 10
OLDIES
LCD BRT
MEM32
LOCKA&B
PWRTEST
TUN 10W
AMP ON
599FAST
MUTE AF
MON OFF
SCANNOW
(K3 only)
STEPPIR

Description
CW DX split starting point: A>B twice, enter
SPLIT, move VFO B up 2 kHz, RIT/XIT off
Boost 100-Hz TX EQ band by 8 dB; others “flat”
Diversity mode, main/sub preamps on, 200-Hz
bandwidth, no IF shift
Turn off split/RIT/XIT; unlink VFOs; open squelch
30 m, AM mode, VFO A to 10.0 MHz, 3 kHz AF
bandwidth (requires 6 kHz IF crystal filter)
Switch to AM radio station at 1550 kHz; 4 kHz BW,
attn. on, preamp off
Set the MAIN:LCD BRT menu parameter to 6
Load frequency memory #32 into VFOs A and B
Lock both VFOs
Send “BT” at 100 W, 10 W, and 1 W, then restore
power to 100 W (“=” embeds a BT prosign)
Set power to 10 W and enter TUNE mode
Turn on an external amplifier and set K3 drive to 65
W (see CONFIG:DIGOUT1, Owner’s Manual)
Send “5NN” at 40 WPM, “TEST ” at 30 WPM
Set main and sub AF GAIN to zero
Set monitor volume to zero (present mode)
Stores VFO A & B in per-band quick-memory M4
and starts scan (> 2 second hold starts “live” scan);
VFO B frequency must be > VFO A
Send frequency info to a device attached to the
serial port, such as an antenna controller or ATU

1

Command string
SWT13;SWT13;FT1;UPB5;RT0;XT0;1
TE+00+08+00+00+00+00+00+00;
DV1;PA1;PA$1;BW0020;IS 9999;
FT0;RT0;XT0;LN0;SQ000;
FA00010000000;MD5;FA00010000000;
BW0300;2
FA00001550000;MD5;FA00001550000;
BW0400;IS 9999;RA01;PA0;
MN003;MP005;MN255;3
MC032;
LK1;LK$1;
PC100;KYW =;PC010;KYW =;
PC001;KYW =;PC100;
PC010;SWH16;
MN019;MP001;MN255;PC065;
KS040;KYW5NN ;KS030;KYWTEST ;
AG000;AG$000;
ML000;
SWT15;SWT39;SWT23;SWT39;SWH41;4
IF;5

SWT13 is a switch-emulation command that has the same effect as tapping A > B . The KX3 has different SWT codes. FT1
enters split mode. The number 5 in UPB5 is not a value in kHz, but an index into the table of step sizes (in this case 2 kHz); see
the DN command in the command reference for full details. RT0 and XT0 turn off RIT and XIT.
2
The first FA command in this macro may cause a band change. MD (mode) is sent after it, so the mode change will apply to
the new band. The second FA command is only required if auto-offset-on-mode-change is in effect. (In CONFIG: CW WGHT,
tapping 5 alternates between V F O N O R and V F O O F S . In the latter case, the VFO frequency is adjusted when switching
between CW and any other mode.)
3
MN accesses menu entries. MP can then be used (in some cases) to read or set the parameter value. In the LCD BRT macro,
MP005 sets L C D B R T to 6 . You can determine a menu entry’s parameter range by manually setting the parameter to the
lowest/highest values, typing “MP;” each time in the command test box at the top of the Command Tester screen.
4
This example uses per-band memory M4 (SWT39), but any of M1-M4 could be used, or quick memories 0-9 (see SWT/SWH
command). If scanning is started with a macro, the last switch emulation command in the macro must be SWH41 (S C A N ).
5
IF is a GET command (general transceiver info, including VFO A’s frequency and mode). When the K3 encounters a GET
command in a macro, it sends the response to any device attached to the serial port, just as if a computer had requested it.
Multiple GET commands could be placed in a macro if necessary; examples include FA and FB (VFO A and B frequencies).

5

Creating and Using Macros
K3/KX3/KX2 Utility can be used to create and test macros. The first eight of these can be sent to the transceiver (K3
and KX3 only), where they can be assigned to any of the programmable function switches. Macros can have a
length of up to 120 characters, along with a label of up to 7 characters.
Example (“SPLIT+2”):

A>B, A>B, SPLIT, VFO B up 2 kHz, RIT/XIT off, assigned to PF1

To create this macro and assign it to a K3 front panel switch, you’ll need to complete all of steps 1-8 below. The
instructions are similar for the KX3, except that KX3 Utility is used, and some SWT/SWH codes are different.
1. Run K3 Utility.
2. Click on the Command Tester/K3 Macros tab.
3. Click on the Edit Macros button at the top of the screen. This brings up the macro edit window.
4. In MACRO 1’s Macro Label field, enter the label “SPLIT+2”.
5. In the Macro Commands field, enter:
SWT13;SWT13;FT1;UPB5;RT0;XT0;

(the KX3 and KX2 have differenent SWT/SWHxx codes)

Note: The number 5 in the “UPB5” command is not a value in kHz; it is an index into a table of step sizes. UPB5
moves VFO B up 2 kHz, DNB5 moves it down 2 kHz, etc. (there are similar commands for VFO A). For the full
list of UP/DN command variations, see the DN (down) command (page 9).
6. Click on Send Macros 1-8 to K3. Exit the edit window by clicking Save. The macro can now be tested from
within the Command Tester by clicking on its associated button. (The label won’t flash on VFO B when this is
done from K3 Utility – only when using the assigned switch at the K3.)
7. At the K3, locate CONFIG:MACRO x menu entry. Tap ‘1’ if the menu entry label is not already “MACRO 1”.
8. Hold P F 1 to assign P F 1 to MACRO 1. Exit the menu.
From then on, using P F 1 will flash S P L IT + 2 and execute the above sequence.
Important Restrictions: (1) Macros normally only use SET commands, since they can’t make use of the response
from a GET. For a very useful exception to this rule, see the last sample in Table 2. (2) Macros should not use
meta-commands (like K31;) as this can interfere with software applications that control meta-modes. (3) Macros
can be used to send direct DSP commands (see ! and @, page 7), but at present this only works from K3 Utility, not
from K3 front-panel switches.

Simple Application Program
The pseudo-code program below displays the VFO A frequency (8 digits) while watching for the user to request a
frequency change via the PC keyboard. For details on individual commands, see the Command Reference section.
VfoControlLoop
{
SendCommand( “FA;” )
StringF = GetResponse( TIMEOUT_100MS )
Display( StringSubset( StringF, 5, 12 ) )
If( KeyboardInput = “+” )
SendCommand( “UP;” )
If( KeyboardInput = “-” )
SendCommand( “DN;” )
}

6

// GET frequency of VFO A
// wait for response; include a timeout, just in case
// show MHz through Hz digits on PC screen
// up/down control could be a mouse click instead
// this is a SET command that moves VFO A up

Command Reference
Note: Commands marked with a dollar sign ($) apply to VFO B (and the sub receiver, in the case of the K3).
Commands marked with an asterisk (*) are not functionally applicable to the Elecraft KX3 or KX2, but the KX3
and KX2 will accept and reply to all K3 commands. For K2 commands, see the KIO2 Programmer’s Reference.
This section describes all K3 GET, SET and RSP (response) command formats. Unless otherwise noted, the GET
format is just the 2 or 3 letters of the command followed by a semicolon. The SET and RSP data formats are
identical unless noted otherwise. When K2 or K3 extended modes are in effect (typically K22 or K31), some
commands have an extended format (see Meta-commands). Both Basic and Extended formats are described here.

! and @* (Direct Main/Auxiliary DSP control)
Elecraft releases documentation on specific DSP commands as user needs for them arise. DSP commands can cause
side effects and should be used with caution. NOTE: At present, DSP commands can not be used in
combination with regular commands in K3 Utility macros. Also, they will not work as K3 switch macros.

AG $ (AF Gain; GET/SET)
SET/RSP format: AGnnn; or AG$nnn; where nnn is 000-255.

AI (Auto-Information; GET/SET)
SET/RSP format: AIn; where n is 0-3. See Meta-commands for details. Note: The AI power-up default is
normally AI0, corresponding to K3 menu setting CONFIG:AUTOINF = N O R . AUTOINF can also be set to
A U T O 1 , which makes the default AI1 on power-up. This is useful for K3s controlling a StepIR antenna, etc.

AK (ATU Network Values; KX3/KX2 only, GET only)
RSP format: AKaabbcc; where: aa = inductance IO bitmap (ASCII hex), bb = capacitance bitmap, and cc = misc
relays bitmap. The <aa> and <bb> bitmaps can be equated to L and C values by looking at the KXAT3 or KXAT2
schematic. For example, a value of "01" would represent the smallest L or C value in the network. At present only
bit 0 of byte <cc> is defined: 00 = capacitors on the antenna side; 01 = capacitors on the transmit side. If the ATU
is not installed or is in one of the Lx/Cx test settings, “AK000000;” is returned. In BYP mode, on some bands L and
C are set to fixed non-zero values in order to cancel the ATU's own reactance when working into a 50-ohm load. In
AUTO mode, the working auto-tuned values are shown.

AN (Antenna Selection; GET/SET)
SET/RSP format: ANn; where n is 1 for antenna 1, and 2 for antenna 2.

AP (Audio Peaking Filter; GET/SET)
SET/RSP format: APn; where n is 0 for APF OFF and 1 for APF ON. Applies to CW mode only, and only if
CONFIG:DUAL PB is set to A P F .

AR (RX Antenna on/off; GET/SET; K3/K3S only)
SET/RSP format: ARn; where n is 0 for RX antenna OFF and 1 for ON.

7

BG (Bargraph Read; GET only)
RSP format: BGnnx; where nn describes which bars are turned on and x (K3 only) indicates receive (R) or
transmit (T). Returns S-meter level in receive (also see SM/SM$ command), and power or ALC level in transmit.
On the K3 and K3S, only, transmit metering mode can be set remotely using the TM command. (CWT and CMP
readings not yet available. The numeric value of SWR can be read using SW.)
K3, Receive: nn is 00 - 21 (CWT off) or 00 - 09 (CWT on).
K3, Transmit: nn is 00 - 12 (PWR) or 00 - 07 (ALC) depending on M E T E R setting. Also see TM command.
K2, Receive or Transmit: nn is 00 - 10 (D O T mode) or 12 - 22 (B A R mode).

BN $ (Band Number; GET/SET)
SET/RSP format: BNnn; where nn is 00-24, the present “logical” band for VFO A (use BN$nn for VFO B).
Also see MC command (memory channel set). Note: BN SET command applies only to VFO A at present.
BN GET works with either VFO A or B. If a band change occurs, allow 300 ms before sending other commands.
nn is defined as follows: 0=160 m, 1=80 m, 2=60 m, 3=40 m, 4=30 m, 5=20 m, 6=17 m, 7=15 m, 8=12 m, 9=10
m, 10=6 m, 11-15 reserved for future expansion, 16=Xvtr band #1, 17=Xvtr band #2… 24=Xvtr band #9.

BR (Serial I/O Baud Rate; SET only)
SET format: BRn; where n is 0 (4800 b), 1 (9600 b), 2 (19200 b), or 3 (38400 b). Note: The K3 firmware
download utility automatically sets the K3 to 38400 baud for downloads, then restores the baud rate to the user’s
selection (made using the K3’s CONFIG:RS232 menu entry).

BW $ (Filter Bandwidth; GET/SET)
SET/RSP format: BWxxxx; where xxxx is 0-9999, the bandwidth in 10-Hz units. May be quantized and/or range
limited based on the present operating mode.
Notes: (1) BW is a dervative of the legacy FW command. BW is safer to use in switch macros, because it makes
no assumptions about meta-command settings (K2x and K3x). FW may be preferred in applications. (2) In
diversity mode, BW matches the sub receiver’s filter bandwidth to the main receiver’s. (3) Both BW and BW$ can
be used in BSET mode (one exception: at present, BW/BW$ SET can’t be used in BSET mode with diversity
receive in effect). (4) If a KX3/KX2 is in DUAL RX (dual watch) mode, BW$ returns the value for BW.

CP (Speech Compression; GET/SET)
SET/RSP format: CPxxx; where xxx is 000-040 (speech compression level).

CW (CW Sidetone Pitch; GET only)
RSP format: CWxx; where xx is 30-80 (sidetone pitch in 10 Hz units).

8

DB (VFO B Display Read/Write; GET/SET; K3, KX3, and KX2 variants)
GET format: DB; (no data). Returns text displayed on VFO B, including decimal points and colons if present.
VFO B normally displays only uppercase alphabetic characters. DB returns the following lower-case characters that
represent symbols: a (antenna), b (mu), c (slashed 0), d (itself), e (sigma), f (<-), g (->), h (II), i (left-justified “1”),
j (delta, large), k (delta, small), l (right-justified “1”), m (superscript “m”), n (lowercase “w”)
There are two SET formats with different functions:
DBn; where n is an ASCII character to send to VFO B, entering at the right end of the display and scrolling left as
additional characters are entered. This can be used to create scrolling messages to alert the operator to something
regarding the computer, send extended help text, insert a newsfeed, report a DX spot, test special characters, etc.
DBnn; where nn is one of the available VFO B alternate display modes:
K3: 00=normal, 01=time, 02=date, 03=RIT/XIT offset, 04=supply voltage, 05=supply current, 06=PA
heatsink temp, 07=front panel temp, 08=PLL1 voltage, 09=PLL2 voltage, 10=AFV, 11=dBV.
(Note: Modes 08 and higher require CONFIG:TECH MD = O N .)
KX3: 00=normal, 01 = time, 02 =supply voltage, 03=battery voltage (if KXBC3 installed), 04=supply
current, 05=PA temp (PA.I=KX3, PA.X=KXPA100), 06=OSC temp, 07=AFV, 08=dBV.
KX2:. 00=normal, 01 = time, 02 =supply or batt. voltage, 03=N/A, 04=supply current, 05=PA temp
(PA.I=KX2, PA.X=KXPA100), 06=N/A (TBD: OSC temp), 07=AFV, 08=dBV, 09=amp hours.
Note: Amp-hours display is “X.XXX AH”. There’s also an AMP HRS menu entry that shows the same
value. CLR can be used from within this menu entry to reset the value to 0.

DE (Command Processing Delay; SET only; K3/K3S only)
SET format: DExxx; where xxx is 001-255, the delay value in 10-ms increments. This is useful in switch or Kpod macros, where a delay may be desired to allow the radio to complete a previous operation before the next
command is processed. Note: DE001 may result in a delay shorter than 10 ms, while DE002 is guaranteed to
provide a delay between 10 and 20 ms (etc.).

DL (DSP Command Debug On/Off; SET only)
SET format: DLx; where x = 2 to turn DSP command debugging OFF, 3 to turn it ON. When it’s ON, all
commands sent from the MCU to the DSP are echoed to the K3’s serial port, with a few exceptions such as during
program loading. The DVR icon will flash as a reminder.

DN/DNB (Move VFO A or B or a Displayed Parameter Down; SET only; also pertains to UP/UPB)
SET format: DN; or DNB; or DNn; or DNBn; where n is an optional VFO change specification. DN; and
DNn; move VFO A down. DNB; and DNBn; move VFO B down. DN; and DNB; also change parameters
shown on VFO B (menu or switch settings). VFO displacement, n: 0=1 Hz; 1 or not used=10 Hz; 2=20 Hz; 3=50
Hz; 4=1 kHz; 5=2 kHz; 6=3 kHz; 7=5 kHz; 8=100 Hz; 9=200 Hz.
Note: If the VFOs are linked (non-SPLIT), DN; and DNn; set VFO B to the same frequency as VFO A.

9

DS (VFO A and Basic Icon Read; GET only)
GET format: DS; (no data). Returns everything needed to reproduce the contents of the VFO A display, as well as
a basic subset of the LCDs icons (also see IC command, which provides many more status indicators and does not
require that K31 be in effect). The format of the response message is: DSttttttttaf; where tttttttt is the LCD text
and decimal point data, a is icon data, and f is icon flash data (all 0 for the K3), or additional K3 icon data. These
fields are detailed below.
TEXT and decimal point data: This field contains 8 bytes, with values 0x30 - 0xFF (hex). The first byte is the
left-most displayed character. Bit 7 (MSB) of each byte indicates whether the decimal point to the left of each
character is on (1) or off (0)6. The other bits contain an ASCII character that corresponds to the displayed character.
Some ASCII characters (e.g., 'X', 'M') cannot be shown on VFO A, which uses a 7-segment display. The K3 uses
such characters as placeholders for special characters that can be displayed – in some cases lowercase versions of
uppercase letters – to enhance display readability. For this reason, the characters returned by the DS command must
sometimes be converted to other characters by the software application. Table 3 shows all possible conversions,
some not used. The table assumes the decimal-point flag (bit 7) is 0.
The menu parameters for MAIN:RX EQ / TX EQ consist of 8 “mini bar-graphs” with 5 possible “levels.” These
show up as the following characters in the DS response string (level 1 through 5): ‘_’, ‘=’, ‘>’, ‘]’, and ‘^’. To see
how these should appear in a graphical application, go into RX EQ and vary one of the EQ bands over its full
range.
Table 3 DS response character conversions (bit 7 cleared).
DS chr.
<
>
@
K

Converts to
small-caps L
dash
space (blank)
H

DS chr.
M
Q
V
W
X

Converts to
N
O
U
I
c-bar

DS chr.
Z
[
\
]
^

Converts to
lowercase c
r-bar
lambda
RX/TX EQ level 4
RX/TX EQ level 5

Icon data: This field is a single byte whose value is between 0x80 and 0xFF. Bit 7 is always 1. The other 7 bits
indicate the on/off states of 8 icons common to the K2 and K3. The bits are defined as follows (B7 = 0x80).
B7: Always 1
B6: 1=NB on*
B5: 1=ANT2 selected
B4: 1=PREAMP on

B3: 1=ATT on
B2: 0=VFO A selected (always 0 for K3)
B1: 1=RIT on
B0: 1=XIT on

Icon flash data or additional K3 icons: This field is a single byte whose value is between 0x80 and 0xFF. Bit 7 is
always 1. In K3 normal mode (K30, or K2 emulation), the other 7 bits are all 0, since in general the K3 doesn’t use
flashing icons to indicate state. In K3 Extended mode (K31), the bits are defined as follows (B7 = 0x80):
B7: Always 1
B6: 1=SUB on*
B5: 1=RX ANT on
B4: 1=ATU on (in-line)

B3: 1=CWT on
B2: 1=NR on*
B1: 1=NTCH on
B0: 1=MAN NOTCH on

* The IC command provides extended info about the K3’s sub receiver (SUB on/off state, linked VFOs, band
independence, diversity, sub antenna selection, sub AUX antenna source, sub NB, and sub NR). IC does not require
the use of K31, which may be an advantage for some applications.

6

K2 decimal point flash status can be obtained directly; use LK for VFO lock, IF for scan on/off, and GT for AGC on/off.

10

DT (DATA Sub-Mode; GET/SET)
SET/RSP format: DTn; where n is the data sub-mode last used with VFO A, whether or not DATA mode is in
effect: 0 (DATA A), 1 (AFSK A), 2 (FSK D), or 3 (PSK D). See MD for setting data normal/reverse. In Diversity
Mode (K3 only, accessed by sending DV1 or via a hold of S U B ), sending DTn matches the sub receiver’s mode
to the main receiver’s. Notes: (1) Use DT only when the transceiver is in DATA mode; otherwise, the returned
value may not be valid. (2) In AI2/3 modes, changing the data sub-mode results in both FW and IS responses. (3)
The present data sub-mode is also reported as part of the IF command, although this requires that K31 be in effect.
Refer to the IF command for details.

DV (Diversity Mode; GET/SET)
SET/RSP format: DVn; where n is 0 to turn diversity mode OFF, 1 to turn it ON, and ‘S’ to toggle both the sub
RX and diversity on/off together. K3 only; requires subreceiver. Turning the sub off also cancels diversity mode.
Also see: LN (VFO A/B link) and (sub receiver on/off).

EL ** (Error Logging; SET only; KX3/KX2 only)
SET format: ELn; where n is 0 to turn error logging OFF, and 1 to turn it ON. When error logging is ON, the
radio will report all “ERR xxx” messages and general warnings (e.g. “HiTemp->5W;”) to an attached PC.

ES (ESSB Mode; GET/SET)
SET/RSP format: ESn; where n is 0 to turn ESSB mode OFF, and 1 to turn it ON. Note: The application must
place the K3 in either LSB or USB mode for the ESSB ON condition to be relevant.

FA and FB (VFO A/B Frequency; GET/SET)
SET/RSP format: FAxxxxxxxxxxx; or FBxxxxxxxxxxx; where xxxxxxxxxxx is the frequency in Hz. Example:
FA00014060000; sets VFO A to 14060 kHz. The Hz digit is ignored if the K3 is not in FINE mode (1-Hz tuning;
use SWT49). If the specified frequency is in a different amateur band than the present one, the K3 will change to
the new band, and will automatically report the new values of parameters that may have changed7. Notes: (1) Band
changes typically take 0.5 seconds; all command handling is deferred until this process is complete. (2) If the
specified frequency is over 30 MHz and is within a valid transverter band (as specified by the operator using the
K3's X V T R menu entries), the K3 will switch to that transverter band. If the specified frequency is outside the
range of 500 kHz-30 MHz and 48-54 MHz, the K3 will switch to the amateur band closest to the requested one, and
the last-used VFO A and VFO B values for that band will be retrieved. (KSYN3A extends low range to 100 kHz.)
If the VFOs are linked (non-SPLIT), FA also sets VFO B to the same frequency as VFO A.

FI * (I.F. Center Frequency; GET only)
RSP format: Finnnn; where nnnn represents the last 4 digits of the K3’s present I.F. center frequency in Hz.
Example: If nnnn = 5000, the I.F. center frequency is 8215000 Hz. Intended for use with panadapters, which need
to keep track of the exact I.F. center frequency as filter bandwidths and shifts are changed by the operator. Not
applicable to the KX3/KX2.

FR (RX VFO Assignment [K2 only] and SPLIT Cancel; GET/SET)
SET/RSP format: FRn; where n is ignored in the K3 case because VFO A is always active for receive mode (the
K3 cannot emulate the K2’s VFO A/B behavior). Any FR SET cancels SPLIT mode.

FT (TX VFO Assignment and optional SPLIT Enable; GET/SET)
SET/RSP format: FTn; where n specifies the transmit-mode VFO assignment: 0 for VFO A, 1 for VFO B.
If B (1) is selected for transmit, the K3 will enter SPLIT (except when split is N/A). Use FR0; to cancel SPLIT.
7

The parameters sent on band change include IF (includes new mode), FA, FB, FR, FT, PA, RA, AN, GT, FW, and NB.

11

FW $ (Filter Bandwidth and Number; GET/SET)
NOTE: FW is a legacy K2 command with side-effects based on the K3x and K2x meta command settings.
For the KX3, KX2 and K3, use BW if possible. Also use BW in switch macros.
K3 Extended SET/RSP format (K31): FWxxxx; where xxxx is 0-9999, the bandwidth in 10-Hz units. May be
quantized and/or range limited based on the present operating mode.
Basic and K2 Extended formats: See KIO2 Programmer’s Reference (K2). In K22 mode, direct selection of
crystal filters is possible by adding a 5th digit (K2 and K3 only). However, K31 must not be in effect, or it will
override the legacy K2 behavior and only allow direct bandwidth selection. For example, you could send
K30;K22;FW00003;K20;K31; to select filter #3 and then restore the original K2x and K3x command modes
(yours may be different).
Notes: (1) In AI2/3 modes, moving the physical WIDTH control results in both FW and IS responses (width and
shift). (2) In diversity mode, FW matches the sub receiver’s filter bandwidth to the main receiver’s, which may
result in the generation of FA/FB/FR/FT responses. (3) Both FW and FW$ can be used in BSET mode (one
exception: at present, FW/FW$ SET can’t be used in BSET mode with diversity receive in effect). (4) In K22
mode, a legacy 6th digit is added to the response. It is always 0. In the K2, it indicated audio filter on/off status.
(5) If a KX3/KX2 is in DUAL RX (dual watch) mode, FW$ returns the value for FW.

GT (AGC Time Constant; GET/SET)
Basic SET/RSP format: GTnnn; where n is 002 for fast AGC and 004 for slow AGC.
K2 Extended SET/RSP format (K22): GTnnnx; where x is 0 (AGC off) or 1 (AGC on).
Note: AGC time constant is stored per-mode, as is AGC on/off and VFO tuning rate.

12

IC (Misc. Icons and Status; GET only)
RSP format: ICabcde; where abcde are 8-bit ASCII characters (Byte in Table 4 below) used as collections of
flags (Bit in table). Each flag represents the status of an LCD icon and/or a specific transceiver function.
Some functions whose status is indicated by IC command flags can be controlled using other commands. For
example, the K3 can be put into TX TEST by sending SWH18. The condition can be verified at any time using the
IC command (byte a, bit 5). Another example: ESSB (extended SSB) can be turned on/off using an MN (menu)
command, followed by SWT11, simulating a tap of 1 on the keypad. Again, IC can be used to verify the present
state (byte d, bit 5).
The 8th bit (B7) of each byte is always 1 to ensure that control characters are not sent to the computer. The other
bits are defined as shown in Table 4.
Table 4 IC response fields. See notes below.
Byte
Bit

a (Misc)

B7
B6

Always 1
1=BSET **
0=Normal

B5

1=TX TEST
0=Normal
1=mW power level
(xvtr or KXV3 test)
0=normal power out
0=MSG bank 1
1=MSG bank 2 §

B4
B3
B2

1=MSG is playing
0=no MSG playing

B1

1 =CONFIG:MEM0-9
= BAND SEL

B0

Preset #: 0=I, 1=II§

b (Sub RX)

c (CW/DATA)

d (Voice Modes)

e (Misc)

Always 1
1=VFOs linked
(VFO A tunes both)
(K3 only)
1=VFO A/B bands
are independent
1=Diversity mode
(K3 only)

Always 1
1=Full QSK
0=Semi QSK

Always 1
1=VOX on in voice,
DATA A, AFSK A

Always 1
1= 10 Hz SHIFT
0= 50 Hz SHIFT

1=Dual-passband
CW or APF in use
1=VOX on for CW,
FSK-D, or PSK-D

1=ESSB
0=Normal
1=Noise gate on
0=Off

1= AM Sync USB
0= AM Sync LSB
1= Main RX is
squelched

1=Sub ant. = MAIN
0=Sub ant. = AUX
(K3 only)
Sub RX aux source:
1=BNC (AUX RF)
0=non-TX ATU ant
(K3 only)
1=Sub RX NB is on
0=Off (K3 only)

1=Dual-tone FSK
filter in use

1=AM Sync RX
0=Normal

1= Sub RX is
squelched (K3 only)

1=Normal FSK TX
polarity
0=inverted

1=FM PL tone on
0=Off

1=Sub RX NR is
on, 0=Off (K3 only)

1=Sync DATA
0=Normal

1=(+) Rptr TX ofs

1=Sub RX is on
(dual watch in
KX3/KX2)

1=Text-to-terminal
is in effect (see TT)

1=(-) Rptr TX ofs

1=OFS LED is on
0=VFOB LED is on
(KX3/KX2 only)
1=Fast Play in
effect (KX3/KX2
only)

* These bits are reserved for future use.
** If BSET is in effect (byte a, bit 6=1), the values of some other flags may change or may be invalid. The
application should examine this bit first.
§ Per-mode, or per mode-group (e.g., MSG bank # is stored separately for CW/FSK-D/PSK-D and voice/DATAA/AFSK-A).

13

ID (Transceiver Identifier; GET only)
RSP format: IDnnn; where nnn is 017. This command is provided only for compatibility with existing software,
which may use ID in order to distinguish between transceivers. New or modified software should send the K3
command to the transceiver. If a K3n; response is then received, the computer must be connected to a K3, KX3,
or KX2. The K3, KX3, and KX2 can be differentiated from each other using the OM command.

IF (Transceiver Information; GET only)
RSP format: IF[f]*****+yyyyrx*00tmvspbd1*; where the fields are defined as follows:
[f]
*
+
yyyy
r
x
t
m
v
s
p
b
d

Operating frequency, excluding any RIT/XIT offset (11 digits; see FA command format)
represents a space (BLANK, or ASCII 0x20)
either "+" or "-" (sign of RIT/XIT offset)
RIT/XIT offset in Hz (range is -9999 to +9999 Hz when computer-controlled)
1 if RIT is on, 0 if off
1 if XIT is on, 0 if off
1 if the K3 is in transmit mode, 0 if receive
operating mode (see MD command)
receive-mode VFO selection, 0 for VFO A, 1 for VFO B
1 if scan is in progress, 0 otherwise
1 if the transceiver is in split mode, 0 otherwise
Basic RSP format: always 0; K2 Extended RSP format (K22): 1 if present IF response
is due to a band change; 0 otherwise
Basic RSP format: always 0; K3 Extended RSP format (K31): DATA sub-mode,
if applicable (0=DATA A, 1=AFSK A, 2= FSK D, 3=PSK D)

The fixed-value fields (space, 0, and 1) are provided for syntactic compatibility with existing software.
IO (KX3/KX2, Internal Use Only)
SET/RSP format: TBD.
IS (I.F. Shift; GET/SET)
SET/RSP format: IS*nnnn; where * must be a space (blank), and nnnn is the AF center frequency (Fc) in Hz.
The SET value may be altered based on the present mode; a subsequent IS GET reports the value used. The
nominal Fc (i.e., with no SHIFT) varies with mode, and in CW or DATA modes will also vary with PITCH. To
center the passband, send IS 9999; . A subsequent IS read will then return the center frequency.
Notes: In AM-Sync mode, send IS 1400 / IS 1600 to shift to LSB / USB. This doesn’t actually shift the AF
passband; an IS get will return IS 1500 in AM-Sync because AF Fc remains at 1500 Hz. To determine which
sideband is in use for AM sync, see the IC command. In AI2/3 modes, moving the physical SHIFT control results
in both IS and FW responses (shift and width). In diversity mode, an IS command also shifts the sub receiver, and
FA/FB/FR/FT commands may be generated. IS is not applicable to FM mode or QRQ CW mode.

K2 (K2 Command Mode; GET/SET)
SET/RSP format: K2n; where n is 0-3. If non-zero, enables K2 command extensions to legacy “2-letter”
commands. (These apply to the K3 as well.) In most cases the effects of the K2 command are independent from
those of the K3 command (see below), and the two can both be non-zero at the same time. The FW command is an
exception; see meta-commands and FW for details. BW is a non-modal version of FW that is preferred in switch
macros and when AI modes aren’t used.

14

K3 * (Command Mode; GET/SET)
SET/RSP format: K3n; where n is 0-1. If n is 1, enables K3-specific command extensions to legacy “2-letter”
commands. Not needed for new commands that are unique to the K3. In most cases the effects of the K3 command
are independent from those of the K2 command (see above), and the two can both be non-zero at the same time.
The FW command is an exception; see meta-commands and FW for details. BW is a non-modal version of FW
that is preferred in switch macros and when AI modes aren’t used.

KS (Keyer Speed; GET/SET)
SET/RSP format: KSnnn; where nnn is 008-050 (8-50 WPM).

KY (CW or CW-to-DATA Keying from Text; GET/SET)
SET format: KY*[text]; where * is normally a BLANK and [text] is 0 to 24 characters. If * is a W (for “wait”),
processing of any following host commands will be delayed until the current message has been sent. This is useful
when a KY command is followed by other commands that may have side-effects, e.g., KS (keyer speed).
Basic RSP format: KYn; where n is 0 (CW text buffer not full) or 1 (buffer full). Also see TB command.
K2 Extended RSP format (K22): KYn; where n is 0 (buffer < 75% full), 1 (buffer > 75% full), or 2 (buffer
completely empty AND transmit of previous string is complete.
The following keyboard characters are mapped to CW "prosigns":
( KN

+ AR

= BT

% AS

* SK

! VE

In addition to these prosigns, these special characters can be inserted anywhere in the KY command text:
<
>
@

Puts the K3 into TX TEST mode, until a '>' character is received
Returns the K3 to TX NORM mode
In CW mode, this character normally terminates any CW message (via KY or manual send),
emulating the K2. However, tapping 2 in CONFIG:CW WGHT changes ‘@’ to a prosign:
the ‘at’ sign as used in e-mail addresses. This is the newest Morse Code character;
it can be remembered as the prosign ‘AC’ (as in “the At Character”).
^D (EOT, ASCII 04) Quickly terminates transmission; use with CW-to-DATA.

LK $ (VFO Lock; GET/SET)
SET/RSP format: LKn; where n is 0 (VFO unlocked) or 1 (locked).

LN * (Link VFOs; GET/SET)
SET/RSP format: LNn; where n is 0 (VFOs unlinked) or 1 (linked).

MC (Memory Channel; GET/SET)
SET/RSP format: MCnnn; where nnn is the memory # (or channel). Regular memories are 000-099. Per-band
quick memories: nnn = 100 + bandNum * 4 + Mn – 1. For bandNum, see BN. Mn is 1 - 4, i.e. M 1 -M 4 tap.
Notes: (1) A SET is ignored if the target memory is invalid. (2) K3 only: If CONFIG:MEM0-9 = B A N D S E L ,
then memories 000-009 only (“Quick memories”) will recall the last-used VFO frequencies in the target band, not
fixed frequencies. (3) Switching to any regular memory (000-099) updates the K3’s default V > M /M > V memory
number; this is not the case when switching to Per-Band Quick memories (M 1 -M 4 ). (4) Switching to any memory
tagged with ‘*’ as the first character in its label enables channel-hop scanning (see K3/KX3/KX2 Owner’s manual).

15

MD $ (Operating Mode; GET/SET)
SET/RSP format: MDn; or MD$n; where n is 1 (LSB), 2 (USB), 3 (CW), 4 (FM), 5 (AM), 6 (DATA), 7 (CWREV), or 9 (DATA-REV). Notes: (1) K3 only: In Diversity Mode (accessed by holding S U B ), sending MDn;
sets both main and sub mode to n. (2) DATA and DATA-REV select the data sub-mode that was last in effect on
the present band. (To read/set data sub-mode, use DT.) The norm/rev conditions for the K3’s data sub-modes are
handled in two pairs at present: DATA A/PSK D, and AFSK A/FSK D. E.g., if the radio is set up for DATA A
mode, alternating between MD6 and MD9 will cause both DATA A and PSK D to be set to the same
normal/reverse condition. In K2 command modes 1 and 3 (K21 and K23), the RSP message converts modes 6 and
7 (DATA and DATA-REV) to modes 1 and 2 (LSB and USB). This may be useful with existing software
applications that don't handle DATA modes correctly. (3) If a KX3/KX2 is in DUAL RX (dual watch) mode, MD$
returns the value for MD. (4) FM mode does not apply to the KX2.
MG (Mic Gain; GET/SET)
SET/RSP format: MGxxx; where xxx is 000-060.
ML (Monitor Level; GET/SET)
SET/RSP format: MLxxx; where xxx is 000-060. Applies to current mode (CW sidetone, voice, or data). In voice
modes, applies to MON level, even if DVR monitor level is independent (MAIN:TX DVR).

16

MN (Menu Selection; GET/SET; K3, KX3, and KX2 variants)
SET/RSP format: MNnnn; where nnn is shown in Table 5 (K3), Table 6 (KX3), or Table 6A (KX2).
MN255 is returned if the menu is not in use. MN commands can be sent in any order. To exit the menu, send
MN255. To change the parameter, use UP / DN (or MP and MQ commands—see table notes). IMPORTANT:
T E C H M D menu entry must be set to ON to access tech-mode menu entries; otherwise MN will skip these
entries. Use MN072 to access the T E C H M D menu entry. On the KX3/KX2, tech-mode parameters are locked
by default when accessed at the radio, but are automatically unlocked when accessed via the MN/MP/MQ
commands.
Table 5 K3 MN values. ‡ = can be read/set using MP command. * = removed from K3 menu (ID number
preserved for backwards compatibility). nnn is permanently associated with a menu entry, even if entries are
moved. md is the data mode pertaining to a menu entry: CW, SB (LSB/USB), DT (DATA), AM, or FM. pwr is
LP (QRP), HP (QRO), or MW (0 to 2 mW, using the KXV3 transverter I/O jacks).
Entry
ALARM
IAMBIC
LCD ADJ ‡
LCD BRT ‡
LED BRT ‡
MSG RPT ‡
PADDLE
RPT OFS ‡
RX EQ
TX EQ
VOX GN
ANTIVOX
WEIGHT
2 TONE
AFV TIM
MIC+LIN
TX DLY
AGC SLP
FM MODE
DIGOUT1 ‡
AGC HLD
FM DEV
EXT ALC
KAT3 ‡
BAT MIN
TX INH
SER NUM
TXG VCE
FW REVS
DATE

nnn
000
001
002
003
004
005
006
007
008
009
010
011
012
013
014
015
016
017
018
019
020
021
022
023
024
025
026
027
028
029

Entry
DATE MD
DDS FRQ
LIN OUT ‡
KIO3
ADC REF
RFI DET
KDVR3
AGC-S
FLx BW
FLx FRQ
FLx GN
FLx ON
FLTX md
FP TEMP
FSK POL
AUTOINF
KBPF3
AF LIM
KNB3 *
KRC2 AC
KRX3
KXV3
LCD TST
MIC SEL
NB SAVE
KPA3 ‡
PA TEMP
RS232
TUN PWR ‡
SYNC DT

nnn
030
031
032
033
034
035
036
037
038
039
040
041
042
043
044
045
046
047
048
049
050
051
052
053
054
055
056
057
058
059

17

Entry
SMTR MD
AGC-F
REF CAL
SQ MAIN
SQ SUB
SMTR OF
SMTR SC
SMTR PK
SPLT SV
SPKRS
SW TEST
SW TONE
TECH MD
TIME
AGC THR ‡
PTT RLS
BND MAP
TTY LTR
TX ALC
TXGN pwr
SUB AF
PWR SET
MIC BTN
VCO MD ‡
VFO CTS
VFO FST
VFO IND
VFO OFS
WMTR pwr
XVx ON

nnn
060
061
062
063
064
065
066
067
068
069
070
071
072
073
074
075
076
077
078
079
080
081
082
083
084
085
086
087
088
089

Entry
XVx RF
XVx IF
XVx PWR
XVx OFS
XVx ADR
AF GAIN
TX ESSB
SPKR+PH
VFO B->A
AGC PLS
RIT CLR
TX GATE
MEM 0-9
PTT KEY
VFO CRS
AFX MD ‡
SIG RMV
AFSK TX
AGC DCY
PB CTRL
MACRO x
L-MIX-R ‡
CW QRQ
TX DVR
TX MON
DUAL PB
VFO LNK
ATTEN ‡
PREAMP2
Exit Menu

nnn
090
091
092
093
094
095
096
097
098
099
100
101
102
103
104
105
106
107
108
109
110
111
112
113
114
115
116
117
118
255

Table 6 KX3 MN values. (See Table 6A for KX2.) These are the same as the K3’s only if the two are functionally
identical. nnn is permanently associated with a menu entry, even if entries are moved.
‡ = can be read/set using MP command (or MQ in the case of TXCRNUL). In some cases the get/set value
requires interpretation, or must be bit-masked to isolate the relevant field. See MP command for details.
Entry
ALARM ‡
CW IAMB ‡

MSG RPT ‡
RPT OFS ‡
RX EQ
TX EQ
VOX GN ‡
CW WGHT ‡
2 TONE

TX DLY ‡
FM MODE ‡

FM DEV ‡
ATU MD ‡
BAT MIN ‡
SER NUM
FW REVS

nnn
000
001
002
003
004
005
006
007
008
009
010
011
012
013
014
015
016
017
018
019
020
021
022
023
024
025
026
027
028
029
030
031
032
033
034
035
036
037
038
039

Entry

AUTOINF ‡
AF LIM ‡

LCD TST

RS232
TUN PWR ‡
SMTR MD ‡
REF CAL

SW TEST
SW TONE ‡
TECH MD ‡
TIME
AGC THR ‡
BND MAP ‡

nnn
040
041
042
043
044
045
046
047
048
049
050
051
052
053
054
055
056
057
058
059
060
061
062
063
064
065
066
067
068
069
070
071
072
073
074
075
076
077
078
079

18

Entry

MIC BTN ‡
VFO CTS ‡

VFO OFS ‡
WATTMTR ‡
XVx ON
XVx RF
XVx IF
XVx PWR
XVx OFS
XVx ADR
TX ESSB ‡

TX GATE ‡

VFO CRS ‡
AFX MD ‡

MACRO x
ATU DATA ‡

VFO NR ‡

nnn
080
081
082
083
084
085
086
087
088
089
090
091
092
093
094
095
096
097
098
099
100
101
102
103
104
105
106
107
108
109
110
111
112
113
114
115
116
117
118
119

Entry
CW KEY1 ‡
CW KEY2 ‡
VOX INH ‡
RX I/Q ‡
RX ISO ‡
RXSBNUL ‡
AM MODE ‡
TXSBNUL ‡
AGC MD ‡
AGC SPD ‡
TX BIAS
TX GAIN
TXCRNUL ‡
AUTOOFF ‡
RX XFIL ‡
MICBIAS ‡
PREAMP ‡
BAT CHG ‡
BKLIGHT ‡
COR LVL ‡
DUAL RX ‡
ACC2 IO ‡
RX SHFT ‡
RX NR ‡
PBT SSB ‡
LED BRT ‡
PA MODE ‡
2M MODE ‡

nnn
120
121
122
123
124
125
126
127
128
129
130
131
132
133
134
135
136
137
138
139
140
141
142
143
144
145
146
147

Exit Menu

255

MN
Table 6A KX2 MN values. * = New KX2-specific menu entry not present in the KX3. ‡ = can be read/set using
MP command (or MQ in the case of TXCRNUL). In some cases the get/set value requires interpretation, or must be
bit-masked to isolate the relevant field. See MP. If the MP command is not available, use the UP and DN knob
emulation commands to change the parameter and DS to read the parameter value from the VFO A display.
Entry
CW IAMB ‡

MSG RPT ‡
RX EQ
TX EQ
VOX GN ‡
CW WGHT ‡
2 TONE
TX DLY ‡

ATU MD ‡
BAT MIN ‡
SER NUM
FW REVS

nnn
000
001
002
003
004
005
006
007
008
009
010
011
012
013
014
015
016
017
018
019
020
021
022
023
024
025
026
027
028
029
030
031
032
033
034
035
036
037
038
039
040
041
042
043

Entry
AUTOINF ‡
AF LIM ‡

LCD TST

RS232
TUN PWR ‡
SMTR MD ‡
REF CAL

SW TEST
SW TONE ‡
TECH MD ‡
TIME
AGC THR ‡

MIC BTN ‡

nnn
044
045
046
047
048
049
050
051
052
053
054
055
056
057
058
059
060
061
062
063
064
065
066
067
068
069
070
071
072
073
074
075
076
077
078
079
080
081
082
083
084
085
086
087
19

Entry
WATTMTR ‡
XVx ON
XVx RF
XVx IF
XVx PWR
XVx OFS

TX GATE ‡
VFO CRS ‡
AFX MD ‡

ATU DATA ‡

CW KEY1 ‡
CW KEY2 ‡
VOX INH ‡
RX I/Q ‡
RXSBNUL ‡
AM MODE ‡
TXSBNUL ‡
AGC MD ‡
AGC SPD ‡
TX BIAS
TX GAIN

nnn
088
089
090
091
092
093
094
095
096
097
098
099
100
101
102
103
104
105
106
107
108
109
110
111
112
113
114
115
116
117
118
119
120
121
122
123
124
125
126
127
128
129
130
131

Entry
TXCRNUL ‡
AUTOOFF ‡

PITCH ‡ *
ALT MD *
CWT *
AMP HRS *
VOX MD *
VOX DLY *
TX CMP ‡ *
RF GAIN ‡ *
XIT *
ANT.X SW *
KXIO2 *
RTC ADJ *
AUX 1 *
AUX 2 *

nnn
132
133
134
135
136
137
138
139
140
141
142
143
144
145
146
147
148
149
150
151
152
153
154
155
156
157
158
159
160
161

Exit Menu

255

MICBIAS ‡
BKLIGHT ‡
COR LVL ‡
DUAL RX ‡

LED BRT ‡
PA MODE ‡

MP (8-bit Direct Menu Parameter Access; GET/SET)
SET/RSP format: MPnnn; where the useful range of nnn is determined by the present menu entry (255 max, or 8
bits). Only menu entries marked with ‡ in Table 5, 6, or 6A can be accessed with MP, while others will return “?;”
(use UP / DN, DS, and SWT/SWH in such cases). There is also no range checking with MP in most cases, so the
user’s macro or application must verify the correct range.
Details: MN (described above) accesses menu entries. MP can then be used (in some cases) to read or set the
parameter value. (In some cases, more than one value can be accessed for a given menu entry via the numeric keys;
see menu listing in manual.)
To determine a numeric menu entry’s parameter values (nnn): First, go into the menu manually and set the
parameter to specific values of interest. Then type “MP;” in the command test box at the top of the Command
Tester screen to see the associated nnn value.
MP Command Special Cases (KX3 and KX2 only): Special cases are listed below. For some menu entries, the
MP get/set value pertains only to specific binary bit fields in the 8-bit quantity. (For MP SETs, the KX2/3 protects
all unrelated bit positions, so the application can’t inadvertently modify them. For MP GETs, the KX2/3 masks off
unused bit positions, so they will always return zero.) Where a single bit is specified in the list below, the values x/y
are associated with bit values of 0/1. Example: To select iambic mode B for CW mode, first send MN001; (to
select the CW IAMB menu entry), then send MP128; (since 2^7 is 128, this sets bit 7 of the parameter). To select
iambic mode A, instead, send MN000; (clearing bit 7; the other bits are unaffected because of the masking
mentioned previously). To read the current value, send MP; and look at only the value of bit 7 in the return
parameter. The response would be either MP000; (mode A) or MP128; (mode B).
AGC MD: bit0=on/off
AGC SPD: bit1=slow/fast
ALARM (KX3 only): bit4=on/off
AM MODE: bit6=disabled/enabled
ATU DATA: bit3=SET1(0)/SET2(1)
ATU MODE: When ATU.X is in effect (KXAT100 mode), MP is GET-only.
KX2: L8/C8 do not apply to the KXAT2, which has only through L7/C7.
BND MAP (KX3 only): bit5=in/out
CW IAMB: bit7=modeA/modeB
CW KEY1: bit0=tip is dot/dash; bit1=paddle/hand-key
CW KEY2: bit4=tip is dot/dash; bit5=paddle/hand-key
DUAL RX: bit4=off/on
FM MODE: bit7=disabled/enabled
MIC BIAS: bit4=off/on
MIC BTN: bit0=PTT disabled/enabled; bit2=UP/DN buttons disabled/enabled
PBT SSB (KX3 only): bit7=lohicut/nor (nor=width-shift)
PREAMP (KX3 only): bit0=10dB, bit1=20dB, both=30dB
RX I/Q (KX3 only): bit2=off/on
RX SHFT (KX3 only): bit0=nor/8.0 kHz
RX XFIL (KX3 only): bit1=KXFL3 option not installed/installed
SMTR MD (KX3 only): bit7=nor (relative)/absolute
SW TONE: bits0-2=CW feedback speed in WPM; bit6=CW UI off/on; bit7=tones off/on
TECH MD: bit2=off/on
TX ESSB (KX3 only): bit0=off/on
TX GATE: bit1=off/on
VFO CRS: bits2-3=one of up to 4 coarse-tuning selections
VFO NR (KX3 only): bit5=on/off
VFO OFS (KX3 only): bit0=coarse offset control (via OFS/B knob) disabled/enabled

20

MQ (16-bit Direct Menu Parameter Access; GET/SET; KX3/KX2 Only)
SET/RSP format: MQnnnnn; where nnnnn is the 16-bit parameter value. Useful range is determined by the
present menu entry (65535 max). Applies only to the TXCRNUL menu entry at present.
NB $ (Noise Blanker On/Off; GET/SET)
SET/RSP format: NBn; or NB$n; where n is 0 (O F F ) or 1 (O N ).
Notes: NB0 always turns the noise blanker off, overriding any non-zero NL settings (see NL). In K2 extended
mode, an additional ‘0’ is appended to the NB response to provide legacy (K2) format compatibility.
NL $ (DSP and IF Noise Blanker Level; GET/SET)
SET/RSP format: NLddii; or NL$ddii; where dd is DSP NB level (00-21), and ii is IF NB level (00-21, K3
only). For the K3’s DSP or IF blanker, 00 effectively turns that blanker off, even if NB1 is in effect (see above).
For the DSP blanker on the K3, 01 = setting t1 -1 , 02 = t1 -2 , etc.; for the KX3/KX2 DSP blanker, 01 = level 1,
etc. For the IF blanker (K3 only), 01 = N A R 1 , 02 = N A R 2 , etc.

OM (Option Module Query; GET Only; K3S, K3, KX3, and KX2 variants)
K3/K3S
RSP format: OM APXSDFfLVR--; where any of the characters APXSDFfLVR, if present, indicate installed
and detected option modules (see list below). The positions of the letters are fixed. If a module is not present, its
letter is replaced by a dash (-). For example, if only a PA and sub receiver were installed, “OM;” would return
“OM -P-S--------;”. Unused dashes are reserved for future module letters and product ID.
Option List: The letters (and associated positions) in the OM string refer to the following option modules:
A = ATU (KAT3A), P = PA (KPA3A), X = XVTR and RX I/O (KXV3, KXV3A, or KXV3B), S = Sub Receiver
(KRX3A), D = DVR (KDVR3), F = Band-Pass Filter module, main (KBPF3A), f = Band-Pass Filter module, sub
(KBPF3A), L = Low-Noise Amplifier available on present band (preamp 2, only available on the KXV3B module),
V = KSYN3A synthesizer (extends VFO tuning range; see note 2 below), and R=K3S RF board.
Note 1: The presence of ‘R’ in the string (K3S RF board) is the preferred way to identify a K3S. In this case: (1)
Use the K3S format for the RA (receive attenuator) command; (2) poll for OM after each band change to 12/10/6
meters to see if the LNA (preamp 2) is enabled. (See PA command for information on preamp 2 use.)
Note 2: Presence of a KSYN3A (‘V’) extends VFO tuning range down to 100 kHz. However, to use frequencies
below 160 meters, a KBPF3 option module is required, and the receiving antenna should be connected to RX ANT
IN or XVTR IN on the KXV3B module (to bypass the high-pass filter in the T/R switch). Low-level (0.5-1 mW)
transmit below 160 meters is also possible via the XVTR OUT jack. Use of frequencies below 600 meters (470
kHz) requires a KBPF3A, or a KBPF3 modified for LF use. See details on the Elecraft web site.
KX3 and KX2
RSP format: OM APF---TBXI0n; where any of the characters APFTBXI, if present, indicate installed and
detected option modules (see list below), and 0n (zero, not ‘O’) is the product identifier (n=1 for KX2, n=2 for
KX3). The positions of the letters are fixed. If a module is not present, its letter is replaced by a dash (-). For
example, if only KXAT3 antenna tuner and KXFL3 roofing filter modules were installed, “OM;” would return
“OM A-F-------02;”. Unused dashes are reserved for future module letters.
Option List: The letters (and associated positions) in the OM string refer to the following KX3 or KX2 option
modules: A = ATU (KXAT3 or KXAT2), P = external 100-W PA (KXPA100), F = roofing filter (KXFL3), T =
external 100-W ATU (KXAT100, a KXPA100 internal option), B = internal NiMH battery-charger/real-time clock
(KXBC3), X = KX3-2M or KX3-4M transverter module, I = KXIO2 RTC I/O module.

21

PA $ (Receive Preamp Control; GET/SET)
SET/RSP format: PAn; or PA$n; where n is 0 (preamp OFF), 1 (preamp ON), or 2 (preamp 2 on the KXV3B
module; requires a KXV3B option, which is standard on the K3S but an optional upgrade to the K3).
Note 1: The main receiver’s preamp setting is saved per-RX ANT state. This is not the case for the sub receiver.
Note 2: Preamp 2 is available on 12/10/6 meters only, and must be enabled individually on each band using the
KXV3B menu entry. If the LNA is enabled on the present band, an ‘L’ will appear in the OM (optional module)
response. See OM for details.
Note 3: Preamp 2 is available for sub receiver use only if the sub is sharing the main antenna path.

PC (Requested Power Output Level; GET/SET)
Basic SET/RSP format: PCnnn;
• For the K3, nnn is normally 000-012 (KPA3 not enabled) or 000-110 watts (KPA3 enabled). If byte a, bit 4 of
the IC command response is set (indicating CONFIG:KXV3 is set to TEST, or a transverter band with lowlevel I/O is selected) then the unit is hundreds of a mW, and the available range is 0.00-1.50 mW.
• For the KX3/KX2, if a KXPA100 is not attached, nnn is 000-012 on 80-20 m and 000-015 on 160/15-6 m. If a
KXPA100 is attached, nnn is 000-110.
K2 Extended SET format (K22): PCnnnx; where nnn is 000-120 (0.1-watt units) or 000-120 (1-watt units) and x
controls the 100-W PA stage. In the K3, x=0 sets CONFIG:KPA3 MD to P A B Y P , and 1 sets it to P A N O R . In
the KX3/KX2, x=0 sets MENU:PA MODE to O F F , and 1 sets it ot O N . See owner’s manual menu descriptions.
K2 Extended RSP format (K22): PCnnnx; where nnn is power, and x is 0 (low range) or 1 (high range).
Notes: (1) A lower power limit may be in effect on trasnsverter bands (menu entries X V T R 1 -9 ). (3) The MN and
DS command can be used to select other settings of the KPA3 MD menu parameter.

PO ** (Actual Power Output Level; GET only; KX3/KX2 only)
RSP format: POnnn; where nnn is the power in tenths of a watt (QRP mode) or watts (QRO mode). Note: The
QRO case only applies if the KXPA100 amplifier enabled via PA MODE=ON, is connected to the KX3/KX2 via
the special control cable, and the PWR level is set to 11 W or higher. The reading is approximate, as it is estimated
from the KX3’s or KX2’s drive level. For a more accurate reading, use the KXPA100’s “^PF;” command.

PS (Transceiver Power Status; GET/SET)
SET/RSP format: PSn; where n = 1 indicates transceiver on. Note: PS0 turns the transceiver off, but this removes
power, so PS1 cannot be used to turn it on. To turn power on, the K3’s POWER_ON line (aux I/O jack) must be
pulled low by an external device, or it can be turned on manually using the power switch.

RA $ (Receive Attenuator Control; GET/SET)
SET/RSP format: RAnn; or RA$nn; .
For the K3/KX3/KX2, nn is 00 (attenuator OFF) or 01 (attenuator ON, -10 dB). For the K3S, nn can be the actual
value in dB: 00/05/10/15 for the main receiver, and 00/10 for the sub. For backward compatibility, RA01 can also
be used to select 10 dB.
Note 1 (K3/K3S): The main receiver’s attenuator on/off condition is saved per-RX ANT state. The sub receivers’s
attenuator setting is not.
Note 2 (K3S only): The user’s desired main receiver attenuator ON level is saved per-band (5, 10, or 15 dB).
Normally the user sets this using menu entry MAIN:ATTEN (a long hold of the ATT switch function is a shortcut
into this menu entry). A host application can directly set this per-band attenuator ON value using RA, while
simultaneously turn the attenuator on, without going into MAIN:ATTEN. Only nonzero values (RA05/10/15) will
update the menu parameter. RA00 turns the attenuator off without updating the menu parameter.

RC (RIT Clear; SET only)
SET format: RC; (no data). Sets RIT/XIT offset to zero, even if RIT and XIT are both turned off (the change will
be reflected when either RIT or XIT is turned on). Note: This command behaves differently in FINE RIT mode in
the case of the K2. Refer to the KIO2 Programmer’s Reference.
22

RD (RIT Offset Down One Unit; SET only)
SET format: RD; (no data). Moves the RIT/XIT offset down one step, which can be 1, 10, 20, or 50 Hz,
depending the present VFO tuning rate. If the user has selected COARSE VFO tuning, RD moves either 20 or 50
Hz, as specified by CONFIG:VFO FST. The offset change occurs even if RIT and XIT are both turned off (the
change will be reflected when either RIT or XIT is turned on). RIT/XIT offset range under computer control is
-9.999 to +9.999 kHz. VFO step size is stored per-mode. Use the IF command to check the present RIT/XIT offset
amount. Note: Both the RD and RU commands behave differently in the case of the K2 when FINE RIT mode is in
effect. Refer to the KIO2 Programmer’s Reference.

RG $ (RF Gain; GET/SET)
SET/RSP format: RGnnn; or RG$nnn; where nnn is 000-250. On the KX3/KX2, 250 = maximum RF gain (that
is, attenuation of –0 dB), and 190 = -60 dB.

RO (RIT/XIT Offset, Absolute; GET/SET)
SET/RSP format: ROsnnnn; where s is +/- and nnnn is 0000-9999. s can also be a space in lieu of +.

RT (RIT Control; GET/SET)
SET/RSP format: RTn; where n is 0 (RIT OFF) or 1 (RIT ON). RIT is disabled in QRQ CW mode.

RU (RIT Offset Up One Unit; SET only)
See RD command.

RV (Firmware Revisions; GET only)
GET format: RVx; where x is M (MCU), D (Main DSP), A (Aux DSP, K3), R (DVR, K3), or F (Front Panel
flash, K3).
RSP format: RVxNN.NN where NN.NN is the firmware revision, e.g. 02.37. If a module isn’t present, or an
unknown module ID is requested, the revision is normally reported as 99.99. A module that is present but
malfunctioning may return revision 00.00.

RX (Receive Mode; SET only)
SET format: RX; (no data). Terminates transmit in all modes, including message play and repeating messages.
RX/TX status is available via the TQ command and is also included in the IF response. Note: RX is not usable in
CW mode in the K2.

SB * (Sub Receiver or Dual Watch On/Off)
SET/RSP format: SBn; where n is 0 (K3 sub receiver off, or KX3/KX2 dual watch off) or 1 (on). Also see DV
command (diversity), which can automatically turn the sub on/off when using the DVS form.

SD (QSK Delay, GET only)
SET/RSP format: SDnnnn; where nnnn is the semi-break-in delay in 50-ms increments. Provided for backwards
compatibility with older applications. If the K3 is in full QSK mode, SD will still read the same value even though
the actual break-in delay is set to as close to 0 as possible.

SM $ (S-meter Read; GET only)
Basic RSP format: SMnnnn; where nnnn is 0000-0015. Examples: S9=6; S9+20=9; S9+40=12; S9+60=15.
K3 Extended RSP format (K31): nnnn is 0000-0021. S9=9; S9+20=13; S9+40=17; S9+60=21.
This command can be used to obtain either the main (SM) or sub (SM$) S-meter readings. Returns 0000 in transmit
mode. Also see BG and BA, which can be used to read exact bargraph levels in both receive and transmit modes.
23

SMH (High-resolution S-meter Read; GET only; K3 only at present)
RSP format: SMHnnn; where nnn has the following approximate values vs. S-meter reading: S1, 5; S9, 40;
S9+60, 100. Max possible value is about 140.

SP (Special Functions)
SPG; (KX3) returns ADC ground-reference reading, typically SP000.

SQ $ (Squelch Level; GET/SET)
SET/RSP format: SQnnn; or SQ$nnn; where nnn is 000-029. If the K3’s CONFIG:SQ MAIN menu entry is set
to a numeric value (0 -2 9 ), then SQ and SQ$ apply to main and sub receivers, respectively, and the SUB RF/SQL
pot on the K3 controls SUB RF GAIN. However, if SQ MAIN is set to = S U B P O T , then SQ and SQ$ are linked
(either applies to both receivers), and the SUB RF/SQL pot controls squelch for both receivers as well. (Also in this
case, the MAIN RF gain pot controls RF gain for both main and sub.)
Note: The SQ command in the K2 used the same format but different units.

SW (SWR; GET only)
RSP format: SWnnn; where nnn is 010-999. Value is SWR in tenths of a unit, from 1.0:1 to 99.9:1. The value is
updated on any transmit, but not on a band change. SW works during transmit, TUNE, and during ATU tuning.

24

SWT/SWH (Switch Emulation; SET only; K3, KX3, and KX2 variants)
SET format: SWTnn; (TAP functions) or SWHnn; (HOLD functions). nn is determined from Table 7 (K3),
Table 8 (KX3), or Table 8A (KX2). Switch emulation commands must sometimes be followed by a delay if
successive commands expect the switch function to have been executed (example: SWT16; [XMIT], delay, TQ;
[transmit status check]). Activating some switch functions results in icon or status changes that can be checked
using the IC or DS commands.
Table 7 Switch identifiers (nn) for the K3 SWT/SWH command. (For the KX3, see Table 8, and for the KX2,
Table 8A.) Table entries are organized similarly to the transceiver’s front panel (e.g. BAND is upper left on the
K3). Numeric keypad switches (0-9, ‘.’, ‘<-’) are shown in parentheses. * DIVERSITY hold function was
implemented in K3 rev. 5.10. Prior to this, a hold of the SUB switch would link/unlink VFOs A and B. To replace
the link/unlink function in 5.10 or later, menu entry CONFIG:VFO LNK was added. VFO link/unlink can also be
accomplished using the LN command.
TAP

HOLD

nn

TAP

HOLD

nn

TAP

HOLD

nn

BANDBAND+
MODEMODE+
MENU
XMIT

VOX
QSK
ALT
TEST
CONFIG
TUNE

09
10
17
18
14
16

SCAN
COARSE
LOCK
DVRSTY*
BSET
n/a

41
49
50
48
11
12

CWT (0)
AFX (<-)
V->M
M->V
M1
M2

TEXT Dec
DATA Md
AF REC
AF PLAY
M1-RPT
M2-RPT

40
43
15
23
21
31

RX ANT
DISP
ATU Tune
ANT
SHIFT/LO
WIDTH/HI
SPD/MIC
CMP/PWR

n/a
METER
ATU
ANT Name
NORM
I/II
DELAY
MON

25
08
19
26
58
59
57
56

FREQ ENT
FINE
RATE
SUB
A/B (1)
REV
(FM/rpt) (2)
A->B (3)
PRE (4)
AGC (5)
XFIL (6)
NB (7)
NR (8)
NTCH (9)
SPOT (‘.’)

SPLIT
ATT
OFF
DUAL PB/APF
LEVEL
ADJ
MANUAL
PITCH

13
24
27
29
33
34
32
42

M3
M4
REC
RIT
XIT
CLR

M3-RPT
M4-RPT
MSG Bank
PF1
PF2
n/a

35
39
37
45
47
53

Table 8 Switch identifiers (nn) for the KX3 SWT/SWH command. Table entries are organized similarly to the
KX3’s front panel (e.g. BAND is upper left); knob functions are shown in the last row. Numeric keypad switches
(0-9, ‘.’, ‘<-’) are shown in parentheses. Note: If “Fast Play” is in effect, switch emulation commands for BAND+,
BAND- and FREQ ENT are blocked (both SWT and SWH). See byte (e), bit 0 of the IC response.
TAP

HOLD

nn

TAP

HOLD

nn

TAP

HOLD

nn

TAP

HOLD

nn

BAND+

RCL

08

NR

19

MODE

ALT

14

A/B

STORE

41

NB

27

DATA

TEXT

17

A->B

REV
(FM/rpt)
SPLIT

24

BANDFREQ ENT

SCAN

10

NTCH

20

RIT

PF1

18

XIT

PF2

26

MSG (<-)

REC

11

CWT

28

RATE

KHZ

12

DISP

MENU

09

ATU TUNE
(‘.’)
XMIT (0)

ANT

44

PITCH

21

TUNE

16

PRE
(1)
ATTN
(2)
APF
(3)
SPOT
(4)
CMP
(5)
DLY
(6)

VOX

29

MON

32

NORM

33

KEYER/
MIC (9)

PWR

34

OFS/
B

CLR

35

AF/RF-SQL
(7)

PBT I/II
(8)

25

25

Table 8A Switch identifiers (nn) for the KX2 SWT/SWH command. Numeric keypad switches (0-9, ‘.’, ‘<-’) are
shown in parentheses.
TAP

HOLD

nn

TAP

HOLD

nn

HOLD

nn

AF GAIN/MON (0)

NB

32

DATA

TEXT

26

MODE

(‘.’)

RCL

08

PRE (/ATTN) (1)

NR

19

MSG

REC

11

BAND

(<-)

STORE

14

RATE

FREQ/

41

A/B

(6)

A>B

44

TAP

FIL

(2)

APF/AN

27

ATU*

(3)

PFn

20

RIT

(7)

SPLIT

18

XMIT

(4)

TUNE

16

DISP

(8)

MENU

09

KYR-SPT/MIC (5)

PWR

34

OFS/B

(9)

CLR

35

* = A T U on the KX2 is the same as A T U T U N E on the KX3.

26

TB (Received Text Read/Transmit Text Count; GET only)
RSP format: TBtrrs; where t is the count of buffered CW/data characters remaining to be sent (from KY
packets); rr is the count of received CW/data characters available (00-40), and s is the corresponding variablelength receive text string. If no received text is available, and no transmit text to be sent, the response is TB000; . t
can be 0-9; if there are more than 9 characters remaining to be sent, then t will be 9.
Notes: (1) Since an RX count is provided, semicolons—which are legal for text decode in some data modes—can
appear in the text string. A terminating semicolon is still provided as a check and to retain compatibility with other
commands. (2) After the K3 responds to a TB command, it clears the RX count to zero and the text just read is no
longer available. (3) Application software must poll with TB; often enough to prevent loss of incoming text.

TBX (Transmitted Text Read/Text Count; GET only; KX3/KX2 only)
RSP format: TBtts; where tt is the count of buffered CW/data characters remaining to be sent (from KY
packets), and s is the corresponding variable-length transmit text string. If no transmitted text is available, the
response is TBX00; . t can be 00-40; if there are more than 40 characters remaining to be sent, then tt will be 40.
Notes: (1) Since a TX count is provided, semicolons—which are legal for text transmit in some data modes—can
appear in the text string. A terminating semicolon is still provided as a check and to retain compatibility with other
commands.

TE (Transmit EQ; SET only)
SET format: TEabcdefgh; where a through h are 3-character fields, each specifying a range of –16 to +16 dB.
Values a through h correspond to EQ bands as follows: a = 50 Hz, b = 100 Hz, c = 200 Hz, d = 400 Hz, e = 800
Hz, f = 1600 Hz, g = 2400 Hz, h = 3200 Hz. Important: If the current transmit mode (the VFO B mode in SPLIT)
is SSB, CW or DATA, TE applies to SSB. If the transmit mode is ESSB, AM, or FM, TE affects ESSB/AM/FM.
The two setups are saved separately because SSB EQ is typically optimized for communications effectiveness,
while ESSB/AM/FM is often optimized for fidelity. (ESSB mode is selected using the CONFIG:TX ESSB menu
entry.) Note: If the TX EQ menu entry is displayed at the time TE is sent, the display will be updated accordingly.

TM (Transmit Meter Mode; GET/SET; K3/K3S only)
RSP format: TM0; (SWR/RF metering) or TM1; (CMP/ALC metering). This sets the transmit meter mode for
the LCD bargraphs, as well as for the BG command (equivalent to using the METER switch). When TM0 is in
effect, BG returns the RF level. When TM1 is in effect, BG returns the ALC level.

TQ (Transmit Query; GET only)
RSP format: TQ0; (receive mode) or TQ1; (transmit mode). This is the preferred way to check RX/TX status
since it requires far fewer bytes than an IF response. Note: TQ1 will be returned even during pseudo-transmit
conditions such as TX TEST or when the radio is “pre-armed” for CW transmit via XMIT or PTT. This is because
such states may turn on the K3’s KEY OUT line, activating down-stream relays (on amplifiers, transverters, etc.).

TT (Text to Terminal; SET only)
Note: TB (text buffer read) provides a more reliable means of implementing a CW/data terminal. TB must be used
rather than TT if a P3 panadapter is attached between the computer and K3.
SET format: TTn; where n is 1 to enable decoded text to be routed to a PC (ASCII). n=0 disables this. (There’s
no GET command for TT, but its status can be checked using the IC command: byte c, bit 0.) When the application
has to send a SET command of another type, it can do without interrupting the TT stream. If it has to send a GET
command, it must either suspend the text stream temporarily by sending TT0, or parse the response stream to look
for the desired return data. (Returned strings are never interspersed with text data, so this can easily be done.) Also
see the KY <text>; command for sending ASCII data as CW, RTTY, or PSK31.

27

TX (Transmit Mode; SET only)
SET format: TX; (no data). Same as activating PTT or using the XMIT switch. Applies to all modes except direct
data, i.e. FSK-D and PSK-D. (In these cases, just hit the paddle, send a message, or use a KY<text> packet. To
avoid problems with existing applications, the TX command is ignored in these modes.) Use the RX command to
cancel TX (some special considerations apply; see RX). RX/TX status is available via TQ and is also included in
the IF response.

UP/UPB (Move VFO A or B or Displayed Parameter Up; SET only)
See DN/DNB.

VX (VOX State; GET/SET on K3, GET only on KX2 and KX3)
SET/RSP format: VXn; where n is 0 (VOX off) or 1 (VOX on). Applies only to present mode only (voice/data,
or CW). In CW mode, VOX refers to “hit-the-key transmit,” i.e. the user doesn’t have to assert the X M IT switch or
the PTT input first. In voice/data modes, VOX refers to voice-operated-relay, which also doesn’t require X M IT or
PTT. KX2 only: In SSB mode, the VOX state returned by VX applies only to the external mic, whether currently
plugged in or not. VOX cannot be used with the internal mic.

XF $ (XFIL Number; GET only)
RSP format: XFn; where n is the present XFIL selection (1-5) for the target receiver. In the K3, the XFIL
selection refers to crystal filters. In the KX3, the XFIL selection refers to the analog I/Q filters on the KXFL3
module. The KX2 has only DSP filters, so XF always returns XF1; .

XT (XIT Control; GET/SET)
SET/RSP format: XTn; where n is 0 (XIT OFF) or 1 (XIT ON). XIT is disabled in QRQ CW mode.

28

Appendix A: Change History

[Applicable MCU revisions shown in brackets]

Note: Prior to revision D1 this document applied only to the K3. For earlier change history, see rev C14.
D1, 1-18-2012 [K3, rev 4.48; KX3, rev 0.58]
§
§

Document now pertains to both the K3 and KX3. Asterisks in Table 1 now show K3 commands that are not
functionally applicable to the KX3. (For K2 commands, refer to the KIO2 Programmer’s Reference.)
SWT/SWH, MN, and OM descriptions updated to show differences between K3 and KX3.

D2, 1-19-2012 [K3, rev 4.48; KX3, rev 0.59]
§
§

KXAT3 menu entry back to MN023.
XMIT/TUNE switch on KX3 remapped to match the K3’s SWT/SWH code (13). This allows KX3
Utility’s TX GAIN cal function work without being rewritten.

D5, 3-20-2012 [K3, rev 4.48; KX3, rev 0.80]
§
§
§
§
§

DB command is different for the KX3.
RG response is different for the KX3.
MQ command added for the KX3 (16-bit menu parameter access)
SPG command added (KX3 ground-reference check).
SMH command added (K3 high-resolution S-meter; to be added to the KX3 later)

D8, 4-5-2012 [K3, rev 4.48; KX3, rev 0.91]
§
§

PO command added to the KX3 (reads actual power output during transmit).
EL command added to the KX3 (turns run-time error logging on/off). Error logging, when ON, reports
“ERR xxx” and other events to the attached PC, unsolicited.

D9, 4-12-2012 [K3, rev 4.48; KX3, rev 0.92]
§

Added RX SHFT menu entry to KX3’s MN command ID list.

D10, 4-17-2012 [K3, rev 4.48; KX3, rev 0.92]
§

Corrected NL command description, including note about the KX3 noise blanker, which does not yet use
the NL command.

E2, 5-7-2012 [K3, rev 4.50; KX3, rev 0.99]
§
§

[KX3] The MN command table now reflects all of the KX3 menu parameters accessible via MP and MQ.
[KX3] The MP command now has a full list of menu entries for which the MP get/set parameters
reference only a subset of the 8 bits. Semantics and examples for these parameters are provided.

E3, 7-12-2012 [K3, rev 4.51; KX3, rev 1.10]
§

[KX3] Added RX NR to MN table.

E4, 9-18-2012 [K3, rev 4.51; KX3, rev 1.20]
§

[KX3] Added internal-only commands BC and KT to command table (documented elsewhere).
29

E5, 1-3-2013 [K3, rev 4.51; KX3, rev 1.35]
§

[KX3] Added bit to IC command to show state of OFS/VFOB LEDs. See byte (e) bit (1).

E6, 2-26-2013 [K3, rev 4.62; KX3, rev 1.38]
§

[KX3] Added MACRO menu function to MN table.

E8, 4-15-2013 [K3, rev 4.66; KX3, rev 1.42]
§

[KX3] Added LED BRT to MN table (MN145).

E9, 7-30-2013 [K3, rev 4.66; KX3, rev 1.54]
§

[KX3] Added PA MODE to MN table (MN146).

E10, 10-7-2013 [K3, rev 4.66; KX3, rev 1.70]
§

[K3 and KX3] Clarified the effect meta-mode “K22” on the PC command (power control). In the long
form of the PC set command (PCnnnx;), x controls the parameter of the KPA3 MD or PA MODE menu
entry (K3 and KX3, respectively). This allows the PC command to place the 100-W stage in-line or bypass
it (applies to the K3/100 or KX3+KXPA100).

§

[KX3] Added 2M MODE menu entry to MN table (MN147).

E11, 10-24-2013 [K3, rev 4.68; KX3, rev 1.72]
§

[K3 and KX3] The SW commands for the “REV” switch on both radios only apply to swapping repeater
input/output frequencies in FM mode (SWT12 in the K3 and SWH24 in the KX3). These SW commands
have no effect in modes other than FM. This is now noted in the SW tables for both transceivers.

E12, 2-20-2014 [K3, rev 4.83; KX3, rev 1.92]
§
§
§
§
§

[KX3] Added ‘T’ and ‘X’ identifiers to the OM (option module detect) resonse, indicating the KXAT100
and KX3-2M modules, respecitively, were detected.
[KX3] Added KE command (for Elecraft internal use only).
[KX3] Clarified PO command usage and imitations in QRO mode (with KXPA100). This command was
not working in QRO mode prior to rev. 1.92.
[KX3] Clarified NL command usage. No change in functionality.
[KX3] For the ATU.X MD menu entry (KXAT100 status), the MP command is GET-only. The host
application can change the mode by sending an appropriate command to the KXPA100 instead of the KX3.

E13, 3-21-2014 [K3, rev 4.84; KX3, rev 1.94]
§

[K3 and KX3] Added special-case LCD characters m and n to DB command.

E14, 4-3-2014 [K3, rev 4.84; KX3, rev 1.95]
§

[KX3] Added TX DLY to KX3’s MN function list (#016). This matches the K3’s TX DLY entry.

E15, 5-12-2014 [KX3, rev 2.01]
§

[KX3] Added KX3-4M module to OM response list (for character ‘X’).
30

E16, 6-26-2014 [KX3, rev. 2.11]
§

[KX3] If KX3 is in “Fast Play” message mode: (1) bit 0 of byte (e) is set in the IC response;
(2) the SWT emulation commands for BAND+, BAND-, and FREQ ENT are blocked, returning “?;”.

E17, 10-6-2014 [KX3, rev. 2.25]
§

[KX3] When the KX3 is in DUAL RX mode (dual watch), it internally sets VFO B to the same mode and
bandwidth as VFO A. In order to provide matching filter bandwidth displays on an attached PX3, the BW$,
FW$, and MD$ commands return the values for VFO A, not VFO B, in the dual-watch case. All other $
commands, as well as FB, still pertain to VFO B itself. Host applications that use these must determine
whether dual-watch mode is in effect, using either an SB or IC command.

E18, 2-20-2015 [K3, rev. 5.12]
§

§

[K3] In DV command: (1) Described DVS command variant, which toggles both diversity and sub RX
on/off together. (2) Removed note about the K3’s SUB switch having three functions. VFO linking is now
accomplished via the CONFIG:VFO LNK menu entry (see below), so the SUB switch has only two
functions: sub RX on/off (tap) and diversity on/off (hold).
[K3] Added CONFIG:VFO LNK menu entry to the MN table for the K3 (#116). This is provided as a way
of linking the VFOs now that the original LINK switch function (hold of the SUB switch) has been
removed in favor of having a hold enter diversity mode. The LN and SB host commands are unaffected.

E19, 3-31-2015 [K3, rev. 5.20]
§

§

[K3] The CONFIG:KNB3 menu entry has been removed; it is not needed since a KNB3 is required for
operation and has no parametric adjustments. This is flagged (*) in the MN command list. The associated
ID number (048) will be reserved for compatibility with K3s running older firmware.
[K3] If a new synthesizer is in use (KSYN3A), the lower limit for the FA and FB commands is 100 kHz
rather than 490 kHz. (If a KSYN3A is not installed, an FA or FB command that sets a frequency below 490
kHz will result in exactly 490 kHz.) Use of the range below 1.6 MHz requires a KBPF3 RF band-pass
filter option. To obtain good sensitivity, the RX ANT IN or XVTR IN jacks on the KXV3 option
should be used, since these bypass the high-pass filter in the T/R switch. Transmit below 1.6 MHz
(including the 600-meter band, ~0.472 MHz) is possible at ~0.5 mW by setting the CONFIG:KXV3 menu
entry to TEST and taking the TX output from the XVTR OUT jack. In this case an external amplifier
would be required (not supplied by Elecraft), and the XVTR IN jack would be used for receive.

************ FIRST K3S/K3/KX3 VERSION OF PROGRAMMER’S REFERENCE *************
F1, 3-31-2015 [K3S/K3, rev. 5.26]
§

§

[K3/K3S] Added ATTEN and PREAMP2 menu entries to the MN table. ATTEN, which is also accessible
via the MP command, has values of 5/10/15 dB in the case of the K3S; it is fixed at 10 dB for the K3.
PREAMP2 enables the built-in low-noise-amplifier on the KXV3B module. It only applies if a KXV3B
module is installed (not the original KXV3), and only on 12/10/6 meters.
[K3/K3S] The PA command now supports preamp 2 get/set (12/10/6 m only; requires KXV3B).

F2, 7-24-2015 [K3S/K3, rev. 5.33]
§

[K3/K3S] The UP/UPB and DN/DNB commands can now be used to adjust most displayed parameters
controlled by VFO A or B, respectively, including NB or NR level, manual notch pitch, sidetone pitch, data
mode, and text decode. (Menus can also be controlled using UP/UPB and DN/DNB, as before.) Up/down
31

§
§

commands cannot be used to select VFO B special displays (use DB for this), or to adjust parameters
controlled by the function encoders.
[K3S] The RA (attenuator) command now has GET/SET values of RA00/05/10/15 (dB) in the K3S case.
See related operating notes in the RA command description. Use OM to detect the K3S (see OM).
[K3/K3S] The OM (option module) command can now be used to detect the following: preamp 2 (LNA)
availability on the present band (‘L’); the KSYN3A synthesizer (‘V’), which extends VFO tuning range;
and presence of the K3S RF board (‘R’), which is the preferred way to identify a K3S transceiver. See OM
and PA commands.

F5, 12-4-2015 [KX3, all firmware revisions]
•

[KX3] AK command (ATU relay values) documented.

F6, 1-8-2016 [K3/K3S, rev. 5.46 or later]
•

[KX3] TX command (start transmit) does not apply to FSK-D and PSK-D modes. See command
description for details.

F7, 3-4-2016 [KX3, rev. 2.52]
•

Correction to “599FAST” macro on pg. 5.

•

[KX3] TBX command documented.

•

PC command description improved; now covers both K3 and KX3.

F8, 5-25-2016 [KX2, rev. 2.60]
•

[KX2] Command changes pertaining to the KX2. See: DB (special displays, including amp hours mode);
MN (menu entries, shown in table 6A); MP (menu parameter get/set); OM (option module list and
transceiver ID); SW (switch IDs, table 8A); VX (VOX mode).

F9, 5-25-2016 [KX2, rev. 2.68]
•

[KX2] AM MODE menu command added to MN table for KX2 (ID = 126). FM mode does not apply to
the KX2 (MD command).

G1, 3-16-2017 [K3/K3S, rev. 5.58]
•

VX SET (VOX on/off) command added.

•

AR GET/SET (RX antenna on/off) command added.

G2, 4-2-2017 [KX3 rev. 2.74, KX2 rev. 2.73]
•

Added ATU DATA menu entry to MN tables for KX3 and KX2 (ID = 112).

•

In MP command, ATU DATA access mask is bit 3 (for SET0/SET1).

G3, 11-14-2017 [K3/K3S, rev. 5.62 or later]
•

[K3/K3S] TM command added. Sets the transmit metering mode (SWR/RF or CMP/ALC) for both the
LCD bargraphs and for the BG command.
32

•

[K3/K3S] DE command added. Inserts a command processing delay of about 10 to 2550 ms. This is useful
in switch or K-pod macros, where a delay may be desired to allow the radio to complete a previous
operation before the next command is processed.

G4, 11-28-2018 [K3/K3S, rev. 5.66; KX2 rev. 2.92; KX3 rev. 2.93]
•

Added SW command. GET only; returns most recent transmit SWR reading.

G5, 2-20-2019 [KX2 & KX3, text corrections only]
•

MN143 is not a valid menu index on the KX2 because there’s no NR menu entry. Removed MN143 from
the KX2’s table. NOTE: NR can still be turned on/off on the KX2 using “SWH19;”.

33

