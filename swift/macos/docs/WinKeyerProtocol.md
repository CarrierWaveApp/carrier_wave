# WinKeyer 3 Host-Mode Protocol Reference

Condensed reference for integrating K1EL WinKeyer 3 (WK3) via USB serial.

## Serial Configuration

| Parameter   | Value          |
|-------------|----------------|
| Baud rate   | 1200 (default), 9600 (WK3 option) |
| Data bits   | 8              |
| Stop bits   | 2              |
| Parity      | None           |
| Flow control| None (XOFF/XON handled in-protocol) |

The WinKeyer presents as a USB CDC serial device (typically `/dev/cu.usbmodemXXXX` on macOS).

## Host Mode Lifecycle

1. **Open**: Send `0x00 0x02` (Admin: Open). WK returns firmware revision byte (e.g., `0x17` = v23).
2. **Configure**: Send immediate commands to set speed, mode, sidetone, etc.
3. **Operate**: Send ASCII characters (0x20–0x7F) for buffered CW output. Send immediate/buffered commands as needed.
4. **Close**: Send `0x00 0x03` (Admin: Close). Returns WK to standalone mode.

## Command Encoding

All commands are single-byte or multi-byte sequences. Bytes 0x01–0x1F are **immediate commands** (processed instantly). Bytes 0x20–0x7F are **ASCII characters** sent to the CW buffer. Byte 0x00 is the **admin command prefix** (followed by admin sub-command byte).

### Admin Commands (prefix 0x00)

| Sub-cmd | Name              | Payload         | Response        |
|---------|-------------------|-----------------|-----------------|
| 0x00    | Calibrate         | —               | —               |
| 0x01    | Reset             | —               | —               |
| 0x02    | Host Open         | —               | Firmware rev byte |
| 0x03    | Host Close        | —               | —               |
| 0x04    | Echo Test         | 1 byte          | Echoed byte     |
| 0x05    | Paddle A2D        | —               | A2D value byte  |
| 0x06    | Speed A2D         | —               | A2D value byte  |
| 0x07    | Get Values        | —               | 15 bytes        |
| 0x08    | Reserved          | —               | —               |
| 0x09    | Get Cal           | —               | 1 byte          |
| 0x0A    | Set WK1 Mode      | —               | —               |
| 0x0B    | Set WK2 Mode      | —               | —               |
| 0x0C    | Dump EEPROM       | —               | 256 bytes       |
| 0x0D    | Load EEPROM       | 256 bytes       | —               |
| 0x0E    | Send Msg          | 1 byte (slot)   | —               |
| 0x0F    | Load Msg          | slot + text + 0 | —               |
| 0x10    | Set WK3 Mode      | —               | —               |
| 0x11    | Write WK3 Reg     | addr + data     | —               |
| 0x12    | Read WK3 Reg      | addr            | data byte       |

### Immediate Commands (0x01–0x1F)

| Code | Name             | Payload       | Description                        |
|------|------------------|---------------|------------------------------------|
| 0x01 | Sidetone Control | 1 byte        | Frequency (0=off, 1-10 = 4kHz–800Hz) |
| 0x02 | Set Speed        | 1 byte (WPM)  | 5–99 WPM                          |
| 0x03 | Set Weighting    | 1 byte        | 10–90 (50 = normal)               |
| 0x04 | Set PTT Lead-in  | 1 byte        | Lead-in time in 10ms units        |
| 0x05 | Set Speed Pot    | 3 bytes       | Min, Range, 0                     |
| 0x06 | Pause            | 1 byte        | 1=pause, 0=resume                 |
| 0x07 | Get Speed Pot    | —             | Returns speed pot byte             |
| 0x08 | Backspace        | —             | Remove last unsent character       |
| 0x09 | Pin Config       | 1 byte        | Bit field for pin assignments      |
| 0x0A | Clear Buffer     | —             | Flush CW send buffer               |
| 0x0B | Key Immediate    | 1 byte        | 1=key down, 0=key up              |
| 0x0C | HSCW Speed       | 2 bytes       | High-speed CW (not standard use)  |
| 0x0D | Farnsworth       | 1 byte        | Farnsworth spacing WPM             |
| 0x0E | Set WinKeyer Mode| 1 byte        | Mode register bits                 |
| 0x0F | Load Defaults    | 15 bytes      | Bulk-load all operating parameters |
| 0x10 | First Extension  | 1 byte        | First-element extension (0–250)    |
| 0x11 | Set Key Comp     | 1 byte        | Key compensation in ms             |
| 0x12 | Null (Pad)       | —             | NOP for serial sync                |
| 0x13 | PTT Control      | 1 byte        | 1=PTT on, 0=PTT off (**buffered**) |
| 0x14 | Timed Key Down   | 1 byte        | Key down for N × 10ms              |
| 0x15 | Wait             | 1 byte        | Pause for N × 10ms (**buffered**)  |
| 0x16 | Merge Letters    | 2 bytes       | Merge two ASCII chars as prosign   |
| 0x17 | Speed Change     | 1 byte (WPM)  | Change speed in-buffer (**buffered**) |
| 0x18 | Port Select      | 1 byte        | Select key output port             |
| 0x19 | Cancel Buffer    | —             | Cancel sending, stop key           |
| 0x1A | Buffered NOP     | —             | No-op in buffer                    |
| 0x1B–0x1F | Reserved    | —             | —                                  |

## Status Byte (WK → Host)

Asynchronous status bytes have the top two bits set: `(byte & 0xC0) == 0xC0`.

```
Bit 7: 1  (tag)
Bit 6: 1  (tag)
Bit 5: XOFF     — send buffer full, stop sending characters
Bit 4: BREAKIN  — paddle squeeze detected (operator interrupt)
Bit 3: BUSY     — WK is currently sending
Bit 2: 0  (reserved)
Bit 1: 0  (reserved)
Bit 0: 0  (reserved)
```

| Mask | Meaning |
|------|---------|
| 0x20 | XOFF — buffer full, pause sending |
| 0x10 | BREAKIN — operator pressed paddles |
| 0x08 | BUSY — keyer is actively sending |

## Speed Pot Byte (WK → Host)

Speed pot change bytes have bit 7 set and bit 6 clear: `(byte & 0xC0) == 0x80`.

```
Bit 7: 1  (tag)
Bit 6: 0  (tag)
Bits 5-0: speed value (add to pot minimum for actual WPM)
```

## Echo Back Bytes

Any byte with `(byte & 0xC0) < 0x80` is an echo of a sent ASCII character, confirming it has been keyed.

## Prosign Encoding

Use the Merge Letters command (0x16) followed by two ASCII characters to send a prosign. Common prosigns:

| Prosign | Merge       | Usage |
|---------|-------------|-------|
| AR      | `0x16 A R`  | End of message |
| BT      | `0x16 B T`  | Separator (=) |
| SK      | `0x16 S K`  | End of contact |
| KN      | `0x16 K N`  | Go ahead (only you) |

## Flow Control

WinKeyer uses in-protocol XOFF: when the status byte has bit 5 (XOFF) set, the host must stop sending characters until a status byte without XOFF is received. This prevents buffer overflow.

## References

- [K1EL WinKeyer 3 Interface and Operation Manual](https://www.k1el.com/WK3iom.pdf)
- [K1EL WK3 Host Mode Protocol](https://www.k1el.com/WK3protocol.pdf)
