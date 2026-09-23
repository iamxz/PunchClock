import Foundation

public protocol ReminderPresenting: AnyObject {
    func showHard(tasks: [PunchTask], settings: Settings, record: DayRecord, now: Date)
    func refresh(settings: Settings, record: DayRecord, now: Date)
    func hide()
}

public final class Scheduler {
    public var onStateChange: ((ReminderState) -> Void)?

    private let clock: DakaClock
    private let evaluator: ScheduleEvaluator
    private let store: PunchStore
    private weak var presenter: ReminderPresenting?
    private let interval: TimeInterval
    private let calendarOverride: Calendar?
    private var calendar: Calendar { calendarOverride ?? .current }

    private var timer: Timer?
    private var lastState: ReminderState?
    private var lastDayKey: String?

    public private(set) var state = ReminderState()

    public init(clock: DakaClock,
                evaluator: ScheduleEvaluator = ScheduleEvaluator(),
                store: PunchStore,
                presenter: ReminderPresenting,
                interval: TimeInterval = 1,
                calendar: Calendar? = nil) {
        self.clock = clock
        self.evaluator = evaluator
        self.store = store
        self.presenter = presenter
        self.interval = interval
        self.calendarOverride = calendar
    }

    deinit {
        stop()
    }

    public func start() {
        stop()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func tick() {
        let now = clock.now
        let dayKey = DakaDate.key(for: now, calendar: calendar)
        let dayChanged = dayKey != lastDayKey
        lastDayKey = dayKey

        let settings = store.data.settings
        let record = store.record(for: now, calendar: calendar)
        let pending = evaluator.pendingReminders(now: now, settings: settings, record: record,
                                                 leaves: store.data.leaves, calendar: calendar)
        apply(state: ReminderState(pending: pending), settings: settings, record: record, now: now, dayChanged: dayChanged)
    }

    private func apply(state newState: ReminderState, settings: Settings, record: DayRecord, now: Date, dayChanged: Bool) {
        state = newState
        let changed = newState != lastState
        if changed {
            lastState = newState
            if !newState.pending.isEmpty {
                presenter?.showHard(tasks: newState.pending, settings: settings, record: record, now: now)
            } else {
                presenter?.hide()
            }
        } else if !newState.isEmpty {
            presenter?.refresh(settings: settings, record: record, now: now)
        }
        if changed || dayChanged {
            onStateChange?(newState)
        }
    }
}
