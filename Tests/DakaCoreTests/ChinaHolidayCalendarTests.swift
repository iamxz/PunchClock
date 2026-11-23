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

    // MARK: - 2027 春节

    func testSpringFestival2027Holiday() {
        // 2/5(除夕)–2/13 放假，共 9 天
        for d in 5...13 {
            let date = TestTime.date(2027, 2, d)
            XCTAssertFalse(WorkdayCalendar().isWorkday(date, calendar: cal),
                           "2027-02-\(d) 应为假日（休息）")
            XCTAssertEqual(WorkdayCalendar().dayType(date, calendar: cal), .holiday(name: "春节"))
        }
    }

    func testSpringFestival2027Makeup() {
        // 1/31、2/14 补班（均为周日）
        let dates = [TestTime.date(2027, 1, 31), TestTime.date(2027, 2, 14)]
        for date in dates {
            XCTAssertTrue(WorkdayCalendar().isWorkday(date, calendar: cal),
                          "\(DakaDate.key(for: date, calendar: cal)) 应为调休补班（上班）")
            XCTAssertEqual(WorkdayCalendar().dayType(date, calendar: cal), .makeupWorkday(name: "春节调休"))
        }
    }

    // MARK: - 2027 其他节日

    func testNewYearAndNationalDay2027() {
        // 元旦：1/1–1/3 放假
        for d in 1...3 {
            let date = TestTime.date(2027, 1, d)
            XCTAssertFalse(WorkdayCalendar().isWorkday(date, calendar: cal))
            XCTAssertEqual(WorkdayCalendar().dayType(date, calendar: cal), .holiday(name: "元旦"))
        }
        // 国庆节：10/1–10/7 放假，9/26、10/9 补班
        for d in 1...7 {
            let date = TestTime.date(2027, 10, d)
            XCTAssertFalse(WorkdayCalendar().isWorkday(date, calendar: cal))
            XCTAssertEqual(WorkdayCalendar().dayType(date, calendar: cal), .holiday(name: "国庆节"))
        }
        for (m, d) in [(9, 26), (10, 9)] {
            let date = TestTime.date(2027, m, d)
            XCTAssertTrue(WorkdayCalendar().isWorkday(date, calendar: cal))
            XCTAssertEqual(WorkdayCalendar().dayType(date, calendar: cal), .makeupWorkday(name: "国庆节调休"))
        }
    }

    func testSingleDayHolidays2027() {
        // 端午 6/9、中秋 9/15 各放假 1 天，不调休
        XCTAssertEqual(WorkdayCalendar().dayType(TestTime.date(2027, 6, 9), calendar: cal), .holiday(name: "端午节"))
        XCTAssertEqual(WorkdayCalendar().dayType(TestTime.date(2027, 9, 15), calendar: cal), .holiday(name: "中秋节"))
        // 劳动节 5/1–5/5 放假，5/8 补班
        for d in 1...5 {
            let date = TestTime.date(2027, 5, d)
            XCTAssertFalse(WorkdayCalendar().isWorkday(date, calendar: cal))
            XCTAssertEqual(WorkdayCalendar().dayType(date, calendar: cal), .holiday(name: "劳动节"))
        }
        XCTAssertEqual(WorkdayCalendar().dayType(TestTime.date(2027, 5, 8), calendar: cal), .makeupWorkday(name: "劳动节调休"))
    }

    // MARK: - 基础星期

    func testNormalWeekdayAndWeekend() {
        // 2026-09-14 周一 -> 工作日；2026-09-19 周六 -> 休息
        XCTAssertTrue(WorkdayCalendar().isWorkday(TestTime.date(2026, 9, 14), calendar: cal))
        XCTAssertFalse(WorkdayCalendar().isWorkday(TestTime.date(2026, 9, 19), calendar: cal))
        XCTAssertEqual(WorkdayCalendar().dayType(TestTime.date(2026, 9, 19), calendar: cal), .weekend)
    }

    func testOutOfRangeFallsBackToBasePattern() {
        // 2028 数据未内置，应按基础星期（周一至周五）判定
        XCTAssertFalse(WorkdayCalendar().isWorkday(TestTime.date(2028, 1, 1), calendar: cal)) // 周六
        XCTAssertTrue(WorkdayCalendar().isWorkday(TestTime.date(2028, 1, 3), calendar: cal)) // 周一
        XCTAssertEqual(WorkdayCalendar().dayType(TestTime.date(2028, 1, 1), calendar: cal), .weekend)
    }
}
