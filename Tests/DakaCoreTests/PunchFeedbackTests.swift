import XCTest
@testable import DakaCore

final class PunchFeedbackTests: XCTestCase {
    private let cal = TestTime.calendar

    private func text(_ task: PunchTask,
                      record: DayRecord,
                      punchedAt: Date,
                      leaves: [LeaveRecord] = [],
                      minHours: Double = 8) -> String? {
        var settings = Settings.default
        settings.workDurationHours = minHours
        return PunchFeedback.text(task: task, record: record, settings: settings,
                                  leaves: leaves, punchedAt: punchedAt, calendar: cal)
    }

    func testMorningAlwaysNil() {
        let day = TestTime.date(2026, 9, 14, 9, 0)
        let record = DayRecord(morningPunches: [day])
        XCTAssertNil(text(.morning, record: record, punchedAt: day))
    }

    func testCompletedEveningReturnsNil() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 18, 0)])
        XCTAssertNil(text(.evening, record: record, punchedAt: TestTime.date(2026, 9, 14, 18, 0)))
    }

    func testEveningUnderMinimumExplainsRemaining() {
        let morning = TestTime.date(2026, 9, 14, 9, 0)
        let evening = TestTime.date(2026, 9, 14, 16, 0)
        let record = DayRecord(morningPunches: [morning], eveningPunches: [evening])
        let message = text(.evening, record: record, punchedAt: evening)
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("还差 1 小时") ?? false, message ?? "nil")
        XCTAssertTrue(message?.contains("16:00") ?? false, message ?? "nil")
    }

    func testEveningWithoutMorningAsksForMorningPunch() {
        let evening = TestTime.date(2026, 9, 14, 16, 0)
        let record = DayRecord(eveningPunches: [evening])
        let message = text(.evening, record: record, punchedAt: evening)
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("还没有上班打卡") ?? false, message ?? "nil")
    }

    func testUsesInjectedCalendarTimeZone() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

        var settings = Settings.default
        settings.workDurationHours = 8
        let morning = utc.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 1, minute: 0))!
        let evening = utc.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 8, minute: 0))!
        let record = DayRecord(morningPunches: [morning], eveningPunches: [evening])

        let message = PunchFeedback.text(task: .evening, record: record, settings: settings,
                                         leaves: [], punchedAt: evening, calendar: utc)
        XCTAssertTrue(message?.contains("08:00") ?? false, message ?? "nil")
    }

    /// 请假抵扣后：文案要说清「请了几小时、还需满几小时」。
    func testLeaveShortensRequiredHoursInMessage() {
        let morning = TestTime.date(2026, 9, 14, 9, 0)
        let evening = TestTime.date(2026, 9, 14, 15, 0)
        let record = DayRecord(morningPunches: [morning], eveningPunches: [evening])
        let leaves = [TestTime.leave(on: TestTime.monday, from: (16, 0), to: (18, 0))]
        let message = text(.evening, record: record, punchedAt: evening,
                           leaves: leaves, minHours: 9)
        XCTAssertTrue(message?.contains("今天请假 2 小时") ?? false, message ?? "nil")
        XCTAssertTrue(message?.contains("满 7 小时") ?? false, message ?? "nil")
        XCTAssertTrue(message?.contains("还差 1 小时") ?? false, message ?? "nil")
    }

    /// 整天请假还顺手打了张卡：告诉他不用打了，而不是催他凑时长。
    /// 有上班卡时 15:00 已满足「应工作 0 小时」，判定直接完成、无提示；
    /// 只有缺一头卡才会走到这句话。
    func testEveningOnFullDayLeaveSaysNoPunchNeeded() {
        let evening = TestTime.date(2026, 9, 14, 15, 0)
        let record = DayRecord(eveningPunches: [evening])
        let leaves = [TestTime.fullDayLeave(on: TestTime.monday)]
        let message = text(.evening, record: record, punchedAt: evening, leaves: leaves)
        XCTAssertEqual(message, "已记录 15:00；今天已整天请假，无需打卡。")
    }

    /// 整天请假与打卡并存 = 已满足，不再啰嗦。
    func testFullDayLeaveWithBothPunchesReturnsNil() {
        let evening = TestTime.date(2026, 9, 14, 15, 0)
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [evening])
        let leaves = [TestTime.fullDayLeave(on: TestTime.monday)]
        XCTAssertNil(text(.evening, record: record, punchedAt: evening, leaves: leaves))
    }

    func testRemainingUnderOneMinute() {
        let morning = TestTime.date(2026, 9, 14, 9, 0)
        let evening = TestTime.date(2026, 9, 14, 16, 59, 30)
        let record = DayRecord(morningPunches: [morning], eveningPunches: [evening])
        let message = text(.evening, record: record, punchedAt: evening)
        XCTAssertTrue(message?.contains("不足 1 分钟") ?? false, message ?? "nil")
    }
}
