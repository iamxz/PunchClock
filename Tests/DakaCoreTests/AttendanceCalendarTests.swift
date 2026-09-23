import XCTest
@testable import DakaCore

final class AttendanceCalendarTests: XCTestCase {
    private let cal = TestTime.calendar
    /// 2026-09-01 为周二（weekday=3），当月 30 天。
    private var month: Date { TestTime.date(2026, 9, 1) }

    private func record(morning: Bool, evening: Bool,
                        mAt: Date? = nil, eAt: Date? = nil) -> DayRecord {
        var r = DayRecord()
        let day = TestTime.date(2026, 9, 1)
        let defM = DakaDate.date(on: day, at: "09:00", calendar: cal)!
        let defE = DakaDate.date(on: day, at: "18:00", calendar: cal)!
        r.morningPunches = morning ? [mAt ?? defM] : []
        r.eveningPunches = evening ? [eAt ?? defE] : []
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

    private func grid(_ recs: [String: DayRecord],
                      leaves: [LeaveRecord] = [],
                      now: Date) -> MonthGrid {
        AttendanceCalendar.monthGrid(records: recs, settings: .default, leaves: leaves,
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
            (1, record(morning: true, evening: true)),      // 已打卡
            (2, record(morning: true, evening: true)),      // 已打卡
            (3, record(morning: false, evening: false)),    // 缺卡（过去工作日）
            (6, record(morning: false, evening: false))     // 周日非工作日
        ])
        let leaves = [TestTime.fullDayLeave(on: TestTime.date(2026, 9, 4))]
        let now = TestTime.date(2026, 9, 10, 12, 0) // 周四
        let g = grid(recs, leaves: leaves, now: now)

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
        let recs = records([(1, record(morning: true, evening: true, mAt: mAt, eAt: eAt))])
        let g = grid(recs, now: TestTime.date(2026, 9, 10, 12, 0))
        let c = cell(g, day: 1)
        XCTAssertEqual(c?.status, .done)
        XCTAssertEqual(c?.morningDoneAt, mAt)
        XCTAssertEqual(c?.eveningDoneAt, eAt)
    }

    func testFullDayLeaveOnWeekendStillShowsLeave() {
        // 在周日（非工作日）请假，仍应显示为请假
        let leaves = [TestTime.fullDayLeave(on: TestTime.date(2026, 9, 6))]
        let g = grid([:], leaves: leaves, now: TestTime.date(2026, 9, 10, 12, 0))
        XCTAssertEqual(cell(g, day: 6)?.status, .leave)
    }

    /// 半天假 + 缩短后的合格下班卡：既是「已打卡」也带着「假」。
    func testHalfDayLeaveWithShortDayIsDone() {
        let recs = records([
            (14, record(morning: true, evening: true,
                        mAt: TestTime.date(2026, 9, 14, 9, 0),
                        eAt: TestTime.date(2026, 9, 14, 16, 0)))
        ])
        let leaves = [TestTime.leave(on: TestTime.date(2026, 9, 14), from: (16, 0), to: (18, 0))]
        let g = grid(recs, leaves: leaves, now: TestTime.date(2026, 9, 20, 12, 0))
        let c = cell(g, day: 14)

        XCTAssertEqual(c?.status, .done)
        XCTAssertEqual(c?.leaveFraction ?? 0, 2.0 / 9.0, accuracy: 0.001)
        XCTAssertEqual(c?.leaveSlices.count, 1)
        XCTAssertEqual(c?.leaveSlices.first?.start, TestTime.date(2026, 9, 14, 16, 0))
        XCTAssertEqual(c?.leaveSlices.first?.end, TestTime.date(2026, 9, 14, 18, 0))
    }

    /// 半天假但一次卡都没打：还欠 7 小时工时，算缺卡。
    func testHalfDayLeaveWithoutPunchIsMissed() {
        let leaves = [TestTime.leave(on: TestTime.date(2026, 9, 14), from: (16, 0), to: (18, 0))]
        let g = grid([:], leaves: leaves, now: TestTime.date(2026, 9, 20, 12, 0))
        XCTAssertEqual(cell(g, day: 14)?.status, .missed)
    }

    /// 提前请未来某天的整天假：当天直接显示「假」，不会被判缺卡。
    func testFutureFullDayLeaveShowsLeave() {
        let leaves = [TestTime.fullDayLeave(on: TestTime.date(2026, 9, 22))]
        let g = grid([:], leaves: leaves, now: TestTime.date(2026, 9, 10, 12, 0))
        let c = cell(g, day: 22)
        XCTAssertEqual(c?.status, .leave)
        XCTAssertTrue(c?.isFuture ?? false)
    }

    /// 周五 14:00 → 周一 09:00 的一次请假：每一天各自拿到裁剪片段，
    /// 周六（非工作日）整日被覆盖仍显示「假」但不折算，周日 09-20 是调休补班日、折算 1 天。
    func testMultiDayLeaveCarriesPerDaySlices() {
        let leaves = [TestTime.leave(from: (TestTime.date(2026, 9, 18), 14, 0),
                                      to: (TestTime.date(2026, 9, 21), 9, 0))]
        let g = grid([:], leaves: leaves, now: TestTime.date(2026, 9, 10, 12, 0))

        let friday = cell(g, day: 18)
        XCTAssertEqual(friday?.leaveSlices.map(\.start), [TestTime.date(2026, 9, 18, 14, 0)])
        XCTAssertEqual(friday?.leaveSlices.map(\.end), [TestTime.date(2026, 9, 19, 0, 0)])
        XCTAssertEqual(friday?.leaveFraction ?? 0, 4.0 / 9.0, accuracy: 0.001)

        let saturday = cell(g, day: 19)
        XCTAssertEqual(saturday?.status, .leave)
        XCTAssertEqual(saturday?.isWorkday, false)
        XCTAssertEqual(saturday?.leaveFraction, 0)

        let makeupSunday = cell(g, day: 20)
        XCTAssertEqual(makeupSunday?.isWorkday, true, "09-20 国庆调休补班")
        XCTAssertEqual(makeupSunday?.leaveFraction ?? 0, 1, accuracy: 0.001)

        // 周一只拿到 00:00–09:00 这一段（结束时刻半开），在应上班窗口之前 → 不折算。
        let monday = cell(g, day: 21)
        XCTAssertEqual(monday?.leaveSlices.map(\.start), [TestTime.date(2026, 9, 21, 0, 0)])
        XCTAssertEqual(monday?.leaveSlices.map(\.end), [TestTime.date(2026, 9, 21, 9, 0)])
        XCTAssertEqual(monday?.leaveFraction ?? 1, 0, accuracy: 0.001)
    }

    /// 请假没覆盖到的日子不受影响，片段为空。
    func testCellsOutsideLeaveHaveNoSlices() {
        let leaves = [TestTime.fullDayLeave(on: TestTime.date(2026, 9, 14))]
        let g = grid([:], leaves: leaves, now: TestTime.date(2026, 9, 20, 12, 0))
        XCTAssertTrue(cell(g, day: 15)?.leaveSlices.isEmpty ?? false)
        XCTAssertEqual(cell(g, day: 15)?.leaveFraction, 0)
    }
}
