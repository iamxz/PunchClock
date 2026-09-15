import XCTest
@testable import DakaCore

final class SpyPresenter: ReminderPresenting {
    var lastHard: [PunchTask]?
    var lastGentle: [PunchTask]?
    var hideCount = 0
    var refreshCount = 0

    func showHard(tasks: [PunchTask], settings: Settings, now: Date) { lastHard = tasks; lastGentle = nil }
    func showGentle(tasks: [PunchTask], settings: Settings, now: Date) { lastGentle = tasks; lastHard = nil }
    func refresh(settings: Settings, now: Date) { refreshCount += 1 }
    func hide() { lastHard = nil; lastGentle = nil; hideCount += 1 }
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

    private func makeScheduler(now: Date) -> (Scheduler, FixedClock, PunchStore, SpyPresenter) {
        let clock = FixedClock(now)
        let store = PunchStore(fileURL: url)
        let presenter = SpyPresenter()
        let scheduler = Scheduler(clock: clock, store: store, presenter: presenter,
                                  interval: 1, calendar: TestTime.calendar)
        return (scheduler, clock, store, presenter)
    }

    func testNothingBeforeWindowHidesOnce() {
        let (scheduler, _, _, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 8, 0))
        scheduler.tick()
        XCTAssertNil(presenter.lastHard)
        XCTAssertNil(presenter.lastGentle)
        XCTAssertEqual(presenter.hideCount, 1)
    }

    func testWindowStartShowsGentle() {
        let (scheduler, _, _, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 9, 0))
        scheduler.tick()
        XCTAssertEqual(presenter.lastGentle, [.morning])
        XCTAssertNil(presenter.lastHard)
    }

    func testDeadlineShowsHard() {
        let (scheduler, _, _, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 9, 30))
        scheduler.tick()
        XCTAssertEqual(presenter.lastHard, [.morning])
        XCTAssertNil(presenter.lastGentle)
    }

    func testGentleToHardTransitionOnTicks() {
        let (scheduler, clock, _, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 9, 29))
        scheduler.tick()
        XCTAssertEqual(presenter.lastGentle, [.morning])

        clock.now = TestTime.date(2026, 9, 14, 9, 30)
        scheduler.tick()
        XCTAssertEqual(presenter.lastHard, [.morning])
        XCTAssertNil(presenter.lastGentle)
    }

    func testHardTakesPriorityOverGentle() {
        let (scheduler, _, _, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 18, 10))
        scheduler.tick()
        XCTAssertEqual(presenter.lastHard, [.morning])
        XCTAssertNil(presenter.lastGentle)
    }

    func testHidesAfterPunch() throws {
        let (scheduler, clock, store, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 9, 35))
        scheduler.tick()
        XCTAssertEqual(presenter.lastHard, [.morning])

        try store.mark(.morning, at: clock.now, calendar: TestTime.calendar)
        scheduler.tick()
        XCTAssertNil(presenter.lastHard)
    }

    func testRefreshWhileStable() {
        let (scheduler, _, _, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 9, 0))
        scheduler.tick()
        XCTAssertEqual(presenter.refreshCount, 0)
        scheduler.tick()
        XCTAssertEqual(presenter.refreshCount, 1)
    }

    func testStateCallbackAndState() {
        let (scheduler, _, _, _) = makeScheduler(now: TestTime.date(2026, 9, 14, 9, 0))
        var observed: [ReminderState] = []
        scheduler.onStateChange = { observed.append($0) }
        scheduler.tick()
        XCTAssertEqual(observed, [ReminderState(gentle: [.morning], hard: [])])
        XCTAssertEqual(scheduler.state, ReminderState(gentle: [.morning], hard: []))
    }

    func testDayRolloverFiresCallback() {
        let (scheduler, clock, _, _) = makeScheduler(now: TestTime.date(2026, 9, 14, 8, 0))
        var observed: [ReminderState] = []
        scheduler.onStateChange = { observed.append($0) }
        scheduler.tick()
        clock.now = TestTime.date(2026, 9, 15, 8, 0)
        scheduler.tick()
        XCTAssertEqual(observed, [ReminderState(), ReminderState()])
    }

    func testWeekendNeverShows() {
        let (scheduler, _, _, presenter) = makeScheduler(now: TestTime.date(2026, 9, 19, 10, 0))
        scheduler.tick()
        XCTAssertNil(presenter.lastHard)
        XCTAssertNil(presenter.lastGentle)
    }

    func testHardToGentleAfterMorningPunched() throws {
        let (scheduler, clock, store, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 18, 10))
        scheduler.tick()
        XCTAssertEqual(presenter.lastHard, [.morning])
        XCTAssertNil(presenter.lastGentle)

        try store.mark(.morning, at: clock.now, calendar: TestTime.calendar)
        scheduler.tick()
        XCTAssertEqual(presenter.lastGentle, [.evening])
        XCTAssertNil(presenter.lastHard)
    }
}
