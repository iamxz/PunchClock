import XCTest
@testable import DakaCore

final class WorkProgressTests: XCTestCase {
    private let eight: TimeInterval = 8 * 3600

    func testNoMorningPunchHasNoElapsedAndZeroFraction() {
        let record = DayRecord(eveningPunches: [TestTime.date(2026, 9, 14, 18, 0)])
        let now = TestTime.date(2026, 9, 14, 18, 0)
        XCTAssertNil(WorkProgress.elapsed(record, now: now, minWorkDuration: eight))
        XCTAssertEqual(WorkProgress.fraction(record, now: now, minWorkDuration: eight), 0)
    }

    func testFourOfEightHoursIsHalf() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)])
        let now = TestTime.date(2026, 9, 14, 13, 0)
        XCTAssertEqual(WorkProgress.elapsed(record, now: now, minWorkDuration: eight),
                       4 * 3600)
        XCTAssertEqual(WorkProgress.fraction(record, now: now, minWorkDuration: eight), 0.5)
    }

    func testOvertimeIsCappedAtOne() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)])
        let now = TestTime.date(2026, 9, 14, 19, 0)
        XCTAssertEqual(WorkProgress.fraction(record, now: now, minWorkDuration: eight), 1)
    }

    func testCompletionUsesQualifyingEveningPunch() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 18, 0)])
        let now = TestTime.date(2026, 9, 14, 20, 0)
        XCTAssertEqual(WorkProgress.elapsed(record, now: now, minWorkDuration: eight),
                       9 * 3600)
        XCTAssertEqual(WorkProgress.fraction(record, now: now, minWorkDuration: eight), 1)
    }

    func testCompletionUsesLatestQualifyingPunch() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 16, 0),
                                                TestTime.date(2026, 9, 14, 18, 0)])
        let now = TestTime.date(2026, 9, 14, 21, 0)
        XCTAssertEqual(WorkProgress.elapsed(record, now: now, minWorkDuration: eight),
                       9 * 3600)
    }

    func testZeroMinimumIsFull() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)])
        let now = TestTime.date(2026, 9, 14, 9, 30)
        XCTAssertEqual(WorkProgress.fraction(record, now: now, minWorkDuration: 0), 1)
    }
}
