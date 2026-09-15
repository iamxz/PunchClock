import Foundation

/// UI 侧实现：展示/刷新/隐藏全屏遮罩。
public protocol ReminderPresenting: AnyObject {
    func show(tasks: [PunchTask], now: Date)
    func refresh(now: Date)
    func hide()
}

public final class Scheduler {
    public var onStateChange: (([PunchTask]) -> Void)?

    private let clock: DakaClock
    private let evaluator: ScheduleEvaluator
    private let store: PunchStore
    private weak var presenter: ReminderPresenting?
    private let interval: TimeInterval
    private let calendarOverride: Calendar?
    private var calendar: Calendar { calendarOverride ?? .current }

    private var launchForcedPending: Bool
    private var timer: Timer?
    private var lastTasks: [PunchTask]?
    private var lastDayKey: String?

    public private(set) var hasPendingTasks: Bool = false

    public init(clock: DakaClock,
                evaluator: ScheduleEvaluator = ScheduleEvaluator(),
                store: PunchStore,
                presenter: ReminderPresenting,
                launchForced: Bool = false,
                interval: TimeInterval = 1,
                calendar: Calendar? = nil) {
        self.clock = clock
        self.evaluator = evaluator
        self.store = store
        self.presenter = presenter
        self.launchForcedPending = launchForced
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

    /// 评估一次。供定时器、打卡后、唤醒/改时间后调用。
    public func tick() {
        let now = clock.now
        let dayKey = DakaDate.key(for: now, calendar: calendar)
        let dayChanged = dayKey != lastDayKey
        lastDayKey = dayKey

        let settings = store.data.settings
        let record = store.record(for: now, calendar: calendar)
        let tasks = evaluator.pendingTasks(now: now, settings: settings, record: record,
                                           calendar: calendar, launchForced: launchForcedPending)
        consumeLaunchForceIfNeeded(now: now, settings: settings, record: record)
        apply(tasks: tasks, now: now, dayChanged: dayChanged)
    }

    /// 开机强制项一旦「被常规日程接管」或已完成，就不再强制。
    private func consumeLaunchForceIfNeeded(now: Date, settings: Settings, record: DayRecord) {
        guard launchForcedPending else { return }
        if record.morningDone {
            launchForcedPending = false
            return
        }
        if let due = DakaDate.date(on: now, at: settings.morningTime, calendar: calendar), now >= due {
            launchForcedPending = false
        }
    }

    private func apply(tasks: [PunchTask], now: Date, dayChanged: Bool) {
        hasPendingTasks = !tasks.isEmpty
        let changed = tasks != lastTasks
        if changed {
            lastTasks = tasks
            if tasks.isEmpty {
                presenter?.hide()
            } else {
                presenter?.show(tasks: tasks, now: now)
            }
        } else if !tasks.isEmpty {
            presenter?.refresh(now: now)
        }
        if changed || dayChanged {
            onStateChange?(tasks)
        }
    }
}
