import Foundation

/// A button on the Hunter SIMPLEconnect controller.
public enum FanCommand: String, CaseIterable, Sendable {
    /// Toggles the light on or off.
    case light
    /// Toggles the fan on or off.
    case fan
    /// Sets the fan speed. Only takes effect while the fan is on.
    case low, medium, high
}

/// Builds the 20-byte packets the controller expects.
///
/// Protocol (reverse-engineered from PacketLogger traces of the official app):
/// - Each packet is a 20-byte plaintext XOR a 4-byte key repeated 5 times.
/// - The key is the CRC-32 of plaintext bytes 0-15, so packets look random.
/// - Plaintext byte 0 is a sequence counter and byte 1 the command. Bytes 8-10
///   are the hour, minute and second of the sender's clock (bytes 7-9 in the
///   hello packet). The rest is fixed.
/// - The controller's replies carry no light or fan state: its 434 MHz link to
///   the fan is transmit-only, so it can't know.
///
/// Packets are built from captured templates, restamped offline to 00:00:00.
/// To set the time we XOR it into the time bytes and fix up the key: CRC-32 is
/// linear, so the key changes by the CRC of the plaintext change alone, and we
/// never need to know the full plaintext.
enum FanPacket {
    /// A captured packet whose time reads 00:00:00, with the offset of its
    /// hour byte (minute and second follow it).
    struct Template {
        let bytes: [UInt8]
        let timeOffset: Int

        init(_ hex: String, timeOffset: Int = 8) {
            self.bytes = FanPacket.bytes(hex)
            self.timeOffset = timeOffset
        }
    }

    /// Sent once after connecting.
    static let hello = Template("dcb7939460e258275f0228009b624a15fa60625b", timeOffset: 7)

    static let templates: [FanCommand: Template] = [
        .light:  Template("f1c9af184889814a7d67ef77b9078d62d805a52c"),
        .fan:    Template("221cd4d99968fa8bac8694b668e6f6a309e4deed"),
        .low:    Template("d1ecc0fd6b9ceeaf5e7280929a12e287fb10cac9"),
        .medium: Template("4bcec2b9f6bfecebc35182d60731e0c36633c88d"),
        .high:   Template("a236d7061e44f9542baa9769efcaf57c8ec8dd32"),
    ]

    /// Returns the packet for `command`, stamped with the time of `date`.
    static func packet(for command: FanCommand, at date: Date = Date(), calendar: Calendar = .current) -> Data {
        packet(from: templates[command]!, at: date, calendar: calendar)
    }

    /// Returns the hello packet, stamped with the time of `date`.
    static func helloPacket(at date: Date = Date(), calendar: Calendar = .current) -> Data {
        packet(from: hello, at: date, calendar: calendar)
    }

    private static func packet(from template: Template, at date: Date, calendar: Calendar) -> Data {
        let time = calendar.dateComponents([.hour, .minute, .second], from: date)

        var delta = [UInt8](repeating: 0, count: 16)
        delta[template.timeOffset] = UInt8(time.hour!)
        delta[template.timeOffset + 1] = UInt8(time.minute!)
        delta[template.timeOffset + 2] = UInt8(time.second!)

        let keyDelta = crc32(delta) ^ crc32([UInt8](repeating: 0, count: 16))
        let key = withUnsafeBytes(of: keyDelta.littleEndian, Array.init)

        return Data(template.bytes.enumerated().map { i, byte in
            byte ^ (i < 16 ? delta[i] : 0) ^ key[i % 4]
        })
    }

    /// Standard CRC-32 (as used by zlib and ZIP).
    static func crc32(_ data: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return ~crc
    }

    fileprivate static func bytes(_ hex: String) -> [UInt8] {
        var result: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            result.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return result
    }
}
