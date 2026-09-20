import XCTest
@testable import DakaCore

final class ChinaHolidayCalendarTests: XCTestCase {
    private let cal = TestTime.calendar

    // MARK: - 2026 春节

    func testSpringFestival2026Holiday() {
        // 2/15(除夕)–2/23 放假，共 9 天
        for d in 15...23 {
            let date = TestTime.date(2026, 2, d)
            XCTAssertFalse(WorkdayCalendar().isWorkday(date, calendar: cal),
                           "2026-02-\(d) 应为假日（休息）")
            XCTAssertEqual(WorkdayCalendar().dayType(date, calendar: cal), .holiday(name: "春节"))
        }
    }

    func testSpringFestival2026Makeup() {
        // 2/14、2/28 补班（周六上班）
        for d in [14, 28] {
            let date = TestTime.date(2026, 2, d)
            XCTAssertTrue(WorkdayCalendar().isWorkday(date, calendar: cal),
                          "2026-02-\(d) 应为调休补班（上班）")
            XCTAssertEqual(WorkdayCalendar().dayType(date, calendar: cal), .makeupWorkday(name: "春节调休"))
        }
    }

    func testDayAfterSpringFestivalIsNormalWorkday() {
        // 2/24 周二，节后首个工作日
        let date = TestTime.date(2026, 2, 24)
        XCTAssertTrue(WorkdayCalendar().isWorkday(date, calendar: cal))
        XCTAssertEqual(WorkdayCalendar().dayType(date, calendar: cal), .workday)
    }

    // MARK: - 2026 国庆

    func testNationalDay2026HolidayAndMakeup() {
        for d in 1...7 {
            let date = TestTime.date(2026, 10, d)
            XCTAssertFalse(WorkdayCalendar().isWorkday(date, calendar: cal))
            XCTAssertEqual(WorkdayCalendar().dayType(date, calendar: cal), .holiday(name: "国庆节"))
        }
        // 9/20、10/10 补班
        for (m, d) in [(9, 20), (10, 10)] {
            let date = TestTime.date(2026, m, d)
            XCTAssertTrue(WorkdayCalendar().isWorkday(date, calendar: cal))
            XCTAssertEqual(WorkdayCalendar().dayType(date, calendar: cal), .makeupWorkday(name: "国庆节调休"))
        }
    }

    // MARK: - 基础星期

    func testNormalWeekdayAndWeekend() {
        // 2026-09-14 周一 -> 工作日；2026-09-19 周六 -> 休息
        XCTAssertTrue(WorkdayCalendar().isWorkday(TestTime.date(2026, 9, 14), calendar: cal))
        XCTAssertFalse(WorkdayCalendar().isWorkday(TestTime.date(2026, 9, 19), calendar: cal))
        XCTAssertEqual(WorkdayCalendar().dayType(TestTime.date(2026, 9, 19), calendar: cal), .weekend)
    }

    func testOutOfRangeFallsBackToBasePattern() {
        // 2027 数据未内置，应按基础星期（周一至周五）判定
        XCTAssertTrue(WorkdayCalendar().isWorkday(TestTime.date(2027, 1, 1), calendar: cal)) // 周五
        XCTAssertFalse(WorkdayCalendar().isWorkday(TestTime.date(2027, 1, 2), calendar: cal)) // 周六
    }

    // MARK: - 手动微调覆盖

    func testOverrideForcesHolidayToWorkday() {
        var s = Settings.default
        s.workdayOverrides = ["2026-02-15": true]
        XCTAssertTrue(s.isWorkday(TestTime.date(2026, 2, 15), calendar: cal))
        XCTAssertEqual(s.dayType(TestTime.date(2026, 2, 15), calendar: cal), .customWorkday)
    }

    func testOverrideForcesWorkdayToOff() {
        var s = Settings.default
        s.workdayOverrides = ["2026-09-14": false]
        XCTAssertFalse(s.isWorkday(TestTime.date(2026, 9, 14), calendar: cal))
        XCTAssertEqual(s.dayType(TestTime.date(2026, 9, 14), calendar: cal), .customOff)
    }

    func testOverridePersistsThroughRoundTrip() throws {
        var s = Settings.default
        s.workdayOverrides = ["2026-02-15": true, "2026-09-14": false]
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(decoded.workdayOverrides, s.workdayOverrides)
    }
}
