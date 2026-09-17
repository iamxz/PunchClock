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

    func testBeforeMorningWindowNoReminders() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 8, 59)), [])
    }

    func testAtMorningWindowStartPending() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 9, 0)), [.morning])
    }

    func testWithinMorningWindowPending() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 9, 29)), [.morning])
    }

    func testAfterWindowStartStillPending() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 9, 31)), [.morning])
    }

    func testNoMorningNoEveningEvenAtNight() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 20, 0)), [.morning])
    }

    func testMorningDoneBeforeLeaveNoEvening() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)])
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 17, 59), record: record), [])
    }

    func testMorningDoneAtLeaveEveningPending() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)])
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 18, 0), record: record), [.evening])
    }

    func testLatePunchPushesEveningLeave() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 16)])
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 18, 15), record: record), [])
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 18, 16), record: record), [.evening])
    }

    func testEarlyEveningPunchStillPending() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 17, 30)])
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 18, 10), record: record), [.evening])
    }

    func testBothDoneNoReminders() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 18, 0)])
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 23, 0), record: record), [])
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

    func testInvalidMorningTimeYieldsNoMorningReminder() {
        var settings = Settings.default
        settings.workStartTime = "oops"
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 10, 0), settings: settings), [])
    }
}
