import XCTest
@testable import DakaCore

final class SpyPresenter: ReminderPresenting {
    var lastHard: [PunchTask]?
    var hideCount = 0
    var refreshCount = 0

    func showHard(tasks: [PunchTask], settings: Settings, record: DayRecord, now: Date) { lastHard = tasks }
    func refresh(settings: Settings, record: DayRecord, now: Date) { refreshCount += 1 }
    func hide() { lastHard = nil; hideCount += 1 }
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
        XCTAssertEqual(presenter.hideCount, 1)
    }

    func testWindowStartShowsHard() {
        let (scheduler, _, _, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 9, 0))
        scheduler.tick()
        XCTAssertEqual(presenter.lastHard, [.morning])
    }

    func testStaysHardAcrossTicks() {
        let (scheduler, clock, _, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 9, 0))
        scheduler.tick()
        XCTAssertEqual(presenter.lastHard, [.morning])

        clock.now = TestTime.date(2026, 9, 14, 9, 30)
        scheduler.tick()
        XCTAssertEqual(presenter.lastHard, [.morning])
    }

    func testHidesAfterPunch() throws {
        let (scheduler, clock, store, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 9, 5))
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
        XCTAssertEqual(observed, [ReminderState(pending: [.morning])])
        XCTAssertEqual(scheduler.state, ReminderState(pending: [.morning]))
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
    }

    func testMorningPunchedSwitchesToEvening() throws {
        let (scheduler, clock, store, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 18, 10))
        scheduler.tick()
        XCTAssertEqual(presenter.lastHard, [.morning])

        try store.mark(.morning, at: clock.now, calendar: TestTime.calendar)
        scheduler.tick()
        XCTAssertNil(presenter.lastHard)
    }

    func testMorningPunchedShowsEveningOnlyAtLeave() throws {
        let (scheduler, clock, store, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 9, 0))
        try store.mark(.morning, at: TestTime.date(2026, 9, 14, 9, 0), calendar: TestTime.calendar)
        clock.now = TestTime.date(2026, 9, 14, 17, 59)
        scheduler.tick()
        XCTAssertNil(presenter.lastHard)
        clock.now = TestTime.date(2026, 9, 14, 18, 0)
        scheduler.tick()
        XCTAssertEqual(presenter.lastHard, [.evening])
    }

    func testLatePunchPushesEveningReminder() throws {
        let (scheduler, clock, store, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 9, 16))
        try store.mark(.morning, at: TestTime.date(2026, 9, 14, 9, 16), calendar: TestTime.calendar)
        clock.now = TestTime.date(2026, 9, 14, 18, 10)
        scheduler.tick()
        XCTAssertNil(presenter.lastHard)
        clock.now = TestTime.date(2026, 9, 14, 18, 16)
        scheduler.tick()
        XCTAssertEqual(presenter.lastHard, [.evening])
    }

    func testNoMorningNeverPresentsEvening() {
        let (scheduler, _, _, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 20, 0))
        scheduler.tick()
        XCTAssertEqual(presenter.lastHard, [.morning])
    }

    func testEarlyEveningPunchKeepsReminding() throws {
        let (scheduler, clock, store, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 18, 10))
        try store.mark(.morning, at: TestTime.date(2026, 9, 14, 9, 0), calendar: TestTime.calendar)
        try store.mark(.evening, at: TestTime.date(2026, 9, 14, 17, 30), calendar: TestTime.calendar)
        scheduler.tick()
        XCTAssertEqual(presenter.lastHard, [.evening])
    }

    func testQualifyingEveningPunchClearsReminder() throws {
        let (scheduler, clock, store, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 18, 10))
        try store.mark(.morning, at: TestTime.date(2026, 9, 14, 9, 0), calendar: TestTime.calendar)
        try store.mark(.evening, at: TestTime.date(2026, 9, 14, 18, 10), calendar: TestTime.calendar)
        scheduler.tick()
        XCTAssertNil(presenter.lastHard)
    }
}
