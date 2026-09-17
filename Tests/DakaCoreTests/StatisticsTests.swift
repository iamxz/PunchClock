import XCTest
@testable import DakaCore

final class StatisticsTests: XCTestCase {
    private let cal = TestTime.calendar
    private var now: Date { TestTime.date(2026, 9, 16, 10, 0) } // 周三

    private func records(_ items: [(Date, Bool, Bool, Date?, Date?, Bool)]) -> [String: DayRecord] {
        var result: [String: DayRecord] = [:]
        for (day, morning, evening, mat, eat, skipped) in items {
            let key = DakaDate.key(for: day, calendar: cal)
            var r = DayRecord()
            let defaultMorning = DakaDate.date(on: day, at: "09:00", calendar: cal) ?? day
            let defaultEvening = DakaDate.date(on: day, at: "18:00", calendar: cal) ?? day
            r.morningPunches = morning ? [mat ?? defaultMorning] : []
            r.eveningPunches = evening ? [eat ?? defaultEvening] : []
            r.skipped = skipped
            result[key] = r
        }
        return result
    }

    private func stat(_ summary: StatisticsSummary, _ key: String) -> DailyStat? {
        summary.days.first { $0.dateKey == key }
    }

    func testRangeLengthAndAscendingOrder() {
        let s = Statistics.compute(records: [:], settings: .default, now: now, rangeDays: 7, calendar: cal)
        XCTAssertEqual(s.days.count, 7)
        XCTAssertEqual(s.days.first?.dateKey, "2026-09-10")
        XCTAssertEqual(s.days.last?.dateKey, "2026-09-16")
    }

    func testWorkDurationAndAverage() {
        let recs = records([
            (TestTime.date(2026, 9, 14), true, true, TestTime.date(2026, 9, 14, 9, 0), TestTime.date(2026, 9, 14, 18, 10), false),
            (TestTime.date(2026, 9, 15), true, true, TestTime.date(2026, 9, 15, 9, 5), TestTime.date(2026, 9, 15, 18, 10), false)
        ])
        let s = Statistics.compute(records: recs, settings: .default, now: now, rangeDays: 7, calendar: cal)
        XCTAssertEqual(stat(s, "2026-09-14")?.workDuration, 33000)
        XCTAssertEqual(stat(s, "2026-09-15")?.workDuration, 32700)
        XCTAssertEqual(s.averageWorkDuration ?? 0, 32850, accuracy: 0.5)
    }

    func testEveningUnderMinimumDoesNotComplete() {
        let recs = records([
            (TestTime.date(2026, 9, 15), true, true,
             TestTime.date(2026, 9, 15, 9, 0), TestTime.date(2026, 9, 15, 16, 0), false)
        ])
        let s = Statistics.compute(records: recs, settings: .default, now: now, rangeDays: 7, calendar: cal)
        XCTAssertEqual(stat(s, "2026-09-15")?.completedBoth, false)
        XCTAssertNil(stat(s, "2026-09-15")?.workDuration)
    }

    func testEveningBeforeMorningYieldsNilDuration() {
        let recs = records([
            (TestTime.date(2026, 9, 14), true, true, TestTime.date(2026, 9, 14, 18, 0), TestTime.date(2026, 9, 14, 9, 0), false)
        ])
        let s = Statistics.compute(records: recs, settings: .default, now: now, rangeDays: 3, calendar: cal)
        XCTAssertNil(stat(s, "2026-09-14")?.workDuration)
        XCTAssertNil(s.averageWorkDuration)
    }

    func testWeekendNeverMissed() {
        let s = Statistics.compute(records: [:], settings: .default, now: now, rangeDays: 7, calendar: cal)
        XCTAssertEqual(s.missedDays, 4)
        XCTAssertEqual(stat(s, "2026-09-12")?.isWorkday, false)
    }

    func testSkippedNotMissedAndKeepsStreak() {
        let recs = records([
            (TestTime.date(2026, 9, 14), true, true, TestTime.date(2026, 9, 14, 9, 0), TestTime.date(2026, 9, 14, 18, 0), false),
            (TestTime.date(2026, 9, 15), false, false, nil, nil, true)
        ])
        let s = Statistics.compute(records: recs, settings: .default, now: now, rangeDays: 7, calendar: cal)
        XCTAssertEqual(stat(s, "2026-09-15")?.skipped, true)
        XCTAssertEqual(s.missedDays, 2)
        XCTAssertEqual(s.currentStreak, 1)
    }

    func testStreakCountsConsecutiveWorkdays() {
        let recs = records([
            (TestTime.date(2026, 9, 14), true, true, nil, nil, false),
            (TestTime.date(2026, 9, 15), true, true, nil, nil, false)
        ])
        let s = Statistics.compute(records: recs, settings: .default, now: now, rangeDays: 14, calendar: cal)
        XCTAssertEqual(s.currentStreak, 2)
    }

    func testTodayIncompleteAfterDeadlineBreaksStreakAndCountsMissed() {
        let lateNow = TestTime.date(2026, 9, 16, 19, 0)
        let recs = records([
            (TestTime.date(2026, 9, 15), true, true, nil, nil, false)
        ])
        let s = Statistics.compute(records: recs, settings: .default, now: lateNow, rangeDays: 7, calendar: cal)
        XCTAssertEqual(s.currentStreak, 1)
        XCTAssertTrue(s.missedDays >= 1)
    }

    func testMonthPunchDays() {
        let recs = records([
            (TestTime.date(2026, 9, 14), true, true, nil, nil, false),
            (TestTime.date(2026, 9, 15), true, true, nil, nil, false),
            (TestTime.date(2026, 8, 31), true, true, nil, nil, false)
        ])
        let s = Statistics.compute(records: recs, settings: .default, now: now, rangeDays: 30, calendar: cal)
        XCTAssertEqual(s.monthPunchDays, 2)
    }

    func testMonthPunchIndependentOfRange() {
        let recs = records([
            (TestTime.date(2026, 9, 14), true, true, nil, nil, false),
            (TestTime.date(2026, 9, 15), true, true, nil, nil, false)
        ])
        // rangeDays 1 -> range only covers today, but the month count still sees 09-14/09-15
        let s = Statistics.compute(records: recs, settings: .default, now: now, rangeDays: 1, calendar: cal)
        XCTAssertEqual(s.monthPunchDays, 2)
        XCTAssertEqual(s.days.count, 1)
    }
}
