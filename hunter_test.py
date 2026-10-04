"""Test controlling the Hunter SIMPLEconnect plug-in controller from a Mac.

Usage:
    python3 hunter_test.py light           # toggle light (stamped with current time)
    python3 hunter_test.py fan --raw       # send the exact captured bytes instead

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

# Captured from trace-2, second session at 08:36:SS:
# (packet, offset of the hour byte, minute, second).
HELLO = ("f5639f63493654d852d524f7b2b646e2d3b46eac", 7, 36, 3)
COMMANDS = {
    "light": ("039eb7d7bade99858714feb84b5095ad2a52bde3", 8, 36, 9),
    "fan":   ("687bc90bd30fe759eec587642281eb714383c33f", 8, 36, 14),
    "low":   ("66aa908ddcdabedfe110c4e22d54b2f74c569ab9", 8, 36, 20),
    "med":   ("874850be3a397eec07f308d1cbb772c4aab55a8a", 8, 36, 24),
    "high":  ("c0c2d1877cb0ffd5417a8ae88d3ef3fdec3cdbb3", 8, 36, 27),
}


def build(template, offset, minute, second, raw, now=None):
    pkt = bytes.fromhex(template)
    if raw:
        return pkt
    # Change the plaintext time bytes, then fix up the CRC-derived key. CRC-32 is
    # linear, so the key changes by the CRC of the plaintext change alone.
    now = now or time.localtime()
    delta = bytearray(16)
    delta[offset] = 8 ^ now.tm_hour
    delta[offset + 1] = minute ^ now.tm_min
    delta[offset + 2] = second ^ now.tm_sec
    key = (zlib.crc32(delta) ^ zlib.crc32(bytes(16))).to_bytes(4, "little")
    return bytes(b ^ (delta[i] if i < 16 else 0) ^ key[i % 4] for i, b in enumerate(pkt))


async def main():
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        sys.exit(f"usage: {sys.argv[0]} {{{','.join(COMMANDS)}}} [--raw]")
    raw = "--raw" in sys.argv

    print("Scanning for Controller...")
    device = await BleakScanner.find_device_by_filter(
        lambda d, ad: SERVICE.lower() in [u.lower() for u in ad.service_uuids], timeout=15
    )
    if not device:
        sys.exit("Controller not found (is the Hunter app closed?)")

    async with BleakClient(device) as client:
        print(f"Connected to {device.name}")
        await client.start_notify(CHAR, lambda _, data: print("  <", data.hex(" ")))

        hello = build(*HELLO, raw)
        print("> hello", hello.hex(" "))
        await client.write_gatt_char(CHAR, hello, response=True)
        await asyncio.sleep(5)  # let the status dump finish

        cmd = build(*COMMANDS[sys.argv[1]], raw)
        print(f"> {sys.argv[1]}", cmd.hex(" "))
        await client.write_gatt_char(CHAR, cmd, response=True)
        await asyncio.sleep(2)


asyncio.run(main())
