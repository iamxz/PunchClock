import XCTest
@testable import DakaCore

final class SpyPresenter: ReminderPresenting {
    var lastShown: [PunchTask]?
    var hideCount = 0
    var refreshCount = 0

    func show(tasks: [PunchTask], now: Date) { lastShown = tasks }
    func refresh(now: Date) { refreshCount += 1 }
    func hide() { lastShown = nil; hideCount += 1 }
}

final class SchedulerTests: XCTestCase {
    private var dir: URL!
    private var url: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("data.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeScheduler(now: Date,
                               launchForced: Bool = false) -> (Scheduler, FixedClock, PunchStore, SpyPresenter) {
        let clock = FixedClock(now)
        let store = PunchStore(fileURL: url)
        let presenter = SpyPresenter()
        let scheduler = Scheduler(clock: clock, store: store, presenter: presenter,
                                  launchForced: launchForced, interval: 1,
                                  calendar: TestTime.calendar)
        return (scheduler, clock, store, presenter)
    }

    func testNoTasksBeforeMorningTime() {
        let (scheduler, _, _, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 8, 0))
        scheduler.tick()
        XCTAssertNil(presenter.lastShown)
        XCTAssertEqual(presenter.hideCount, 1)
    }

    func testShowsMorningWhenDue() {
        let (scheduler, _, _, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 9, 0))
        scheduler.tick()
        XCTAssertEqual(presenter.lastShown, [.morning])
    }

    func testHidesAfterMorningDone() throws {
        let (scheduler, clock, store, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 9, 0))
        scheduler.tick()
        XCTAssertEqual(presenter.lastShown, [.morning])

        try store.mark(.morning, at: clock.now, calendar: TestTime.calendar)
        scheduler.tick()
        XCTAssertNil(presenter.lastShown)
    }

    func testShowsEveningAfterMorningDone() throws {
        let (scheduler, clock, store, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 9, 0))
        try store.mark(.morning, at: clock.now, calendar: TestTime.calendar)
        clock.now = TestTime.date(2026, 9, 14, 18, 30)
        scheduler.tick()
        XCTAssertEqual(presenter.lastShown, [.evening])
    }

    func testLaunchForcedShowsMorningEarly() {
        let (scheduler, _, _, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 7, 0),
                                                         launchForced: true)
        scheduler.tick()
        XCTAssertEqual(presenter.lastShown, [.morning])
    }

    func testLaunchForcedIgnoredBeforeEarliest() {
        let (scheduler, _, _, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 5, 0),
                                                         launchForced: true)
        scheduler.tick()
        XCTAssertNil(presenter.lastShown)
    }

    func testWeekendNeverShows() {
        let (scheduler, _, _, presenter) = makeScheduler(now: TestTime.date(2026, 9, 19, 9, 0))
        scheduler.tick()
        XCTAssertNil(presenter.lastShown)
    }

    func testPendingStateCallback() {
        let (scheduler, _, _, _) = makeScheduler(now: TestTime.date(2026, 9, 14, 9, 0))
        var observed: [PunchTask] = []
        scheduler.onStateChange = { observed = $0 }
        scheduler.tick()
        XCTAssertEqual(observed, [.morning])
        XCTAssertTrue(scheduler.hasPendingTasks)
    }

    func testRefreshCalledOnSubsequentPendingTicks() {
        let (scheduler, _, _, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 9, 0))
        scheduler.tick()
        XCTAssertEqual(presenter.refreshCount, 0)
        scheduler.tick()
        XCTAssertEqual(presenter.refreshCount, 1)
    }

    func testRefreshNotCalledWhenNothingPending() {
        let (scheduler, _, _, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 8, 0))
        scheduler.tick()
        scheduler.tick()
        XCTAssertEqual(presenter.refreshCount, 0)
    }

    func testStateChangeFiresOnDayRollover() {
        let (scheduler, clock, _, _) = makeScheduler(now: TestTime.date(2026, 9, 14, 8, 0))
        var observed: [[PunchTask]] = []
        scheduler.onStateChange = { observed.append($0) }

        scheduler.tick()
        clock.now = TestTime.date(2026, 9, 15, 8, 0)
        scheduler.tick()
        XCTAssertEqual(observed, [[], []])
    }

    func testStateChangeFiresOnlyOnTransition() {
        let (scheduler, clock, store, _) = makeScheduler(now: TestTime.date(2026, 9, 14, 9, 0))
        var observed: [[PunchTask]] = []
        scheduler.onStateChange = { observed.append($0) }

        scheduler.tick()
        scheduler.tick()
        XCTAssertEqual(observed, [[.morning]])

        try? store.mark(.morning, at: clock.now, calendar: TestTime.calendar)
        scheduler.tick()
        XCTAssertEqual(observed, [[.morning], []])
        XCTAssertFalse(scheduler.hasPendingTasks)
    }
}
