#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pyserial"]
# ///
"""Test CI-V communication with a Xiegu G90 (or any CI-V radio) over USB serial."""

import sys
import time
import glob
import serial

def find_port():
    ports = glob.glob("/dev/cu.usbserial*") + glob.glob("/dev/cu.SLAB*")
    if not ports:
        print("No USB serial device found. Plug in the FTDI cable.")
        sys.exit(1)
    print(f"Found: {ports[0]}")
    return ports[0]

def civ_frame(to_addr, cmd, data=b""):
    return bytes([0xFE, 0xFE, to_addr, 0xE0, cmd]) + data + bytes([0xFD])

def hex_dump(data):
    return " ".join(f"{b:02X}" for b in data)

def try_baud(port_path, baud):
    print(f"\n--- Trying {baud} baud ---")
    try:
        ser = serial.Serial(port_path, baud, timeout=1)
    except serial.SerialException as e:
        print(f"  Failed to open: {e}")
        return None

    time.sleep(0.2)
    ser.reset_input_buffer()

    # Send CI-V identify to broadcast address (0x00)
    identify = civ_frame(0x00, 0x19, b"\x00")
    print(f"  TX: {hex_dump(identify)}")
    ser.write(identify)

    time.sleep(0.5)
    rx = ser.read(ser.in_waiting or 64)
    if rx:
        print(f"  RX: {hex_dump(rx)}")
        # Parse CI-V frames
        i = 0
        while i < len(rx) - 5:
            if rx[i] == 0xFE and rx[i+1] == 0xFE:
                to_addr = rx[i+2]
                from_addr = rx[i+3]
                # Find terminator
                end = rx.find(0xFD, i+4)
                if end >= 0:
                    frame = rx[i:end+1]
                    if to_addr == 0xE0:  # addressed to us
                        print(f"  -> Response from 0x{from_addr:02X}: {hex_dump(frame)}")
                        ser.close()
                        return (baud, from_addr, frame)
                    i = end + 1
                    continue
            i += 1
        print("  (no valid CI-V response to us)")
    else:
        print("  (no response)")

    ser.close()
    return None

def main():
    port = find_port()
    print(f"Testing CI-V on {port}")

    for baud in [19200, 9600, 38400, 115200]:
        result = try_baud(port, baud)
        if result:
            baud, addr, frame = result
            print(f"\n=== Radio detected! ===")
            print(f"  Baud: {baud}")
            print(f"  CI-V address: 0x{addr:02X}")
            print(f"  Raw frame: {hex_dump(frame)}")

            # Try reading frequency
            time.sleep(0.2)
            ser = serial.Serial(port, baud, timeout=1)
            ser.reset_input_buffer()
            read_freq = civ_frame(addr, 0x03)
            print(f"\n  Reading frequency...")
            print(f"  TX: {hex_dump(read_freq)}")
            ser.write(read_freq)
            time.sleep(0.3)
            rx = ser.read(ser.in_waiting or 64)
            if rx:
                print(f"  RX: {hex_dump(rx)}")
            ser.close()
            return

    print("\nNo CI-V radio detected at any baud rate.")

if __name__ == "__main__":
    main()
