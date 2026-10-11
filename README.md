# Sniffan

An unofficial iOS app and Swift package for controlling a ceiling fan through the
**Hunter SIMPLEconnect plug-in control** (FCC ID [IN2TX44](https://fccid.io/IN2TX44)),
built entirely from **sniffed Bluetooth traffic**.

The official "SIMPLEconnect plug-in control" app was removed from the App Store years
ago and was never updated for modern iPhones. Sniffan replaces it: light on/off, fan
on/off and the three fan speeds, from your own app.

> **Not affiliated with or endorsed by Hunter Fan Company.** Hunter and SIMPLEconnect
> are trademarks of Hunter Fan Company. Use at your own risk.

## How it was built

No firmware was dumped and no app code was decompiled. The protocol was worked out
by capturing the official app's Bluetooth LE traffic with Apple's **PacketLogger**
(with the iOS Bluetooth logging profile installed), pressing one button at a time,
and comparing packets until every byte that changes was explained. Hence the name.

## The hardware

The plug-in "controller" is a bridge with two radios:

```
iPhone ──Bluetooth LE──> plug-in controller ──434 MHz RF──> receiver in the fan
```

- The 434 MHz link to the fan is **transmit-only**, so the controller can't know
  whether the light or fan is on. The official app didn't show state either.
- **Light and fan commands are toggles.** Speed commands only take effect while the
  fan is on.
- The controller accepts **one Bluetooth connection at a time**. Close the official
  app (and any other app using the controller) before connecting.
- The controller appears to store the schedules set in the official app and run
  them itself. Sniffan doesn't read or change schedules.

## The protocol

Everything goes through one GATT characteristic:

| | UUID |
|---|---|
| Service | `F4641530-2F5C-11E3-8B00-0002A5D5C51B` |
| Characteristic (write + indicate) | `F4641535-2F5C-11E3-8B00-0002A5D5C51B` |

After connecting, the app enables indications and writes a 20-byte **hello** packet.
The controller echoes it back, followed by a burst of about 40 indications (probably
its stored schedules). Each button press is then one 20-byte write, which the
controller acknowledges and echoes back as an indication.

Each packet is a 20-byte message XORed with a 4-byte key repeated five times. The key
is the **CRC-32 of the message's first 16 bytes**, so every packet looks random, but
it is a checksum, not encryption. Within the message:

| Byte | Meaning |
|---|---|
| 0 | Sequence counter |
| 1 | Command (light, fan, low, medium, high) |
| 8–10 | Hour, minute, second of the sender's clock (7–9 in the hello packet) |

Sniffan builds packets from captured templates restamped to 00:00:00. To send a
command it XORs the current time into the time bytes and, because CRC-32 is linear,
fixes up the key by XORing in the CRC of that change. See
[`FanPacket.swift`](SniffanKit/Sources/SniffanKit/FanPacket.swift). The tests check
the output byte for byte against packets the official app sent.

## Project layout

```
App/                 SwiftUI app (one screen: buttons plus a collapsible protocol log)
SniffanKit/          Swift package with all Bluetooth and protocol code, no UI
  FanController      connects, sends commands, keeps a protocol log (@Observable)
  FanPacket          builds packets
  FanLogEntry        one protocol log entry
sniffan_test.py      Python script to send a command from a Mac
```

## Running the app

Requires Xcode and an iPhone running iOS 17 or later. The simulator has no Bluetooth.

1. Open `Sniffan.xcodeproj`.
2. In the Sniffan target's **Signing & Capabilities**, choose your team and set your
   own bundle identifier.
3. Close the official app if it's running, then build and run on your iPhone and
   allow Bluetooth access.

## Using SniffanKit

```swift
import SniffanKit

let controller = FanController()
controller.connect()                 // scan, connect, send hello
// controller.state: .scanning → .connecting → .ready
try await controller.send(.light)    // .light, .fan, .low, .medium, .high
```

`FanController` is `@Observable`, so SwiftUI updates when `state` or `log` changes.
The package also builds for macOS 14 or later.

Run the tests with:

```bash
cd SniffanKit && swift test
```

## Sending commands from a Mac

```bash
python3 -m venv .venv
.venv/bin/pip install bleak
.venv/bin/python sniffan_test.py light
```

Commands: `light`, `fan`, `low`, `med`, `high`. macOS asks to allow Bluetooth access
for your terminal the first time.

## License

[MIT](LICENSE)
