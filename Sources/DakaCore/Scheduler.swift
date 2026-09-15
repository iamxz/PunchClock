import Foundation

/// UI 侧实现：展示/刷新/隐藏全屏遮罩。
public protocol ReminderPresenting: AnyObject {
    func show(tasks: [PunchTask], settings: Settings, now: Date)
    func refresh(settings: Settings, now: Date)
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
    private let launchDayKey: String

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
        self.launchDayKey = DakaDate.key(for: clock.now, calendar: calendar ?? .current)
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
        let forceMorning = launchForcedPending && dayKey == launchDayKey
        let tasks = evaluator.pendingTasks(now: now, settings: settings, record: record,
                                           calendar: calendar, launchForced: forceMorning)
        consumeLaunchForceIfNeeded(now: now, settings: settings, record: record, dayKey: dayKey)
        apply(tasks: tasks, settings: settings, now: now, dayChanged: dayChanged)
    }

    /// 开机强制项仅在启动当天有效；当天上班已打卡或已到上班时间后不再强制。
    private func consumeLaunchForceIfNeeded(now: Date, settings: Settings, record: DayRecord, dayKey: String) {
        guard launchForcedPending else { return }
        if dayKey != launchDayKey || record.morningDone {
            launchForcedPending = false
            return
        }
        if let due = DakaDate.date(on: now, at: settings.morningTime, calendar: calendar), now >= due {
            launchForcedPending = false
        }
    }

    private func apply(tasks: [PunchTask], settings: Settings, now: Date, dayChanged: Bool) {
        hasPendingTasks = !tasks.isEmpty
        let changed = tasks != lastTasks
        if changed {
            lastTasks = tasks
            if tasks.isEmpty {
                presenter?.hide()
            } else {
                presenter?.show(tasks: tasks, settings: settings, now: now)
            }
        } else if !tasks.isEmpty {
            presenter?.refresh(settings: settings, now: now)
        }
        if changed || dayChanged {
            onStateChange?(tasks)
        }
    }
}
