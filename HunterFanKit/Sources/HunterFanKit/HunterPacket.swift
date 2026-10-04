import Foundation

/// A button on the Hunter SIMPLEconnect controller.
public enum HunterCommand: String, CaseIterable, Sendable {
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
/// Packets are built from captured templates: we change only the time bytes
/// and fix up the key. CRC-32 is linear, so the key changes by the CRC of the
/// plaintext change alone, and we never need to know the full plaintext.
enum HunterPacket {
    /// A packet captured from the official app at 08:MM:SS, with the offset of
    /// its hour byte (minute and second follow it).
    struct Template {
        let bytes: [UInt8]
        let timeOffset: Int
        let minute: UInt8
        let second: UInt8
        let hour: UInt8 = 8

        init(_ hex: String, timeOffset: Int = 8, minute: UInt8, second: UInt8) {
            self.bytes = HunterPacket.bytes(hex)
            self.timeOffset = timeOffset
            self.minute = minute
            self.second = second
        }
    }

    /// Sent once after connecting.
    static let hello = Template("f5639f63493654d852d524f7b2b646e2d3b46eac", timeOffset: 7, minute: 36, second: 3)

    static let templates: [HunterCommand: Template] = [
        .light:  Template("039eb7d7bade99858714feb84b5095ad2a52bde3", minute: 36, second: 9),
        .fan:    Template("687bc90bd30fe759eec587642281eb714383c33f", minute: 36, second: 14),
        .low:    Template("66aa908ddcdabedfe110c4e22d54b2f74c569ab9", minute: 36, second: 20),
        .medium: Template("874850be3a397eec07f308d1cbb772c4aab55a8a", minute: 36, second: 24),
        .high:   Template("c0c2d1877cb0ffd5417a8ae88d3ef3fdec3cdbb3", minute: 36, second: 27),
    ]

    /// Returns the packet for `command`, stamped with the time of `date`.
    static func packet(for command: HunterCommand, at date: Date = Date(), calendar: Calendar = .current) -> Data {
        packet(from: templates[command]!, at: date, calendar: calendar)
    }

    /// Returns the hello packet, stamped with the time of `date`.
    static func helloPacket(at date: Date = Date(), calendar: Calendar = .current) -> Data {
        packet(from: hello, at: date, calendar: calendar)
    }

    private static func packet(from template: Template, at date: Date, calendar: Calendar) -> Data {
        let time = calendar.dateComponents([.hour, .minute, .second], from: date)

        var delta = [UInt8](repeating: 0, count: 16)
        delta[template.timeOffset] = template.hour ^ UInt8(time.hour!)
        delta[template.timeOffset + 1] = template.minute ^ UInt8(time.minute!)
        delta[template.timeOffset + 2] = template.second ^ UInt8(time.second!)

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
