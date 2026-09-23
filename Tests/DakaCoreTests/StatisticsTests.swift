import XCTest
@testable import DakaCore

final class StatisticsTests: XCTestCase {
    private let cal = TestTime.calendar
    private var now: Date { TestTime.date(2026, 9, 16, 10, 0) } // 周三

    private func records(_ items: [(Date, Bool, Bool, Date?, Date?)]) -> [String: DayRecord] {
        var result: [String: DayRecord] = [:]
        for (day, morning, evening, mat, eat) in items {
            let key = DakaDate.key(for: day, calendar: cal)
            var r = DayRecord()
            let defaultMorning = DakaDate.date(on: day, at: "09:00", calendar: cal) ?? day
            let defaultEvening = DakaDate.date(on: day, at: "18:00", calendar: cal) ?? day
            r.morningPunches = morning ? [mat ?? defaultMorning] : []
            r.eveningPunches = evening ? [eat ?? defaultEvening] : []
            result[key] = r
        }
        return result
    }

    private func compute(_ recs: [String: DayRecord],
                         leaves: [LeaveRecord] = [],
                         now: Date? = nil,
                         rangeDays: Int = 7) -> StatisticsSummary {
        Statistics.compute(records: recs, settings: .default, leaves: leaves,
                           now: now ?? self.now, rangeDays: rangeDays, calendar: cal)
    }

    private func stat(_ summary: StatisticsSummary, _ key: String) -> DailyStat? {
        summary.days.first { $0.dateKey == key }
    }

    func testRangeLengthAndAscendingOrder() {
        let s = compute([:])
        XCTAssertEqual(s.days.count, 7)
        XCTAssertEqual(s.days.first?.dateKey, "2026-09-10")
        XCTAssertEqual(s.days.last?.dateKey, "2026-09-16")
    }

    func testWorkDurationAndAverage() {
        let recs = records([
            (TestTime.date(2026, 9, 14), true, true, TestTime.date(2026, 9, 14, 9, 0), TestTime.date(2026, 9, 14, 18, 10)),
            (TestTime.date(2026, 9, 15), true, true, TestTime.date(2026, 9, 15, 9, 5), TestTime.date(2026, 9, 15, 18, 10))
        ])
        let s = compute(recs)
        XCTAssertEqual(stat(s, "2026-09-14")?.workDuration, 33000)
        XCTAssertEqual(stat(s, "2026-09-15")?.workDuration, 32700)
        XCTAssertEqual(s.averageWorkDuration ?? 0, 32850, accuracy: 0.5)
    }

    func testEveningUnderMinimumDoesNotComplete() {
        let recs = records([
            (TestTime.date(2026, 9, 15), true, true,
             TestTime.date(2026, 9, 15, 9, 0), TestTime.date(2026, 9, 15, 16, 0))
        ])
        let s = compute(recs)
        XCTAssertEqual(stat(s, "2026-09-15")?.completedBoth, false)
        XCTAssertNil(stat(s, "2026-09-15")?.workDuration)
    }

    func testEveningBeforeMorningYieldsNilDuration() {
        let recs = records([
            (TestTime.date(2026, 9, 14), true, true, TestTime.date(2026, 9, 14, 18, 0), TestTime.date(2026, 9, 14, 9, 0))
        ])
        let s = compute(recs, rangeDays: 3)
        XCTAssertNil(stat(s, "2026-09-14")?.workDuration)
        XCTAssertNil(s.averageWorkDuration)
    }

    func testWeekendNeverMissed() {
        let s = compute([:])
        XCTAssertEqual(s.missedDays, 4)
        XCTAssertEqual(stat(s, "2026-09-12")?.isWorkday, false)
    }

    func testFullDayLeaveNotMissedAndKeepsStreak() {
        let recs = records([
            (TestTime.date(2026, 9, 14), true, true, TestTime.date(2026, 9, 14, 9, 0), TestTime.date(2026, 9, 14, 18, 0))
        ])
        let leaves = [TestTime.fullDayLeave(on: TestTime.date(2026, 9, 15))]
        let s = compute(recs, leaves: leaves)
        XCTAssertEqual(stat(s, "2026-09-15")?.onLeave, true)
        XCTAssertEqual(s.missedDays, 2)
        XCTAssertEqual(s.currentStreak, 1)
    }

    /// 半天假却一次卡都没打：还欠着工时，算缺卡（这是本次改动对用户可见的行为变化）。
    func testHalfDayLeaveWithoutPunchIsMissed() {
        let leaves = [TestTime.leave(on: TestTime.date(2026, 9, 15), from: (16, 0), to: (18, 0))]
        let s = compute([:], leaves: leaves)
        XCTAssertEqual(stat(s, "2026-09-15")?.onLeave, false)
        XCTAssertEqual(stat(s, "2026-09-15")?.leaveFraction ?? 0, 2.0 / 9.0, accuracy: 0.001)
        XCTAssertEqual(s.missedDays, 4, "半天假不减少缺卡天数")
    }

    func testStreakCountsConsecutiveWorkdays() {
        let recs = records([
            (TestTime.date(2026, 9, 14), true, true, nil, nil),
            (TestTime.date(2026, 9, 15), true, true, nil, nil)
        ])
        let s = compute(recs, rangeDays: 14)
        XCTAssertEqual(s.currentStreak, 2)
    }

    /// 连续打卡中间夹一天整天假：不断裂，且这天不算缺卡。
    func testStreakSurvivesFullDayLeaveInBetween() {
        let recs = records([
            (TestTime.date(2026, 9, 14), true, true, nil, nil),
            (TestTime.date(2026, 9, 16), true, true, nil, nil)
        ])
        let leaves = [TestTime.fullDayLeave(on: TestTime.date(2026, 9, 15))]
        let lateNow = TestTime.date(2026, 9, 16, 19, 0)
        let s = compute(recs, leaves: leaves, now: lateNow)
        XCTAssertEqual(s.currentStreak, 2)
    }

    func testTodayIncompleteAfterDeadlineBreaksStreakAndCountsMissed() {
        let lateNow = TestTime.date(2026, 9, 16, 19, 0)
        let recs = records([
            (TestTime.date(2026, 9, 15), true, true, nil, nil)
        ])
        let s = compute(recs, now: lateNow)
        XCTAssertEqual(s.currentStreak, 1)
        XCTAssertTrue(s.missedDays >= 1)
    }

    func testMonthPunchDays() {
        let recs = records([
            (TestTime.date(2026, 9, 14), true, true, nil, nil),
            (TestTime.date(2026, 9, 15), true, true, nil, nil),
            (TestTime.date(2026, 8, 31), true, true, nil, nil)
        ])
        let s = compute(recs, rangeDays: 30)
        XCTAssertEqual(s.monthPunchDays, 2)
    }

    func testMonthPunchIndependentOfRange() {
        let recs = records([
            (TestTime.date(2026, 9, 14), true, true, nil, nil),
            (TestTime.date(2026, 9, 15), true, true, nil, nil)
        ])
        // rangeDays 1 -> range only covers today, but the month count still sees 09-14/09-15
        let s = compute(recs, rangeDays: 1)
        XCTAssertEqual(s.monthPunchDays, 2)
        XCTAssertEqual(s.days.count, 1)
    }

    /// 半天假 + 缩短后的下班卡 = 正常考勤：计入月打卡、算在岗 7 小时。
    func testHalfDayLeaveWithQualifyingPunchCountsAsDone() {
        let recs = records([
            (TestTime.date(2026, 9, 14), true, true,
             TestTime.date(2026, 9, 14, 9, 0), TestTime.date(2026, 9, 14, 16, 0))
        ])
        let leaves = [TestTime.leave(on: TestTime.date(2026, 9, 14), from: (16, 0), to: (18, 0))]
        let s = compute(recs, leaves: leaves)
        XCTAssertEqual(stat(s, "2026-09-14")?.completedBoth, true)
        // 平均在岗时长统计的是「实际待了多久」，不因请假折算。
        XCTAssertEqual(s.averageWorkDuration ?? 0, 7 * 3600, accuracy: 1)
        XCTAssertEqual(s.monthPunchDays, 1)
    }

    // MARK: - 请假天数

    func testLeaveDaysSumsHalfAndFullDays() {
        let leaves = [
            TestTime.leave(on: TestTime.date(2026, 9, 14), from: (13, 30), to: (18, 0)),  // 半天 0.5
            TestTime.fullDayLeave(on: TestTime.date(2026, 9, 15)),                          // 1
            TestTime.fullDayLeave(on: TestTime.date(2026, 9, 19)),                          // 周六：0
        ]
        let days = Statistics.leaveDays(leaves: leaves, settings: .default, month: now, calendar: cal)
        XCTAssertEqual(days, 1.5, accuracy: 0.001)
    }

    func testLeaveDaysSkipsHolidaysAndCountsMakeupWorkday() {
        // 09-25 中秋（周五，法定假日）不计；09-20 国庆调休补班（周日）要计。
        let holiday = Statistics.leaveDays(leaves: [TestTime.fullDayLeave(on: TestTime.date(2026, 9, 25))],
                                            settings: .default, month: now, calendar: cal)
        XCTAssertEqual(holiday, 0, accuracy: 0.001)

        let makeup = Statistics.leaveDays(leaves: [TestTime.fullDayLeave(on: TestTime.date(2026, 9, 20))],
                                          settings: .default, month: now, calendar: cal)
        XCTAssertEqual(makeup, 1, accuracy: 0.001)
    }

    /// 未来已经排好的请假也算这个月的成本。
    func testLeaveDaysIncludesFutureDays() {
        let leaves = [TestTime.fullDayLeave(on: TestTime.date(2026, 9, 28))]  // 月末的下周一
        let days = Statistics.leaveDays(leaves: leaves, settings: .default, month: now, calendar: cal)
        XCTAssertEqual(days, 1, accuracy: 0.001)
    }

    /// 跨月的一次请假：两个月各折算各的那几天。
    func testLeaveDaysSplitsAcrossMonths() {
        let trip = [TestTime.leave(from: (TestTime.date(2026, 9, 30), 13, 30),
                                   to: (TestTime.date(2026, 10, 8), 13, 30))]
        let september = Statistics.leaveDays(leaves: trip, settings: .default,
                                             month: TestTime.date(2026, 9, 1), calendar: cal)
        let october = Statistics.leaveDays(leaves: trip, settings: .default,
                                           month: TestTime.date(2026, 10, 1), calendar: cal)
        XCTAssertEqual(september, 0.5, accuracy: 0.001)
        XCTAssertEqual(october, 0.5, accuracy: 0.001)
    }

    /// 摘要里的「本月请假」与独立函数同口径。
    func testSummaryCarriesMonthLeaveDays() {
        let leaves = [TestTime.leave(on: TestTime.date(2026, 9, 14), from: (13, 30), to: (18, 0))]
        let s = compute([:], leaves: leaves)
        XCTAssertEqual(s.monthLeaveDays, 0.5, accuracy: 0.001)
    }

    func testLeaveDaysTextFormatting() {
        XCTAssertEqual(Statistics.leaveDaysText(0), "0")
        XCTAssertEqual(Statistics.leaveDaysText(3), "3")
        XCTAssertEqual(Statistics.leaveDaysText(2.5), "2.5")
        XCTAssertEqual(Statistics.leaveDaysText(1.0 / 3.0), "0.3")
        XCTAssertEqual(Statistics.leaveDaysText(0.04), "0")
    }
}
