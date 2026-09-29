import XCTest
@testable import DakaCore

final class AttendanceRuleTests: XCTestCase {
    private let cal = TestTime.calendar
    private let settings = Settings.default

    private func leave(_ record: DayRecord, on day: Date) -> Date? {
        AttendanceRule.expectedLeave(record, settings: settings, on: day, leaves: [], calendar: cal)
    }
    private func complete(_ record: DayRecord, on day: Date) -> Bool {
        AttendanceRule.isEveningComplete(record, settings: settings, on: day, leaves: [], calendar: cal)
    }

    func testNoMorningPunchYieldsNil() {
        let day = TestTime.date(2026, 9, 14, 18, 0)
        let record = DayRecord(eveningPunches: [TestTime.date(2026, 9, 14, 18, 0)])
        XCTAssertNil(AttendanceRule.effectiveStart(record, settings: settings, on: day, calendar: cal))
        XCTAssertNil(leave(record, on: day))
        XCTAssertFalse(complete(record, on: day))
    }

    func testEarlyPunchCountsAsWorkStart() {
        let day = TestTime.date(2026, 9, 14, 8, 40)
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 8, 40)])
        XCTAssertEqual(AttendanceRule.effectiveStart(record, settings: settings, on: day, calendar: cal),
                       TestTime.date(2026, 9, 14, 9, 0))
        XCTAssertEqual(leave(record, on: day), TestTime.date(2026, 9, 14, 18, 0))
    }

    /// 8:30 上班按 9:00 起算：17:30 的下班卡还差半小时，不能算完成。
    func testEarlyPunchNeedsFullDayFromWorkStart() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 8, 30)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 17, 30)])
        let day = TestTime.date(2026, 9, 14, 17, 30)
        XCTAssertNil(AttendanceRule.effectiveEveningPunch(record, settings: settings, on: day,
                                                          leaves: [], calendar: cal))
        XCTAssertFalse(complete(record, on: day))
    }

    /// 早到不早走：8:30 上班 → 18:00 的下班卡刚好做满 9 小时。
    func testEarlyPunchQualifiesAtFlooredDeadline() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 8, 30)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 18, 0)])
        XCTAssertTrue(complete(record, on: TestTime.date(2026, 9, 14, 18, 0)))
    }

    func testPunchWithinFlexShiftsLeave() {
        let day = TestTime.date(2026, 9, 14, 9, 16)
        let record = DayRecord(morningPunches: [day])
        XCTAssertEqual(leave(record, on: day), TestTime.date(2026, 9, 14, 18, 16))
    }

    func testLatePunchNoUpperBound() {
        let day = TestTime.date(2026, 9, 14, 10, 0)
        let record = DayRecord(morningPunches: [day])
        XCTAssertEqual(leave(record, on: day), TestTime.date(2026, 9, 14, 19, 0))
    }

    func testEarliestMorningPunchUsed() {
        let day = TestTime.date(2026, 9, 14, 9, 0)
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 30),
                                                 TestTime.date(2026, 9, 14, 8, 50)])
        XCTAssertEqual(AttendanceRule.effectiveStart(record, settings: settings, on: day, calendar: cal),
                       TestTime.date(2026, 9, 14, 9, 0))
    }

    func testEarlyEveningPunchDoesNotComplete() {
        let day = TestTime.date(2026, 9, 14, 9, 0)
        let record = DayRecord(morningPunches: [day],
                               eveningPunches: [TestTime.date(2026, 9, 14, 17, 50)])
        XCTAssertFalse(complete(record, on: day))
    }

    func testQualifyingEveningPunchCompletes() {
        let day = TestTime.date(2026, 9, 14, 9, 0)
        let record = DayRecord(morningPunches: [day],
                               eveningPunches: [TestTime.date(2026, 9, 14, 18, 0)])
        XCTAssertTrue(complete(record, on: day))
    }

    func testLatestQualifyingPunchWins() {
        let day = TestTime.date(2026, 9, 14, 9, 0)
        let record = DayRecord(morningPunches: [day],
                               eveningPunches: [TestTime.date(2026, 9, 14, 18, 0),
                                                TestTime.date(2026, 9, 14, 19, 0)])
        XCTAssertEqual(AttendanceRule.effectiveEveningPunch(record, settings: settings, on: day, leaves: [], calendar: cal),
                       TestTime.date(2026, 9, 14, 19, 0))
    }

    func testEffectiveEveningPunchUsesLatestQualifyingPunch() {
        let record = DayRecord(
            morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
            eveningPunches: [
                TestTime.date(2026, 9, 14, 17, 0),
                TestTime.date(2026, 9, 14, 18, 0)
            ]
        )

        let result = AttendanceRule.effectiveEveningPunch(
            record,
            settings: .default,
            on: TestTime.date(2026, 9, 14, 21, 0),
            leaves: [],
            calendar: cal
        )

        XCTAssertEqual(result, TestTime.date(2026, 9, 14, 18, 0))
    }

    func testCustomWorkDuration() {
        var s = Settings.default
        s.workDurationHours = 8
        let day = TestTime.date(2026, 9, 14, 9, 0)
        let record = DayRecord(morningPunches: [day])
        XCTAssertEqual(AttendanceRule.expectedLeave(record, settings: s, on: day, leaves: [], calendar: cal),
                       TestTime.date(2026, 9, 14, 17, 0))
    }

    func testWindows() {
        XCTAssertEqual(AttendanceRule.windowStart(settings, on: TestTime.monday, calendar: cal),
                       TestTime.date(2026, 9, 14, 9, 0))
        XCTAssertEqual(AttendanceRule.windowEnd(settings, on: TestTime.monday, calendar: cal),
                       TestTime.date(2026, 9, 14, 9, 30))
    }

    // MARK: - 弹性方式（只管考勤起点）

    /// 弹性方式与迟到记账是两个正交开关，用例按需要单独开合。
    private func rule(flex: Settings.FlexMode = .elasticBackward,
                      late: Bool = false) -> Settings {
        var s = Settings.default
        s.flexMode = flex
        s.recordsLateArrival = late
        return s
    }

    /// 9:00 上班、做满 9 小时：下班线随考勤起点浮动。
    private func line(_ flex: Settings.FlexMode, _ punch: Date) -> Date? {
        AttendanceRule.expectedLeave(DayRecord(morningPunches: [punch]), settings: rule(flex: flex),
                                     on: punch, leaves: [], calendar: cal)
    }
    private func late(_ s: Settings, _ punch: Date) -> Bool {
        AttendanceRule.isLate(DayRecord(morningPunches: [punch]), settings: s,
                              on: punch, calendar: cal)
    }

    func testDefaultModeIsBackwardOnly() {
        XCTAssertEqual(Settings.default.flexMode, .elasticBackward)
        // 默认模式下起点就是今天的行为：早到按 9:00、晚到全额顺延。
        XCTAssertEqual(line(.elasticBackward, TestTime.date(2026, 9, 14, 7, 50)),
                       TestTime.date(2026, 9, 14, 18, 0))
        XCTAssertEqual(line(.elasticBackward, TestTime.date(2026, 9, 14, 10, 0)),
                       TestTime.date(2026, 9, 14, 19, 0))
    }

    func testElasticBothClampsToFlexBand() {
        // 7:50 与 8:30 等效：最早只按 09:00 - 弹性 起算。
        XCTAssertEqual(line(.elasticBoth, TestTime.date(2026, 9, 14, 7, 50)),
                       TestTime.date(2026, 9, 14, 17, 30))
        XCTAssertEqual(line(.elasticBoth, TestTime.date(2026, 9, 14, 8, 30)),
                       TestTime.date(2026, 9, 14, 17, 30))
        XCTAssertEqual(line(.elasticBoth, TestTime.date(2026, 9, 14, 9, 17)),
                       TestTime.date(2026, 9, 14, 18, 17))
        // 9:50 也只顺延到 9:30：超出弹性带的部分不再往后挪下班线。
        XCTAssertEqual(line(.elasticBoth, TestTime.date(2026, 9, 14, 9, 50)),
                       TestTime.date(2026, 9, 14, 18, 30))
    }

    func testBothModesFloorEarlyPunchTheSameWay() {
        for flex in [Settings.FlexMode.elasticBackward, .elasticBoth] {
            // 早到不早走：起点不早于上班时间（前后弹性最多早到「弹性时间」）。
            XCTAssertEqual(AttendanceRule.effectiveStart(DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 6, 0)]),
                                                         settings: rule(flex: flex), on: TestTime.monday,
                                                         calendar: cal)!.timeIntervalSince(TestTime.monday),
                           flex == .elasticBoth ? 8.5 * 3600 : 9 * 3600,
                           "\(flex) 早到被夹住")
        }
    }

    // MARK: - 迟到记账（与弹性方式无关）

    func testLateArrivalOffJudgesNobody() {
        for flex in [Settings.FlexMode.elasticBackward, .elasticBoth] {
            XCTAssertFalse(late(rule(flex: flex), TestTime.date(2026, 9, 14, 11, 0)),
                           "开关关着就不判迟到（\(flex)）")
        }
    }

    func testLateArrivalGraceIsWorkStartPlusFlexInBothModes() {
        for flex in [Settings.FlexMode.elasticBackward, .elasticBoth] {
            let s = rule(flex: flex, late: true)
            XCTAssertFalse(late(s, TestTime.date(2026, 9, 14, 9, 30)), "宽限线上不算迟到（\(flex)）")
            XCTAssertTrue(late(s, TestTime.date(2026, 9, 14, 9, 31)), "\(flex)")
            XCTAssertFalse(late(s, TestTime.date(2026, 9, 14, 8, 0)), "早到不是迟到（\(flex)）")
        }
    }

    func testLateMinutesMeasuredFromGraceEdge() {
        // tooltip 要说「迟到 20 分钟」而不是只说迟到了。
        XCTAssertEqual(AttendanceRule.lateBy(DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 50)]),
                                             settings: rule(late: true), on: TestTime.monday, calendar: cal),
                       20 * 60)
    }

    func testNoMorningPunchIsNeverLate() {
        XCTAssertFalse(AttendanceRule.isLate(DayRecord(), settings: rule(late: true),
                                             on: TestTime.monday, calendar: cal))
    }

    // MARK: - 工时 = 真实在岗时长

    /// 超出应工作时长的那段照常计入工时，不做封顶。
    func testOvertimeCountedInFull() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 19, 0)])
        for flex in [Settings.FlexMode.elasticBackward, .elasticBoth] {
            XCTAssertEqual(AttendanceRule.workDuration(record, settings: rule(flex: flex),
                                                       on: TestTime.monday, leaves: [], calendar: cal),
                           10 * 3600, "\(flex) 加班要如实计入")
        }
    }

    /// 老配置里残留的「加班不计工时」标记不再生效：读到它也不该封顶工时。
    func testLegacyOvertimeFlagIsIgnored() throws {
        var raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Settings.default)) as! [String: Any]
        raw["excludesOvertime"] = true
        let s = try JSONDecoder().decode(Settings.self,
                                        from: try JSONSerialization.data(withJSONObject: raw))
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 19, 0)])
        XCTAssertEqual(AttendanceRule.workDuration(record, settings: s, on: TestTime.monday,
                                                   leaves: [], calendar: cal), 10 * 3600)
    }

    // MARK: - 请假抵扣

    private func span(_ h1: Int, _ m1: Int, _ h2: Int, _ m2: Int, day: Int = 14) -> LeaveRecord {
        LeaveRecord(start: TestTime.date(2026, 9, day, h1, m1),
                    end: TestTime.date(2026, 9, day, h2, m2))
    }

    private func deducted(_ leaves: [LeaveRecord], day: Date = TestTime.monday) -> TimeInterval {
        AttendanceRule.leaveDuration(settings, on: day, leaves: leaves, calendar: cal)
    }

    func testNoLeavesDeductNothing() {
        XCTAssertEqual(deducted([]), 0, accuracy: 1)
        XCTAssertEqual(AttendanceRule.requiredWorkDuration(settings, on: TestTime.monday,
                                                          leaves: [], calendar: cal),
                       settings.workDuration, accuracy: 1)
        XCTAssertEqual(AttendanceRule.leaveFraction(settings, on: TestTime.monday,
                                                    leaves: [], calendar: cal), 0)
        XCTAssertFalse(AttendanceRule.isFullDayLeave(settings, on: TestTime.monday,
                                                     leaves: [], calendar: cal))
    }

    /// 用户的原始诉求：9:00 上班、工时 9h、请 16:00–18:00 → 下班线提前到 16:00。
    func testAfternoonLeaveShortensExpectedLeave() {
        let day = TestTime.date(2026, 9, 14, 9, 0)
        let record = DayRecord(morningPunches: [day])
        let leaves = [span(16, 0, 18, 0)]
        XCTAssertEqual(deducted(leaves), 2 * 3600, accuracy: 1)
        XCTAssertEqual(AttendanceRule.expectedLeave(record, settings: settings, on: day,
                                                    leaves: [], calendar: cal),
                       TestTime.date(2026, 9, 14, 18, 0), "没有请假时下班线不动")
        XCTAssertEqual(AttendanceRule.expectedLeave(record, settings: settings, on: day,
                                                    leaves: leaves, calendar: cal),
                       TestTime.date(2026, 9, 14, 16, 0))
    }

    func testMorningLeaveDoesNotDeductTwice() {
        // 上午请 2 小时、11:05 才上班：抵扣仍按 canonical 窗口算 2h，下班线 = 11:05 + 7h。
        let day = TestTime.date(2026, 9, 14, 11, 5)
        let record = DayRecord(morningPunches: [day])
        let leaves = [span(9, 0, 11, 0)]
        XCTAssertEqual(deducted(leaves), 2 * 3600, accuracy: 1)
        XCTAssertEqual(AttendanceRule.expectedLeave(record, settings: settings, on: day,
                                                    leaves: leaves, calendar: cal),
                       TestTime.date(2026, 9, 14, 18, 5))
    }

    func testHalfDayLeaveIsExactlyHalf() {
        let leaves = [span(13, 30, 18, 0)]
        XCTAssertEqual(deducted(leaves), 4.5 * 3600, accuracy: 1)
        XCTAssertEqual(AttendanceRule.requiredWorkDuration(settings, on: TestTime.monday,
                                                          leaves: leaves, calendar: cal),
                       4.5 * 3600, accuracy: 1)
        XCTAssertEqual(AttendanceRule.leaveFraction(settings, on: TestTime.monday,
                                                    leaves: leaves, calendar: cal), 0.5, accuracy: 0.001)
        XCTAssertFalse(AttendanceRule.isFullDayLeave(settings, on: TestTime.monday,
                                                     leaves: leaves, calendar: cal))
    }

    func testFullDayLeaveEmitsRequiredWork() {
        let leaves = [LeaveRecord(start: TestTime.date(2026, 9, 14),
                                  end: TestTime.date(2026, 9, 15))]
        XCTAssertEqual(deducted(leaves), settings.workDuration, accuracy: 1)
        XCTAssertEqual(AttendanceRule.requiredWorkDuration(settings, on: TestTime.monday,
                                                          leaves: leaves, calendar: cal), 0, accuracy: 1)
        XCTAssertEqual(AttendanceRule.leaveFraction(settings, on: TestTime.monday,
                                                    leaves: leaves, calendar: cal), 1, accuracy: 0.001)
        XCTAssertTrue(AttendanceRule.isFullDayLeave(settings, on: TestTime.monday,
                                                    leaves: leaves, calendar: cal))
    }

    func testLeaveOutsideRequiredWindowDeductsNothing() {
        for leaves in [[span(7, 0, 9, 0)], [span(18, 0, 19, 0)]] {
            XCTAssertEqual(deducted(leaves), 0, accuracy: 1)
            XCTAssertFalse(AttendanceRule.isFullDayLeave(settings, on: TestTime.monday,
                                                         leaves: leaves, calendar: cal))
        }
        // 夜里 20:00 → 次日 04:00：两天都不该有抵扣（那段时间本来不用上班）。
        let night = [LeaveRecord(start: TestTime.date(2026, 9, 14, 20),
                                 end: TestTime.date(2026, 9, 15, 4))]
        XCTAssertEqual(deducted(night), 0, accuracy: 1)
        XCTAssertEqual(AttendanceRule.leaveDuration(settings, on: TestTime.date(2026, 9, 15, 12),
                                                    leaves: night, calendar: cal), 0, accuracy: 1)
    }

    func testOverlappingLeavesClampToWorkDuration() {
        let duplicated = [span(9, 0, 18, 0), span(9, 0, 18, 0)]
        XCTAssertEqual(deducted(duplicated), settings.workDuration, accuracy: 1)
        XCTAssertEqual(AttendanceRule.leaveFraction(settings, on: TestTime.monday,
                                                    leaves: duplicated, calendar: cal), 1, accuracy: 0.001)
    }

    func testTwoDayLeaveDeductsBothWorkdaysCompletely() {
        let trip = [LeaveRecord(start: TestTime.date(2026, 9, 14, 9),
                                end: TestTime.date(2026, 9, 16, 9))]
        for day in [TestTime.monday, TestTime.date(2026, 9, 15)] {
            XCTAssertTrue(AttendanceRule.isFullDayLeave(settings, on: day, leaves: trip, calendar: cal),
                          "\(DakaDate.key(for: day, calendar: cal))")
        }
        // 第三天已恢复上班：请假在 09:00 结束，窗口内没有覆盖。
        XCTAssertFalse(AttendanceRule.isFullDayLeave(settings, on: TestTime.date(2026, 9, 16),
                                                     leaves: trip, calendar: cal))
    }

    func testFlexMinutesDoNotExtendDeductionWindow() {
        // 09:20 迟到上班 → 应工作窗口仍是 09:00–18:00，18:00 之后的请假不重复抵扣。
        let late = TestTime.date(2026, 9, 14, 9, 20)
        let leaves = [span(18, 0, 18, 20)]
        XCTAssertEqual(deducted(leaves), 0, accuracy: 1)
        XCTAssertEqual(AttendanceRule.expectedLeave(DayRecord(morningPunches: [late]),
                                                    settings: settings, on: late,
                                                    leaves: leaves, calendar: cal),
                       TestTime.date(2026, 9, 14, 18, 20))
    }

    func testInvalidWorkStartTimeDeductsNothing() {
        var broken = Settings.default
        broken.workStartTime = "not-a-time"
        let leaves = [span(9, 0, 18, 0)]
        XCTAssertEqual(AttendanceRule.leaveDuration(broken, on: TestTime.monday,
                                                    leaves: leaves, calendar: cal), 0, accuracy: 1)
        XCTAssertEqual(AttendanceRule.requiredWorkDuration(broken, on: TestTime.monday,
                                                           leaves: leaves, calendar: cal),
                       broken.workDuration, accuracy: 1)
        XCTAssertFalse(AttendanceRule.isFullDayLeave(broken, on: TestTime.monday,
                                                     leaves: leaves, calendar: cal))
    }
}
