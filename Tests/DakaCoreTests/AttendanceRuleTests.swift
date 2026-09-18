import XCTest
@testable import DakaCore

final class AttendanceRuleTests: XCTestCase {
    private let cal = TestTime.calendar
    private let settings = Settings.default

    private func leave(_ record: DayRecord, on day: Date) -> Date? {
        AttendanceRule.expectedLeave(record, settings: settings, on: day, calendar: cal)
    }
    private func complete(_ record: DayRecord, on day: Date) -> Bool {
        AttendanceRule.isEveningComplete(record, settings: settings, on: day, calendar: cal)
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
        XCTAssertEqual(AttendanceRule.effectiveEveningPunch(record, settings: settings, on: day, calendar: cal),
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
            calendar: Calendar.current
        )

        XCTAssertEqual(result, TestTime.date(2026, 9, 14, 18, 0))
    }

    func testCustomWorkDuration() {
        var s = Settings.default
        s.workDurationHours = 8
        let day = TestTime.date(2026, 9, 14, 9, 0)
        let record = DayRecord(morningPunches: [day])
        XCTAssertEqual(AttendanceRule.expectedLeave(record, settings: s, on: day, calendar: cal),
                       TestTime.date(2026, 9, 14, 17, 0))
    }

    func testWindows() {
        XCTAssertEqual(AttendanceRule.windowStart(settings, on: TestTime.monday, calendar: cal),
                       TestTime.date(2026, 9, 14, 9, 0))
        XCTAssertEqual(AttendanceRule.windowEnd(settings, on: TestTime.monday, calendar: cal),
                       TestTime.date(2026, 9, 14, 9, 30))
    }
}
