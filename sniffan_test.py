"""Test controlling the Hunter SIMPLEconnect plug-in controller from a Mac.

Usage:
    python3 sniffan_test.py light           # toggle light (stamped with current time)

Commands: light, fan, low, med, high

Protocol notes (from trace-1/trace-2):
  - Everything goes through characteristic F4641535 (write + indicate).
  - Each 20-byte packet is plaintext XOR a 4-byte key repeated 5 times, where the
    key is the CRC-32 of plaintext bytes 0-15 (so it is not random).
  - Plaintext byte 0 = sequence counter, byte 1 = command, bytes 8-10 = hour,
    minute, second of the phone clock (bytes 7-9 in the hello packet).
  - Light and fan buttons are toggles.
"""

import asyncio
import zlib
import sys
import time

from bleak import BleakClient, BleakScanner

SERVICE = "F4641530-2F5C-11E3-8B00-0002A5D5C51B"
CHAR = "F4641535-2F5C-11E3-8B00-0002A5D5C51B"

# Captured packets restamped to 00:00:00: (packet, offset of the hour byte).
HELLO = ("dcb7939460e258275f0228009b624a15fa60625b", 7)
COMMANDS = {
    "light": ("f1c9af184889814a7d67ef77b9078d62d805a52c", 8),
    "fan":   ("221cd4d99968fa8bac8694b668e6f6a309e4deed", 8),
    "low":   ("d1ecc0fd6b9ceeaf5e7280929a12e287fb10cac9", 8),
    "med":   ("4bcec2b9f6bfecebc35182d60731e0c36633c88d", 8),
    "high":  ("a236d7061e44f9542baa9769efcaf57c8ec8dd32", 8),
}


def build(template, offset, now=None):
    pkt = bytes.fromhex(template)
    # XOR the time into the plaintext time bytes, then fix up the CRC-derived
    # key. CRC-32 is linear, so the key changes by the CRC of that change alone.
    now = now or time.localtime()
    delta = bytearray(16)
    delta[offset] = now.tm_hour
    delta[offset + 1] = now.tm_min
    delta[offset + 2] = now.tm_sec
    key = (zlib.crc32(delta) ^ zlib.crc32(bytes(16))).to_bytes(4, "little")
    return bytes(b ^ (delta[i] if i < 16 else 0) ^ key[i % 4] for i, b in enumerate(pkt))


async def main():
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        sys.exit(f"usage: {sys.argv[0]} {{{','.join(COMMANDS)}}}")

    print("Scanning for Controller...")
    device = await BleakScanner.find_device_by_filter(
        lambda d, ad: SERVICE.lower() in [u.lower() for u in ad.service_uuids], timeout=15
    )
    if not device:
        sys.exit("Controller not found (is the official app closed?)")

    async with BleakClient(device) as client:
        print(f"Connected to {device.name}")
        await client.start_notify(CHAR, lambda _, data: print("  <", data.hex(" ")))

        hello = build(*HELLO)
        print("> hello", hello.hex(" "))
        await client.write_gatt_char(CHAR, hello, response=True)
        await asyncio.sleep(5)  # let the status dump finish

        cmd = build(*COMMANDS[sys.argv[1]])
        print(f"> {sys.argv[1]}", cmd.hex(" "))
        await client.write_gatt_char(CHAR, cmd, response=True)
        await asyncio.sleep(2)


asyncio.run(main())
