import XCTest
@testable import DakaCore

final class PunchFeedbackTests: XCTestCase {
    private let cal = TestTime.calendar

    private func text(_ task: PunchTask,
                      record: DayRecord,
                      punchedAt: Date,
                      minHours: Double = 8) -> String? {
        var settings = Settings.default
        settings.minWorkDurationHours = minHours
        return PunchFeedback.text(task: task, record: record, settings: settings,
                                  punchedAt: punchedAt, calendar: cal)
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
        settings.minWorkDurationHours = 8
        let morning = utc.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 1, minute: 0))!
        let evening = utc.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 8, minute: 0))!
        let record = DayRecord(morningPunches: [morning], eveningPunches: [evening])

        let message = PunchFeedback.text(task: .evening, record: record, settings: settings,
                                         punchedAt: evening, calendar: utc)
        XCTAssertTrue(message?.contains("08:00") ?? false, message ?? "nil")
    }

    func testRemainingUnderOneMinute() {
        let morning = TestTime.date(2026, 9, 14, 9, 0)
        let evening = TestTime.date(2026, 9, 14, 16, 59, 30)
        let record = DayRecord(morningPunches: [morning], eveningPunches: [evening])
        let message = text(.evening, record: record, punchedAt: evening)
        XCTAssertTrue(message?.contains("不足 1 分钟") ?? false, message ?? "nil")
    }
}
