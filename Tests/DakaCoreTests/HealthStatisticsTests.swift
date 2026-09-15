import XCTest
@testable import DakaCore

final class HealthStatisticsTests: XCTestCase {
    private let cal = TestTime.calendar

    private var schedule: Settings {
        Settings(workdays: [2, 3, 4, 5, 6])
    }

    private func record(cups: Int, stands: Int = 0, on day: Date) -> (String, DayHealthRecord) {
        let drinks = (0..<cups).map { day.addingTimeInterval(TimeInterval($0 * 3600)) }
        let moves = (0..<stands).map { day.addingTimeInterval(TimeInterval($0 * 3600)) }
        return (DakaDate.key(for: day, calendar: cal),
                DayHealthRecord(drinks: drinks, stands: moves))
    }

    func testDailyAggregation() {
        let now = TestTime.date(2026, 9, 14, 10, 0) // 周一
        var records: [String: DayHealthRecord] = [:]
        let (k1, r1) = record(cups: 8, stands: 3, on: TestTime.date(2026, 9, 14))
        let (k2, r2) = record(cups: 4, stands: 1, on: TestTime.date(2026, 9, 13)) // 周日
        records[k1] = r1
        records[k2] = r2

        let summary = HealthStatistics.compute(records: records, settings: .default,
                                               schedule: schedule, now: now,
                                               rangeDays: 7, calendar: cal)
        XCTAssertEqual(summary.days.count, 7)
        XCTAssertEqual(summary.days.last?.cups, 8)
        XCTAssertEqual(summary.averageCups, 12.0 / 7.0, accuracy: 0.001)
        XCTAssertEqual(summary.waterGoalDays, 1)     // 仅周一达标（周日非工作日）
        XCTAssertEqual(summary.movementGoalDays, 0)
    }

    func testStreakSkipsWeekendAndCountsConsecutiveWorkdays() {
        let now = TestTime.date(2026, 9, 14, 10, 0) // 周一
        var records: [String: DayHealthRecord] = [:]
        records[record(cups: 8, on: TestTime.date(2026, 9, 14)).0] = record(cups: 8, on: TestTime.date(2026, 9, 14)).1
        records[record(cups: 8, on: TestTime.date(2026, 9, 11)).0] = record(cups: 8, on: TestTime.date(2026, 9, 11)).1 // 周五
        records[record(cups: 8, on: TestTime.date(2026, 9, 10)).0] = record(cups: 8, on: TestTime.date(2026, 9, 10)).1 // 周四

        let summary = HealthStatistics.compute(records: records, settings: .default,
                                               schedule: schedule, now: now,
                                               rangeDays: 14, calendar: cal)
        XCTAssertEqual(summary.waterStreak, 3) // 周一 + 周五 + 周四，跳过周末
    }

    func testUnmetTodayDoesNotBreakStreak() {
        let now = TestTime.date(2026, 9, 14, 10, 0) // 周一，今天还没达标
        var records: [String: DayHealthRecord] = [:]
        records[record(cups: 8, on: TestTime.date(2026, 9, 11)).0] = record(cups: 8, on: TestTime.date(2026, 9, 11)).1
        let summary = HealthStatistics.compute(records: records, settings: .default,
                                               schedule: schedule, now: now,
                                               rangeDays: 14, calendar: cal)
        XCTAssertEqual(summary.waterStreak, 1)
    }
}
