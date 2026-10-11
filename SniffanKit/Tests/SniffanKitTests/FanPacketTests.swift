import XCTest
@testable import SniffanKit

final class FanPacketTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int, _ second: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: hour, minute: minute, second: second))!
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    func testCRC32MatchesZlib() {
        XCTAssertEqual(FanPacket.crc32(Array("123456789".utf8)), 0xCBF4_3926)
    }

    func testTemplateTimeReproducesTemplate() {
        let packet = FanPacket.packet(for: .light, at: date(8, 36, 9), calendar: calendar)
        XCTAssertEqual(hex(packet), "039eb7d7bade99858714feb84b5095ad2a52bde3")
    }

    /// The official app sent this "light" packet at 08:34:55 (trace-2, first session).
    func testRetimedPacketMatchesCapture() {
        let packet = FanPacket.packet(for: .light, at: date(8, 34, 55), calendar: calendar)
        XCTAssertEqual(hex(packet), "e4cd178a5d8d39d8604160e5ac0335f0cd011dbe")
    }

    /// Captured at 10:07:11 (trace-3). The light command is a toggle, so this
    /// "light off" packet is the same command as the 08:36:09 template.
    func testRetimedPacketMatchesCaptureInAnotherHour() {
        let packet = FanPacket.packet(for: .light, at: date(10, 7, 11), calendar: calendar)
        XCTAssertEqual(hex(packet), "741b0f26cd5b2174f2b244493cd52d5c5dd70512")
    }

    /// Hello packets captured at 10:06:57 (trace-3) and 10:11:22 (trace-4).
    func testRetimedHelloMatchesCaptures() {
        XCTAssertEqual(hex(FanPacket.helloPacket(at: date(10, 6, 57), calendar: calendar)),
                       "44d429faf881e243c158926e0301f07b6203d835")
        XCTAssertEqual(hex(FanPacket.helloPacket(at: date(10, 11, 22), calendar: calendar)),
                       "e088d9585cdd12e1682b62cca75d00d9c65f2897")
    }
}
