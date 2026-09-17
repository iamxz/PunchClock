import XCTest
@testable import DakaCore

final class PunchTargetTests: XCTestCase {
    private let cal = TestTime.calendar

    func testMorningNotDoneTargetsMorning() {
        let record = DayRecord()
        let now = TestTime.date(2026, 9, 16, 9, 0)
        XCTAssertEqual(PunchTarget.resolve(record: record, now: now, settings: .default, calendar: cal), .morning)
    }

    func testMorningDoneTargetsEvening() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 16, 9, 0)])
        let now = TestTime.date(2026, 9, 16, 9, 5)
        XCTAssertEqual(PunchTarget.resolve(record: record, now: now, settings: .default, calendar: cal), .evening)
    }

    func testBothDoneBeforeNoonTargetsMorning() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 16, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 16, 18, 0)])
        let now = TestTime.date(2026, 9, 16, 9, 30)
        XCTAssertEqual(PunchTarget.resolve(record: record, now: now, settings: .default, calendar: cal), .morning)
    }

    func testBothDoneAtNoonTargetsEvening() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 16, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 16, 18, 0)])
        let now = TestTime.date(2026, 9, 16, 12, 0)
        XCTAssertEqual(PunchTarget.resolve(record: record, now: now, settings: .default, calendar: cal), .evening)
    }

    func testBothDoneAfternoonTargetsEvening() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 16, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 16, 18, 0)])
        let now = TestTime.date(2026, 9, 16, 18, 5)
        XCTAssertEqual(PunchTarget.resolve(record: record, now: now, settings: .default, calendar: cal), .evening)
    }

    func testEveningPunchUnderMinimumStillTargetsEvening() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 16, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 16, 15, 0)])
        let now = TestTime.date(2026, 9, 16, 18, 10)
        XCTAssertEqual(PunchTarget.resolve(record: record, now: now, settings: .default, calendar: cal), .evening)
    }
}
