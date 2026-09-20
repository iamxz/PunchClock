import XCTest
@testable import DakaCore

final class AttendanceCalendarTests: XCTestCase {
    private let cal = TestTime.calendar
    /// 2026-09-01 为周二（weekday=3），当月 30 天。
    private var month: Date { TestTime.date(2026, 9, 1) }

    private func record(morning: Bool, evening: Bool, skipped: Bool,
                         mAt: Date? = nil, eAt: Date? = nil) -> DayRecord {
        var r = DayRecord()
        let day = TestTime.date(2026, 9, 1)
        let defM = DakaDate.date(on: day, at: "09:00", calendar: cal)!
        let defE = DakaDate.date(on: day, at: "18:00", calendar: cal)!
        r.morningPunches = morning ? [mAt ?? defM] : []
        r.eveningPunches = evening ? [eAt ?? defE] : []
        r.skipped = skipped
        return r
    }

    private func records(_ items: [(Int, DayRecord)]) -> [String: DayRecord] {
        var result: [String: DayRecord] = [:]
        for (day, rec) in items {
            let key = String(format: "2026-09-%02d", day)
            result[key] = rec
        }
        return result
    }

    private func grid(_ recs: [String: DayRecord], now: Date) -> MonthGrid {
        AttendanceCalendar.monthGrid(records: recs, settings: .default,
                                     month: month, now: now, calendar: cal)
    }

    private func cell(_ g: MonthGrid, day: Int) -> AttendanceDayCell? {
        g.weeks.joined().compactMap { $0 }.first { $0.day == day }
    }

    func testSeptember2026GridShape() {
        let g = grid([:], now: TestTime.date(2026, 9, 10, 12, 0))
        XCTAssertEqual(g.year, 2026)
        XCTAssertEqual(g.month, 9)
        XCTAssertEqual(g.firstWeekday, 3) // 周二
        let nonNil = g.weeks.joined().compactMap { $0 }
        XCTAssertEqual(nonNil.count, 30)
        // 30 天 + 前置 2 个补齐 = 32，补齐到 35（5 周）
        XCTAssertEqual(g.weeks.count, 5)
        XCTAssertEqual(g.weeks[0][0], nil) // 周日补齐
        XCTAssertEqual(g.weeks[0][1], nil) // 周一补齐
        XCTAssertEqual(cell(g, day: 1)?.weekday, 3)
    }

    func testStatusClassification() {
        let recs = records([
            (1, record(morning: true, evening: true, skipped: false)),       // 已打卡
            (2, record(morning: true, evening: true, skipped: false)),       // 已打卡
            (3, record(morning: false, evening: false, skipped: false)),     // 缺卡（过去工作日）
            (4, record(morning: false, evening: false, skipped: true)),      // 请假
            (6, record(morning: false, evening: false, skipped: false))      // 周日非工作日
        ])
        let now = TestTime.date(2026, 9, 10, 12, 0) // 周四
        let g = grid(recs, now: now)

        XCTAssertEqual(cell(g, day: 1)?.status, .done)
        XCTAssertEqual(cell(g, day: 2)?.status, .done)
        XCTAssertEqual(cell(g, day: 3)?.status, .missed)
        XCTAssertEqual(cell(g, day: 4)?.status, .leave)
        XCTAssertEqual(cell(g, day: 5)?.status, AttendanceStatus.none)     // 周六非工作日
        XCTAssertEqual(cell(g, day: 6)?.status, AttendanceStatus.none)     // 周日非工作日
        XCTAssertEqual(cell(g, day: 7)?.status, .missed)   // 周一已过去且未打卡 -> missed
    }

    func testPendingToday() {
        // 今天（9-10 周四）未打卡，且未到应下班时间 -> pending
        let now = TestTime.date(2026, 9, 10, 12, 0)
        let g = grid([:], now: now)
        XCTAssertEqual(cell(g, day: 10)?.status, .pending)
        XCTAssertTrue(cell(g, day: 10)?.isToday ?? false)
    }

    func testFutureWorkdaysAreNone() {
        // 本月 9-11 之后为未来工作日 -> none（尚未到期，不标记缺卡）
        let now = TestTime.date(2026, 9, 10, 12, 0)
        let g = grid([:], now: now)
        XCTAssertEqual(cell(g, day: 11)?.status, AttendanceStatus.none)
        XCTAssertEqual(cell(g, day: 15)?.status, AttendanceStatus.none)
    }

    func testDoneCellCarriesTimes() {
        let mAt = TestTime.date(2026, 9, 1, 9, 5)
        let eAt = TestTime.date(2026, 9, 1, 18, 20)
        let recs = records([(1, record(morning: true, evening: true, skipped: false, mAt: mAt, eAt: eAt))])
        let g = grid(recs, now: TestTime.date(2026, 9, 10, 12, 0))
        let c = cell(g, day: 1)
        XCTAssertEqual(c?.status, .done)
        XCTAssertEqual(c?.morningDoneAt, mAt)
        XCTAssertEqual(c?.eveningDoneAt, eAt)
    }

    func testSkippedOverridesWorkdayOnWeekend() {
        // 在周日（非工作日）标记请假，仍应显示为请假
        let recs = records([(6, record(morning: false, evening: false, skipped: true))])
        let g = grid(recs, now: TestTime.date(2026, 9, 10, 12, 0))
        XCTAssertEqual(cell(g, day: 6)?.status, .leave)
    }
}
