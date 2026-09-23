import XCTest
@testable import DakaCore

final class ScheduleEvaluatorTests: XCTestCase {
    private let evaluator = ScheduleEvaluator()
    private let cal = TestTime.calendar

    private func reminders(_ date: Date,
                           settings: Settings = .default,
                           record: DayRecord = DayRecord(),
                           leaves: [LeaveRecord] = []) -> [PunchTask] {
        evaluator.pendingReminders(now: date, settings: settings, record: record,
                                   leaves: leaves, calendar: cal)
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

    func testFullDayLeaveNoReminders() {
        let leaves = [TestTime.fullDayLeave(on: TestTime.monday)]
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 10, 0), leaves: leaves), [])
    }

    // MARK: - 请假期间的提醒抑制

    /// 上午请假 09:00–11:00：这段时间不唠叨，11:00 一结束就照常催上班卡。
    func testMorningLeaveSilencesRemindersUntilItEnds() {
        let leaves = [TestTime.leave(on: TestTime.monday, from: (9, 0), to: (11, 0))]
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 9, 0), leaves: leaves), [])
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 10, 59), leaves: leaves), [])
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 11, 0), leaves: leaves), [.morning])
    }

    /// 下午请假 16:00–18:00：请假期间不打扰，结束后仍催那张下班卡。
    func testAfternoonLeaveSilencesEveningReminderOnlyWhileOnLeave() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)])
        let leaves = [TestTime.leave(on: TestTime.monday, from: (16, 0), to: (18, 0))]
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 16, 0), record: record, leaves: leaves), [])
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 17, 59), record: record, leaves: leaves), [])
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 18, 0), record: record, leaves: leaves), [.evening])
    }

    /// 上午请假后 11:05 才上班：下班线顺延到 18:05，那时照常提醒。
    func testMorningLeaveStillRemindsAtShortenedLeaveTime() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 11, 5)])
        let leaves = [TestTime.leave(on: TestTime.monday, from: (9, 0), to: (11, 0))]
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 18, 4), record: record, leaves: leaves), [])
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 18, 5), record: record, leaves: leaves), [.evening])
    }

    /// 未来的请假不影响今天。
    func testFutureLeaveDoesNotAffectToday() {
        let leaves = [TestTime.fullDayLeave(on: TestTime.date(2026, 9, 20))]
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 10, 0), leaves: leaves), [.morning])
    }

    func testInvalidMorningTimeYieldsNoMorningReminder() {
        var settings = Settings.default
        settings.workStartTime = "oops"
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 10, 0), settings: settings), [])
    }
}
