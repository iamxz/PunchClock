import XCTest
@testable import DakaCore

final class PunchRulesTests: XCTestCase {
    private let eight: TimeInterval = 8 * 3600

    func testNoMorningPunchIsNeverComplete() {
        let record = DayRecord(eveningPunches: [TestTime.date(2026, 9, 14, 18, 0)])
        XCTAssertNil(PunchRules.effectiveEveningPunch(record, minWorkDuration: eight))
        XCTAssertFalse(PunchRules.isEveningComplete(record, minWorkDuration: eight))
    }

    func testSevenHoursDoesNotCount() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 16, 0)])
        XCTAssertNil(PunchRules.effectiveEveningPunch(record, minWorkDuration: eight))
    }

    func testExactlyEightHoursCounts() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 17, 0)])
        XCTAssertEqual(PunchRules.effectiveEveningPunch(record, minWorkDuration: eight),
                       TestTime.date(2026, 9, 14, 17, 0))
    }

    func testLatestQualifyingPunchWins() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 17, 0),
                                                TestTime.date(2026, 9, 14, 18, 0)])
        XCTAssertEqual(PunchRules.effectiveEveningPunch(record, minWorkDuration: eight),
                       TestTime.date(2026, 9, 14, 18, 0))
    }

    func testZeroMinimumCountsAnyEveningPunch() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 9, 1)])
        XCTAssertEqual(PunchRules.effectiveEveningPunch(record, minWorkDuration: 0),
                       TestTime.date(2026, 9, 14, 9, 1))
    }

    func testLatestPunchReturnsMostRecentPerTask() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0),
                                               TestTime.date(2026, 9, 14, 9, 20)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 18, 0),
                                                TestTime.date(2026, 9, 14, 18, 30)])
        XCTAssertEqual(PunchRules.latestPunch(record, task: .morning),
                       TestTime.date(2026, 9, 14, 9, 20))
        XCTAssertEqual(PunchRules.latestPunch(record, task: .evening),
                       TestTime.date(2026, 9, 14, 18, 30))
    }

    func testLatestPunchNilWhenEmpty() {
        let record = DayRecord()
        XCTAssertNil(PunchRules.latestPunch(record, task: .morning))
        XCTAssertNil(PunchRules.latestPunch(record, task: .evening))
    }
}
