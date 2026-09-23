import XCTest
@testable import DakaCore

final class HealthRulesTests: XCTestCase {
    private let cal = TestTime.calendar

    private var schedule: Settings {
        Settings(enabled: true, workdays: [2, 3, 4, 5, 6],
                 workStartTime: "09:00", workDurationHours: 9, flexMinutes: 30)
    }

    private func status(now: Date,
                        record: DayHealthRecord = DayHealthRecord(),
                        health: HealthSettings = .default,
                        leaves: [LeaveRecord] = []) -> HealthStatus {
        HealthRules.status(health: health, schedule: schedule, record: record,
                           leaves: leaves, now: now, calendar: cal)
    }

    // 2026-09-14 为周一
    func testDueAfterIntervalWithinWorkWindow() {
        let s = status(now: TestTime.date(2026, 9, 14, 10, 30))
        XCTAssertTrue(s.active)
        XCTAssertTrue(s.waterDue)      // 09:00 起 90 分钟 >= 60
        XCTAssertTrue(s.movementDue)
        XCTAssertEqual(s.minutesSinceDrink, 90)
    }

    func testNotDueBeforeInterval() {
        let s = status(now: TestTime.date(2026, 9, 14, 9, 30))
        XCTAssertTrue(s.active)
        XCTAssertFalse(s.waterDue)     // 30 分钟 < 60
        XCTAssertFalse(s.movementDue)
    }

    func testDrinkingResetsTimer() {
        let record = DayHealthRecord(drinks: [TestTime.date(2026, 9, 14, 10, 15)])
        let s = status(now: TestTime.date(2026, 9, 14, 10, 30), record: record)
        XCTAssertEqual(s.cups, 1)
        XCTAssertEqual(s.minutesSinceDrink, 15)
        XCTAssertFalse(s.waterDue)
    }

    func testOutsideWindowInactive() {
        let s = status(now: TestTime.date(2026, 9, 14, 8, 0))
        XCTAssertFalse(s.active)
        XCTAssertFalse(s.waterDue)
        XCTAssertFalse(s.movementDue)
    }

    func testWeekendInactive() {
        let s = status(now: TestTime.date(2026, 9, 19, 10, 30)) // 周六
        XCTAssertFalse(s.active)
        XCTAssertFalse(s.waterDue)
    }

    func testFullDayLeaveInactive() {
        let s = status(now: TestTime.date(2026, 9, 14, 10, 30),
                       leaves: [TestTime.fullDayLeave(on: TestTime.monday)])
        XCTAssertFalse(s.active)
        XCTAssertFalse(s.waterDue)
    }

    /// 半天假：请假的这段时间安静，工作时段照常。
    func testMorningLeaveOnlySilencesItsOwnWindow() {
        let leaves = [TestTime.leave(on: TestTime.monday, from: (9, 0), to: (11, 0))]
        XCTAssertFalse(status(now: TestTime.date(2026, 9, 14, 10, 30), leaves: leaves).active)
        XCTAssertTrue(status(now: TestTime.date(2026, 9, 14, 11, 0), leaves: leaves).active)
    }

    /// 已知取舍：喝水基线仍锚在上班时刻，上午请假一结束就会立刻提示补喝水。
    func testMorningLeaveResumesWithImmediateReminder() {
        let leaves = [TestTime.leave(on: TestTime.monday, from: (9, 0), to: (11, 0))]
        let s = status(now: TestTime.date(2026, 9, 14, 11, 0), leaves: leaves)
        XCTAssertTrue(s.active)
        XCTAssertEqual(s.minutesSinceDrink, 120)
        XCTAssertTrue(s.waterDue)
    }

    /// 下午请假：16:00 起安静，18:00 恢复。
    func testAfternoonLeaveSilencesOnlyAfternoon() {
        let leaves = [TestTime.leave(on: TestTime.monday, from: (16, 0), to: (18, 0))]
        XCTAssertTrue(status(now: TestTime.date(2026, 9, 14, 15, 30), leaves: leaves).active)
        XCTAssertFalse(status(now: TestTime.date(2026, 9, 14, 17, 0), leaves: leaves).active)
        XCTAssertTrue(status(now: TestTime.date(2026, 9, 14, 18, 0), leaves: leaves).active)
    }

    func testDisabledToolDoesNotRemind() {
        var health = HealthSettings.default
        health.waterEnabled = false
        let s = status(now: TestTime.date(2026, 9, 14, 10, 30), health: health)
        XCTAssertFalse(s.waterDue)
        XCTAssertTrue(s.movementDue)
    }

    func testCustomInterval() {
        var health = HealthSettings.default
        health.waterIntervalMinutes = 30
        let s = status(now: TestTime.date(2026, 9, 14, 9, 30), health: health)
        XCTAssertTrue(s.waterDue)      // 30 分钟 >= 30
    }

    func testEffectiveIntervalFloor() {
        var health = HealthSettings.default
        health.waterIntervalMinutes = 1
        XCTAssertEqual(health.effectiveWaterIntervalMinutes, 15)
    }

    func testInvalidTimesInactive() {
        var s = schedule
        s.workStartTime = "oops"
        let result = HealthRules.status(health: .default, schedule: s,
                                        record: DayHealthRecord(), leaves: [],
                                        now: TestTime.date(2026, 9, 14, 10, 30), calendar: cal)
        XCTAssertFalse(result.active)
        XCTAssertFalse(result.waterDue)
        XCTAssertFalse(result.movementDue)
    }
}
