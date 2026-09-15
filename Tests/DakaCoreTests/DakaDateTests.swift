import XCTest
@testable import DakaCore

final class DakaDateTests: XCTestCase {
    private let cal = TestTime.calendar

    func testKeyFormatsZeroPadded() {
        XCTAssertEqual(DakaDate.key(for: TestTime.date(2026, 9, 4), calendar: cal), "2026-09-04")
    }

    func testTimeComponentsValid() {
        XCTAssertEqual(DakaDate.timeComponents("09:30")?.hour, 9)
        XCTAssertEqual(DakaDate.timeComponents("09:30")?.minute, 30)
    }

    func testTimeComponentsRejectsInvalid() {
        XCTAssertNil(DakaDate.timeComponents(""))
        XCTAssertNil(DakaDate.timeComponents("9:00:00"))
        XCTAssertNil(DakaDate.timeComponents("24:00"))
        XCTAssertNil(DakaDate.timeComponents("12:60"))
        XCTAssertNil(DakaDate.timeComponents("ab:cd"))
    }

    func testDateOnBuildsTime() {
        let d = DakaDate.date(on: TestTime.date(2026, 9, 14, 15, 0), at: "09:30", calendar: cal)
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: d!)
        XCTAssertEqual([c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0],
                       [2026, 9, 14, 9, 30])
    }

    func testDateOnInvalidTimeReturnsNil() {
        XCTAssertNil(DakaDate.date(on: TestTime.monday, at: "25:00", calendar: cal))
    }

    func testWeekday() {
        XCTAssertEqual(DakaDate.weekday(of: TestTime.monday, calendar: cal), 2)
        XCTAssertEqual(DakaDate.weekday(of: TestTime.saturday, calendar: cal), 7)
    }
}
