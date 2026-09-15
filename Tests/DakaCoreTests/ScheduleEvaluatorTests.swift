import XCTest
@testable import DakaCore

final class ScheduleEvaluatorTests: XCTestCase {
    private let evaluator = ScheduleEvaluator()
    private let cal = TestTime.calendar

    private func pending(_ date: Date,
                        settings: Settings = .default,
                        record: DayRecord = DayRecord(),
                        launchForced: Bool = false) -> [PunchTask] {
        evaluator.pendingTasks(now: date, settings: settings, record: record,
                               calendar: cal, launchForced: launchForced)
    }

    func testBeforeMorningTimeHasNoTasks() {
        let now = TestTime.date(2026, 9, 14, 8, 0)
        XCTAssertEqual(pending(now), [])
    }

    func testAtMorningTimeYieldsMorning() {
        let now = TestTime.date(2026, 9, 14, 9, 0)
        XCTAssertEqual(pending(now), [.morning])
    }

    func testAfterEveningYieldsBothWhenNoneDone() {
        let now = TestTime.date(2026, 9, 14, 19, 0)
        XCTAssertEqual(pending(now), [.morning, .evening])
    }

    func testMorningDoneYieldsOnlyEvening() {
        let now = TestTime.date(2026, 9, 14, 19, 0)
        var record = DayRecord()
        record.morningDone = true
        XCTAssertEqual(pending(now, record: record), [.evening])
    }

    func testBothDoneYieldsNothing() {
        let now = TestTime.date(2026, 9, 14, 23, 0)
        var record = DayRecord()
        record.morningDone = true
        record.eveningDone = true
        XCTAssertEqual(pending(now, record: record), [])
    }

    func testWeekendHasNoTasks() {
        let now = TestTime.date(2026, 9, 19, 10, 0) // 周六
        XCTAssertEqual(pending(now), [])
    }

    func testDisabledHasNoTasks() {
        let now = TestTime.date(2026, 9, 14, 19, 0)
        var settings = Settings.default
        settings.enabled = false
        XCTAssertEqual(pending(now, settings: settings), [])
    }

    func testSkippedHasNoTasks() {
        let now = TestTime.date(2026, 9, 14, 19, 0)
        var record = DayRecord()
        record.skipped = true
        XCTAssertEqual(pending(now, record: record), [])
    }

    func testLaunchForcedBeforeMorningYieldsMorning() {
        let now = TestTime.date(2026, 9, 14, 7, 0)
        XCTAssertEqual(pending(now, launchForced: true), [.morning])
    }

    func testLaunchForcedBeforeEarliestYieldsNothing() {
        let now = TestTime.date(2026, 9, 14, 5, 0)
        XCTAssertEqual(pending(now, launchForced: true), [])
    }

    func testLaunchForcedDoesNotForceEveningEarly() {
        let now = TestTime.date(2026, 9, 14, 7, 0)
        XCTAssertEqual(pending(now, launchForced: true), [.morning])
        XCTAssertFalse(pending(now, launchForced: true).contains(.evening))
    }

    func testLaunchForcedOnWeekendYieldsNothing() {
        let now = TestTime.date(2026, 9, 19, 7, 0)
        XCTAssertEqual(pending(now, launchForced: true), [])
    }

    func testAtEveningTimeYieldsEvening() {
        let now = TestTime.date(2026, 9, 14, 18, 30)
        var record = DayRecord()
        record.morningDone = true
        XCTAssertEqual(pending(now, record: record), [.evening])
    }

    func testLaunchForcedAtEarliestBoundaryYieldsMorning() {
        let now = TestTime.date(2026, 9, 14, 6, 0)
        XCTAssertEqual(pending(now, launchForced: true), [.morning])
    }

    func testLaunchForcedIginoredWhenMorningAlreadyDone() {
        let now = TestTime.date(2026, 9, 14, 7, 0)
        var record = DayRecord()
        record.morningDone = true
        XCTAssertEqual(pending(now, record: record, launchForced: true), [])
    }
}
