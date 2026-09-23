import XCTest
@testable import DakaCore

final class PunchTargetTests: XCTestCase {
    private let cal = TestTime.calendar

    private func target(_ record: DayRecord, _ now: Date, leaves: [LeaveRecord] = []) -> PunchTask {
        PunchTarget.resolve(record: record, now: now, settings: .default, leaves: leaves, calendar: cal)
    }

    func testMorningNotDoneTargetsMorning() {
        let record = DayRecord()
        let now = TestTime.date(2026, 9, 16, 9, 0)
        XCTAssertEqual(target(record, now), .morning)
    }

    func testMorningDoneTargetsEvening() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 16, 9, 0)])
        let now = TestTime.date(2026, 9, 16, 9, 5)
        XCTAssertEqual(target(record, now), .evening)
    }

    func testBothDoneBeforeNoonTargetsMorning() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 16, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 16, 18, 0)])
        let now = TestTime.date(2026, 9, 16, 9, 30)
        XCTAssertEqual(target(record, now), .morning)
    }

    func testBothDoneAtNoonTargetsEvening() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 16, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 16, 18, 0)])
        let now = TestTime.date(2026, 9, 16, 12, 0)
        XCTAssertEqual(target(record, now), .evening)
    }

    func testBothDoneAfternoonTargetsEvening() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 16, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 16, 18, 0)])
        let now = TestTime.date(2026, 9, 16, 18, 5)
        XCTAssertEqual(target(record, now), .evening)
    }

    func testEveningPunchUnderMinimumStillTargetsEvening() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 16, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 16, 15, 0)])
        let now = TestTime.date(2026, 9, 16, 18, 10)
        XCTAssertEqual(target(record, now), .evening)
    }

    /// 请假把应工作时长缩短后，那张早退的下班卡就合格了，目标项回到「按时间补打」。
    func testLeaveMakesEarlyEveningPunchComplete() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 16, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 16, 15, 0)])
        let now = TestTime.date(2026, 9, 16, 18, 10)
        let leaves = [TestTime.leave(on: TestTime.date(2026, 9, 16), from: (15, 0), to: (18, 0))]
        XCTAssertEqual(target(record, now, leaves: leaves), .evening, "18:00 之后仍以下班卡为补打目标")
    }
}
