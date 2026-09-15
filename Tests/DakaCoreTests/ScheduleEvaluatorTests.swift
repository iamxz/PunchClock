import XCTest
@testable import DakaCore

final class ScheduleEvaluatorTests: XCTestCase {
    private let evaluator = ScheduleEvaluator()
    private let cal = TestTime.calendar

    private func reminders(_ date: Date,
                           settings: Settings = .default,
                           record: DayRecord = DayRecord()) -> [PunchTask] {
        evaluator.pendingReminders(now: date, settings: settings, record: record, calendar: cal)
    }

    func testBeforeMorningWindowHasNoReminders() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 8, 59)), [])
    }

    func testAtMorningWindowStartIsPending() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 9, 0)), [.morning])
    }

    func testWithinMorningWindowIsPending() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 9, 29)), [.morning])
    }

    func testAfterMorningDeadlineStillPending() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 9, 31)), [.morning])
    }

    func testBeforeEveningWindowMorningOnly() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 17, 59)), [.morning])
    }

    func testAtEveningWindowStartBothPending() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 18, 0)), [.morning, .evening])
    }

    func testMorningDoneOnlyEveningPending() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)])
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 18, 10), record: record), [.evening])
    }

    func testBothDoneNoReminders() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 18, 30)])
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 23, 0), record: record), [])
    }

    func testEveningUnderMinimumKeepsReminding() {
        var settings = Settings.default
        settings.minWorkDurationHours = 8
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 16, 0)])
        let now = TestTime.date(2026, 9, 14, 18, 30)
        XCTAssertEqual(reminders(now, settings: settings, record: record), [.evening])
    }

    func testEveningAboveMinimumClears() {
        var settings = Settings.default
        settings.minWorkDurationHours = 8
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 18, 0)])
        let now = TestTime.date(2026, 9, 14, 18, 30)
        XCTAssertEqual(reminders(now, settings: settings, record: record), [])
    }

    func testWeekendNoReminders() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 19, 10, 0)), [])
    }

    func testDisabledNoReminders() {
        var settings = Settings.default
        settings.enabled = false
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 10, 0), settings: settings), [])
    }

    func testSkippedNoReminders() {
        let record = DayRecord(skipped: true)
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 10, 0), record: record), [])
    }

    func testInvalidMorningTimesYieldNoMorningReminder() {
        var settings = Settings.default
        settings.morningWindowStart = "oops"
        settings.morningDeadline = "oops"
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 10, 0), settings: settings), [])
    }

    func testInvalidStartYieldsNoReminder() {
        var settings = Settings.default
        settings.morningWindowStart = "oops"
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 10, 0), settings: settings), [])
    }
}
