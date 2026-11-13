# Sheet 02 — I2C Bus + UART Architecture

## I2C Bus (Main Box)

```
+3V3 ──[4.7kΩ]──┬──────────────────────────────── SDA BUS
                 │
+3V3 ──[4.7kΩ]──┼──────────────────────────────── SCL BUS
                 │
           (pull-ups at bus origin, near ESP32)

     SDA BUS ────┬──────────┐
                 │          │
              SC16IS752  SC16IS752
              SDA(0x4D)  SDA(0x4E)

     SCL BUS ────┴──────────┘

ESP32 GPIO21 ── SDA BUS
ESP32 GPIO47 ── SCL BUS

SC16IS752 address:
  SC16IS752 #1: A0=VDD, A1=VDD → 0x4D  (per datasheet address table)
  SC16IS752 #2: A0=GND, A1=VDD → 0x4E

Note: Audio mux (CD4051 ×3) and key mux (CD4052) are GPIO-addressed —
they are NOT on the I2C bus.
```

> **Future RF box (deferred).** When the bandpass-filter switching matrix is
> added, an I2C extension via P82B96 buffers and a Cat5e cable will fan out
> to two MCP23017 expanders at 0x20 / 0x21. Reserve those addresses and
> leave a header / panel cutout for an RJ45 jack if board space allows. The
> earlier P82B96 wiring in this doc was wrong (Sx/Sy pin numbering) — design
> from the NXP datasheet directly when the time comes.

---

## UART Architecture (CAT Control)

```
COMPUTER SIDE                    ESP32-S3 INTERNAL              RADIO SIDE

Radio 1:
Computer USB ──► Heltec USB-C (native USB CDC)
                     │ (virtual COM port, no UART pins used)
                     ▼
              ESP32 firmware (Radio 1 CDC handler)
                     │
                     ▼ software bridge
              SC16IS752 #1, UART A ──► MAX3232 #1 ──► DB9 #1 ──► Radio 1 ACC

Radio 2:
Computer USB ──► CP2102N #1 (USB-UART)
                     │ TXD/RXD
                     ▼
              ESP32 GPIO43 (UART0 RX) ← CP2102N #1 TXD
              ESP32 GPIO44 (UART0 TX) → CP2102N #1 RXD
                     │ UART0 software bridge
                     ▼
              SC16IS752 #1, UART B ──► MAX3232 #2 ──► DB9 #2 ──► Radio 2 ACC

Radio 3:
Computer USB ──► CP2102N #2 (USB-UART)
                     │
              ESP32 GPIO1  (UART1 RX) ← CP2102N #2 TXD
              ESP32 GPIO2  (UART1 TX) → CP2102N #2 RXD
                     │
              SC16IS752 #2, UART A ──► MAX3232 #3 ──► DB9 #3 ──► Radio 3 ACC

Radio 4:
Computer USB ──► CP2102N #3 (USB-UART)
                     │
              ESP32 GPIO4  (UART2 RX) ← CP2102N #3 TXD
              ESP32 GPIO5  (UART2 TX) → CP2102N #3 RXD
                     │
              SC16IS752 #2, UART B ──► MAX3232 #4 ──► DB9 #4 ──► Radio 4 ACC
```

---

## CP2102N Module Wiring (×3, identical)

```
                    CP2102N Module
                    ┌─────────────────────────┐
Computer USB-C ────►│ USB-C or micro-USB      │
                    │                         │
                    │ TXD ────────────────────►│── ESP32 UARTn RX GPIO
                    │ RXD ◄────────────────────│── ESP32 UARTn TX GPIO
                    │ GND ────────────────────►│── GND (common)
                    │ VCC (3.3V out) ── NC     │  (don't connect, ESP32 has own 3V3)
                    └─────────────────────────┘

Module  │ ESP32 RX GPIO │ ESP32 TX GPIO
--------|---------------|---------------
#1 (R2) │ GPIO43        │ GPIO44
#2 (R3) │ GPIO1         │ GPIO2
#3 (R4) │ GPIO4         │ GPIO5
```

---

## SC16IS752 Wiring (×2, identical except address)

```
                    SC16IS752 Breakout (CJMCU-752)
                    ┌─────────────────────────────┐
I2C SDA ───────────►│ SDA                         │
I2C SCL ───────────►│ SCL                         │
                    │ A0 ── see address table      │
                    │ A1 ── see address table      │
                    │                             │
                    │ UARTA_TX (pin TXDA) ────────►│── MAX3232 T1IN (Radio A)
                    │ UARTA_RX (pin RXDA) ◄────────│── MAX3232 R1OUT (Radio A)
                    │                             │
                    │ UARTB_TX (pin TXDB) ────────►│── MAX3232 T1IN (Radio B)
                    │ UARTB_RX (pin RXDB) ◄────────│── MAX3232 R1OUT (Radio B)
                    │                             │
                    │ XTAL1 ──[1.8432MHz]── XTAL2 │  (crystal across these pins)
                    │ VCC ── +3V3                 │
                    │ GND ── GND                  │
                    │ /RST ── +3V3 (no reset)     │
                    └─────────────────────────────┘

Chip   │ UART A radio │ UART B radio │ A0  │ A1
-------|-------------|--------------|-----|-----
#1     │ Radio 1     │ Radio 2      │ VDD │ VDD  → 0x4D
#2     │ Radio 3     │ Radio 4      │ GND │ VDD  → 0x4E
```

---

## MAX3232 Wiring (×4, identical)

```
                    MAX3232ECPE (DIP-16)
                    ┌─────────────────────────┐
SC16IS752 UART TX ─►│ T1IN (pin 11)           │
SC16IS752 UART RX ◄─│ R1OUT (pin 12)          │
                    │                         │
                    │ T1OUT (pin 14) ──────────►│── DB9 pin 3 (TXD → radio)
                    │ R1IN  (pin 13) ◄──────────│── DB9 pin 2 (RXD ← radio)
                    │                         │
                    │ C1+  (pin 1) ──[100nF]── C1− (pin 3)
                    │ C2+  (pin 4) ──[100nF]── C2− (pin 5)
                    │ V+   (pin 2) ──[100nF]── GND
                    │ V−   (pin 6) ──[100nF]── GND
                    │ VCC  (pin 16) ── +3V3    │
                    │ GND  (pin 15) ── GND     │
                    └─────────────────────────┘

DB9 Female connector (radio side):
  Pin 2: RXD (data from radio to box)
  Pin 3: TXD (data from box to radio)
  Pin 5: GND
  Pin 7: RTS ──[wire loop]── Pin 8: CTS  (loopback — omit if radio needs flow control)
  Pins 1,4,6,9: NC

Radio baud rates (configure in radio menu to match firmware):
  Kenwood: 9600 or 38400 (TS-590, TS-890)
  Yaesu: 4800–38400 (FT-991A, FTDX10)
  Icom: 9600 (IC-7300, IC-7610, CI-V via RS-232 adapter)
