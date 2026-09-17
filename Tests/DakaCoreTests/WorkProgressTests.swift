import XCTest
@testable import DakaCore

final class WorkProgressTests: XCTestCase {
    func testNoMorningPunchHasNoElapsedAndZeroFraction() {
        let record = DayRecord(eveningPunches: [TestTime.date(2026, 9, 14, 18, 0)])
        let now = TestTime.date(2026, 9, 14, 18, 0)
        XCTAssertNil(WorkProgress.elapsed(record, now: now, settings: .default))
        XCTAssertEqual(WorkProgress.fraction(record, now: now, settings: .default), 0)
    }

    func testFourOfEightHoursIsHalf() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)])
        let now = TestTime.date(2026, 9, 14, 13, 0)
        XCTAssertEqual(WorkProgress.elapsed(record, now: now, settings: .default),
                       4 * 3600)
        XCTAssertEqual(WorkProgress.fraction(record, now: now, settings: .default), 4.0 / 9.0, accuracy: 0.01)
    }

    func testOvertimeIsCappedAtOne() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)])
        let now = TestTime.date(2026, 9, 14, 19, 0)
        XCTAssertEqual(WorkProgress.fraction(record, now: now, settings: .default), 1)
    }

    func testCompletionUsesQualifyingEveningPunch() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 18, 0)])
        let now = TestTime.date(2026, 9, 14, 20, 0)
        XCTAssertEqual(WorkProgress.elapsed(record, now: now, settings: .default),
                       9 * 3600)
        XCTAssertEqual(WorkProgress.fraction(record, now: now, settings: .default), 1)
    }

    func testIgnoresNonQualifyingEveningPunch() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 16, 0),
                                                TestTime.date(2026, 9, 14, 18, 0)])
        let now = TestTime.date(2026, 9, 14, 21, 0)
        XCTAssertEqual(WorkProgress.elapsed(record, now: now, settings: .default),
                       9 * 3600)
    }

    func testCompletionUsesLatestOfTwoQualifyingPunches() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 17, 0),
                                                TestTime.date(2026, 9, 14, 18, 0)])
        let now = TestTime.date(2026, 9, 14, 21, 0)
        XCTAssertEqual(WorkProgress.elapsed(record, now: now, settings: .default),
                       9 * 3600)
        XCTAssertEqual(WorkProgress.fraction(record, now: now, settings: .default), 1)
    }

    func testExactlyMinimumIsComplete() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 18, 0)])
        let now = TestTime.date(2026, 9, 14, 18, 0)
        XCTAssertEqual(WorkProgress.elapsed(record, now: now, settings: .default),
                       9 * 3600)
        XCTAssertEqual(WorkProgress.fraction(record, now: now, settings: .default), 1)
    }

    func testZeroMinimumIsFull() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)])
        let now = TestTime.date(2026, 9, 14, 9, 30)
        var settings = Settings.default
        settings.workDurationHours = 0
        XCTAssertEqual(WorkProgress.fraction(record, now: now, settings: settings), 1)
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
