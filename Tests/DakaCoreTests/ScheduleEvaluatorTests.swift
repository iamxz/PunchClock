import XCTest
@testable import DakaCore

final class ScheduleEvaluatorTests: XCTestCase {
    private let evaluator = ScheduleEvaluator()
    private let cal = TestTime.calendar

    private func reminders(_ date: Date,
                           settings: Settings = .default,
                           record: DayRecord = DayRecord()) -> [PendingReminder] {
        evaluator.pendingReminders(now: date, settings: settings, record: record, calendar: cal)
    }

    func testBeforeMorningWindowHasNoReminders() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 8, 59)), [])
    }

    func testAtMorningWindowStartIsGentle() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 9, 0)),
                       [PendingReminder(task: .morning, level: .gentle)])
    }

    func testWithinMorningWindowIsGentle() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 9, 29)),
                       [PendingReminder(task: .morning, level: .gentle)])
    }

    func testAtMorningDeadlineIsHard() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 9, 30)),
                       [PendingReminder(task: .morning, level: .hard)])
    }

    func testAfterMorningDeadlineIsHard() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 9, 31)),
                       [PendingReminder(task: .morning, level: .hard)])
    }

    func testBeforeEveningWindowMorningHardEveningSilent() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 17, 59)),
                       [PendingReminder(task: .morning, level: .hard)])
    }

    func testAtEveningWindowStartMorningHardEveningGentle() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 18, 0)),
                       [PendingReminder(task: .morning, level: .hard),
                        PendingReminder(task: .evening, level: .gentle)])
    }

    func testAtEveningDeadlineBothHard() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 18, 30)),
                       [PendingReminder(task: .morning, level: .hard),
                        PendingReminder(task: .evening, level: .hard)])
    }

    func testMorningDoneOnlyEveningGentle() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)])
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 18, 10), record: record),
                       [PendingReminder(task: .evening, level: .gentle)])
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
        XCTAssertEqual(reminders(now, settings: settings, record: record),
                       [PendingReminder(task: .evening, level: .hard)])
    }

    func testEveningAtMinimumClears() {
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
        // 10:00: morning unparseable -> none; evening window not reached yet -> none
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 10, 0), settings: settings), [])
    }

    func testInvalidStartWithValidDeadlineStillHardAfterDeadline() {
        var settings = Settings.default
        settings.morningWindowStart = "oops"
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 10, 0), settings: settings),
                       [PendingReminder(task: .morning, level: .hard)])
    }
}
