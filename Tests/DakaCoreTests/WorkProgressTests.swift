import XCTest
@testable import DakaCore

final class WorkProgressTests: XCTestCase {
    func testNoMorningPunchHasNoElapsedAndZeroFraction() {
        let record = DayRecord(eveningPunches: [TestTime.date(2026, 9, 14, 18, 0)])
        let now = TestTime.date(2026, 9, 14, 18, 0)
        XCTAssertNil(WorkProgress.elapsed(record, now: now, settings: .default, leaves: []))
        XCTAssertEqual(WorkProgress.fraction(record, now: now, settings: .default, leaves: []), 0)
    }

    func testFourOfEightHoursIsHalf() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)])
        let now = TestTime.date(2026, 9, 14, 13, 0)
        XCTAssertEqual(WorkProgress.elapsed(record, now: now, settings: .default, leaves: []),
                       4 * 3600)
        XCTAssertEqual(WorkProgress.fraction(record, now: now, settings: .default, leaves: []), 4.0 / 9.0, accuracy: 0.01)
    }

    func testOvertimeIsCappedAtOne() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)])
        let now = TestTime.date(2026, 9, 14, 19, 0)
        XCTAssertEqual(WorkProgress.fraction(record, now: now, settings: .default, leaves: []), 1)
    }

    func testCompletionUsesQualifyingEveningPunch() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 18, 0)])
        let now = TestTime.date(2026, 9, 14, 20, 0)
        XCTAssertEqual(WorkProgress.elapsed(record, now: now, settings: .default, leaves: []),
                       9 * 3600)
        XCTAssertEqual(WorkProgress.fraction(record, now: now, settings: .default, leaves: []), 1)
    }

    func testIgnoresNonQualifyingEveningPunch() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 16, 0),
                                                TestTime.date(2026, 9, 14, 18, 0)])
        let now = TestTime.date(2026, 9, 14, 21, 0)
        XCTAssertEqual(WorkProgress.elapsed(record, now: now, settings: .default, leaves: []),
                       9 * 3600)
    }

    func testCompletionUsesLatestOfTwoQualifyingPunches() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 17, 0),
                                                TestTime.date(2026, 9, 14, 18, 0)])
        let now = TestTime.date(2026, 9, 14, 21, 0)
        XCTAssertEqual(WorkProgress.elapsed(record, now: now, settings: .default, leaves: []),
                       9 * 3600)
        XCTAssertEqual(WorkProgress.fraction(record, now: now, settings: .default, leaves: []), 1)
    }

    func testExactlyMinimumIsComplete() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 18, 0)])
        let now = TestTime.date(2026, 9, 14, 18, 0)
        XCTAssertEqual(WorkProgress.elapsed(record, now: now, settings: .default, leaves: []),
                       9 * 3600)
        XCTAssertEqual(WorkProgress.fraction(record, now: now, settings: .default, leaves: []), 1)
    }

    func testZeroMinimumIsFull() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)])
        let now = TestTime.date(2026, 9, 14, 9, 30)
        var settings = Settings.default
        settings.workDurationHours = 0
        XCTAssertEqual(WorkProgress.fraction(record, now: now, settings: settings, leaves: []), 1)
    }

    /// 中间请 1 小时假：进度里的已工作时长要把这一小时扣掉。
    func testLeaveInTheMiddleIsNotCountedAsWorked() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)])
        let now = TestTime.date(2026, 9, 14, 13, 0)
        let leaves = [TestTime.leave(on: TestTime.monday, from: (10, 0), to: (11, 0))]
        XCTAssertEqual(WorkProgress.elapsed(record, now: now, settings: .default,
                                            leaves: leaves, calendar: TestTime.calendar),
                       3 * 3600)
        XCTAssertEqual(WorkProgress.fraction(record, now: now, settings: .default,
                                             leaves: leaves, calendar: TestTime.calendar),
                       3.0 / 8.0, accuracy: 0.001)
    }

    /// 下午请假把应上班窗口缩短到 16:00，那时进度就该满格。
    func testAfternoonLeaveMakesShortDayComplete() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 16, 0)])
        let now = TestTime.date(2026, 9, 14, 16, 0)
        let leaves = [TestTime.leave(on: TestTime.monday, from: (16, 0), to: (18, 0))]
        XCTAssertEqual(WorkProgress.elapsed(record, now: now, settings: .default,
                                            leaves: leaves, calendar: TestTime.calendar),
                       7 * 3600)
        XCTAssertEqual(WorkProgress.fraction(record, now: now, settings: .default,
                                             leaves: leaves, calendar: TestTime.calendar), 1)
    }

    /// 整天请假还没打卡时进度是 0（没什么可推进的），误打一张卡后直接满格。
    func testFullDayLeaveProgress() {
        let now = TestTime.date(2026, 9, 14, 13, 0)
        let leaves = [TestTime.fullDayLeave(on: TestTime.monday)]
        XCTAssertEqual(WorkProgress.fraction(DayRecord(), now: now, settings: .default,
                                             leaves: leaves, calendar: TestTime.calendar), 0)
        let punched = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)])
        XCTAssertEqual(WorkProgress.fraction(punched, now: now, settings: .default,
                                             leaves: leaves, calendar: TestTime.calendar), 1)
    }

    func testHoursTextUnderOneHourShowsMinutes() {
        XCTAssertEqual(WorkProgress.hoursText(45 * 60), "45m")
    }

    func testHoursTextWholeHours() {
        XCTAssertEqual(WorkProgress.hoursText(4 * 3600), "4h")
    }

    func testHoursTextHalfHour() {
        XCTAssertEqual(WorkProgress.hoursText(4.5 * 3600), "4.5h")
    }

    func testHoursTextNegativeIsZero() {
        XCTAssertEqual(WorkProgress.hoursText(-60), "0m")
    }
}
